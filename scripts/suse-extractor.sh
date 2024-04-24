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

echo "Executing suse-extractor.sh"

# some variables
# outDir MUST NOT end in space or newline characters due to how this script functions
outDir="/var/opt/metaeffekt/extraction/analysis"

# define required functions
# BEGIN INCLUSION (portable)

# Here goes stuff that's portable between (most) distributions.
# Stuff that's specific to a package-manager should probably be sourced separately.

# this function will prepare variables to be used as double-quoted strings in scripts or eval.
# the reason we use a global variable to return is so spaces aren't automagically trimmed by shells.
escapeStringResult=""
escapeString()
{
  printf "string to escape: '%s'\n" "${1}"
  # escape backslash FIRST (since we'll use this to escape)
  escapeStringResult="$(printf %s "${1}" | sed 's/\\/\\\\/g' -)"
  # escape double quote
  escapeStringResult="$(printf %s "${escapeStringResult}" | sed 's/"/\\"/g' -)"
  # escape dollar sign
  escapeStringResult="$(printf %s "${escapeStringResult}" | sed 's/\$/\\\$/g' -)"
  # escape backquote
  escapeStringResult="$(printf %s "${escapeStringResult}" | sed 's/`/\\`/g' -)"
  printf "string escaped: '%s'\n" "${1}"
}

processArguments() {
  # check the input flags
  OPTIND=1
  OPTSPEC="t:e:u:"

  machineTag=""
  findExcludes=""
  myNonrootUsers=""

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
        printf "findExcludes: %s\n" "${findExcludes}"
        ;;
      u )
        myNonrootUsers="${myNonrootUsers} ${OPTARG}"
        ;;
      ? )
        exit 1
        ;;
    esac
  done

  # reenable pathname expansion while we may need it
  set +f
}

checkFirstArgDefined() {
  # checks that the first argument input to this function is defined (not empty).
  # usually outDir, important to check that it's there so we don't attempt to write into root
  if [ -z "${1}" ] ; then
    printf "%s\n" "outDir (passed to function as \$1) was empty! aborting to not write output to root. This may be a bug."
    exit 1
  fi
}

mkOutputDirs()
{
  checkFirstArgDefined "${1}"
  # create folder structure in analysis folder (assuming sufficient permissions)
  mkdir -p "${1}"/package-meta
  mkdir -p "${1}"/package-files
  mkdir -p "${1}"/filesystem
}

dumpFilepaths()
{
  checkFirstArgDefined "${1}"
  # exclude some paths by default
  # this also acts to finish the last "-o" arg generated by the argument appender.
  local localFindExcludes="${2} -path \"${1}/*\" -o -path \"/container-extractors/*\""
  # generate list of all files (excluding the analysis folders; excluding symlinks)
  # work around shell split / quoting issues by using specially prepared strings and eval.
  eval "find / ! \( \( ${localFindExcludes} \) -prune \) -type f" | sort > "${1}"/filesystem/files.txt
  eval "find / ! \( \( ${localFindExcludes} \) -prune \) -type d" | sort > "${1}"/filesystem/folders.txt
  eval "find / ! \( \( ${localFindExcludes} \) -prune \) -type l" | sort > "${1}"/filesystem/links.txt
  # output data with NUL-delimited paths (instead of unreliable newline) as file paths don't contain NUL
  eval "find / ! \( \( ${localFindExcludes} \) -prune \) -type f -print0" | sort > "${1}"/filesystem/files_z.bin || ( printf "%s\n" "find's -print0 failed on this system. removing files_z.bin" ; rm "${1}"/filesystem/files_z.bin )
  eval "find / ! \( \( ${localFindExcludes} \) -prune \) -type d -print0" | sort > "${1}"/filesystem/folders_z.bin || ( printf "%s\n" "find's -print0 failed on this system. removing folders_z.bin" ; rm "${1}"/filesystem/folders_z.bin )
  eval "find / ! \( \( ${localFindExcludes} \) -prune \) -type l -print0" | sort > "${1}"/filesystem/links_z.bin || ( printf "%s\n" "find's -print0 failed on this system. removing links_z.bin" ; rm "${1}"/filesystem/links_z.bin )
}

analyseSymbolicLinks()
{
  checkFirstArgDefined "${1}"
  # analyse symbolic links
  rm -f "${1}"/filesystem/symlinks.txt
  touch "${1}"/filesystem/symlinks.txt
  while IFS= read -r file
  do
    echo "$file --> `readlink $file`" >> "${1}"/filesystem/symlinks.txt
  done < "${1}"/filesystem/links.txt
  rm -f "${1}"/filesystem/symlinks_z.bin
  touch "${1}"/filesystem/symlinks_z.bin
  while IFS= read -r -d "" file
  do
    printf "%s\x00 --> %s\x00\n" "${file}" "$(readlink "$file")" >> "${1}"/filesystem/symlinks_z.bin
  done < "${1}"/filesystem/links_z.bin
}

