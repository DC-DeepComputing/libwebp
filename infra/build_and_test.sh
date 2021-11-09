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
readonly WORKSPACE=${WORKSPACE:-"$(mktemp -d -t webp.test.XXX)"}

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
WORKSPACE   directory where the build is done. If workspace already has
            build-BUILD_TYPE/ or artifacts/, build will be skipped.
EOF
}

################################################################################
BUILD_TYPE=${1:?"Build type not defined.$(
  echo
  usage
)"}
TARGET=${2:?"Target not defined.$(
  echo
  usage
)"}

readonly BUILD_DIR="${WORKSPACE}/build-${BUILD_TYPE}"

if [[ ! -d "${BUILD_DIR}" ]]; then
  export WORKSPACE
  "${LIBWEBP_ROOT}/infra/compile.sh" static "${TARGET}"
  [[ -d "${BUILD_DIR}" ]] || exit 1
fi

ARTIFACTS_DIR="$(ensure_artifacts "${BUILD_DIR}")"
TEST_DATA_DIR="$(ensure_libwebp_dependency_repo "${LIBWEBP_TEST_DATA_REPO}")"

find_artifacts="$(find "${ARTIFACTS_DIR}" -name 'dwebp' -o -name 'dwebp.exe')"
DECODE_WEBP_BINARIES=()
while IFS='' read -r line; do
  DECODE_WEBP_BINARIES+=("${line}")
done < <(echo "${find_artifacts}")

pushd "${ARTIFACTS_DIR}"

echo "Running decode tests for ${TARGET}."
ls -R
TEST_LOSSY="${TEST_DATA_DIR}/test_dwebp.sh"
TEST_LOSSLESS="${TEST_DATA_DIR}/test_lossless.sh"

for dwebp in "${DECODE_WEBP_BINARIES[@]}"; do
  perl_strip='/dwebp.*\.gcda/ or next; print scalar(split /\//) - 4; last;'
  # strip up to 'build-static'
  GCOV_PREFIX_STRIP="$(strings "${dwebp}" | perl -ne "${perl_strip}" || true)"
  export GCOV_PREFIX_STRIP
  exe="$(get_driver "${TARGET}" "${dwebp}")"
  if [[ -n "${exe}" ]]; then
    "${TEST_LOSSY}" -v --exec="${exe}"
    "${TEST_LOSSY}" -v --exec="${exe}" --mt
    "${TEST_LOSSLESS}" -v --exec="${exe}"
  fi
done

date

export WORKSPACE
"${LIBWEBP_ROOT}/infra/run_encode_tests.sh" "${BUILD_TYPE}" "${TARGET}"
