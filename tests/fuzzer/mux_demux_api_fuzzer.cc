// Copyright 2018 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////////

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <string_view>
#include <utility>

#include "./fuzz_utils.h"
#include "gtest/gtest.h"
#include "src/mux/muxi.h"
#include "webp/demux.h"
#include "webp/mux.h"
#include "webp/mux_types.h"

namespace {

void MuxDemuxApiTest(std::string_view data_in, bool use_mux_api,
                     const std::array<int, 10>& chunk_flags) {
  const size_t size = data_in.size();
  WebPData webp_data;
  WebPDataInit(&webp_data);
  webp_data.size = size;
  webp_data.bytes = reinterpret_cast<const uint8_t*>(data_in.data());

  // Extracted chunks and frames are not processed or decoded,
  // which is already covered extensively by the other fuzz targets.

  if (use_mux_api) {
    // Mux API
    WebPMux* mux = WebPMuxCreate(&webp_data, size & 2);
    if (!mux) return;

    WebPData chunk;
    (void)WebPMuxGetChunk(mux, "EXIF", &chunk);
    (void)WebPMuxGetChunk(mux, "ICCP", &chunk);
    (void)WebPMuxGetChunk(mux, "FUZZ", &chunk);  // unknown

    uint32_t flags;
    (void)WebPMuxGetFeatures(mux, &flags);

    int width = 0, height = 0;
    (void)WebPMuxGetCanvasSize(mux, &width, &height);

    WebPMuxAnimParams params;
    (void)WebPMuxGetAnimationParams(mux, &params);

    WebPMuxError status;
    WebPMuxFrameInfo info;
    for (int i = 0; i < fuzz_utils::kFuzzFrameLimit; i++) {
      status = WebPMuxGetFrame(mux, i + 1, &info);
      if (status == WEBP_MUX_NOT_FOUND) {
        break;
      } else if (status == WEBP_MUX_OK) {
        WebPDataClear(&info.bitstream);
      }
    }

    // Try setting a custom chunk.
    if (size > 20) {
      WebPData custom_chunk;
      custom_chunk.bytes = reinterpret_cast<const uint8_t*>(data_in.data()) + 4;
      custom_chunk.size = size - 4;
      int chunk_idx = 0;
      for (std::string_view fourcc : {"VP8X", "ICCP", "ANIM", "EXIF", "XMP ",
                                      "ANMF", "ALPH", "VP8 ", "VP8L", "FUZZ"}) {
        // The last five image chunks should return WEBP_MUX_INVALID_ARGUMENT.
        for (int i = 0; i < chunk_flags[chunk_idx]; i++) {
          (void)WebPMuxSetChunk(mux, fourcc.data(), &custom_chunk, 0);
        }
        chunk_idx++;
      }
    }

    // Try assembling the mux
    WebPData assembled;
    WebPDataInit(&assembled);
    (void)WebPMuxAssemble(mux, &assembled);
    WebPDataClear(&assembled);

    // Get number of chunks of various types
    for (int chunk_type = WEBP_CHUNK_VP8X; chunk_type <= WEBP_CHUNK_NIL;
         ++chunk_type) {
      int num_chunks = 0;
      (void)WebPMuxNumChunks(mux, static_cast<WebPChunkId>(chunk_type),
                             &num_chunks);
    }

    WebPMuxDelete(mux);
  } else {
    // Demux API
    WebPDemuxer* demux;
    if (size & 2) {
      WebPDemuxState state;
      demux = WebPDemuxPartial(&webp_data, &state);
      if (state < WEBP_DEMUX_PARSED_HEADER) {
        WebPDemuxDelete(demux);
        return;
      }
    } else {
      demux = WebPDemux(&webp_data);
      if (!demux) return;
    }

    WebPChunkIterator chunk_iter;
    if (WebPDemuxGetChunk(demux, "EXIF", 1, &chunk_iter)) {
      (void)WebPDemuxNextChunk(&chunk_iter);
    }
    WebPDemuxReleaseChunkIterator(&chunk_iter);
    if (WebPDemuxGetChunk(demux, "ICCP", 0, &chunk_iter)) {  // 0 == last
      (void)WebPDemuxPrevChunk(&chunk_iter);
    }
    WebPDemuxReleaseChunkIterator(&chunk_iter);
    // Skips FUZZ because the Demux API has no concept of (un)known chunks.

    WebPIterator iter;
    if (WebPDemuxGetFrame(demux, 1, &iter)) {
      for (int i = 1; i < fuzz_utils::kFuzzFrameLimit; i++) {
        if (!WebPDemuxNextFrame(&iter)) break;
      }
    }

    WebPDemuxReleaseIterator(&iter);
    WebPDemuxDelete(demux);
  }
}

// Tests building and modifying a WebPMux object from scratch (canvas size,
// animation params, image/frame insertion, chunk setting/deletion, frame
// deletion, and final assembly).
void MuxEditApiTest(std::string_view data_in,
                    const std::array<int, 10>& chunk_flags,
                    std::pair<int, int> canvas_size, uint32_t bgcolor,
                    int loop_count, int x_offset, int y_offset, int duration,
                    bool dispose_bg, bool no_blend, bool use_set_image,
                    bool copy_data, uint32_t delete_frame_nth) {
  const std::unique_ptr<WebPMux, fuzz_utils::UniquePtrDeleter> mux(
      WebPMuxNew());
  if (!mux) return;

  // Set canvas size and animation parameters.
  if (WebPMuxSetCanvasSize(mux.get(), canvas_size.first, canvas_size.second) !=
      WEBP_MUX_OK) {
    return;
  }

  const WebPMuxAnimParams params = {bgcolor, loop_count};
  if (WebPMuxSetAnimationParams(mux.get(), &params) != WEBP_MUX_OK) return;

  const size_t size = data_in.size();
  WebPData webp_data;
  WebPDataInit(&webp_data);
  webp_data.size = size;
  webp_data.bytes = reinterpret_cast<const uint8_t*>(data_in.data());

  // Set a single image or push an animation frame.
  if (use_set_image) {
    if (WebPMuxSetImage(mux.get(), &webp_data, copy_data) != WEBP_MUX_OK) {
      return;
    }
  } else {
    WebPMuxFrameInfo frame_info = {};
    frame_info.bitstream = webp_data;
    frame_info.x_offset = x_offset;
    frame_info.y_offset = y_offset;
    frame_info.duration = duration;
    frame_info.id = WEBP_CHUNK_ANMF;
    frame_info.dispose_method =
        dispose_bg ? WEBP_MUX_DISPOSE_BACKGROUND : WEBP_MUX_DISPOSE_NONE;
    frame_info.blend_method = no_blend ? WEBP_MUX_NO_BLEND : WEBP_MUX_BLEND;
    if (WebPMuxPushFrame(mux.get(), &frame_info, copy_data) != WEBP_MUX_OK) {
      return;
    }
  }

  // Try setting or deleting chunks of various known and unknown types.
  if (size > 20) {
    WebPData custom_chunk;
    custom_chunk.bytes = reinterpret_cast<const uint8_t*>(data_in.data()) + 4;
    custom_chunk.size = size - 4;
    int chunk_idx = 0;
    for (std::string_view fourcc : {"VP8X", "ICCP", "ANIM", "EXIF", "XMP ",
                                    "ANMF", "ALPH", "VP8 ", "VP8L", "FUZZ"}) {
      if (chunk_flags[chunk_idx] == 1) {
        if (WebPMuxSetChunk(mux.get(), fourcc.data(), &custom_chunk,
                            copy_data) != WEBP_MUX_OK) {
          return;
        }
      } else if (chunk_flags[chunk_idx] == 2) {
        if (WebPMuxDeleteChunk(mux.get(), fourcc.data()) != WEBP_MUX_OK) return;
      }
      chunk_idx++;
    }
  }

  // Optionally delete a frame (1-based index).
  if (delete_frame_nth > 0) {
    if (WebPMuxDeleteFrame(mux.get(), delete_frame_nth) != WEBP_MUX_OK) return;
  }

  // Try assembling the mux and verify that the result can be demuxed.
  WebPData assembled;
  WebPDataInit(&assembled);
  if (WebPMuxAssemble(mux.get(), &assembled) != WEBP_MUX_OK) return;
  const std::unique_ptr<WebPDemuxer, fuzz_utils::UniquePtrDeleter> demux(
      WebPDemux(&assembled));
  EXPECT_NE(demux, nullptr);
  WebPDataClear(&assembled);
}

auto ArbitraryWebPString() {
  return fuzztest::String().WithMaxSize(fuzz_utils::kMaxWebPFileSize + 1);
}

}  // namespace

