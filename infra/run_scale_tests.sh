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

# shellcheck disable=SC2310
set -xeo pipefail
shopt -s inherit_errexit

LIBWEBP_ROOT="$(realpath "$(dirname "$0")/..")"
readonly LIBWEBP_ROOT

# shellcheck source=infra/common.sh
source "${LIBWEBP_ROOT}/infra/common.sh"

usage() {
  cat << EOF
  Usage: $(basename "$0") BUILD_TYPE TARGET
  Options:
  BUILD_TYPE  supported build type: (static, static-debug)
  TARGET      supported target platforms:
              aarch64-linux-clang
              aarch64-linux-gnu
              arm-linux-gnueabi
              arm-neon-linux-gnueabi
              cmake
              disable-near-lossless
              disable-sse4.1
              disable-stats
              i686-linux-asan
              i686-linux-clang
              i686-linux-gnu
              i686-w64-mingw32
              reduce-csp
              reduce-size
              reduce-size-disable-stats
              visibility-hidden-clang
              visibility-hidden-gnu
              wasm
              x86_64-linux-clang
              x86_64-linux-gnu
              x86_64-linux-msan
              x86_64-w64-mingw32
  Environment variables:
  ARTIFACTS_DIR directory where the binary are located.
EOF
}

# Declared scale tests.
SCALE_TESTS=(
  "test_scale -noasm"
  "test_scale -mt"
  "test_scale_yuva"
)

