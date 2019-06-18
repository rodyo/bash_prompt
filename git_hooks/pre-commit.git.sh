#!/bin/bash
#

# A git hook script to find and fix trailing whitespace
# in your commits. Bypass it with the --no-verify option
# to git-commit
#
# usage: make a soft link to this file, e.g., ln -s ~/config/pre-commit.git.sh ~/some_project/.git/hooks/pre-commit

# detect platform
platform="win"
uname_result=`uname`
if [ "$uname_result" = "Linux" ]; then
    platform="linux"
elif [ "$uname_result" = "Darwin" ]; then
    platform="mac"
fi

# change IFS to ignore filename's space in |for|
IFS="
"
# autoremove trailing whitespace
for file in `git diff --check --cached | sed '/: trailing whitespace.$/!d' | sed -E 's/:[0-9]+: .*//' | uniq`
do
    # display tips
    echo -e "auto remove trailing whitespace in \033[31m$file\033[0m!"

    # since $file in working directory isn't always equal to $file in
    # index, so we back it up
    mv -f "$file" "${file}.save"

    # discard changes in working directory
    git checkout -- "$file"

    # remove trailing whitespace
    if [ "$platform" = "win" ]; then
        # in windows, `sed -i` adds ready-only attribute to $file
        # (I don't kown why), so we use temp file instead
        sed 's/[[:space:]]*$//' "$file" > "${file}.bak"
        mv -f "${file}.bak" "$file"
    elif [ "$platform" == "mac" ]; then
        sed -i "" 's/[[:space:]]*$//' "$file"
    else
        sed -i 's/[[:space:]]*$//' "$file"
    fi

    git add "$file"

    # restore the $file
    sed 's/[[:space:]]*$//' "${file}.save" > "$file"
    rm "${file}.save"

done
