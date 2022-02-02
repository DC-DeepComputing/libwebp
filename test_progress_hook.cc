// Copyright 2022 Google LLC.
//
// Progress hook granularity (called frequently and enough times).
//
// Author: Yannis Guyon (yguyon@google.com)

#include <string>
#include <unordered_set>

#include "file/base/file.h"
#include "testing/base/public/gunit.h"
#include "third_party/absl/flags/flag.h"
#include "third_party/libwebp/v0_2/imageio/image_dec.h"
#include "third_party/libwebp/v0_2/imageio/imageio_util.h"
#include "third_party/libwebp/webp/encode.h"

namespace {

//-----------------------------------------------------------------------------

struct UserData {
  std::unordered_set<int> percents;
  int last_percent = -1;
};

int ProgressHook(int percent, const WebPPicture* picture) {
  UserData& user_data = *reinterpret_cast<UserData*>(picture->user_data);
  EXPECT_GE(percent, 0);
  EXPECT_LE(percent, 100);
  EXPECT_GT(percent, user_data.last_percent);  // Strictly increasing.
  user_data.percents.insert(percent);
  user_data.last_percent = percent;
  return 1;
}

TEST(WebPEnc, TestProgressGranularity) {
  const std::string file_path =
      absl::GetFlag(FLAGS_test_srcdir) +
      "/google3/third_party/libwebp/tests/testdata/panorama.jpg";
  const uint8_t* data = nullptr;
  size_t data_size = 0;
  ASSERT_TRUE(ImgIoUtilReadFile(file_path.c_str(), &data, &data_size));
  WebPPicture picture;
  EXPECT_TRUE(WebPPictureInit(&picture));
  WebPImageReader reader = WebPGuessImageReader(data, data_size);
  EXPECT_TRUE(reader(data, data_size, &picture, /*keep_alpha=*/1, nullptr));
  WebPFree(reinterpret_cast<void*>(const_cast<uint8_t*>(data)));
  WebPConfig config;
  EXPECT_TRUE(WebPConfigInit(&config));

  for (bool lossless : {false, true}) {
    config.lossless = static_cast<int>(lossless);
    UserData user_data;
    picture.progress_hook = ProgressHook;
    picture.user_data = reinterpret_cast<void*>(&user_data);
    WebPMemoryWriter writer;
    WebPMemoryWriterInit(&writer);
    EXPECT_TRUE(WebPEncode(&config, &picture));
    // The user progress hook should be called at least 40 times.
    EXPECT_GT(user_data.percents.size(), 40);
  }

  WebPPictureFree(&picture);
}

//-----------------------------------------------------------------------------

}  // namespace
