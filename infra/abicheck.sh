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
readonly WORKSPACE=${WORKSPACE:-"$(mktemp -d -t webp.XXX)"}
LIBWEBP_ROOT="$(realpath "$(dirname "$0")/..")"
readonly LIBWEBP_ROOT

# shellcheck source=infra/common.sh
source "${LIBWEBP_ROOT}/infra/common.sh"

usage() {
  cat << EOF
Usage: abicheck.sh PREV_VERSION
Options:
PREV_VERSION commit id or ref of previous version. default HEAD~
Environment variables:
WORKSPACE   directory where the build is done
EOF
}

#######################################
# Cleanup files from the all created directories in abidiff.
# Globals:
#   LIBWEBP_ROOT repository's root path
#   HEAD_VERSION current change
#   PREV_VERSION previous change
#######################################
cleanup_abidiff() {
  for commit in ${PREV_VERSION} ${HEAD_VERSION}; do
    cleanup "${WORKSPACE}/build-${commit}"
  done
}

if [[ ! -x "$(command -v abidiff)" ]]; then
  log_err "unable to find abidiff in PATH"
  exit 1
fi

# git repo might checked out 1 branch and the args might use other refs.
git -C "${LIBWEBP_ROOT}" fetch --all

HEAD_VERSION="$(git -C "${LIBWEBP_ROOT}" log --pretty="%h" -1 "${2:-"HEAD"}")"
readonly HEAD_VERSION
PREV_VERSION="$(git -C "${LIBWEBP_ROOT}" log --pretty="%h" -1 "${1:-"HEAD~"}")"
readonly PREV_VERSION

# check for source changes before bothering to run the diff,
# except when a version is forced
git -C "${LIBWEBP_ROOT}" diff --name-only "${PREV_VERSION}" \
  | grep '^src/' \
  || exit 0

echo "Building libwebp abidiff in ${WORKSPACE}"

trap 'cleanup_abidiff' EXIT
setup_ccache

for commit in "${HEAD_VERSION}" "${PREV_VERSION}"; do
  cd "${LIBWEBP_ROOT}"
  git checkout -q "${commit}"
  echo "Building in ${WORKSPACE} $(git log -1)"
  ./autogen.sh

  BUILD_DIR="${WORKSPACE}/build-${commit}"
  make_build_dir "${BUILD_DIR}"
  cd "${BUILD_DIR}"

  "${LIBWEBP_ROOT}/configure" \
    CFLAGS="-g -fvisibility=hidden" \
    --prefix="${BUILD_DIR}/I" \
    --enable-everything
  make -C "${BUILD_DIR}" V=1
  make -C "${BUILD_DIR}" install
done

git -C "${LIBWEBP_ROOT}" checkout -q "${HEAD_VERSION}"
set +e
for lib in "${WORKSPACE}/build-${HEAD_VERSION}/I/lib/"*.so; do
  abidiff "${WORKSPACE}/build-${PREV_VERSION}/I/lib/$(basename "${lib}")" \
    "${lib}" 2>&1
  retcode="$?"

  # ABIDIFF_ERROR sets bit 1
  if [[ $((retcode & 1)) -eq 1 ]]; then
    exit "${retcode}"
  fi

done
