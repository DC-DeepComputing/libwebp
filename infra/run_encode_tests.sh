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
                i686-linux-clang
                i686-w64-mingw32
                x86_64-linux-clang
                x86_64-w64-mingw32
  Environment variables:
  WORKSPACE directory where the binaries are located in WORKSPACE/artifacts.
EOF
}

# Declared decode tests.
ENCODE_TESTS=(
  "encode_test   0  25 100 0 6"
  "encode_test   0  25 100 0 6 --mt"
  "encode_test   0  25 100 0 6 --noalpha"
  "encode_test   0  25  75 0 6 --lossless"
  "encode_test   0  25  75 0 4 --lossless --noalpha"
  "encode_test 100 100   1 5 5 --lossless --noalpha"
  "encode_test 100 100   1 6 6 --lossless"
  "encode_test 100 100   1 5 5 --lossless --noalpha"
  "encode_test 100 100   1 6 6 --lossless --noalpha"
  "encode_test 100 100   1 6 6 --lossless --noalpha"
  "decode_tmpfile   0  25 100 0 6"
  "decode_tmpfile   0  25 100 0 6 --mt"
  "decode_tmpfile   0  25 100 0 6 --noalpha"
  "decode_tmpfile   0  25  75 0 4 --lossless"
  "decode_tmpfile   0  25  75 0 4 --lossless --noalpha"
  "decode_tmpfile 100 100   1 5 5 --lossless"
  "decode_tmpfile 100 100   1 6 6 --lossless"
  "decode_tmpfile 100 100   1 5 5 --lossless --noalpha"
  "decode_tmpfile 100 100   1 6 6 --lossless --noalpha"
)

#######################################
# Runs encode test
# Globals:
#   ENCODE_LOGS log.txt file
# Arguments:
#   $1 file
#   $2 tmpfile to decode
#   extra options
# Outputs:
#   test outputs
#######################################
do_encode() {
  local f="$1"
  local tmpfile="$1"
  shift 2

  rm -f log.txt
  ${exe} "$@" -o "${tmpfile}" "${f}" -exact -print_psnr 2>&1 | tee log.txt
  sync
  cwebp_psnr=$(awk '/Total:/ {print $NF}' "log.txt" | cut -d: -f2)
  disto_psnr=$(${get_disto} "${tmpfile}" "${f}" | awk '{print $2}')
  if echo "$@" | grep -q -- "-lossless" \
    && ! echo "$@" | grep -q -- "-noalpha"; then
    perl -e "${cwebp_psnr} == 99.00 or exit 1"
    perl -e "${disto_psnr} == 99.00 or exit 1"
  fi
}

#######################################
# Filters out test depending on conditions.
# Globals:
#   BUILD_TYPE supported build
#   TARGET supported target platform
# Arguments:
#   $1 test type
#   $2 q
#   $3 m
# Returns:
#   0 to filter in, else filter out
#######################################
filter_test() {
  local type="${1// /_}"
  local q="$2"
  local m="$3"
  local ret=0

  case "${BUILD_TYPE}:${q}:${m}" in
    static-debug:0:4 | static-debug:75:4) ;;

    static-debug:*)
      ret=1
      ;;
    *) ;;  # Skip configuration
  esac

  case "${type}:${q}:${m}" in
    *:100:1 | *:100:2 | *:100:4 | *:100:5)
      ret=1
      ;;
    *:25:0 | *:25:6 | *:50:0 | *:50:6)
      ret=0
      ;;
    *:25:* | *:50:*)
      ret=1
      ;;
    *:*:1 | *:*:2 | *:*:3 | *:*:5)
      ret=1
      ;;
    *) ;; # Skip configuration
  esac
  case "${TARGET}" in
    mips2el-linux-gnu | mips32el-linux-gnu | mips32r2el-linux-gnu | \
      mips32dspr2el-linux-gnu |   mips32eb-linux-gnu | \
      arm-linux-gnueabi |   arm-neon-linux-gnueabi)
      case "${ret}:${type}:${q}:${m}" in
        0:encode_test_0*:75:4 | 0:encode_test_0*:75:6) ;;
        0:*:75:0 | 0:*:75:4) ;;
        *) ret=1 ;;
      esac
      ;;
    *) ;;  # Skip configuration
  esac
  case "${TARGET}" in
    x86_64* | i686*) ;;
    *)
      case "${type}" in
        encode6 | encode8)
          ret=1
          ;;
        *) ;;  # Skip configuration
      esac
      ;;
  esac
  return "${ret}"
}