dumpDockerIfPresent()
{
  checkFirstArgDefined "${1}"
  # if docker is installed dump the image list
  command -v docker > /dev/null && docker image list --no-trunc --digests > "${1}"/docker-images.txt || true
  command -v docker > /dev/null && docker ps --no-trunc --all > "${1}"/docker-ps.txt || true

  # TODO: list created containers?

  # call runuser variant
  dumpDockerWithDroppedPrivsIfPresent "${1}"
}

dumpDockerWithDroppedPrivsIfPresent()
{
  checkFirstArgDefined "${1}"
  dockerDumpsDir="${1}/docker-images-users"
  # delete the dump dir so that old or failed dumps do not persist
  rm -rf "${1}/docker-images-users"

  if [ "$(command -v docker)" ] && [ ! -z "$myNonrootUsers" ]
  then
    # check if this user really exists, otherwise return an error value
    for myNonrootUser in ${myNonrootUsers}
    do
      userId="id -u ${myNonrootUser}"
      retVal="$?"

      # if we were able to find the user id, execute commands as this user
      if [ ! 0 -eq "${retVal}" ]
      then
        printf "The given non-root user [%s] does not exist. Can't run image/container listing.\n" "${myNonrootUser}"
        continue
      fi

      # check that the user doesn't have an insane name
      if [ "${myNonrootUser#*".."}" != "$myNonrootUser" ] ||
        [ "${myNonrootUser#*"$"}" != "$myNonrootUser" ] ||
        [ "${myNonrootUser#*"/"}" != "$myNonrootUser" ]
      then
        printf "Username [%s] contains potentially dangerous characters. Skipping user in image/container listing.\n" "$myNonrootUser"
        continue
      fi

      dockerUserDumpDir="${dockerDumpsDir}/${myNonrootUser}"

      mkdir -p "${dockerUserDumpDir}"
      retVal="$?"
      if [ ! "${retVal}" -eq 0 ]
      then
        printf "Could not create dump directory [%s] for given non-root user [%s]\n" "${dockerUserDumpDir}"
      fi

      dumpDockerWithDroppedPrivs "${dockerUserDumpDir}" "${myNonrootUser}"
    done
  fi
}

dumpDockerWithDroppedPrivs()
{
  checkFirstArgDefined "${1}"
    if [ -z "${2}" ]
    then
      echo "No user given for docker dump with dropped privileges."
      exit 1
    fi
    if [ ! "$(command -v runuser)" ]
    then
      printf "Executable runuser not installed. Can't dump docker with dropped privileges for user [%s].\n" "${2}"
      return 1
    fi

  runuser -u "${2}" -- docker image list --no-trunc --digests > "${1}"/docker-images-user.txt || true
  runuser -u "${2}" -- docker ps --no-trunc --all > "${1}"/docker-ps-user.txt || true
}

dumpPodmanIfPresent()
{
  checkFirstArgDefined "${1}"
  # if podman is installed, dump the image list (might return the same as docker with present docker -> podman symlinks)
  command -v podman > /dev/null && podman image list --no-trunc --digests > "${1}"/podman-images.txt || true
  command -v podman > /dev/null && podman ps --no-trunc --all > "${1}"/podman-ps.txt || true

  # TODO: list created containers?

  # call runuser variant
  dumpPodmanWithDroppedPrivsIfPresent "${1}"
}

dumpPodmanWithDroppedPrivsIfPresent()
{
  checkFirstArgDefined "${1}"

  podmanDumpsDir="${1}/podman-images-users"
  # delete the dump dir so that old or failed dumps do not persist
  rm -rf "${1}/podman-images-users"

  if [ "$(command -v podman)" ] && [ ! -z "$myNonrootUsers" ]
  then
    # check if this user really exists, otherwise return an error value
    for myNonrootUser in ${myNonrootUsers}
    do
      userId="id -u ${myNonrootUser}"
      retVal="$?"

      # if we were able to find the user id, execute commands as this user
      if [ ! 0 -eq "${retVal}" ]
      then
        printf "The given non-root user [%s] does not exist. Can't run image/container listing.\n" "${myNonrootUser}"
        continue
      fi

      # check that the user doesn't have an insane name
      if [ "${myNonrootUser#*".."}" != "$myNonrootUser" ] ||
        [ "${myNonrootUser#*"$"}" != "$myNonrootUser" ] ||
        [ "${myNonrootUser#*"/"}" != "$myNonrootUser" ]
      then
        printf "Username [%s] contains potentially dangerous characters. Skipping user in image/container listing.\n" "$myNonrootUser"
        continue
      fi

      podmanUserDumpDir="${podmanDumpsDir}/${myNonrootUser}"

      mkdir -p "${podmanUserDumpDir}"
      retVal="$?"
      if [ ! 0 -eq "${retVal}" ]
      then
        printf "Could not create dump directory [%s] for given non-root user [%s]\n" "${podmanUserDumpDir}"
      fi

      dumpPodmanWithDroppedPrivs "${podmanUserDumpDir}" "${myNonrootUser}"
    done
  fi
}