declare -A md5 md5_yuva
# TODO: pre-color conversion change, enable this when appropriate
# md5["vp80-03-segmentation-1414.webp_pgm_0"]="d9dad4b8702c3aa18ffad31ba2c16c0f"
# md5["vp80-03-segmentation-1414.webp_pgm_1"]="c3133fcfed366988072199faeb7644ac"
# md5["vp80-03-segmentation-1414.webp_pgm_2"]="339a89ee928fb56348807041e8c04d76"
# md5["vp80-03-segmentation-1414.webp_pgm_3"]="929aa72d58e25dc90343131e76af4ba6"
# md5["vp80-03-segmentation-1414.webp_pgm_4"]="c2a5fa67496019ed29820b37b3b54b04"
# md5["vp80-03-segmentation-1414.webp_pgm_5"]="128ee676a2b4a4f82bb87f05b88b7d69"
# md5["vp80-03-segmentation-1414.webp_ppm_0"]="284dde554bd9eddee8fc6ddeb36058c1"
# md5["vp80-03-segmentation-1414.webp_ppm_1"]="1380d7248763904a16eb5973a373070e"
# md5["vp80-03-segmentation-1414.webp_ppm_2"]="84145cb4e2ee9c67110f2459770b07ed"
# md5["vp80-03-segmentation-1414.webp_ppm_3"]="54a0ce63d49494189ef41f821d2aba8f"
# md5["vp80-03-segmentation-1414.webp_ppm_4"]="be0351c7028e9d2e344699fa123c354b"
# md5["vp80-03-segmentation-1414.webp_ppm_5"]="118aca9f134e9fcd916c75ebbc386491"
# md5["vp80-03-segmentation-1414.webp_pam_0"]="2c48ad000f5298d5ec9b3fc3d9273a9d"
# md5["vp80-03-segmentation-1414.webp_pam_1"]="25c141c1ba04c4d5630a1f5f9c8a1600"
# md5["vp80-03-segmentation-1414.webp_pam_2"]="748f37e2171840e1969032011b304e3b"
# md5["vp80-03-segmentation-1414.webp_pam_3"]="44f28ac0efa0ae0ffafa9699e6a49aeb"
# md5["vp80-03-segmentation-1414.webp_pam_4"]="048cd9822fc02132529fd90e2a76e575"
# md5["vp80-03-segmentation-1414.webp_pam_5"]="bd9d2698a448fddc54de0a485c84eaa8"
# md5["vp80-03-segmentation-1414.webp_yuv_0"]="f6de9af15642a7d45f26195b906c869a"
# md5["vp80-03-segmentation-1414.webp_yuv_1"]="115a17bfb159c477ab061cf41555de94"
# md5["vp80-03-segmentation-1414.webp_yuv_2"]="b325e5e04f558b35999000db00fef686"
# md5["vp80-03-segmentation-1414.webp_yuv_3"]="ae50ee688edefda3a14f3f3c41e0eb99"
# md5["vp80-03-segmentation-1414.webp_yuv_4"]="7c8b2c7ebb8cc0dc3ee33bc9d13433ed"
# md5["vp80-03-segmentation-1414.webp_yuv_5"]="0bddae1542b6211372ebb658d1f2f77c"
# md5["lossless1.webp_pgm_0"]="2a372c5db5351f939524c17049e5ca51"
# md5["lossless1.webp_pgm_1"]="5c922d03ce7c219fbcf3682328fbe15a"
# md5["lossless1.webp_pgm_2"]="a52487cc28ef48eb9fd8eb32ada4433b"
# md5["lossless1.webp_pgm_3"]="919e2462c4f9c4473f6752215ad3f93e"
# md5["lossless1.webp_pgm_4"]="e92959b6021d515127a82e263d0fd12e"
# md5["lossless1.webp_pgm_5"]="491dbc709fb552a2d3544f8ceba8cefa"
# md5["lossless1.webp_ppm_0"]="c1c92e526a176672658f51e1fcf7a76c"
# md5["lossless1.webp_ppm_1"]="62c5e69a033855354eb41cf7a727236e"
# md5["lossless1.webp_ppm_2"]="8328ec93efc4422d7e0fa968b89d7444"
# md5["lossless1.webp_ppm_3"]="14a0459af634d0da1184f3eeadd8abe1"
# md5["lossless1.webp_ppm_4"]="118081c6ed49766771263715b80269bc"
# md5["lossless1.webp_ppm_5"]="1864c75bf0c4bfddb48b0767510e1572"
# md5["lossless1.webp_pam_0"]="98a43c18aa062ad1b13d4e4275df0e84"
# md5["lossless1.webp_pam_1"]="064cf8811fbc6dce49d65892897b69dd"
# md5["lossless1.webp_pam_2"]="4fa467fabb21d0fe9ff43df512926841"
# md5["lossless1.webp_pam_3"]="0beca301975aea7aa1d81a08e337608b"
# md5["lossless1.webp_pam_4"]="32f4f4ff5ba49d754ed8b16f3cee041a"
# md5["lossless1.webp_pam_5"]="126394804bb317c905875cc290cb9f67"
# md5["lossless1.webp_yuv_0"]="b59beba25d7e4f92276c4115ae60cb8e"
# md5["lossless1.webp_yuv_1"]="427f98a51c40b526827f314201db14b3"
# md5["lossless1.webp_yuv_2"]="e1abbea194ef981352d0a3eb4a5311a1"
# md5["lossless1.webp_yuv_3"]="85c6d238a261b67085e6f3ebabf756f4"
# md5["lossless1.webp_yuv_4"]="c6bba7f48e29c6c3a7e05624da8b3aed"
# md5["lossless1.webp_yuv_5"]="816d0708ecdb1eabb012c519b27dd83a"

