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

# create folder structure in analysis folder (assuming sufficient permissions)
mkdir -p /analysis/package-meta
mkdir -p /analysis/package-files
mkdir -p /analysis/filesystem

# generate list of all files (excluding the analysis folders; excluding symlinks)
find / ! -path "/analysis/*" ! -path "/container-extractors/*" -type f | sort > /analysis/filesystem/files.txt
find / ! -path "/analysis/*" ! -path "/container-extractors/*" -type d | sort > /analysis/filesystem/folders.txt
find / ! -path "/analysis/*" ! -path "/container-extractors/*" -type l | sort > /analysis/filesystem/links.txt

# analyse symbolic links
rm -f /analysis/filesystem/symlinks.txt
touch /analysis/filesystem/symlinks.txt
set filelist="$(cat /analysis/filesystem/links.txt)"
for file in $filelist
do
  echo "$file --> `readlink $file`" >> /analysis/filesystem/symlinks.txt
done

# examine distributions metadata
uname -a > /analysis/uname.txt
cat /etc/version > /analysis/release.txt

# list packages
pkg info --all --full -R --raw-format json > /analysis/packages_pkg.json

# list packages names (no version included)
pkg query '%n' | sort > /analysis/packages_pkg-name-only.txt

# query package metadata and covered files
# information is already in packages_pkg.json which includes ALL available information about packages.

# copy resources in /usr/share/doc
mkdir -p /analysis/usr-share-doc/
cp -rf /usr/share/doc/* /analysis/usr-share-doc/ || true

# copy resources in /usr/share/licenses
mkdir -p /analysis/usr-share-licenses/
cp -rf /usr/local/share/licenses/* /analysis/usr-share-licenses/ || true

# if docker is installed dump the image list
# this SHOULD NEVER WORK on pfSense! let's test anyway.
command -v docker && docker images > /analysis/docker-images.txt || true

# adapt ownership of extracted files to match folder creator user and group
chown -R `stat -f '%u' /analysis`:`stat -f '%g' /analysis` /analysis
