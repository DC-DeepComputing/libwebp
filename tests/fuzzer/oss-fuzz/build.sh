#!/bin/bash
# Copyright 2018 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

set -eu

# limit allocation size to reduce spurious OOMs
WEBP_CFLAGS="$CFLAGS -DWEBP_MAX_IMAGE_SIZE=838860800" # 800MiB

export CFLAGS="$WEBP_CFLAGS"
cmake -S . -B build -DWEBP_BUILD_FUZZTEST=ON
cd build && make -j$(nproc) && cd ..

find $SRC/libwebp-test-data -type f -size -32k -iname "*.webp" \
  -exec zip -qju fuzz_seed_corpus.zip "{}" \;

fuzzer_list=`find ./build/tests/fuzzer/ -executable -type f`

for fuzzer in "${fuzzer_list}"; do
  cp ${fuzzer} $OUT/
done

for fuzzer in "${fuzzer_list}"; do
  fuzzer_name=`basename ${fuzzer}`
  cp fuzz_seed_corpus.zip $OUT/${fuzzer_name}_seed_corpus.zip
  cp tests/fuzzer/fuzz.dict $OUT/${fuzzer_name}.dict
done
