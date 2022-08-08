#!/bin/sh

#
# Copyright 2020 metaeffekt GmbH.
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

echo "Executing pfsense-extractor.sh"

outDir="/var/opt/metaeffekt/extraction/analysis"

# check the input flags

OPTIND=1
OPTSPEC="te:"

machineTag=""
findExcludes=""

while getopts "${OPTSPEC}" fopt ; do
  #echo "DEBUG: $fopt . $OPTARG"
  case "${fopt}" in
    t)
      # set, at runtime, a custom machineTag for identification.
      # should only contain the base64 characters and - and _
      machineTag="${OPTARG}"
      ;;
    e)
      # exclude this directory from find command.
      # each path requires its own option.
      # don't forget to quote pathnames (even with glob)!
      findExcludes="${findExcludes} ! -path \"${OPTARG}\""
      ;;
    ?)
      exit 1
      ;;
  esac
done

# create folder structure in analysis folder (assuming sufficient permissions)
mkdir -p "${outDir}"/package-meta
mkdir -p "${outDir}"/package-files
mkdir -p "${outDir}"/filesystem

# write machineTag
printf "%s\n" "$machineTag" > "${outDir}"/machine-tag.txt

# generate list of all files (excluding the analysis folders; excluding symlinks)
find / ! -path "${outDir}/*" ! -path "/container-extractors/*" -type f | sort > "${outDir}"/filesystem/files.txt
find / ! -path "${outDir}/*" ! -path "/container-extractors/*" -type d | sort > "${outDir}"/filesystem/folders.txt
find / ! -path "${outDir}/*" ! -path "/container-extractors/*" -type l | sort > "${outDir}"/filesystem/links.txt

# analyse symbolic links
rm -f "${outDir}"/filesystem/symlinks.txt
touch "${outDir}"/filesystem/symlinks.txt
filelist="$(cat "${outDir}"/filesystem/links.txt)"
for file in $filelist
do
  echo "$file --> `readlink $file`" >> "${outDir}"/filesystem/symlinks.txt
done

# examine distributions metadata
uname -a > "${outDir}"/uname.txt
cat /etc/version > "${outDir}"/release.txt

# list packages
pkg info --all --full -R --raw-format json > "${outDir}"/packages_pkg.json

# list packages names (no version included)
pkg query '%n' | sort > "${outDir}"/packages_pkg-name-only.txt

# query package metadata and covered files
# information is already in packages_pkg.json which includes ALL available information about packages.

# copy resources in /usr/share/doc
mkdir -p "${outDir}"/usr-share-doc/
cp -rf /usr/share/doc/* "${outDir}"/usr-share-doc/ || true

# copy resources in /usr/share/licenses
mkdir -p "${outDir}"/usr-share-licenses/
cp -rf /usr/local/share/licenses/* "${outDir}"/usr-share-licenses/ || true

# if docker is installed dump the image list
# this SHOULD NEVER WORK on pfSense! let's test anyway.
command -v docker && docker images > "${outDir}"/docker-images.txt || true

# adapt ownership of extracted files to match folder creator user and group
chown -R `stat -f '%u' "${outDir}"`:`stat -f '%g' "${outDir}"` "${outDir}"