FUZZ_TEST(MuxDemuxApi, MuxDemuxApiTest)
    .WithDomains(
        ArbitraryWebPString(),
        /*use_mux_api=*/fuzztest::Arbitrary<bool>(),
        /*chunk_flags=*/fuzztest::ArrayOf<10>(fuzztest::InRange(0, 2)));

FUZZ_TEST(MuxDemuxApi, MuxEditApiTest)
    .WithDomains(
        ArbitraryWebPString(),
        /*chunk_flags=*/fuzztest::ArrayOf<10>(fuzztest::InRange(0, 2)),
        /*canvas_size=*/
        fuzztest::PairOf(fuzztest::OneOf(fuzztest::Arbitrary<int>(),
                                         fuzztest::InRange(0, (1 << 16) - 1),
                                         fuzztest::InRange(0, 1 << 24)),
                         fuzztest::OneOf(fuzztest::Arbitrary<int>(),
                                         fuzztest::InRange(0, (1 << 16) - 1),
                                         fuzztest::InRange(0, 1 << 24))),
        /*bgcolor=*/fuzztest::Arbitrary<uint32_t>(),
        /*loop_count=*/fuzztest::Arbitrary<int>(),
        /*x_offset=*/fuzztest::Arbitrary<int>(),
        /*y_offset=*/fuzztest::Arbitrary<int>(),
        /*duration=*/fuzztest::Arbitrary<int>(),
        /*dispose_bg=*/fuzztest::Arbitrary<bool>(),
        /*no_blend=*/fuzztest::Arbitrary<bool>(),
        /*use_set_image=*/fuzztest::Arbitrary<bool>(),
        /*copy_data=*/fuzztest::Arbitrary<bool>(),
        /*delete_frame_nth=*/fuzztest::InRange<uint32_t>(0, 2));

