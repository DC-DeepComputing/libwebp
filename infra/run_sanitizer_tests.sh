#!/bin/bash
# Copyright (c) 2021, Google Inc. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#
#   * Neither the name of Google nor the names of its contributors may
#     be used to endorse or promote products derived from this software
#     without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -xeo pipefail
shopt -s inherit_errexit

LIBWEBP_TEST_DATA_REPO="https://chromium.googlesource.com/webm/libwebp-test-data"
readonly LIBWEBP_TEST_DATA_REPO
readonly WORKSPACE="${WORKSPACE:-"$(mktemp -d -t webp.sanitizer.XXX)"}"
LIBWEBP_ROOT="$(realpath "$(dirname "$0")/..")"
readonly LIBWEBP_ROOT

# shellcheck source=infra/common.sh
source "${LIBWEBP_ROOT}/infra/common.sh"

usage() {
  cat << EOF
Usage: $(basename "$0") TARGET SANITIZER ASM
Options:
TARGET    supported platforms:
            x86
            x86_64
SANITIZER supported sanitizers:
            address
            cfi
            integer
            thread
            undefined
ASM       enable asm (default: enabled)
Environment variables:
WORKSPACE directory where the build is done
EOF
}

#######################################
# Symbolizes and dumps warnings in the address sanitizer log.
# Arguments:
#   $1 sanitizer log filepath.
# Outputs:
#   dumps sanitizer_log to stdout.
#######################################
dump_sanitizer_log() {
  local sanitizer_log="$1"

  if [[ -f "${BUILD_DIR}" ]]; then
    cat "${sanitizer_log}"
  fi
}

if [[ ! -d "${WORKSPACE}" ]]; then
  log_err "${WORKSPACE} directory does not exist."
  exit 1
fi

LLVM_SYMBOLIZER="$(command -v llvm-symbolizer)"
if [[ -z "${LLVM_SYMBOLIZER}" ]]; then
  log_err "${WORKSPACE} directory does not exist."
  exit 1
fi

TARGET=${1:?"TARGET is not defined.$(
  echo
  usage
)"}

readonly SANITIZER=${2:?"SANITIZER not defined.$(
  echo
  usage
)"}

readonly ASM=${3:-"enabled"}

readonly BUILD_DIR="${WORKSPACE}/build-static"
readonly SANITIZER_LOG="${BUILD_DIR}/ubsan_log.txt"

trap 'dump_sanitizer_log ${SANITIZER_LOG}; cleanup ${BUILD_DIR}' EXIT

TEST_DATA_DIR="$(ensure_libwebp_dependency_repo "${LIBWEBP_TEST_DATA_REPO}")"
readonly TEST_DATA_DIR

make_build_dir "${BUILD_DIR}"

case "${TARGET}" in
  x86)
    TARGET=i686-linux-clang
    case "${SANITIZER}" in
      integer | undefined)
        LDFLAGS="-rtlib=compiler-rt -lgcc_s"
        ;;
      *) ;;  # Skip configuration
    esac
    ;;
  x86_64) TARGET=x86_64-linux-clang ;;
  *)
    usage
    exit 1
    ;;
esac

CFLAGS="${CFLAGS} -O1 -g -fsanitize=${SANITIZER}"
CFLAGS="${CFLAGS} -fno-omit-frame-pointer -fno-optimize-sibling-calls"
LDFLAGS="${LDFLAGS} -fsanitize=${SANITIZER}"

case "${SANITIZER}" in
  cfi)
    CFLAGS="${CFLAGS} -fno-strict-aliasing -fno-omit-frame-pointer"
    CFLAGS="${CFLAGS} -fno-optimize-sibling-calls -fno-sanitize-trap=cfi -flto"
    CFLAGS="${CFLAGS} -fvisibility=hidden"
    LDFLAGS="${LDFLAGS} -rtlib=compiler-rt -lgcc_s -fno-sanitize-trap=cfi"
    LDFLAGS="${LDFLAGS} -flto -fuse-ld=gold"
    ;;
  integer | undefined)
    CFLAGS="${CFLAGS} -fno-strict-aliasing -fno-omit-frame-pointer"
    CFLAGS="${CFLAGS} -fno-optimize-sibling-calls"
    ;;
  *) ;;  # Skip configuration.
