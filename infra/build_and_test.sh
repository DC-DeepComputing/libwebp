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

set -xe
LIBWEBP_TEST_DATA_REPO="https://chromium.googlesource.com/webm/libwebp-test-data"
readonly LIBWEBP_TEST_DATA_REPO
LIBWEBP_ROOT="$(realpath "$(dirname "$0")/..")"
readonly LIBWEBP_ROOT
readonly WORKSPACE=${WORKSPACE:-"$(mktemp -d -t webp.XXX)"}

# shellcheck source=infra/common.sh
source "${LIBWEBP_ROOT}/infra/common.sh"

usage() {
  cat << EOF
Usage: $(basename "$0") BUILD_TYPE TARGET
Options:
BUILD_TYPE  supported build type: (static, static-debug)
TARGET      supported target platforms:
              i686-w64-mingw32
              x86_64-w64-mingw32
Environment variables:
WORKSPACE   directory where the build is done. If workspace already has
            build-BUILD_TYPE/ or artifacts/, build will be skipped.
EOF
}

#######################################
# Ensure test artifacts are in WORKSPACE/artifacts.
# Globals:
#  BUILD_DIR libwebp build
#  WORKSPACE directory where the build is done
# Arguments:
#  None
# Outputs:
#   artifacts directory
#######################################
ensure_artifacts() {
  local artifacts_dir="${WORKSPACE}/artifacts"
  if [[ -d "${artifacts_dir}" ]]; then
    echo "${artifacts_dir}"
    return 0
  fi

  make_build_dir "${artifacts_dir}"

  case "${BUILD_DIR}" in
    *-debug)
      cp "${BUILD_DIR}/examples/dwebp"* "${artifacts_dir}"
      cp "${BUILD_DIR}/examples/cwebp"* "${artifacts_dir}"
      cp "${BUILD_DIR}/extras/get_disto"* "${artifacts_dir}"
      cp "${BUILD_DIR}/"**/*.gcno "${artifacts_dir}"
      ;;
    *)
      cp "${BUILD_DIR}/examples/dwebp"* "${artifacts_dir}"
      cp "${BUILD_DIR}/examples/cwebp"* "${artifacts_dir}"
      cp "${BUILD_DIR}/extras/get_disto"* "${artifacts_dir}"
      ;;
  esac
  echo "${artifacts_dir}"
}

BUILD_TYPE=${1:?"Build type not defined.$(
  echo
  usage
)"}
TARGET=${2:?"Target not defined.$(
  echo
  usage
)"}

readonly BUILD_DIR="${WORKSPACE}/build-${BUILD_TYPE}"

if [[ -z "${SKIP_BUILD}" ]]; then
  export WORKSPACE
  "${LIBWEBP_ROOT}/infra/compile.sh" static "${TARGET}"
  [[ -d "${BUILD_DIR}" ]] || exit 1
fi

ARTIFACTS_DIR="$(ensure_artifacts)"
TEST_DATA_DIR="$(ensure_libwebp_dependency_repo "${LIBWEBP_TEST_DATA_REPO}")"

DECODE_WEBP_BINARIES=()
while IFS='' read -r line; do
  DECODE_WEBP_BINARIES+=("${line}")
done < <(find "${ARTIFACTS_DIR}" -name 'dwebp' -o -name 'dwebp.exe')

pushd "${ARTIFACTS_DIR}"

echo "Running decode tests for ${TARGET}."
ls -R
TEST_LOSSY="${TEST_DATA_DIR}/test_dwebp.sh"
TEST_LOSSLESS="${TEST_DATA_DIR}/test_lossless.sh"

for dwebp in "${DECODE_WEBP_BINARIES[@]}"; do
  perl_strip='/dwebp.*\.gcda/ or next; print scalar(split /\//) - 4; last;'
  # strip up to 'build-static'
  GCOV_PREFIX_STRIP="$(strings "${dwebp}" | perl -ne "${perl_strip}")"
  export GCOV_PREFIX_STRIP
  exe="$(get_driver "${TARGET}" "${dwebp}")"
  if [[ -n "${exe}" ]]; then
    "${TEST_LOSSY}" -v --exec="${exe}"
    "${TEST_LOSSY}" -v --exec="${exe}" --mt
    "${TEST_LOSSLESS}" -v --exec="${exe}"
  fi
done

date

ENCODE_WEBP_BINARIES=()
while IFS='' read -r line; do
  ENCODE_WEBP_BINARIES+=("${line}")
done < <(find "${ARTIFACTS_DIR}" -name 'cwebp' -o -name 'cwebp.exe')

echo "Running encode tests for ${TARGET}."
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

for cwebp in "${ENCODE_WEBP_BINARIES[@]}"; do
  perl_strip='/cwebp.*\.gcda/ or next; print scalar(split /\//) - 4; last;'
  # strip up to 'build-static'
  GCOV_PREFIX_STRIP="$(strings "${cwebp}" | perl -ne "${perl_strip}")"
  export GCOV_PREFIX_STRIP

  exe="$(get_driver "${TARGET}" "${cwebp}")"

  if [[ -n "${exe}" ]]; then
    for f in "${files[@]}"; do
      "${TEST}" --exec="${exe}" "${f}"
      "${TEST}" --exec="${exe}" --extra_args='-m 6' "${f}"
      "${TEST}" --exec="${exe}" --mt "${f}"
      "${TEST}" --exec="${exe}" --noalpha "${f}"
      "${TEST}" --exec="${exe}" --lossless "${f}"
      "${TEST}" --exec="${exe}" --lossless --noalpha "${f}"
    done
  fi
done

popd
date