// WebPMuxSetCanvasSize() multiplied 'width * height' as ints, which overflows
// for valid canvases whose area is in [2^31, 2^32).
TEST(MuxDemuxApi, SetCanvasSizeLargeArea) {
  WebPMux* const mux = WebPMuxNew();
  ASSERT_NE(mux, nullptr);
  EXPECT_EQ(WebPMuxSetCanvasSize(mux, 50000, 50000), WEBP_MUX_OK);
  EXPECT_EQ(WebPMuxSetCanvasSize(mux, 65535, 65537), WEBP_MUX_OK);
  EXPECT_EQ(WebPMuxSetCanvasSize(mux, 65536, 65536), WEBP_MUX_INVALID_ARGUMENT);
  EXPECT_EQ(WebPMuxSetCanvasSize(mux, 0, 5), WEBP_MUX_INVALID_ARGUMENT);
  EXPECT_EQ(WebPMuxSetCanvasSize(mux, 5, 0), WEBP_MUX_INVALID_ARGUMENT);
  EXPECT_EQ(WebPMuxSetCanvasSize(mux, 0, 0), WEBP_MUX_OK);
  WebPMuxDelete(mux);
}

// These size-only tests use null payloads and never allocate or emit RIFF data.
// Full assembly below uses small, fully backed chunk buffers.
TEST(MuxDemuxApi, RiffSizeAdditionBounds) {
  const size_t limit = MAX_RIFF_SIZE;
  EXPECT_EQ(MuxAddRiffSize(0, 0), 0u);
  EXPECT_EQ(MuxAddRiffSize(limit - 1, 1), limit);
  EXPECT_EQ(MuxAddRiffSize(limit, 0), limit);
  EXPECT_EQ(MuxAddRiffSize(limit, 1), limit + 1);
  EXPECT_EQ(MuxAddRiffSize(limit + 1, 0), limit + 1);
  EXPECT_EQ(MuxAddRiffSize(0, limit + 1), limit + 1);
  EXPECT_EQ(MuxAddRiffSize(std::numeric_limits<size_t>::max(), 1), limit + 1);
  EXPECT_EQ(MuxAddRiffSize(1, std::numeric_limits<size_t>::max()), limit + 1);
}

