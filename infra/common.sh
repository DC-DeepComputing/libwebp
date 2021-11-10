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

export LIBWEBP_TEST_DATA_REPO="https://chromium.googlesource.com/webm/libwebp-test-data"

log_err() {
  local date_fmt
  date_fmt="$(date +'%Y-%m-%dT%H:%M:%S%z')"
  echo "[${date_fmt}]: $*" >&2
}

#######################################
# Create build directory. Build directory will be deleted if it exists.
# Arguments:
#   $1 build directory's path
# Returns:
#   mkdir result.
#######################################
make_build_dir() {
  if [[ "$#" -ne 1 ]]; then
    return 1
  fi

  local build_dir
  build_dir="$1"
  rm -rf "${build_dir}"
  mkdir -p "${build_dir}"
}

#######################################
# Cleanup files from the build directory.
# Globals:
#   LIBWEBP_ROOT repository's root path.
# Arguments:
#   $1 build directory.
#######################################
cleanup() {
  # $1 is not completely removed to allow for binary artifacts to be
  # extracted.
  find "${1:?"Build directory not defined"}" \
    \( -name "*.[ao]" -o -name "*.l[ao]" \) -exec rm -f {} +
}

#######################################
# Setup ccache for toolchain.
# Globals:
#   PATH
# Arguments:
#   None
#######################################
setup_ccache() {
  local command_ccache
  command_ccache="$(command -v ccache)"
  if [[ -x "${command_ccache}" ]]; then
    export CCACHE_CPP2=yes
    export PATH="/usr/lib/ccache:${PATH}"
  fi
}

#######################################
# Detects whether test block should be run in the current test shard.
# Globals:
#   TEST_TOTAL_SHARDS: Valid range: [1, N]. Defaults to 1.
#   TEST_SHARD_INDEX: Valid range: [0, TEST_TOTAL_SHARDS). Defaults to 0.
#   libwebp_test_id: current test number; incremented with each call.
# Arguments:
#   None
# Returns:
#   true if the shard is active
#   false if the shard is inactive
#######################################
shard_should_run() {
  TEST_TOTAL_SHARDS=${TEST_TOTAL_SHARDS:=1}
  TEST_SHARD_INDEX=${TEST_SHARD_INDEX:=0}
  libwebp_test_id=${libwebp_test_id:=-1}
  : $((libwebp_test_id += 1))

  if [[ "${TEST_SHARD_INDEX}" -lt 0 ||
    "${TEST_SHARD_INDEX}" -ge "${TEST_TOTAL_SHARDS}" ]]; then
    log_err "Invalid TEST_SHARD_INDEX (${TEST_SHARD_INDEX})!" \
      "Expected [0, ${TEST_TOTAL_SHARDS})."
  fi

  [[ "$((libwebp_test_id % TEST_TOTAL_SHARDS))" -eq "${TEST_SHARD_INDEX}" ]]
}

#######################################
# Ensures libwebp's dependency repository is setup.
# Globals:
#  WORKSPACE directory where the build is done
# Arguments:
#  $1 repository url
# Outputs:
#  Path to repo
#######################################
ensure_libwebp_dependency_repo() {
  local repo_url
  repo_url="$1"
  local repo_dir
  repo_dir="${WORKSPACE:?WORKSPACE is not defined.}/${repo_url##*/}"

  if [[ ! -d "${repo_dir}" ]] \
    || ! git -C "${repo_dir}" pull > /dev/null; then
    rm -rf "${repo_dir}"
    git clone --depth 1 "${repo_url}" "${repo_dir}"
  fi
  echo "${repo_dir}"
}

#######################################
# Ensure test artifacts are in WORKSPACE/artifacts.
# Globals:
#  WORKSPACE directory where the build is done.
# Arguments:
#   $1 build directory's path
#   $2 supported target platform
# Outputs:
#   artifacts directory
# Returns:
#   0 when artifacts' dir is created/found
#   non-zero for errors.
#######################################
ensure_artifacts() {
  local build_dir="$1"
  local target="$2"
  local artifacts_dir="${WORKSPACE}/artifacts"

  if [[ "$#" -ne 2 ]]; then
    return 1
  fi

  if [[ ! -d "${artifacts_dir}" ]]; then
    make_build_dir "${artifacts_dir}"

    cp "${build_dir}/examples/"[cd]webp* "${artifacts_dir}"
    cp "${build_dir}/extras/"get_disto* "${artifacts_dir}"
  fi

  # only the recently added cmake config should ever have no artifacts
  empty_artifacts="$(ls "${artifacts_dir}")"
  case "${target}" in
    cmake | wasm)
      [[ -z "${empty_artifacts}" ]] && exit 0
      ;;
    reduce-size | disable-stats | reduce-size-disable-stats | reduce-csp)
      [[ -z "${empty_artifacts}" ]] && exit 0
      ;;
    *) ;;  # Skip configuration
  esac

  echo "${artifacts_dir}"
}

#######################################
# Get driver to run cross-platform tests.
# Arguments:
#   $1 target host
#   $2 target binary
# Outputs:
#   command executable (i.e. wine webp.exe)
# Returns:
#   non-zero when target host is not supported
#######################################
get_driver() {
  local exe
  case "$1" in
    *-w64-mingw32) exe="wine" ;;
    aarch64-linux-*)
      exe="qemu-aarch64 -L /usr/aarch64-linux-gnu"
      ;;
    arm-linux-gnueabi | arm-neon-linux-gnueabi)
      exe="qemu-arm -L /usr/arm-linux-gnueabi"
      ;;
    disable-near-lossless | disable-sse4.1 | disable-stats) ;;
    visibility-*) ;;
    i686-linux-* | x86_64-linux-*) ;;
    cmake | wasm) ;;
    reduce-size | reduce-size-disable-stats | reduce-csp) ;;
    *) return 1 ;;  # Unsupported target host.
  esac
  echo "${exe:+${exe} }$2"
}
