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
              x86_64-w64-mingw3
Environment variables:
WORKSPACE directory where the binaries are located in WORKSPACE/artifacts.
EOF
}

# Declared scale tests.
CROP_TESTS=(
  "test_crop -noasm"
  "test_crop -mt"
)

declare -A md5
LOSSY_ALPHA="lossy_alpha1.webp"
md5["${LOSSY_ALPHA}_pgm_0"]="54f424de170dfd0c5386b07b48052b4b"
md5["${LOSSY_ALPHA}_pgm_1"]="825607daf1e143fddb3103fcd5f5400a"
md5["${LOSSY_ALPHA}_pgm_2"]="0f59cd340e35dfbc68ece77d07f8ddd2"
md5["${LOSSY_ALPHA}_pgm_3"]="e921eaf1c6f2a48c368925e4d0d07840"
md5["${LOSSY_ALPHA}_pgm_4"]="0df9aadfb0d194d212dd88e0296e4305"
md5["${LOSSY_ALPHA}_pgm_5"]="d5fc474844821e8851d8696a4b5968c5"
md5["${LOSSY_ALPHA}_pgm_6"]="54f424de170dfd0c5386b07b48052b4b"
md5["${LOSSY_ALPHA}_pgm_7"]="274ddab85cb5753367d789e0e11ef388"
md5["${LOSSY_ALPHA}_pgm_8"]="1b34a37732a2a651187fb028e9fa3f51"
md5["${LOSSY_ALPHA}_pgm_9"]="7035a201615724ec61978d279cb32f3e"
md5["${LOSSY_ALPHA}_pgm_10"]="377e0accc2f114d16d73bbeb792546db"
md5["${LOSSY_ALPHA}_pgm_11"]="d5fc474844821e8851d8696a4b5968c5"
md5["${LOSSY_ALPHA}_ppm_0"]="6ef3216edc1f2e18728466e901d40ca2"
md5["${LOSSY_ALPHA}_ppm_1"]="ae1fd7ac01fab72244a1158eb5cc18ed"
md5["${LOSSY_ALPHA}_ppm_2"]="fe08142d5e9fafc0526706b290297091"
md5["${LOSSY_ALPHA}_ppm_3"]="dd174f360a15f874b892540fe20f9c1e"
md5["${LOSSY_ALPHA}_ppm_4"]="a42e7355a2e23117d6a1f031a381a001"
md5["${LOSSY_ALPHA}_ppm_5"]="d55a50dcdae537fffed51874d884359f"
md5["${LOSSY_ALPHA}_ppm_6"]="6ef3216edc1f2e18728466e901d40ca2"
md5["${LOSSY_ALPHA}_ppm_7"]="ae1fd7ac01fab72244a1158eb5cc18ed"
md5["${LOSSY_ALPHA}_ppm_8"]="fe08142d5e9fafc0526706b290297091"
md5["${LOSSY_ALPHA}_ppm_9"]="dd174f360a15f874b892540fe20f9c1e"
md5["${LOSSY_ALPHA}_ppm_10"]="a42e7355a2e23117d6a1f031a381a001"
md5["${LOSSY_ALPHA}_ppm_11"]="d55a50dcdae537fffed51874d884359f"
md5["${LOSSY_ALPHA}_pam_0"]="ba4eb59dc40d3ff9c591820a32f908be"
md5["${LOSSY_ALPHA}_pam_1"]="8db1c9dc7a754286c08518dbe6c6f176"
md5["${LOSSY_ALPHA}_pam_2"]="85007ff25acefe7aaa7b63118da6ded3"
md5["${LOSSY_ALPHA}_pam_3"]="f3fbac241d8abd0dea99bd7b9d8bb3c8"
md5["${LOSSY_ALPHA}_pam_4"]="7841336ccf3dcaf377945ce20363b91d"
md5["${LOSSY_ALPHA}_pam_5"]="e13b9f728da8504c3514a58c11bf4f9a"
md5["${LOSSY_ALPHA}_pam_6"]="ba4eb59dc40d3ff9c591820a32f908be"
md5["${LOSSY_ALPHA}_pam_7"]="4ab8f5b5d7fabfb84e911e0f302c0525"
md5["${LOSSY_ALPHA}_pam_8"]="fa7bc8008cdee477cb13c3fcea7e9f57"
md5["${LOSSY_ALPHA}_pam_9"]="713eb0cca057af95b792d257790f00b7"
md5["${LOSSY_ALPHA}_pam_10"]="15fcfa38990f0a2060214f46d2e15bdb"
md5["${LOSSY_ALPHA}_pam_11"]="e13b9f728da8504c3514a58c11bf4f9a"
md5["${LOSSY_ALPHA}_yuv_0"]="ea0405c24181629a407d938c66263029"
md5["${LOSSY_ALPHA}_yuv_1"]="70b558f5612b73f5dcb3495e317e1df4"
md5["${LOSSY_ALPHA}_yuv_2"]="ee98d2e0d550a57ed995750190aa84cb"
md5["${LOSSY_ALPHA}_yuv_3"]="a258373315585a84ba9d21e2912585b0"
md5["${LOSSY_ALPHA}_yuv_4"]="b5f3e1b433669ef14bc5094c9436ad66"
md5["${LOSSY_ALPHA}_yuv_5"]="4fe7c22bcd41174d732e8a924c121059"
md5["${LOSSY_ALPHA}_yuv_6"]="ea0405c24181629a407d938c66263029"
md5["${LOSSY_ALPHA}_yuv_7"]="75133cfe8d3aebf2b28138bf5ebec742"
md5["${LOSSY_ALPHA}_yuv_8"]="072b4d779a18b3fd248b3d84e08f90a7"
md5["${LOSSY_ALPHA}_yuv_9"]="87282738aa7ccafd2c01b1c9d8e1cc79"
md5["${LOSSY_ALPHA}_yuv_10"]="e6b00ba17b2a3f8a06b28f9066ce99ff"
md5["${LOSSY_ALPHA}_yuv_11"]="4fe7c22bcd41174d732e8a924c121059"
md5["lossless1.webp_pgm_0"]="00cf4996af0da0962fd36d981a40b30b"
md5["lossless1.webp_pgm_1"]="10821f9216fe03558a2694f27825cf93"
md5["lossless1.webp_pgm_2"]="336ccff26f63ad13b8a2e243b73c82dc"
md5["lossless1.webp_pgm_3"]="3a65c6f98ebdf2ea45829c7bfe8ae4ce"
md5["lossless1.webp_pgm_4"]="ac01f724151d2562763e2fcbf7219773"
md5["lossless1.webp_pgm_5"]="fc4f51219267163b945d2b12b3e846f4"
md5["lossless1.webp_pgm_6"]="00cf4996af0da0962fd36d981a40b30b"
md5["lossless1.webp_pgm_7"]="10821f9216fe03558a2694f27825cf93"
md5["lossless1.webp_pgm_8"]="336ccff26f63ad13b8a2e243b73c82dc"
md5["lossless1.webp_pgm_9"]="3a65c6f98ebdf2ea45829c7bfe8ae4ce"
md5["lossless1.webp_pgm_10"]="ac01f724151d2562763e2fcbf7219773"
md5["lossless1.webp_pgm_11"]="fc4f51219267163b945d2b12b3e846f4"
md5["lossless1.webp_ppm_0"]="cc2afbc1ea39bf4863af18eff3ce4bed"
md5["lossless1.webp_ppm_1"]="4ac3a471496a8a5613124f483185aadf"
md5["lossless1.webp_ppm_2"]="4e58bcc85b8fbfb51669d1de4ae2f42d"
md5["lossless1.webp_ppm_3"]="1deb73ae98200b518be49ac15696eb9c"
md5["lossless1.webp_ppm_4"]="71896d353f0cff85a9952a9c2942e47b"
md5["lossless1.webp_ppm_5"]="b4ca01153ce161dedd3e473cf311143d"
md5["lossless1.webp_ppm_6"]="cc2afbc1ea39bf4863af18eff3ce4bed"
md5["lossless1.webp_ppm_7"]="4ac3a471496a8a5613124f483185aadf"
md5["lossless1.webp_ppm_8"]="4e58bcc85b8fbfb51669d1de4ae2f42d"
md5["lossless1.webp_ppm_9"]="1deb73ae98200b518be49ac15696eb9c"
md5["lossless1.webp_ppm_10"]="71896d353f0cff85a9952a9c2942e47b"
md5["lossless1.webp_ppm_11"]="b4ca01153ce161dedd3e473cf311143d"
md5["lossless1.webp_pam_0"]="ac734b41024c37d3bec898350161bcc1"
md5["lossless1.webp_pam_1"]="3ca58323ea79824462552f40c0442783"
md5["lossless1.webp_pam_2"]="5c70c490f1b43c67705491fa27b699fa"
md5["lossless1.webp_pam_3"]="47e80a6ec7cfdb9d41ecb473b67e73e3"
md5["lossless1.webp_pam_4"]="70c744b7d290bf972eb281706e136d93"
md5["lossless1.webp_pam_5"]="95f69bfa2b7351d75a8fd399b2b44e3b"
md5["lossless1.webp_pam_6"]="ac734b41024c37d3bec898350161bcc1"
md5["lossless1.webp_pam_7"]="3ca58323ea79824462552f40c0442783"
md5["lossless1.webp_pam_8"]="5c70c490f1b43c67705491fa27b699fa"
md5["lossless1.webp_pam_9"]="47e80a6ec7cfdb9d41ecb473b67e73e3"
md5["lossless1.webp_pam_10"]="70c744b7d290bf972eb281706e136d93"
md5["lossless1.webp_pam_11"]="95f69bfa2b7351d75a8fd399b2b44e3b"
md5["lossless1.webp_yuv_0"]="9a5329df1a15116f8a5e0891470088f3"
md5["lossless1.webp_yuv_1"]="c5f14ee9108d2fe8d10bd4abb61033a6"
md5["lossless1.webp_yuv_2"]="6d662a25b7b112f338af0599b721cc11"
md5["lossless1.webp_yuv_3"]="de152c49fee750bb89acb538e76a3762"
md5["lossless1.webp_yuv_4"]="63bec0df058994af7cccfbe3c4e0fa45"
md5["lossless1.webp_yuv_5"]="17ff736c4272cdc85c7fd04cd2df64cd"
md5["lossless1.webp_yuv_6"]="9a5329df1a15116f8a5e0891470088f3"
md5["lossless1.webp_yuv_7"]="c5f14ee9108d2fe8d10bd4abb61033a6"
md5["lossless1.webp_yuv_8"]="6d662a25b7b112f338af0599b721cc11"
md5["lossless1.webp_yuv_9"]="de152c49fee750bb89acb538e76a3762"
md5["lossless1.webp_yuv_10"]="63bec0df058994af7cccfbe3c4e0fa45"
md5["lossless1.webp_yuv_11"]="17ff736c4272cdc85c7fd04cd2df64cd"