TEST(MuxDemuxApi, ChunkListRiffSizeBounds) {
  std::array<WebPChunk, 3> chunks = {};
  for (size_t i = 0; i < chunks.size(); ++i) {
    chunks[i].data.size = MAX_CHUNK_PAYLOAD / 3;
    if (i + 1 < chunks.size()) chunks[i].next = &chunks[i + 1];
  }
  EXPECT_EQ(ChunkListDiskSize(nullptr), 0u);
  EXPECT_EQ(ChunkListDiskSize(&chunks[2]), ChunkDiskSize(&chunks[2]));
  EXPECT_EQ(ChunkListDiskSize(chunks.data()), MAX_RIFF_SIZE + 1);
  WebPMux mux = {};
  mux.unknown = chunks.data();
  size_t size = 1;
  EXPECT_EQ(MuxGetRiffSize(&mux, &size), WEBP_MUX_BAD_DATA);
  EXPECT_EQ(size, 0u);
}

TEST(MuxDemuxApi, ImageRiffSizeBounds) {
  std::array<WebPChunk, 3> chunks = {};
  for (auto& chunk : chunks) chunk.data.size = MAX_CHUNK_PAYLOAD / 3;
  WebPMuxImage image = {};
  EXPECT_EQ(MuxImageDiskSize(&image), 0u);
  image.header = &chunks[0];
  image.alpha = &chunks[1];
  image.img = &chunks[2];
  EXPECT_EQ(MuxImageDiskSize(&image), MAX_RIFF_SIZE + 1);
  // Include per-image unknown chunks in the same bounded accumulation.
  image.img = nullptr;
  image.unknown = &chunks[2];
  EXPECT_EQ(MuxImageDiskSize(&image), MAX_RIFF_SIZE + 1);
  image.header = nullptr;
  image.alpha = nullptr;
  chunks[2].next = &chunks[0];
  chunks[0].next = &chunks[1];
  EXPECT_EQ(MuxImageDiskSize(&image), MAX_RIFF_SIZE + 1);
}

TEST(MuxDemuxApi, ImageListRiffSizeBounds) {
  std::array<WebPChunk, 3> chunks = {};
  std::array<WebPMuxImage, 3> images = {};
  for (size_t i = 0; i < images.size(); ++i) {
    chunks[i].data.size = MAX_CHUNK_PAYLOAD / 3;
    images[i].img = &chunks[i];
    if (i + 1 < images.size()) images[i].next = &images[i + 1];
  }
  WebPMux mux = {};
  mux.images = images.data();
  size_t size = 1;
  EXPECT_EQ(MuxGetRiffSize(&mux, &size), WEBP_MUX_BAD_DATA);
  EXPECT_EQ(size, 0u);
}

TEST(MuxDemuxApi, CrossListRiffSizeBounds) {
  WebPChunk iccp = {};
  WebPChunk exif = {};
  iccp.data.size = MAX_CHUNK_PAYLOAD / 2;
  exif.data.size = MAX_CHUNK_PAYLOAD / 2;
  WebPMux mux = {};
  mux.iccp = &iccp;
  mux.exif = &exif;
  size_t size = 1;
  EXPECT_EQ(MuxGetRiffSize(&mux, &size), WEBP_MUX_BAD_DATA);
  EXPECT_EQ(size, 0u);
}

TEST(MuxDemuxApi, RiffSizeIncludesHeaderAndPadding) {
  WebPMux mux = {};
  WebPChunk chunk = {};
  size_t size = 0;
  EXPECT_EQ(MuxGetRiffSize(&mux, &size), WEBP_MUX_OK);
  EXPECT_EQ(size, static_cast<size_t>(RIFF_HEADER_SIZE));
  mux.unknown = &chunk;
  chunk.data.size = MAX_RIFF_SIZE - RIFF_HEADER_SIZE - CHUNK_HEADER_SIZE;
  EXPECT_EQ(MuxGetRiffSize(&mux, &size), WEBP_MUX_OK);
  EXPECT_EQ(size, MAX_RIFF_SIZE);
  --chunk.data.size;
  EXPECT_EQ(MuxGetRiffSize(&mux, &size), WEBP_MUX_OK);
  EXPECT_EQ(size, MAX_RIFF_SIZE);
  chunk.data.size += 2;
  EXPECT_EQ(MuxGetRiffSize(&mux, &size), WEBP_MUX_BAD_DATA);
  EXPECT_EQ(size, 0u);
}