esac

export LDFLAGS
export CFLAGS
export WORKSPACE
"${LIBWEBP_ROOT}/infra/compile.sh" static "${TARGET}"

[[ -d "${BUILD_DIR}" ]] || exit 1

cd "${BUILD_DIR}"

case "${SANITIZER}" in
  thread | address)
    TSAN_OPTIONS="${TSAN_OPTIONS} halt_on_error=1"
    TSAN_OPTIONS="${TSAN_OPTIONS} external_symbolizer_path=${LLVM_SYMBOLIZER}"
    export TSAN_OPTIONS

    "${TEST_DATA_DIR}/test_dwebp.sh" --exec="${BUILD_DIR}/examples/dwebp" -v \
      --mt
    "${TEST_DATA_DIR}/test_lossless.sh" --exec="${BUILD_DIR}/examples/dwebp" -v

    files=()
    files+=("${TEST_DATA_DIR}/test.webp")
    files+=("${TEST_DATA_DIR}/lossless1.webp")
    cwebp="${BUILD_DIR}/examples/cwebp"

    for f in "${files[@]}"; do
      "${TEST_DATA_DIR}/test_cwebp.sh" --exec="${cwebp}" "${f}"
      "${TEST_DATA_DIR}/test_cwebp.sh" --exec="${cwebp}" --mt "${f}"
      "${TEST_DATA_DIR}/test_cwebp.sh" --exec="${cwebp}" --lossless "${f}"
    done
    ;;
  integer | undefined | cfi)
    if [[ "${SANITIZER}" = "undefined" ]]; then
        "${TEST_DATA_DIR}/test_dwebp.sh" --exec="${BUILD_DIR}/examples/dwebp" \
          -v 2>&1 | tee -a "${SANITIZER_LOG}"
        "${TEST_DATA_DIR}/test_lossless.sh" \
          --exec="${BUILD_DIR}/examples/dwebp" \
          -v 2>&1 | tee -a "${SANITIZER_LOG}"
    fi

    files=()
    files+=("${TEST_DATA_DIR}/alpha_color_cache.webp")
    files+=("${TEST_DATA_DIR}/bryce.webp")
    files+=("${TEST_DATA_DIR}/lossless1.webp")
    files+=("${TEST_DATA_DIR}/lossless_big_random_alpha.webp")
    files+=("${TEST_DATA_DIR}/lossless_color_transform.webp")
    files+=("${TEST_DATA_DIR}/lossy_alpha4.webp")
    files+=("${TEST_DATA_DIR}/near_lossless_75.webp")
    files+=("${TEST_DATA_DIR}/small_31x13.webp")
    files+=("${TEST_DATA_DIR}/test.webp")
    files+=("${TEST_DATA_DIR}/alpha_color_cache.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_0_method_0.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_0_method_1.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_1_method_0.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_1_method_1.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_1.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_2_method_0.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_2_method_1.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_2.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_3_method_0.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_3_method_1.webp")
    files+=("${TEST_DATA_DIR}/alpha_filter_3.webp")
    files+=("${TEST_DATA_DIR}/alpha_no_compression.webp")
    files+=("${TEST_DATA_DIR}/bad_palette_index.webp")
    files+=("${TEST_DATA_DIR}/bryce.webp")
    files+=("${TEST_DATA_DIR}/bug3.webp")
    files+=("${TEST_DATA_DIR}/color_cache_bits_11.webp")
    files+=("${TEST_DATA_DIR}/lossless1.webp")
    files+=("${TEST_DATA_DIR}/lossless2.webp")
    files+=("${TEST_DATA_DIR}/lossless3.webp")
    files+=("${TEST_DATA_DIR}/lossless4.webp")
    files+=("${TEST_DATA_DIR}/lossless_big_random_alpha.webp")
    files+=("${TEST_DATA_DIR}/lossless_color_transform.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_0.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_10.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_11.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_12.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_13.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_14.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_15.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_1.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_2.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_3.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_4.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_5.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_6.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_7.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_8.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_1_9.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_0.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_10.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_11.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_12.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_13.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_14.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_15.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_1.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_2.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_3.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_4.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_5.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_6.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_7.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_8.webp")
    files+=("${TEST_DATA_DIR}/lossless_vec_2_9.webp")
    files+=("${TEST_DATA_DIR}/lossy_alpha1.webp")
    files+=("${TEST_DATA_DIR}/lossy_alpha2.webp")
    files+=("${TEST_DATA_DIR}/lossy_alpha3.webp")
    files+=("${TEST_DATA_DIR}/lossy_alpha4.webp")
    files+=("${TEST_DATA_DIR}/lossy_extreme_probabilities.webp")
    files+=("${TEST_DATA_DIR}/lossy_q0_f100.webp")
    files+=("${TEST_DATA_DIR}/near_lossless_75.webp")
    files+=("${TEST_DATA_DIR}/segment01.webp")
    files+=("${TEST_DATA_DIR}/segment02.webp")
    files+=("${TEST_DATA_DIR}/segment03.webp")
    files+=("${TEST_DATA_DIR}/small_13x1.webp")
    files+=("${TEST_DATA_DIR}/small_1x13.webp")
    files+=("${TEST_DATA_DIR}/small_1x1.webp")
    files+=("${TEST_DATA_DIR}/small_31x13.webp")
    files+=("${TEST_DATA_DIR}/test-nostrong.webp")
    files+=("${TEST_DATA_DIR}/test.webp")
    files+=("${TEST_DATA_DIR}/very_short.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-001.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-002.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-003.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-004.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-005.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-006.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-007.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-008.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-009.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-010.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-011.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-012.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-013.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-014.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-015.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-016.webp")
    files+=("${TEST_DATA_DIR}/vp80-00-comprehensive-017.webp")
    files+=("${TEST_DATA_DIR}/vp80-01-intra-1400.webp")
    files+=("${TEST_DATA_DIR}/vp80-01-intra-1411.webp")
    files+=("${TEST_DATA_DIR}/vp80-01-intra-1416.webp")
    files+=("${TEST_DATA_DIR}/vp80-01-intra-1417.webp")
    files+=("${TEST_DATA_DIR}/vp80-02-inter-1402.webp")
    files+=("${TEST_DATA_DIR}/vp80-02-inter-1412.webp")
    files+=("${TEST_DATA_DIR}/vp80-02-inter-1418.webp")
    files+=("${TEST_DATA_DIR}/vp80-02-inter-1424.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1401.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1403.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1407.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1408.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1409.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1410.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1413.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1414.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1415.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1425.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1426.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1427.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1432.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1435.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1436.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1437.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1441.webp")
    files+=("${TEST_DATA_DIR}/vp80-03-segmentation-1442.webp")
    files+=("${TEST_DATA_DIR}/vp80-04-partitions-1404.webp")
    files+=("${TEST_DATA_DIR}/vp80-04-partitions-1405.webp")
    files+=("${TEST_DATA_DIR}/vp80-04-partitions-1406.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1428.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1429.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1430.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1431.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1433.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1434.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1438.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1439.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1440.webp")
    files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1443.webp")

    cwebp="${BUILD_DIR}/examples/cwebp"
    [[ "${ASM}" = "disabled" ]] && cwebp="${cwebp} -noasm"

    for f in "${files[@]}"; do
      "${TEST_DATA_DIR}/test_cwebp.sh" --exec="${cwebp}" "${f}" 2>&1 \
        | tee -a "${SANITIZER_LOG}"
      "${TEST_DATA_DIR}/test_cwebp.sh" --exec="${cwebp}" --mt "${f}" 2>&1 \
        | tee -a "${SANITIZER_LOG}"
      "${TEST_DATA_DIR}/test_cwebp.sh" --exec="${cwebp}" \
        --extra_args="-near_lossless 40" "${f}" 2>&1 \
        | tee -a "${SANITIZER_LOG}"
      "${TEST_DATA_DIR}/test_cwebp.sh" --exec="${cwebp}" \
        --extra_args="-lossless -q 100 -m 6" "${f}" 2>&1 \
        | tee -a "${SANITIZER_LOG}"
    done
    ;;
  *)
    usage
    exit 1
    ;;
esac
