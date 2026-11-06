#!/usr/bin/env bash

#
# Copyright 2026 metaeffekt GmbH.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This script works on a per-project basis. For ideal results, the binary output from associated conan runs should
# be the exact ones used in the repo (i.e. this script should be fully integrated into a team's actual build pipelines).

set -e

# Commented below are commands to generate required intermediate files.
# In essence, this is just a build including `-f json --out-file conan_install_out.json`.
# The python script will use this to create "repackaged" artifacts
# (complete enough to be used for compliance work) from a populated
# (local) conan cache (expected to have been filled by the build).
# Unfortunately, this means we need output from an actual, successful build.
# Conan isn't helpful about gathering all this stuff with sufficient precision.
# It natively seems to drop potentially important details like package_id and prev.
# You SHOULD be properly connected to your internal artifactory binary caches,
# otherwise output may not be consistent or reusable.
# Note that this is a real build, and it may take a while.

# For below commands, one MUST adjust requires, profile and potentially other environment configs.
# If you have a "remote" configured that holds your recipes, use something like
# this example command (derived from testing with recipe "ros-conan"):
: '
conan install \
    -c tools.build:download_source=True \
    --requires=ros-kilted/2026.06.17 \
    --profile=ros-conan/profiles/ros \
    -o ros-kilted/*:variant=desktop \
    --build=missing \
    -f json --out-file conan_install_out.json
'
# The following command is derived from my tests with recipes for "gerbera".
# If you have a local directory to build with, use:
: '
conan install \
    -c tools.build:download_source=True \
    --profile=path-to-my-build-profile\
    --build=missing\
    -f json --out-file conan_install_out.json\
    .
'
# ... where you may replace the dot to point to your conanfile.


# Quick summary of the output directory structure:
# output_dir_name - root of the output for this run of the extraction script
# output_dir_name/metadata - general metadata files, examples: parts of conan's config, graphs, package lists
# output_dir_name/repackaged - re-packaged packages; actual package data, can later be used for code / binary scanning

# The conan and python3 executables to use. We'll default to those on PATH for now.
conan_executable="conan"
python_executable="python3"
ae_python_script_location="aggregate-conan-project.py"

if [ -z "$1" ];
then
  >&2  printf 'need reference to the "input_graph.json"\n'
  >&2  printf 'usage: ./[script.sh] [input graph json]\n'
fi

# verify commands
echo "checking commands..."
printf '"conan version: %s\n' "$("$conan_executable" --version)"
# shellcheck disable=SC2016
printf '"python version: %s\n' "$("$python_executable" --version)"

# create output dir
echo "preparing vars for target dir..."
uuid="$("$python_executable" -c 'import uuid; print(uuid.uuid4())')"
date_for_filename="$(date -u +"%Y-%m-%dT%H:%M:%SZ" | sed 's/:/_/g')"
output_dir="conan_artifact_export_${date_for_filename}_${uuid}"
repackaged_dir="$output_dir"/repackaged
meta_dir="$output_dir"/metadata

printf 'creating output dir at [%s]\n' "$output_dir"
mkdir -p "$output_dir"
mkdir "$repackaged_dir"
mkdir "$meta_dir"

# copying input graph into the dir
input_copied_to_output_dir="$meta_dir"/input_graph.json
cp "$1" "$input_copied_to_output_dir"

# generate auxiliary files
echo "generating auxiliary files with conan..."
conan_list_output="$meta_dir"/conan_list_from_input_graph.json
echo " - conan list"
"$conan_executable" list --graph="$input_copied_to_output_dir" --format=json > "$conan_list_output"
echo " - conan remote list"
conan_remotes_dump_output="$meta_dir"/conan_remote_list.json
"$conan_executable" remote list --format=json --out-file "$conan_remotes_dump_output"

# pass it the file generated from your conan install command.
# this will generate compliance artifacts.
echo "running python script to do repackaging of packages found in the graph..."
"$python_executable" "$ae_python_script_location" "$1" "$repackaged_dir"
echo "python script returned."

# Package the results; uncomment to activate
# tar -c "$output_dir" | zstd -9 -T0 - -o "conan_artifact_export".tar.zst