TEST(MuxDemuxApi, AssembleMultipleChunksAndFrames) {
  uint8_t* encoded = nullptr;
  const size_t encoded_size =
      WebPEncodeLosslessRGBA(kImgAlphaData, kImgAlphaWidth, kImgAlphaHeight,
                             kImgAlphaWidth * 4, &encoded);
  const std::unique_ptr<uint8_t, decltype(&WebPFree)> encoded_owner(encoded,
                                                                    WebPFree);
  ASSERT_NE(encoded, nullptr);
  ASSERT_GT(encoded_size, 0u);
  const WebPData image = {encoded, encoded_size};
  for (const bool animation : {false, true}) {
    SCOPED_TRACE(animation);
    const std::unique_ptr<WebPMux, fuzz_utils::UniquePtrDeleter> mux(
        WebPMuxNew());
    ASSERT_NE(mux, nullptr);
    if (animation) {
      const WebPMuxAnimParams params = {0, 0};
      ASSERT_EQ(WebPMuxSetAnimationParams(mux.get(), &params), WEBP_MUX_OK);
      WebPMuxFrameInfo frame = {};
      frame.bitstream = image;
      frame.id = WEBP_CHUNK_ANMF;
      frame.duration = 10;
      for (int i = 0; i < 3; ++i) {
        ASSERT_EQ(WebPMuxPushFrame(mux.get(), &frame, 1), WEBP_MUX_OK);
      }
    } else {
      ASSERT_EQ(WebPMuxSetImage(mux.get(), &image, 1), WEBP_MUX_OK);
    }
    // Different unknown tags coexist in one list. Setting the same tag replaces
    // its prior value. Exercise both odd and even payload sizes.
    const std::array<const char*, 5> tags = {"ICCP", "EXIF", "UNK1", "UNK2",
                                             "UNK3"};
    const uint8_t payload[] = {1, 2, 3, 4, 5};
    for (size_t i = 0; i < tags.size(); ++i) {
      const WebPData chunk = {payload, i + 1};
      ASSERT_EQ(WebPMuxSetChunk(mux.get(), tags[i], &chunk, 1), WEBP_MUX_OK);
    }
    int num_unknown = 0;
    ASSERT_EQ(WebPMuxNumChunks(mux.get(), WEBP_CHUNK_UNKNOWN, &num_unknown),
              WEBP_MUX_OK);
    EXPECT_EQ(num_unknown, 3);
    WebPData assembled = {};
    const WebPMuxError err = WebPMuxAssemble(mux.get(), &assembled);
    const std::unique_ptr<WebPData, decltype(&WebPDataClear)> assembled_owner(
        &assembled, WebPDataClear);
    ASSERT_EQ(err, WEBP_MUX_OK);
    size_t expected_size = 0;
    ASSERT_EQ(MuxGetRiffSize(mux.get(), &expected_size), WEBP_MUX_OK);
    EXPECT_EQ(assembled.size, expected_size);
    const std::unique_ptr<WebPDemuxer, fuzz_utils::UniquePtrDeleter> demux(
        WebPDemux(&assembled));
    ASSERT_NE(demux, nullptr);
    EXPECT_EQ(WebPDemuxGetI(demux.get(), WEBP_FF_FRAME_COUNT),
              animation ? 3u : 1u);
    for (size_t i = 0; i < tags.size(); ++i) {
      WebPChunkIterator iter = {};
      ASSERT_TRUE(WebPDemuxGetChunk(demux.get(), tags[i], 1, &iter));
      EXPECT_EQ(iter.chunk.size, i + 1);
      EXPECT_EQ(
          std::string_view(reinterpret_cast<const char*>(iter.chunk.bytes),
                           iter.chunk.size),
          std::string_view(reinterpret_cast<const char*>(payload), i + 1));
      WebPDemuxReleaseChunkIterator(&iter);
    }
  }
}