#######################################
# Run single -crop tests.
# Globals:
#   exe executable
# Arguments:
#   $1 file to test
#   $2 --format option
#   $3 x
#   $4 y
#   $5 w
#   $6 h
#   $7 expected md5 hash
# Returns:
#   Returns non-zero when test fails
#######################################
crop_test() {
  local file="$1"
  local fmt="$2"
  local x="$3"
  local y="$4"
  local w="$5"
  local  h="$6"
  local expected_md5="$7"
  shift 7

  # exe and extra options need re-splitting
  # shellcheck disable=SC2068
  actual_md5="$(${exe} "-${fmt}" "${file}" -crop "${x}" "${y}" "${w}" "${h}" \
    -o - $@ \
    | md5sum \
    | cut -d' ' -f1)"
  [[ "${expected_md5}" = "${actual_md5}" ]] || exit 1
  idx=$((idx + 1))
}

#######################################
# Run -crop test suite
# Globals:
#   TEST_SOURCES
# Arguments:
#   extra options
# Output:
#   test outputs
#######################################
test_crop() {
  for f in "${TEST_SOURCES[@]}"; do
    basen="$(basename "${f}")"
    for fmt in ${formats}; do
        declare -i idx=0
        for dither in "" "-alpha_dither"; do
          crop_test "${f}" "${fmt}"   1   1   1   1 \
            "${md5[${basen}_${fmt}_${idx}]}" "$@" "${dither}"
          crop_test "${f}" "${fmt}"   0   0 160 120 \
            "${md5[${basen}_${fmt}_${idx}]}" "$@" "${dither}"
          crop_test "${f}" "${fmt}"  20   0 640 200 \
            "${md5[${basen}_${fmt}_${idx}]}" "$@" "${dither}"
          crop_test "${f}" "${fmt}"   0  30  15 240 \
            "${md5[${basen}_${fmt}_${idx}]}" "$@" "${dither}"
          crop_test "${f}" "${fmt}"  11  11 701 201 \
            "${md5[${basen}_${fmt}_${idx}]}" "$@" "${dither}"
          crop_test "${f}" "${fmt}"  11  11   2   2 \
            "${md5[${basen}_${fmt}_${idx}]}" "$@" "${dither}"
      done
    done
  done
}

echo "Running crop tests for ${TARGET}."

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

TEST_SOURCES=("${TEST_DATA_DIR}/lossy_alpha1.webp")
TEST_SOURCES+=("${TEST_DATA_DIR}/lossless1.webp")

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
    for run_test in "${CROP_TESTS[@]}"; do
      if shard_should_run; then
        echo "Run ${run_test} on shard ${TEST_SHARD_INDEX}"
        ${run_test}
        : $((total_tests += 1))
      fi
    done
  fi
done

echo "Run ${total_tests:=0} tests in shard ${TEST_SHARD_INDEX}."
date