md5["vp80-03-segmentation-1414.webp_pgm_0"]="d9dad4b8702c3aa18ffad31ba2c16c0f"
md5["vp80-03-segmentation-1414.webp_pgm_1"]="c3133fcfed366988072199faeb7644ac"
md5["vp80-03-segmentation-1414.webp_pgm_2"]="339a89ee928fb56348807041e8c04d76"
md5["vp80-03-segmentation-1414.webp_pgm_3"]="929aa72d58e25dc90343131e76af4ba6"
md5["vp80-03-segmentation-1414.webp_pgm_4"]="c2a5fa67496019ed29820b37b3b54b04"
md5["vp80-03-segmentation-1414.webp_pgm_5"]="128ee676a2b4a4f82bb87f05b88b7d69"
md5["vp80-03-segmentation-1414.webp_ppm_0"]="284dde554bd9eddee8fc6ddeb36058c1"
md5["vp80-03-segmentation-1414.webp_ppm_1"]="b5b3ab083e207abc03445b9a6b7d31ca"
md5["vp80-03-segmentation-1414.webp_ppm_2"]="be1bbc586d49f8b52c7401808380e96a"
md5["vp80-03-segmentation-1414.webp_ppm_3"]="6673a01a913fa3f6709080c80b7e059f"
md5["vp80-03-segmentation-1414.webp_ppm_4"]="2596f2d6e66ebdc32700dc8b7e0e4779"
md5["vp80-03-segmentation-1414.webp_ppm_5"]="118aca9f134e9fcd916c75ebbc386491"
md5["vp80-03-segmentation-1414.webp_pam_0"]="2c48ad000f5298d5ec9b3fc3d9273a9d"
md5["vp80-03-segmentation-1414.webp_pam_1"]="050078f748dd56c37f36f7d9e6c79754"
md5["vp80-03-segmentation-1414.webp_pam_2"]="5e63b88acb83a6eba6eb5dcff9d686d5"
md5["vp80-03-segmentation-1414.webp_pam_3"]="73b32e7958b0a9efdf227a9bc58a57b7"
md5["vp80-03-segmentation-1414.webp_pam_4"]="f86a835052da1de5dda32f42f9c1c400"
md5["vp80-03-segmentation-1414.webp_pam_5"]="bd9d2698a448fddc54de0a485c84eaa8"
md5["vp80-03-segmentation-1414.webp_yuv_0"]="f6de9af15642a7d45f26195b906c869a"
md5["vp80-03-segmentation-1414.webp_yuv_1"]="115a17bfb159c477ab061cf41555de94"
md5["vp80-03-segmentation-1414.webp_yuv_2"]="b325e5e04f558b35999000db00fef686"
md5["vp80-03-segmentation-1414.webp_yuv_3"]="ae50ee688edefda3a14f3f3c41e0eb99"
md5["vp80-03-segmentation-1414.webp_yuv_4"]="7c8b2c7ebb8cc0dc3ee33bc9d13433ed"
md5["vp80-03-segmentation-1414.webp_yuv_5"]="0bddae1542b6211372ebb658d1f2f77c"
md5["lossless1.webp_pgm_0"]="2a372c5db5351f939524c17049e5ca51"
md5["lossless1.webp_pgm_1"]="5c922d03ce7c219fbcf3682328fbe15a"
md5["lossless1.webp_pgm_2"]="a52487cc28ef48eb9fd8eb32ada4433b"
md5["lossless1.webp_pgm_3"]="919e2462c4f9c4473f6752215ad3f93e"
md5["lossless1.webp_pgm_4"]="e92959b6021d515127a82e263d0fd12e"
md5["lossless1.webp_pgm_5"]="491dbc709fb552a2d3544f8ceba8cefa"
md5["lossless1.webp_ppm_0"]="c1c92e526a176672658f51e1fcf7a76c"
md5["lossless1.webp_ppm_1"]="0e0c294fb34f9182473f0dd01191055a"
md5["lossless1.webp_ppm_2"]="8328ec93efc4422d7e0fa968b89d7444"
md5["lossless1.webp_ppm_3"]="14a0459af634d0da1184f3eeadd8abe1"
md5["lossless1.webp_ppm_4"]="118081c6ed49766771263715b80269bc"
md5["lossless1.webp_ppm_5"]="1864c75bf0c4bfddb48b0767510e1572"
md5["lossless1.webp_pam_0"]="98a43c18aa062ad1b13d4e4275df0e84"
md5["lossless1.webp_pam_1"]="5a09357ed9e9c41cac1a5de8538d65de"
md5["lossless1.webp_pam_2"]="4fa467fabb21d0fe9ff43df512926841"
md5["lossless1.webp_pam_3"]="0beca301975aea7aa1d81a08e337608b"
md5["lossless1.webp_pam_4"]="32f4f4ff5ba49d754ed8b16f3cee041a"
md5["lossless1.webp_pam_5"]="126394804bb317c905875cc290cb9f67"
md5["lossless1.webp_yuv_0"]="b59beba25d7e4f92276c4115ae60cb8e"
md5["lossless1.webp_yuv_1"]="427f98a51c40b526827f314201db14b3"
md5["lossless1.webp_yuv_2"]="e1abbea194ef981352d0a3eb4a5311a1"
md5["lossless1.webp_yuv_3"]="85c6d238a261b67085e6f3ebabf756f4"
md5["lossless1.webp_yuv_4"]="c6bba7f48e29c6c3a7e05624da8b3aed"
md5["lossless1.webp_yuv_5"]="816d0708ecdb1eabb012c519b27dd83a"

