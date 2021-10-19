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
readonly WORKSPACE="${WORKSPACE:-"$(mktemp -d -t webp.sanitizer.XXX)"}"
LIBWEBP_ROOT="$(realpath "$(dirname "$0")/..")"
readonly LIBWEBP_ROOT

# shellcheck source=infra/common.sh
source "${LIBWEBP_ROOT}/infra/common.sh"

usage() {
  cat << EOF
Usage: $(basename "$0") TARGET SANITIZER
Options:
TARGET    supported platforms:
            x86
            x86_64
SANITIZER supported sanitizer:
            address
            cfi
            integer
            thread
            undefined
Environment variables:
WORKSPACE directory where the build is done
EMSDK_DIR directory where emsdk is installed
EOF
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

readonly BUILD_DIR="${WORKSPACE}/build-${TARGET}-${SANITIZER}"

TEST_DATA_DIR="$(ensure_libwebp_dependency_repo "${LIBWEBP_TEST_DATA_REPO}")"

make_build_dir "${BUILD_DIR}"

case "${TARGET}" in
  i686-linux-clang | x86)
    TARGET=i686-linux-gnu
    export CC='clang -m32'
    ;;
  x86_64-linux-clang | x86_64)
    TARGET=x86_64-linux-gnu
    export CC=clang
    ;;
  *)
    usage
    exit 1
    ;;
esac

setup_ccache

cd "${LIBWEBP_ROOT}"
./autogen.sh

grep -m 1 -q 'enable-asserts' configure.ac \
  && config_flags="--enable-asserts"

CFLAGS="-O1 -g -fsanitize=${SANITIZER}"
CFLAGS="${CFLAGS} -fno-omit-frame-pointer -fno-optimize-sibling-calls"
LDFLAGS="-fsanitize=${SANITIZER}"
export LDFLAGS
export CFLAGS

cd "${BUILD_DIR}"
"${LIBWEBP_ROOT}/configure" \
  --host "${TARGET}" --build "$("${LIBWEBP_ROOT}/config.guess")" \
  "${config_flags}"

make -j2 V=1

# Thread and Address Sanitizers
TSAN_OPTIONS=
TSAN_OPTIONS="${TSAN_OPTIONS} halt_on_error=1"
TSAN_OPTIONS="${TSAN_OPTIONS} external_symbolizer_path=${LLVM_SYMBOLIZER}"
export TSAN_OPTIONS

"${TEST_DATA_DIR}/test_dwebp.sh" --exec="${BUILD_DIR}/examples/dwebp" -v --mt
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
