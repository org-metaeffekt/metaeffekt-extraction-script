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

echo "Executing alma-extractor.sh"

# some variables

outDir="/var/opt/metaeffekt/extraction/analysis"

# define some functions

# this function will prepare variables to be used as double-quoted strings in scripts or eval.
escapeStringResult=""
escapeString()
{
  # escape backslash FIRST (since we'll use this to escape)
  escapeStringResult="$(printf %s "${1}" | sed 's/\\/\\\\/g' -)"
  # escape double quote
  escapeStringResult="$(printf %s "${escapeStringResult}" | sed 's/"/\\"/g' -)"
  # escape dollar sign
  escapeStringResult="$(printf %s "${escapeStringResult}" | sed 's/\$/\\\$/g' -)"
  # escape backquote
  escapeStringResult="$(printf %s "${escapeStringResult}" | sed 's/`/\\`/g' -)"
}

# check the input flags

OPTIND=1
OPTSPEC="t:e:"

machineTag=""
findExcludes=""

# posix way to disable pathname expansion
set -f

while getopts "${OPTSPEC}" fopt ; do
  #echo "DEBUG: $fopt . $OPTARG"
  case "${fopt}" in
    t )
      # set, at runtime, a custom machineTag for identification.
      # should only contain the base64 characters and - and _
      machineTag="${OPTARG}"
      ;;
    e )
      # exclude this directory from find command.
      # each path requires its own option.
      # make sure that relative paths start with "./" .

      escapeString "${OPTARG}"
      # prepare string that will later be used with eval
      findExcludes="${findExcludes} -path \"${escapeStringResult}\" -o"
      ;;
    ? )
      exit 1
      ;;
  esac
done

# reenable pathname expansion while we may need it
set +f

# create folder structure in analysis folder (assuming sufficient permissions)
mkdir -p "${outDir}"/package-meta
mkdir -p "${outDir}"/package-files
mkdir -p "${outDir}"/filesystem
mkdir -p "${outDir}"/package-deps

# write machineTag
printf "%s\n" "$machineTag" > "${outDir}"/machine-tag.txt

# disable pathname expansion so find gets the patterns raw
set -f

# exclude some paths by default
# this also acts to finish the last "-o" arg generated by the argument appender.
findExcludes="${findExcludes} -path \"${outDir}/*\" -o -path \"/container-extractors/*\""

# generate list of all files (excluding the analysis folders; excluding symlinks)
# work around shell split / quoting issues by using specially prepared strings and eval.
eval "find / ! \( \( ${findExcludes} \) -prune \) -type f" | sort > "${outDir}"/filesystem/files.txt
eval "find / ! \( \( ${findExcludes} \) -prune \) -type d" | sort > "${outDir}"/filesystem/folders.txt
eval "find / ! \( \( ${findExcludes} \) -prune \) -type l" | sort > "${outDir}"/filesystem/links.txt
# output data with NUL-delimited paths (instead of unreliable newline) as file paths don't contain NUL
eval "find / ! \( \( ${findExcludes} \) -prune \) -type f -print0" | sort > "${outDir}"/filesystem/files_z.bin || true
eval "find / ! \( \( ${findExcludes} \) -prune \) -type d -print0" | sort > "${outDir}"/filesystem/folders_z.bin || true
eval "find / ! \( \( ${findExcludes} \) -prune \) -type l -print0" | sort > "${outDir}"/filesystem/links_z.bin || true

# analyse symbolic links
rm -f "${outDir}"/filesystem/symlinks.txt
touch "${outDir}"/filesystem/symlinks.txt
rm -f "${outDir}"/filesystem/symlinks_z.txt
touch "${outDir}"/filesystem/symlinks_z.txt
filelist=`cat "${outDir}"/filesystem/links.txt`
for file in $filelist
do
  echo "$file --> `readlink $file`" >> "${outDir}"/filesystem/symlinks.txt
  printf "${file}\x00$(readlink $file)\x00\x00" >> "${outDir}"/filesystem/symlinks_z.txt
done

# reenable pathname expansion
set +f

# examine distributions metadata
uname -a > "${outDir}"/uname.txt
cat /etc/issue > "${outDir}"/issue.txt
cat /etc/almalinux-release > "${outDir}"/release.txt || true

# list packages
rpm -qa --qf '| %{NAME} | %{VERSION} | %{LICENSE} |\n' | sort > "${outDir}"/packages_rpm.txt

# list packages names (no version included)
rpm -qa --qf '%{NAME}\n' | sort > "${outDir}"/packages_rpm-name-only.txt

# query package metadata and covered files
packagenames=`cat "${outDir}"/packages_rpm-name-only.txt`
for package in $packagenames
do
  rpm -qi $package > "${outDir}"/package-meta/"${package}"_rpm.txt
  rpm -q glibc --qf "[%{FILENAMES}\n]" | sort > "${outDir}"/package-files/"${package}"_files.txt
  # rpm doesn't support NUL-delimiters in query formats. trust that rpm disallows insane filenames.

  # query package's dependencies. record all types (like weak and backward) of dependencies if possible.
  packageDD="${outDir}/package-deps/${package}"
  mkdir -p "$packageDD"
  rpm -q --requires "$package" > "${packageDD}/requires.txt"
  rpm -q --recommends "$package" > "${packageDD}/recommends.txt"
  rpm -q --suggests "$package" > "${packageDD}/suggests.txt"

  rpm -q --supplements "$package" > "${packageDD}/supplements.txt"
  rpm -q --enhances "$package" > "${packageDD}/enhances.txt"
  rpm -q --provides "$package" > "${packageDD}/provides.txt"
done

# copy resources in /usr/share/doc
mkdir -p "${outDir}"/usr-share-doc/
cp --no-preserve=mode -rf /usr/share/doc/* "${outDir}"/usr-share-doc/ || true

# copy resources in /usr/share/licenses
mkdir -p "${outDir}"/usr-share-licenses/
cp --no-preserve=mode -rf /usr/share/licenses/* "${outDir}"/usr-share-licenses/ || true

# if docker is installed dump the image list
command -v docker > /dev/null && docker images > "${outDir}"/docker-images.txt || true

# if podman is installed, dump the image list (might return the same as docker with present docker -> podman symlinks)
command -v podman > /dev/null && podman images > "${outDir}"/podman-images.txt || true

# adapt ownership of extracted files to match folder creator user and group
chown `stat -c '%u' "${outDir}"`:`stat -c '%g' "${outDir}"` -R "${outDir}"