#######################################
# Runs lossless decode test suite
# Globals:
#   TEST_LOSSLESS lossless test script found in TEST_DATA_DIR.
#   TEST_LOSSY lossy test script found in TEST_DATA_DIR.
# Arguments:
#   $1 q seq begin
#   $2 q seq end
#   $3 q seq increment
#   $4 m seq begin
#   $5 m seq end
# Outputs:
#   test outputs
#######################################
encode_test() {
    local seq_q
    local seq_m
    local type="encode_test $*"

    seq_q="$(seq "$1" "$2" "$3")"
    seq_m="$(seq "$4" "$5")"
    shift 5

    for f in "${files[@]}"; do
        for q in ${seq_q}; do
            for m in ${seq_m}; do
                filter_test "${type}" "${q}" "${m}" || continue
                "${TEST}" "$@" --exec="${exe}" --extra_args="-q ${q} -m ${m}" \
                  "${f}"
      done
    done
  done
}

#######################################
# Runs decode tmpfile test suite.
# Globals:
#   TEST_LOSSLESS lossless test script found in TEST_DATA_DIR.
#   TEST_LOSSY lossy test script found in TEST_DATA_DIR.
#   files array with test-data files
# Arguments:
#   $1 q seq begin
#   $2 q seq end
#   $3 q seq increment
#   $4 m seq begin
#   $5 m seq end
# Outputs:
#   test outputs
#######################################
decode_tmpfile() {
    local dwebp="${exe/cwebp/dwebp}"
    local get_disto
    local seq_q
    local seq_m
    local tmpfile="tmp.webp"

    get_disto="$(echo "${exe}" | sed -n 's;examples/cwebp;extras/get_disto;g')"
    seq_q="$(seq "$1" "$2" "$3")"
    seq_m="$(seq "$4" "$5")"
    shift 5

    for f in "${files[@]}"; do
        for q in ${seq_q}; do
            for m in ${seq_m}; do
                filter_test "$0" "${q}" "${m}" || continue
                do_encode "${f}" "${tmpfile}" -q "${q}" -m "${m}"
                "${dwebp}" "${tmpfile}"
      done
    done
  done
}

echo "Running encode tests for ${TARGET}."

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

pushd "${ARTIFACTS_DIR}"

ls -R
TEST="${TEST_DATA_DIR}/test_cwebp.sh"
files=()
files+=("${TEST_DATA_DIR}/test.webp")
files+=("${TEST_DATA_DIR}/lossless1.webp")
files+=("${TEST_DATA_DIR}/lossless_color_transform.webp")
files+=("${TEST_DATA_DIR}/lossy_extreme_probabilities.webp")
files+=("${TEST_DATA_DIR}/vp80-02-inter-1412.webp")
files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1431.webp")
files+=("${TEST_DATA_DIR}/vp80-05-sharpness-1443.webp")
files+=("${TEST_DATA_DIR}/grid.pam")
files+=("${TEST_DATA_DIR}/peak.pam")
files+=("${TEST_DATA_DIR}/lossless_color_transform.pam")
files+=("${TEST_DATA_DIR}/grid.ppm")
files+=("${TEST_DATA_DIR}/peak.ppm")
files+=("${TEST_DATA_DIR}/lossless_color_transform.ppm")

find_artifacts="$(find "${ARTIFACTS_DIR}" -name 'cwebp' -o -name 'cwebp.exe')"
ENCODE_WEBP_BINARIES=()
while IFS='' read -r line; do
  ENCODE_WEBP_BINARIES+=("${line}")
done < <(echo "${find_artifacts}")

for cwebp in "${ENCODE_WEBP_BINARIES[@]}"; do
  perl_strip='/cwebp.*\.gcda/ or next; print scalar(split /\//) - 4; last;'
  # strip up to 'build-static'
  GCOV_PREFIX_STRIP="$(strings "${cwebp}" | perl -ne "${perl_strip}")"
  export GCOV_PREFIX_STRIP
  GCOV_PREFIX="$(pwd)"
  export GCOV_PREFIX

  exe="$(get_driver "${TARGET}" "${cwebp}")"

  if [[ -n "${exe}" ]]; then
    total_tests=0
    for run_test in "${ENCODE_TESTS[@]}"; do
      if shard_should_run; then
        echo "Run ${run_test} on shard ${TEST_SHARD_INDEX}"
        ${run_test}
        : $((total_tests += 1))
      else
        echo "Skip ${run_test} on shard ${TEST_SHARD_INDEX}"
      fi
    done
  fi
done

date
echo "Run ${total_tests:=0} in shard ${TEST_SHARD_INDEX}."
popd