readonly VP80="vp80-03-segmentation-1414"
md5_yuva["${VP80}.webp_pgm_0"]="a612177851eb603cee655ec9fea12c82"
md5_yuva["${VP80}.webp_pgm_1"]="e9dae523c2b8664e1999719c743c20c5"
md5_yuva["${VP80}.webp_pgm_2"]="8b2ed3708c4cfb603f403b61223a20f5"
md5_yuva["${VP80}.webp_pgm_3"]="94e6fa020c6986f482ee28fd1350d90d"
md5_yuva["${VP80}.webp_pgm_4"]="ef3a19b9d40adddfaea8b9b4612e0485"
md5_yuva["${VP80}.webp_pgm_5"]="bd38e2f4d3d6327ba5236d4857e104bd"
md5_yuva["${VP80}.webp_ppm_0"]="a612177851eb603cee655ec9fea12c82"
md5_yuva["${VP80}.webp_ppm_1"]="e9dae523c2b8664e1999719c743c20c5"
md5_yuva["${VP80}.webp_ppm_2"]="8b2ed3708c4cfb603f403b61223a20f5"
md5_yuva["${VP80}.webp_ppm_3"]="94e6fa020c6986f482ee28fd1350d90d"
md5_yuva["${VP80}.webp_ppm_4"]="ef3a19b9d40adddfaea8b9b4612e0485"
md5_yuva["${VP80}.webp_ppm_5"]="bd38e2f4d3d6327ba5236d4857e104bd"
md5_yuva["${VP80}.webp_pam_0"]="a612177851eb603cee655ec9fea12c82"
md5_yuva["${VP80}.webp_pam_1"]="e9dae523c2b8664e1999719c743c20c5"
md5_yuva["${VP80}.webp_pam_2"]="8b2ed3708c4cfb603f403b61223a20f5"
md5_yuva["${VP80}.webp_pam_3"]="94e6fa020c6986f482ee28fd1350d90d"
md5_yuva["${VP80}.webp_pam_4"]="ef3a19b9d40adddfaea8b9b4612e0485"
md5_yuva["${VP80}.webp_pam_5"]="bd38e2f4d3d6327ba5236d4857e104bd"
md5_yuva["${VP80}.webp_yuv_0"]="a612177851eb603cee655ec9fea12c82"
md5_yuva["${VP80}.webp_yuv_1"]="e9dae523c2b8664e1999719c743c20c5"
md5_yuva["${VP80}.webp_yuv_2"]="8b2ed3708c4cfb603f403b61223a20f5"
md5_yuva["${VP80}.webp_yuv_3"]="94e6fa020c6986f482ee28fd1350d90d"
md5_yuva["${VP80}.webp_yuv_4"]="ef3a19b9d40adddfaea8b9b4612e0485"
md5_yuva["${VP80}.webp_yuv_5"]="bd38e2f4d3d6327ba5236d4857e104bd"
md5_yuva["lossless1.webp_pgm_0"]="2a372c5db5351f939524c17049e5ca51"
md5_yuva["lossless1.webp_pgm_1"]="5c922d03ce7c219fbcf3682328fbe15a"
md5_yuva["lossless1.webp_pgm_2"]="a52487cc28ef48eb9fd8eb32ada4433b"
md5_yuva["lossless1.webp_pgm_3"]="919e2462c4f9c4473f6752215ad3f93e"
md5_yuva["lossless1.webp_pgm_4"]="e92959b6021d515127a82e263d0fd12e"
md5_yuva["lossless1.webp_pgm_5"]="491dbc709fb552a2d3544f8ceba8cefa"
md5_yuva["lossless1.webp_ppm_0"]="2a372c5db5351f939524c17049e5ca51"
md5_yuva["lossless1.webp_ppm_1"]="5c922d03ce7c219fbcf3682328fbe15a"
md5_yuva["lossless1.webp_ppm_2"]="a52487cc28ef48eb9fd8eb32ada4433b"
md5_yuva["lossless1.webp_ppm_3"]="919e2462c4f9c4473f6752215ad3f93e"
md5_yuva["lossless1.webp_ppm_4"]="e92959b6021d515127a82e263d0fd12e"
md5_yuva["lossless1.webp_ppm_5"]="491dbc709fb552a2d3544f8ceba8cefa"
md5_yuva["lossless1.webp_pam_0"]="2a372c5db5351f939524c17049e5ca51"
md5_yuva["lossless1.webp_pam_1"]="5c922d03ce7c219fbcf3682328fbe15a"
md5_yuva["lossless1.webp_pam_2"]="a52487cc28ef48eb9fd8eb32ada4433b"
md5_yuva["lossless1.webp_pam_3"]="919e2462c4f9c4473f6752215ad3f93e"
md5_yuva["lossless1.webp_pam_4"]="e92959b6021d515127a82e263d0fd12e"
md5_yuva["lossless1.webp_pam_5"]="491dbc709fb552a2d3544f8ceba8cefa"
md5_yuva["lossless1.webp_yuv_0"]="2a372c5db5351f939524c17049e5ca51"
md5_yuva["lossless1.webp_yuv_1"]="5c922d03ce7c219fbcf3682328fbe15a"
md5_yuva["lossless1.webp_yuv_2"]="a52487cc28ef48eb9fd8eb32ada4433b"
md5_yuva["lossless1.webp_yuv_3"]="919e2462c4f9c4473f6752215ad3f93e"
md5_yuva["lossless1.webp_yuv_4"]="e92959b6021d515127a82e263d0fd12e"
md5_yuva["lossless1.webp_yuv_5"]="491dbc709fb552a2d3544f8ceba8cefa"

