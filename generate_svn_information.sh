#!/usr/bin/env bash


rootDir=$(svn info 2> /dev/null | awk '/^Working Copy Root Path:/ {print $NF}')
if [ -z "$rootDir" ]; then
    >&2 echo "This is not a subversion repository."
    return
fi

# Go to the repository root dir; trunk/ if it exists
cd "$rootDir"
if [ -d "trunk" ]; then
    \cd "trunk"; fi

# Parse output from svn info -R
# Order of strings filtered for:
# 1. Path
# 2. Revision
# 3. Node Kind
# 4. Checksum
#if [ $(which awk) ]; then
if [ 0 == 1 ]; then
    # pure awk version (faster)
    \svn info -R | \awk '
        BEGIN {

            printf "%-6s  %-40s  %s\n", "Rev.", "MD5 checksum", "File in repository"

            numFiles = 0
            isFile = 0

            oldestRev = -log(0)
            oldestFile = ""
            isOldest = 1

            pth = ""
            rev = 0
        }
        {
            if ($1 == "Path:") {
                pth = $2
                isFile = 1
            }
            else if ($1 == "Revision:") {
                rev = $2
                if (rev < oldestRev){
                    isOldest = 1
                    oldestRev = rev
                }
            }
            else if ($1 == "Node Kind:") {
                if ($2 != "file")
                    isFile = 0
            }
            else if ($1 == "Checksum:") {
                if (isFile) {
                    printf "%-6s  %-40s  %s\n", rev, $2, pth
                    numFiles++
                    if (isOldest) {
                        isOldest = 0
                        oldestFile = pth
                    }
                }
            }
        }

        END {
            printf "\nTotal number of files: %d\nOldest file (%d): %s\n", numFiles, oldestRev, oldestFile
        }
    '
else
    # pure bash version (slower)
    declare -a svn_output
    declare i IFS_old

    IFS_old="$IFS"; IFS=$'\n'

    svn_output=($(\svn info -R | \grep "^\(Node Kind:\|Revision:\|Checksum:\|Path:\)" | cut -d ":" -f 2-) )
    for (( i=0; i<${#svn_output[@]}; i+=4 )); do
        if [ "${svn_output[(($i+3))]}" == " file" ]; then
            printf "%-6s  %-40s  %s\n" \
                "${svn_output[(($i+1))]}" \
                "${svn_output[(($i+3))]}" \
                "${svn_output[(($i))]}";
        fi
    done

    IFS="$IFS_old"
fi