dumpPodmanWithDroppedPrivs()
{
  checkFirstArgDefined "${1}"
  if [ -z "${2}" ]
  then
    echo "No user given for podman dump with dropped privileges."
    exit 1
  fi
  if [ ! "$(command -v runuser)" ]
  then
    printf "Executable runuser missing: can't dump podman with dropped privileges for user [%s].\n" "${2}"
    return 1
  fi

  runuser -u "${2}" -- podman image list --no-trunc --digests > "${1}"/podman-images-user.txt || true
  runuser -u "${2}" -- podman ps --no-trunc --all > "${1}"/podman-ps-user.txt || true
}

adaptOutdirOwnership()
{
  checkFirstArgDefined "${1}"
  # adapt ownership of extracted files to match folder creator user and group
  chown `stat -c '%u' "${1}"`:`stat -c '%g' "${1}"` -R "${1}"
}

checkPortableFunctionsPresent()
{
  # dummy function to fail early if functions where not included correctly
  :
}
# END INCLUSION (portable)

# BEGIN INCLUSION (rpm)

runRpmExtract()
{
  if [ -z "$1" ] ; then
    echo "outDir (passed to function as \$1) was empty! aborting to not write output to root. This may be a bug."
    exit 1
  fi

  local outDir="$1"

  # list packages
  rpm -qa --qf '| %{NAME} | %{VERSION} | %{LICENSE} |\n' | sort > "${outDir}"/packages_rpm.txt

  # list packages names (no version included)
  rpm -qa --qf '%{NAME}\n' | sort > "${outDir}"/packages_rpm-name-only.txt

  # query package metadata and covered files
  packagenames=`cat "${outDir}"/packages_rpm-name-only.txt`
  for package in $packagenames
  do
    rpm -qi "$package" > "${outDir}"/package-meta/"${package}"_rpm.txt
    rpm -q "$package" --qf "[%{FILENAMES}\n]" | sort > "${outDir}"/package-files/"${package}"_files.txt
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
}

checkRpmFunctionsPresent()
{
  # dummy function to fail early if functions where not included correctly
  :
}
# END INCLUSION (rpm)


# check that the libraries are there
checkPortableFunctionsPresent || { echo "missing required portable functions. quitting" 1>&2 ; exit 1; }
checkRpmFunctionsPresent || { echo "missing required rpm functions. quitting." 1>&2 ; exit 1; }

# check the input flags
processArguments "$@"

# create folder structure in analysis folder (assuming sufficient permissions)
mkOutputDirs "${outDir}"
mkdir -p "${outDir}"/package-deps

# write machineTag
printf "%s\n" "$machineTag" > "${outDir}"/machine-tag.txt

# disable pathname expansion so find gets the patterns raw
set -f

# exclude some paths by default
# this also acts to finish the last "-o" arg generated by the argument appender.
findExcludes="${findExcludes} -path \"${outDir}/*\" -o -path \"/container-extractors/*\""

# generate list of all files
dumpFilepaths "${outDir}" "${findExcludes}"

# analyse symbolic links
analyseSymbolicLinks "${outDir}"

# reenable pathname expansion
set +f

# examine distributions metadata
uname -a > "${outDir}"/uname.txt
cat /etc/os-release > "${outDir}"/os-release.txt

runRpmExtract "$outDir"

# copy resources in /usr/share/doc
mkdir -p "${outDir}"/usr-share-doc/
cp --no-preserve=mode -rf /usr/share/doc/* "${outDir}"/usr-share-doc/ || true

# copy resources in /usr/share/licenses
mkdir -p "${outDir}"/usr-share-licenses/
cp --no-preserve=mode -rf /usr/share/licenses/* "${outDir}"/usr-share-licenses/ || true

# if docker is installed dump the image list
dumpDockerIfPresent "${outDir}"

# if podman is installed, dump the image list (might return the same as docker with present docker -> podman symlinks)
dumpPodmanIfPresent "${outDir}"

# adapt ownership of extracted files to match folder creator user and group
adaptOutdirOwnership "${outDir}"