#######################################
# Run single -scale tests.
# Globals:
#   exe executable
# Arguments:
#   $1 file to test
#   $2 --format option
#   $3 w
#   $4 h
#   $5 expected md5 hash
# Returns:
#   Returns non-zero when test fails
#######################################
scale_test() {
  local file=$1
  local fmt=$2
  local w=$3
  local h=$4
  local expected_md5=$5
  shift 5
  actual_md5="$(${exe} "-${fmt}" "${file}" -scale "${w}" "${h}" -o - "$@" \
    | md5sum \
    | cut -d' ' -f1)"
  [[ "${expected_md5}" = "${actual_md5}" ]] || exit 1
}

#######################################
# Run -scale test suite
# Globals:
#   TEST_SOURCES
# Arguments:
#   extra options
# Output:
#   test outputs
#######################################
test_scale() {
  for f in "${SOURCES[@]}"; do
    basen="$(basename "${f}")"
    for fmt in ${formats}; do
      scale_test "${f}" "${fmt}"   1   1 "${md5[${basen}_${fmt}_0]}" "$@"
      scale_test "${f}" "${fmt}" 160 120 "${md5[${basen}_${fmt}_1]}" "$@"
      scale_test "${f}" "${fmt}" 640 480 "${md5[${basen}_${fmt}_2]}" "$@"
      scale_test "${f}" "${fmt}"  15 240 "${md5[${basen}_${fmt}_3]}" "$@"
      scale_test "${f}" "${fmt}" 701 701 "${md5[${basen}_${fmt}_4]}" "$@"
      scale_test "${f}" "${fmt}"   2   2 "${md5[${basen}_${fmt}_5]}" "$@"
    done
  done
}

