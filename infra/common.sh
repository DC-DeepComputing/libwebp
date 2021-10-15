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

log_err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Create build directory. Build directory will be deleted if it exists.
# Arguments:
#   None.
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
#   None.
#######################################
setup_ccache() {
  if [[ -x "$(command -v ccache)" ]]; then
    export CCACHE_CPP2=yes
    export PATH="/usr/lib/ccache:${PATH}"
  fi
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
# Get driver to run cross-platform tests.
# Args:
#   $1 target host
#   $2 target binary
# Output:
#   command executable (i.e. wine webp.exe)
#######################################
get_driver() {
  local exe
  case "$1" in
    i686-w64-mingw32 | x86_64-w64-mingw32) exe="wine" ;;
    *) return 1 ;;  # Unsupported target host.
  esac
  echo "${exe} $2"
}