#######################################
# Run -scale test suite for YUVA.
# Globals:
#   TEST_DATA_DIR libwebp-test-data directory
#   formats --formats options
# Arguments:
#   extra options
# Output:
#   test outputs
#######################################
test_scale_yuva() {
  for f in "${SOURCES[@]}"; do
    basen="$(basename "${f}")"
    for fmt in ${formats}; do
      scale_test "${f}" "${fmt}"   1   1 "${md5_yuva[${basen}_${fmt}_0]}" \
        "-pixel_format" "YUVA"
      scale_test "${f}" "${fmt}" 160 120 "${md5_yuva[${basen}_${fmt}_1]}" \
        "-pixel_format" "YUVA"
      scale_test "${f}" "${fmt}" 640 480 "${md5_yuva[${basen}_${fmt}_2]}" \
        "-pixel_format" "YUVA"
      scale_test "${f}" "${fmt}"  15 240 "${md5_yuva[${basen}_${fmt}_3]}" \
        "-pixel_format" "YUVA"
      scale_test "${f}" "${fmt}" 701 701 "${md5_yuva[${basen}_${fmt}_4]}" \
        "-pixel_format" "YUVA"
      scale_test "${f}" "${fmt}"   2   2 "${md5_yuva[${basen}_${fmt}_5]}" \
        "-pixel_format" "YUVA"
    done
  done
}

echo "Running scale tests for ${TARGET}."

ARTIFACTS_DIR="$(ensure_artifacts "${BUILD_DIR}")"
BUILD_TYPE=${1:?"Build type not defined.$(
  echo
  usage
)"}
TARGET=${2:?"Target not defined.$(
  echo
  usage
)"}

readonly BUILD_DIR="${WORKSPACE}/build-${BUILD_TYPE}"
ARTIFACTS_DIR="$(ensure_artifacts "${BUILD_DIR}")"
readonly ARTIFACTS_DIR
TEST_DATA_DIR="$(ensure_libwebp_dependency_repo "${LIBWEBP_TEST_DATA_REPO}")"
readonly TEST_DATA_DIR

SOURCES=("${TEST_DATA_DIR}/vp80-03-segmentation-1414.webp")
SOURCES+=("${TEST_DATA_DIR}/lossless1.webp")

case "${TARGET}" in
  reduce-csp*)
    formats="pam pgm"
    ;;
  *)
    formats="pgm ppm pam yuv"
    ;;
esac

pushd "${ARTIFACTS_DIR}"

find_artifacts="$(find "${ARTIFACTS_DIR}" -name 'dwebp' -o -name 'dwebp.exe')"
DECODE_WEBP_BINARIES=()
while IFS='' read -r line; do
  DECODE_WEBP_BINARIES+=("${line}")
done < <(echo "${find_artifacts}")

for dwebp in "${DECODE_WEBP_BINARIES[@]}"; do
  perl_strip='/dwebp.*\.gcda/ or next; print scalar(split /\//) - 4; last;'
  # strip up to 'build-static'
  GCOV_PREFIX_STRIP="$(strings "${dwebp}" | perl -ne "${perl_strip}")"
  # set both for compatibility with clang.
  export GCOV_PREFIX_STRIP
  export GCOV_PREFIX="${ARTIFACTS_DIR}"
  exe="$(get_driver "${TARGET}" "${dwebp}")"
  if [[ -n "${exe}" ]]; then
    case "${TARGET}" in
      i686-linux-gnu | x86_64-linux-gnu)
        debian_suppresion="/usr/lib/valgrind/debian.supp"
        if [[ -f "${debian_suppresion}" ]]; then
          valgrind="valgrind --malloc-fill=0xcc"
          valgrind="${valgrind} --suppressions=${debian_suppresion}"
          valgrind="${valgrind} --error-exitcode=1"
        else
          valgrind="valgrind --malloc-fill=0xcc"
          valgrind="${valgrind} --suppressions=/usr/lib/valgrind/default.supp"
          valgrind="${valgrind} --error-exitcode=1"
        fi
        exe="${valgrind} ${exe}"
        ;;
      *) ;;  # Skip configuration.
    esac

    total_tests=0
    for run_test in "${SCALE_TESTS[@]}"; do
      if shard_should_run; then
        echo "Run ${run_test} on shard ${TEST_SHARD_INDEX}"
        ${run_test}
        : $((total_tests += 1))
      fi
    done
  fi
done

date
echo "Run ${total_tests:=0} in shard ${TEST_SHARD_INDEX}."
popd
