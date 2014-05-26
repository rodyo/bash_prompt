# TODO: put the repository aliases in an associative array
# TODO: find proper workaround for bash v. < 4

# TODO: profile everything (multicolumn ls) and find ways to make it  faster!



# --------------------------------------------------------------------------------------------------
# Create global associative arrays
# --------------------------------------------------------------------------------------------------

declare -A REPO_COLOR
declare -A ALL_COLORS

# USE_COLORS
USE_COLORS=
if [ "yes" == "$SHELL_COLORS" ]; then
    USE_COLORS=1

    IFS_=$IFS; IFS=": "
    tmp=($LS_COLORS)
    IFS=$IFS_

    keys=("${tmp[@]%%=*}")
    keys=(${keys[@]/\*\./})
    values=(${tmp[@]##*=})

    for ((i=0; i<${#keys[@]}; ++i)); do
        ALL_COLORS["${keys[$i]}"]="${values[$i]}"; done

    unset tmp keys values
fi

# Repository info and generic commands
REPO_MODE=false;       REPO_TYPE=""
REPO_PATH=

# colors used for different repositories in prompt/prettyprint
REPO_COLOR[svn]="\033[01;35m";    REPO_COLOR[CVS]="\033[43;30";
REPO_COLOR[git]="\033[01;31m";    REPO_COLOR[hg]="\033[01;36m";
REPO_COLOR[bzr]="\033[01;33m";



# --------------------------------------------------------------------------------------------------
# Execute things in current dir when command is not found
# --------------------------------------------------------------------------------------------------
command_not_found_handle()
{
    # shell scripts
    ([[ -f "${1}.sh" && -x "${1}.sh" ]] && "./${1}.sh") ||

    # other things
    ([[ -f "${1}" && -x "${1}" ]] && "./${1}") ||

    # not found
    echo "Command not found."
}


# --------------------------------------------------------------------------------------------------
# Multicolumn colored filelist
# --------------------------------------------------------------------------------------------------

# TODO: field width of file size field can be a bit more flexible
#   (e.g., we don't ALWAYS need 7 characters...but: difficult if you want to get /dev/ right)
# TODO: show [seq] and ranges for simple sequences, with min/max file size

# FIXME: seems that passing an argument does not work properly
# FIXME: breaks when upgrading to Ubuntu 14.04???

multicolumn_ls()
{


# PROFILING
#PS4='+ $(date "+%s.%N")\011 '
#exec 3>&2 2>/tmp/bashstart.$$.log
#set -x


    # preferences
    local maxColumnWidth=35
    local minLines=15

    # derived quantities & declarations
    local numColumns=$(($COLUMNS/$maxColumnWidth))
    local maxNameWidth=$(($maxColumnWidth-10))
    local IFS_=$IFS;

    # get initial file, as stripped down as possible, but including the file sizes.
    # NOTE: arguments to multicolumn_ls() get appended behind the base ls command
    IFS=$'\n'
    local dirlist=($(command ls -opgh --group-directories-first --time-style=+ --si "$@"))

    # also get the file attribute list (for filesystems that are known to work)
    # FIXME: the order of the output of lsattr is different than that of ls.
    # the elements in the attributes array will therefore not correspond to the elements in the ls array...
    local haveAttrlist=0
    case $(find . -maxdepth 0 -printf %F) in
        ext2|ext3|ext4) haveAttrlist=1 ;;
        # TODO: also cifs and fuse.sshfs etc. --might--support it, but how to check for this...
    esac

    ( ((${BASH_VERSION:0:1}>=4)) && command -v lsattr && if [ $haveAttrlist ]; then
        local attrlist
        local attlist=($(lsattr 2>&1))
        local attribs=($(echo "${attlist[*]%% *}"))
        local attnames=($(echo "${attlist[*]##*\.\/}"))
        for ((i=0; i<${#attnames[@]}; i++)); do
            if [ ${attribs[$i]%%lsattr:*} ]; then
                printf -v "attrlist_${attnames[$i]}" %s "${attribs[$i]}"; fi
        done
        unset attnames attribs attlist
    fi) || haveAttrlist=

    # check if any of the arguments was a "file" (and not just an option)
    local haveFiles=false
    for ((i=0; i<$#; ++i)); do
        if [ -e "$1" ]; then
            haveFiles=true
            break;
        fi
        shift
    done

    # get "total: XXk" line
    local firstline=
    if [ $haveFiles == false ]; then
        firstline="${dirlist[0]}"
        unset dirlist[0]
    fi

    # Compute number of rows to use (equivalent to ceil)
    local numRows=$(( (${#dirlist[@]}+$numColumns-1)/$numColumns ))
    if [ $numRows -lt $minLines ]; then
        numRows=$minLines; fi

    # Split dirlist up in permissions, filesizes, names, and extentions
    local perms=($(printf '%s\n' "${dirlist[@]}" | awk '{print $1}'))
    local sizes=($(printf '%s\n' "${dirlist[@]}" | awk '{print $3}'))
    # NOTE: awkward yes, but the only way to get all spaces etc. right under ALL circumstances
    local names=($(printf '%s\n' "${dirlist[@]}" | awk '{for(i=4;i<=NF;i++) $(i-3)=$i; if (NF>0)NF=NF-3; print $0}'))
    local extensions
    for ((i=0; i<${#names[@]}; i++)); do
        extensions[$i]=${names[$i]##*\.}
        if [ ${extensions[$i]} == ${names[$i]} ]; then
            extensions[$i]="."; fi
    done

    # Now print the list
    if [ $USE_COLORS ]; then
        printf "\E[0m"; fi

    local lastColumnWidth ind paint device=0 lastColumn=0 lastsymbol=" "
    local n numDirs=0 numFiles=0 numLinks=0 numDevs=0 numPipes=0 numSockets=0

    for ((i=0; i<$numRows; i++)); do
        if [ $i -ge ${#names[@]} ]; then break; fi
        for ((j=0; j<$numColumns; j++)); do

            device=0
            lastColumn=0
            lastsymbol=" "

            ind=$((i+$numRows*j));
            if [ $ind -ge ${#names[@]} ]; then
                break; fi
            if [ $((i+$numRows*((j+1)))) -ge ${#names[@]} ]; then
                lastColumn=1; fi

            # we ARE using colors:
            if [ $USE_COLORS ]; then

                # get type (dir, link, file)
                case ${perms[$ind]:0:1} in

                    # dir, link, port, socket
                    d)  paint="${ALL_COLORS[di]}"; ((numDirs++));;
                    p)  paint="${ALL_COLORS[pi]}"; ((numPipes++));;
                    s)  paint="${ALL_COLORS[so]}"; ((numSockets++));;
                    l)  # check validity of link
                        if [ -L "${names[$ind]%% ->*}" ] && [ ! -e "${names[$ind]%% ->*}" ]; then
                            paint=09\;"${ALL_COLORS[or]}"
                        else
                            paint="${ALL_COLORS[ln]}"
                        fi
                        ((numLinks++))
                        ;;

                    # block/character devices
                    b)  device=1
                        ((numDevs++))
                        paint="${ALL_COLORS[bd]}"
                        ;;
                    c)  device=1;
                        ((numDevs++))
                        paint="${ALL_COLORS[cd]}"
                        ;;

                    *) # regular files
                        ((numFiles++))
                        if [[ ${extensions[$ind]} != "." ]]; then
                            paint="ALL_COLORS[${extensions[$ind]}]"
                            paint=${!paint};
                            if [[ ${#paint} = 0 ]]; then
                                paint="${ALL_COLORS[no]}"; fi
                        else
                            paint="${ALL_COLORS[no]}";
                        fi
                        ;;
                esac

                # check for specials (acl, group permissions, ...)
                case ${perms[$ind]:((${#perms[$ind]}-1)):1} in
                    +)   paint=04\;"$paint";;      # underline files/dirs with acls
                    t|T) paint="${ALL_COLORS[ow]}";; # other-writable
                    *);;
                esac

                # attribute lists
                if [ $haveAttrlist ]; then

                    # immutables
                    n=attrlist_${names[$ind]}; n=${!n}
                    if [ ${n//[^i]} ]; then
                        paint=44\;"$paint"
                        lastsymbol="i";
                    fi
                fi

                # truncate name if it is longer than maximum displayable length
                if [ ${#names[$ind]} -gt $maxNameWidth ] && [ $lastColumn -eq 0 ]; then
                    names[$ind]=${names[$ind]:0:$(($maxNameWidth-3))}"...";
                elif [ $lastColumn -eq 1 ]; then
                    lastColumnWidth=$(($COLUMNS-$j*$maxColumnWidth-10-3))
                    if [ ${#names[$ind]} -gt $lastColumnWidth ]; then
                        names[$ind]=${names[$ind]:0:$lastColumnWidth}"..."; fi
                fi

                # and finally, print it:
                if [[ $device = 1 ]]; then
                    # block/character devices
                    printf "%7s\E[01;31m%s\E[0m \E[${paint}m%-*s \E[0m" "${sizes[$ind]}${names[$ind]%% *}" "$lastsymbol" $maxNameWidth "${names[$ind]#* }"
                else
                    # all others
                    printf "%7s\E[01;31m%s\E[0m \E[${paint}m%-*s \E[0m" "${sizes[$ind]}" "$lastsymbol" $maxNameWidth "${names[$ind]}"
                fi

            # we're NOT using colors:
            else
                # block/character devices need different treatment
                case ${perms[$ind]:0:1} in
                    b|c) device=1;;
                esac
                if [[ $device = 1 ]]; then
                    printf "%7s  %-*s " "${sizes[$ind]}${names[$ind]%% *}" $maxNameWidth "${names[$ind]#* }"
                else
                    printf "%7s  %-*s " "${sizes[$ind]}" $maxNameWidth "${names[$ind]}"
                fi
            fi
        done

        printf "\n"

    done

    # finish up
    if [ $numDirs -eq 0 ] && [ $numFiles -eq 0 ] && [ $numLinks -eq 0 ] &&
       [ $numDevs -eq 0 ] && [ $numPipes -eq 0 ] && [ $numSockets -eq 0 ]; then
        echo "Empty dir."

    else
        if [ $haveFiles == false ]; then
            printf "%s in " $firstline
        else
            printf "Total "
        fi

        if [[ $numDirs != 0 ]]; then
            printf "%d dirs, " $numDirs; fi
        if [[ $numFiles != 0 ]]; then
            printf "%d files, " $numFiles; fi
        if [[ $numLinks != 0 ]]; then
            printf "%d links, " $numLinks; fi
        if [[ $numDevs != 0 ]]; then
            printf "%d devices, " $numDevs; fi
        if [[ $numPipes != 0 ]]; then
            printf "%d pipes, " $numPipes; fi
        if [[ $numSockets != 0 ]]; then
            printf "%d sockets, " $numSockets; fi

        printf "\b\b.\n"
    fi

    IFS=$IFS_


# END PROFILING
#set +x
#exec 2>&3 3>&-

}


# --------------------------------------------------------------------------------------------------
# Prompt function
# --------------------------------------------------------------------------------------------------

# command executed just PRIOR to showing the prompt
promptcmd()
{
    # write previous command to disk
    history -a

    # initialize
    local ES exitstatus=$?    # exitstatus of previous command
    local pth pthlen

    # put full path in the upper right corner
    # repositories will show the normal part blue, the repository part red
    pth=$(prettyprint_dir "$(pwd)")
    pthlen=$(echo "$pth" | sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g")
    printf "\E7\E[001;$(($COLUMNS-${#pthlen}-2))H\E[1m\E[32m[$pth\E[1m\E[32m]\E8\E[0m"

    # previous command exit status
    if [ $exitstatus -eq 0 ]; then
        if [ $USE_COLORS ]; then
            ES='\[\033[02;32m\]^_^ \[\033[00m\]'
        else
            ES='^_^ '; fi
    else
        if [ $USE_COLORS ]; then
            ES='\[\033[02;31m\]o_O \[\033[00m\]'
        else
            ES='o_O '; fi
    fi

    case "$REPO_TYPE" in

        # GIT repo
        "git")
            branch=$(git branch | command grep "*")
            branch=${branch#\* }
            if [ $? == 0 ]; then
                if [ $USE_COLORS ]; then
                     PS1=$ES'\[\033[01;32m\]\u@\h\[\033[00m\]:\['${REPO_COLOR[git]}'\] [git: $branch] : \W\[\033[00m\]\$ '
                else PS1=$ES'\u@\h: [git: $branch] : \W\$ '; fi
            else
                if [ $USE_COLORS ]; then
                     PS1=$ES'\[\033[01;32m\]\u@\h\[\033[00m\]:\['${REPO_COLOR[git]}'\] [*unknown branch*] : \W\[\033[00m\]\$ '
                else PS1=$ES'\u@\h: [*unknown branch*] : \W\$ '; fi
            fi
            ;;

        # SVN repo
        "svn")
            if [ $USE_COLORS ]; then
                 PS1=$ES'\[\033[01;32m\]\u@\h\[\033[00m\]:\['${REPO_COLOR[svn]}'\] [svn] : \W\[\033[00m\]\$ '
            else PS1=$ES'\u@\h: [svn] : \W\$ '; fi
            ;;

        # mercurial repo
        "hg")
            if [ $USE_COLORS ]; then
                 PS1=$ES'\[\033[01;32m\]\u@\h\[\033[00m\]:\['${REPO_COLOR[hg]}'\] [hg] : \W\[\033[00m\]\$ '
            else PS1=$ES'\u@\h: [hg] : \W\$ '; fi
            ;;

        # CVS repo
        "CVS")
            if [ $USE_COLORS ]; then
                 PS1=$ES'\[\033[01;32m\]\u@\h\[\033[00m\]:\['${REPO_COLOR[CVS]}'\] [CVS] : \W\[\033[00m\]\$ '
            else PS1=$ES'\u@\h: [CVS] : \W\$ '; fi
            ;;

        # bazaar repo
        "bzr")
            if [ $USE_COLORS ]; then
                 PS1=$ES'\[\033[01;32m\]\u@\h\[\033[00m\]:\['${REPO_COLOR[bzr]}'\] [bzr] : \W\[\033[00m\]\$ '
            else PS1=$ES'\u@\h: [bzr] : \W\$ '; fi
            ;;

        # normal prompt
        *)
            if [ $USE_COLORS ]; then
                # user is root
                if [ `id -u` = 0 ]; then
                    PS1=$ES'\[\033[01;31m\]\u@\h\[\033[0m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
                # non-root user
                else
                    PS1=$ES'\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\W\[\033[00m\]\$ '
                fi
            else
                PS1=$ES'\u@\h:\w\$ '
            fi
            ;;
    esac

}
# make this function the function called at each prompt display
PROMPT_COMMAND=promptcmd


# --------------------------------------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------------------------------------

# trim bash string
trim()
{
    local var="$@"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}

# delete single element and re-order array
# usage:  array=($(delete_reorder array[@] 10))
delete_reorder()
{
    if [[ $# != 2 ]]; then
        echo "Usage:  array=($(delete_reorder array[@] [index]))"; fi

    local array=("${!1}") rmindex="$2"
    for ((i=0; i<${#array[@]}; i++)); do
        if [[ $i == $rmindex ]]; then
            continue; fi
        echo ${array[$i]}
    done
}

# print dirlist if command exited with code 0
print_list_if_OK()
{
    if [ $1 == 0 ]; then
        clear
        multicolumn_ls
    fi
}

# pretty print directory
prettyprint_dir()
{
    local pwdmaxlen=$(($COLUMNS/3))
    local trunc_symbol="..."
    local pthoffset truncated=0 pth="${@/$HOME/~}"

    # truncate argument if it's longer than 30 chars
    if [ ${#pth} -gt $pwdmaxlen ]; then
        truncated=1
        pthoffset=$((${#pth}-$pwdmaxlen))
        pth="${trunc_symbol}${pth:$pthoffset:$pwdmaxlen}"
    fi

    # Color print
    if [ $USE_COLORS ]; then

        # We're in a repository; additional colors are required
        if [[ $REPO_MODE = true ]]; then

            # split input in repo path and deeper levels
            local firstpart=$(dirname "${REPO_PATH/$HOME/~}")
            firstpart=$(trim "$firstpart")
            local lastpart=$(trim "${1/$HOME/~}")
            lastpart="${lastpart##$firstpart}"

            # re-do the truncating when needed
            if [ $truncated = 1 ]; then
                if [ ${#lastpart} -gt $pwdmaxlen ]; then
                    firstpart=
                    pthoffset=$((${#lastpart}-$pwdmaxlen))
                    lastpart="${trunc_symbol}${lastpart:$pthoffset:$pwdmaxlen}"
                else
                    pthoffset=$((${#firstpart}-$pwdmaxlen+${#lastpart}))
                    firstpart="${trunc_symbol}${firstpart:$pthoffset:${#firstpart}}"
                fi
            fi

            # print repos
            case "$REPO_TYPE" in
                "git")  printf "\E[${ALL_COLORS[di]}m$firstpart${REPO_COLOR[git]}$lastpart/\E[0m" ;;
                "svn")  printf "\E[${ALL_COLORS[di]}m$firstpart${REPO_COLOR[svn]}$lastpart/\E[0m" ;;
                "CVS")  printf "\E[${ALL_COLORS[di]}m$firstpart${REPO_COLOR[CVS]}$lastpart/\E[0m" ;;
                "bzr")  printf "\E[${ALL_COLORS[di]}m$firstpart${REPO_COLOR[bzr]}$lastpart/\E[0m" ;;
                 "hg")  printf "\E[${ALL_COLORS[di]}m$firstpart${REPO_COLOR[hg]}$lastpart/\E[0m"  ;;
            esac

        # print only in dircolor
        else
            printf "\E[${ALL_COLORS[di]}m$pth/\E[0m"

        fi

    # non-color print
    else
        printf "$pth/"
    fi
}

# Check if we're in a repository
#
# Return values:
#   0: repository found
#   1: not a repository
#   2: cd to given dir gave error
#
# Input values:
#   0 arguments: check current dir
#   1 or more arguments: check given FULL path ("$@")
#
check_repo()
{
    local cpath f IFS_=$IFS
    local repos=(".git" ".svn" "CVS" ".hg" ".bzr")
    IFS="/"

    # function can take argument(s); argument is a FULL path
    # to a potential repo
    if [ $# -ne 0 ]; then
        cpath=($@) # NOTE: don't quote!
    # Function can take no arguments; check current dir
    else
        cpath=($(pwd)) # NOTE: don't quote!
    fi

    # loop through all parent directories to check for repository signatures
    command cd /
    for f in "${cpath[@]}"; do

        # CD to current dir
        # NOTE: tilde expansion is disabled
        command cd "${f/\~/$HOME}" 2> /dev/null

        # Given dir may not exist anymore
        if [ $? -ne 0 ]; then
            IFS=$IFS_
            return 2;
        fi

        # Perform repo check
        for repo in "${repos[@]}"; do
            if [ -d "$repo" ]; then
                IFS=$IFS_
                echo "${repo#.}"
                echo "$(pwd)"
                return 0
            fi
        done

    done

    # no repository found:
    IFS=$IFS_;
    return 1
}

# Update all repositories under the current dir
update_all()
{
    for d in */; do
        rp=($(check_repo "$(pwd)/$d"))
        case "${rp[0]}" in
            "svn")
                cd "${rp[@]:1}"
                svn update
                cd ..
                ;;

            "git")
                cd "${rp[@]:1}"
                git pull
                cd ..
                ;;

            "hg")
                cd "${rp[@]:1}"
                hg update
                cd ..
                ;;

            "bzr")
                cd "${rp[@]:1}"
                bzr update
                cd ..
                ;;

            "CSV")
                # TODO
                ;;

            *)
                ;;
        esac
    done
}

# Enter GIT mode
enter_GIT()
{
    # set type
    REPO_TYPE="git"
    REPO_MODE=true
    REPO_PATH="$@"

    # alias everything
    alias gp="git push"                    ;  REPO_CMD_push="gp"
    alias gP="git pull"                    ;  REPO_CMD_pull="gP"
    alias gc="git commit -am"              ;  REPO_CMD_commit="gc"
    alias gs="git status"                  ;  REPO_CMD_status="gs"
    alias gl="git log --oneline"           ;  REPO_CMD_log="gl"
    alias ga="git add"                     ;  REPO_CMD_add="ga"
    alias grm="git rm"                     ;  REPO_CMD_remove="grm"
    alias gm="git merge"                   ;  REPO_CMD_merge="gm"
    alias gmt="git mergetool"              ;  REPO_CMD_mergetool="gmt"

    alias gco="git checkout"               ;  REPO_CMD_checkout="gco"
    complete -o default -o nospace -F _git_checkout gco

    alias gu="git pull && git push"        ;  REPO_CMD_update="gu"
    alias glg="git log --graph --oneline"  ;  REPO_CMD_loggraph="glg"
    alias gg=gitg                          ;

    alias gt="git tag"                     ;  REPO_CMD_tag="gt"
    alias gpt="git push --tags"            ;  REPO_CMD_pushtgs="gpt"

    alias gcb="git diff --name-status"     ;  REPO_CMD_diffnamestatus="gcb"
    alias gbr="git branch -r"              ;  REPO_CMD_branchremote="gbr"
    alias gb="git branch"                  ;  REPO_CMD_branch="gb"
    alias gd="git diff"                    ;  REPO_CMD_diff="gd"
}

# Enter SVN mode
enter_SVN()
{
    # enter SVN mode
    REPO_TYPE="svn"
    REPO_MODE=true
    REPO_PATH="$@"

    # alias everything
    # TODO
    alias su="svn up"           ; REPO_CMD_update="su"
    alias sc="svn commit -m "   ; REPO_CMD_commit="sc"
    alias ss="svn status"       ; REPO_CMD_status="ss"
}

# Enter Mercurial mode
enter_HG()
{
    # enter GIT mode
    REPO_TYPE="hg"
    REPO_MODE=true
    REPO_PATH="$@"

    # alias everything
    # TODO
}

# Enter CVS mode
enter_CVS()
{
    # enter CVS mode
    REPO_TYPE="CVS"
    REPO_MODE=true
    REPO_PATH="$@"

    # alias everything
    # TODO
}

# Enter Bazaar mode
enter_BZR()
{
    # enter CVS mode
    REPO_TYPE="bzr"
    REPO_MODE=true
    REPO_PATH="$@"

    # alias everything
    # TODO
}

# leave any and all repositories
leave_repos()
{
    if [[ $REPO_MODE != true ]]; then
        return; fi

    # unalias everything
    for cmd in ${!REPO_CMD_*}; do
        eval unalias ${!cmd}; done

    # reset everything to normal
    REPO_PATH=       ;  PS1=$PS1_;
    REPO_TYPE=
    REPO_MODE=false;

    unset ${!REPO_CMD_*}
}


# --------------------------------------------------------------------------------------------------
# More advanced list functions
# --------------------------------------------------------------------------------------------------

# count and list directory sizes
lds()
{
    local sz h dirs IFS_=$IFS
    clear
    IFS=$'\n'

    # When no argument is given, process all dirs. Otherwise: process only given dirs
    if [ $# -eq 0 ]; then
       dirs=$(command ls -dh1 --time-style=+ */ 2> /dev/null)
    else
       dirs=$(command ls -dh1 --time-style=+ "${@/%//}" 2> /dev/null)
    fi

    if [ $USE_COLORS ]; then
        # find proper color used for directories
        local color="${ALL_COLORS[di]}"
        # loop through dirlist and parse
        for f in $dirs; do
            sz=$(du -bsh --si $f 2> /dev/null);
            sz=${sz%%$'\t'*}
            printf "$sz\t\E[${color#*;}m\E[${color%;*}m$f\n\E[0m"
        done
    else
        for f in $dirs; do
            sz=$(du -bsh --si $f 2> /dev/null);
            sz=${sz%%$'\t'*}
            printf "$sz\t$f\n"
        done
    fi
    IFS=$IFS_
}

# count and list directory sizes, including hidden dirs
lads()
{
    local sz h dirs IFS_=$IFS
    clear
    IFS=$'\n'

    # When no argument is given, process all dirs and dot-dirs.
    # Otherwise: process only given dirs
    if [ $# -eq 0 ]; then
        dirs=$(command ls -dh1 --time-style=+ */ .*/ 2> /dev/null)
    else
        dirs=$(command ls -dh1 --time-style=+ "${@/%//}" 2> /dev/null)
    fi

    if [ $USE_COLORS ]; then
        # find proper color used for directories
        local color="${ALL_COLORS[di]}"
        # loop through dirlist and parse
        for f in $dirs; do
            sz=$(du -bsh --si $f 2> /dev/null);
            sz=${sz%%$'\t'*}
            printf "$sz\t\E[${color#*;}m\E[${color%;*}m$f\n\E[0m"
        done
    else
        for f in $dirs; do
            sz=$(du -bsh --si $f 2> /dev/null);
            sz=${sz%%$'\t'*}
            printf "$sz\t$f\n"
        done
    fi
    IFS=$IFS_
}

# display only dirs/files with given octal permissions for current user
lo()
{
    local cmd str

    # Contruct proper command and display string
    case "$1" in
        0) str="no permissions"              ; cmd="" ;; # TODO
        1) str="Executable"                  ; cmd="-executable" ;;
        2) str="Writable"                    ; cmd="-writable" ;;
        3) str="Writable/executable"         ; cmd="-writable -executable" ;;
        4) str="Readable"                    ; cmd="-readable" ;;
        5) str="Readable/executable"         ; cmd="-readable -executable" ;;
        6) str="Readable/writable"           ; cmd="-readable -writable" ;;
        7) str="Readable/writable/executable"; cmd="-readable -writable -executable" ;;

        *) echo "Invalid octal permission."; return 1 ;;
    esac

    # default: find non-dot files only.
    # when passing 2 args: find also dot-files.
    if [ $# -ne 2 ]; then
        cmd="-name \"[^\.]*\" "$cmd; fi

    echo "$str files:"

    # the actual find
    local fs IFS_=$IFS
    IFS=$'\n'
        fs=($(eval find . -maxdepth 1 -type f $cmd))
    IFS=$IFS_

    # parse file list and pass on to multicolumn_ls
    if [[ ${#fs[@]} != 0 ]]; then

        # add quotes to all args
        for ((i=0; i<${#fs[@]}; ++i)); do
            fs[$i]=\"${fs[i]#./}\"; done

        # and call (NOTE: eval required for quote expansion)
        eval multicolumn_ls ${fs[@]}

    else
        echo "No such files found."
    fi

    return 0

}

# display only files readable by current user
lr() { lo 4; }
# display only files readable by current user, including dot-dirs
lar() { lo 4 "all"; }

# display only files writable by current user
lw() { lo 2; }
# display only files writable by current user, including dot-dirs
law() { lo 2 "all"; }

# display only files executable by current user
lx() { lo 1; }
# display only files executable by current user, including dot-dirs
lax() { lo 1 "all"; }


# --------------------------------------------------------------------------------------------------
# More advanced cd, mkdir, rmdir, mv, rm, cp, ln
# --------------------------------------------------------------------------------------------------

# Navigate to directory. Check if directory is in a repo
# TODO: jump to dir in the stack (without autocomplete) when its not in the current dir
# TODO: autocomplete dirs in the stack (if none exist in the current path)
_cd_DONTUSE()
{
    # first cd to given directory
    # NOTE: use "--" to allow dirnames like "+package" or "-some-dir"

    # Home
    if [ $# -eq 0 ]; then
        builtin pushd -- "$HOME" > /dev/null

    # Previous
    elif [[ $# -eq 1 && "-" = "$1" ]]; then
        builtin pushd > /dev/null

    # All others
    else
        builtin pushd -- "$@" > /dev/null
    fi

    # if successful, display abbreviated dirlist and check if it is a GIT repository
    if [ $? -eq 0 ]; then

        # Assume we're not going to use any of the repository modes
        leave_repos

        # Check if we're in a repo. If so, enter a repo mode
        repo=($(check_repo))

        #clear
        #echo  "${repo[0]}"
        #sleep 1
        #clear
        #echo "${repo[@]:1}"
        #sleep 1
        #clear

        if [ $? -eq 0 ]; then
            case "${repo[0]}" in
                "git") enter_GIT "${repo[@]:1}" ;;
                "svn") enter_SVN "${repo[@]:1}" ;;
                "CVS") enter_CVS "${repo[@]:1}" ;;
                "hg")  enter_HG  "${repo[@]:1}" ;;
                "bzr") enter_BZR "${repo[@]:1}" ;;
                *) ;;
            esac
        fi
        clear
        multicolumn_ls

    fi
}

# jump dirs via dir-numbers
_cdn_DONTUSE()
{
    # create initial stack array
    # (take care of dirs with spaces in the name)
    local stack=("${DIRSTACK[@]}")
    stack=("${stack[@]/\~/$HOME}")
    stack=("${stack[@]/%/\n}")
    stack[0]=" ${stack[0]}"

    # Sort entries, and find unique ones:
    local entry IFS_=$IFS; IFS=$'\n'
    stack=( $(echo "${stack[@]}" | sort -u) )
    IFS=$IFS_

    # if no function arguments provided, show list
    if [ $# -eq 0 ]; then

        # check for color prompt
        local colors=0
        if [ $USE_COLORS ]; then
            local REPO_PATH_="$REPO_PATH"
            local REPO_TYPE_=$REPO_TYPE
            local REPO_MODE_=$REPO_MODE
            local PWD_=$(pwd)
            colors=1
        fi



        # print list
        local repo
        for ((i=0; i<${#stack[@]}; i++)); do
            if [ $colors -eq 1 ]; then

                repo=($(check_repo "$(trim ${stack[$i]})"))

                # continue on any errors
                if (( $? > 1 )); then
                    continue; fi

                # set appropriate mode
                case "${repo[0]}" in
                    "git") REPO_MODE=true;  REPO_TYPE=git; REPO_PATH="${repo[@]:1}" ;;
                    "svn") REPO_MODE=true;  REPO_TYPE=svn; REPO_PATH="${repo[@]:1}" ;;
                    "bzr") REPO_MODE=true;  REPO_TYPE=bzr; REPO_PATH="${repo[@]:1}" ;;
                    "hg")  REPO_MODE=true;  REPO_TYPE=hg ; REPO_PATH="${repo[@]:1}" ;;
                    "CVS") REPO_MODE=true;  REPO_TYPE=CVS; REPO_PATH="${repo[@]:1}" ;;
                    *)     REPO_MODE=false; REPO_TYPE=   ; REPO_PATH=               ;;
                esac

                printf "%3d: " $i
                prettyprint_dir "$(trim ${stack[$i]})"
                printf "\n"

            else
                printf "%3d: %s\n" $i "${stack[$i]%%\n}"
            fi
        done

        # reset stuff
        if [ $colors -eq 1 ]; then
            REPO_PATH=$REPO_PATH_
            REPO_TYPE=$REPO_TYPE_
            REPO_MODE=$REPO_MODE_
            builtin cd "$PWD_"
        fi

    # otherwise, go to dir number
    else
        entry="${stack[$1]%%\n}"
        _cd_DONTUSE "${entry#"${entry%%[![:space:]]*}"}"

    fi
}



# TODO Complete partial CD paths, including the current dir AND the dirstack
cd_completer()
{
    local IFS_=$IFS

    # create initial stack array (uniques only)
    IFS=$'\n'
    local stack=("${DIRSTACK[@]}")
    stack=("${stack[@]/\~/$HOME}")
    stack=("${stack[@]/%/$'\n'}")
    stack=($(echo "${stack[@]}" | sort -u))

for i in "${stack[@]}"; do
    k="${#COMPREPLY[@]}"
    COMPREPLY[k++]=${j#$i/}
done





return 0

    # from /etc/bash_completion///_cd():

    #local cur IFS=$'\n' i j k
    #_get_comp_words_by_ref cur

    # try to allow variable completion
    #if [[ "$cur" == ?(\\)\$* ]]; then
        #COMPREPLY=( $( compgen -v -P '$' -- "${cur#?(\\)$}" ) )
        #return 0
    #fi

    #_compopt_o_filenames

    ## Use standard dir completion if no CDPATH or parameter starts with /,
    ## ./ or ../
    #if [[ -z "${CDPATH:-}" || "$cur" == ?(.)?(.)/* ]]; then
        #_filedir -d
        #return 0
    #fi

    #local -r mark_dirs=$(_rl_enabled mark-directories && echo y)
    #local -r mark_symdirs=$(_rl_enabled mark-symlinked-directories && echo y)

    ## we have a CDPATH, so loop on its contents
    #for i in ${CDPATH//:/$'\n'}; do
        ## create an array of matched subdirs
        #k="${#COMPREPLY[@]}"
        #for j in $( compgen -d $i/$cur ); do
            #if [[ ( $mark_symdirs && -h $j || $mark_dirs && ! -h $j ) && ! -d ${j#$i/} ]]; then
                #j="${j}/"
            #fi
            #COMPREPLY[k++]=${j#$i/}
        #done
    #done

    #_filedir -d

    #if [[ ${#COMPREPLY[@]} -eq 1 ]]; then
        #i=${COMPREPLY[0]}
        #if [[ "$i" == "$cur" && $i != "*/" ]]; then
            #COMPREPLY[0]="${i}/"
        #fi
    #fi

    #return 0
}
#if shopt -q cdable_vars; then
    #complete -v -F cdn_complete -o nospace cd
#else
    #complete -F cdn_complete -o nospace cd
#fi



# create dir(s), taking into account current repo mode
_mkdir_DONTUSE()
{
    command mkdir -p "$@"
    if [ $? == 0 ]; then
        if [ $REPO_MODE == true ]; then
            eval $REPO_CMD_add "$@"; fi
        print_list_if_OK 0
    fi
}

# remove dir(s), taking into account current repo mode
# TODO: not done yet
_rmdir_DONTUSE()
{
    command rmdir "$@"
    print_list_if_OK $?
}

# remove file(s), taking into account current repo mode
_rm_DONTUSE()
{
    # we are in REPO mode
    if [[ $REPO_MODE == true ]]; then

        local err msg not_addedoutside_repo

        # perform repo-specific delete
        err=$(eval ${REPO_CMD_remove} "$@" 2>&1 1> /dev/null)

        # different repositories issue different errors
        case "$REPO_TYPE" in

            "git" )
                not_added="did not match any files"
                outside_repo="outside repository"
                ;;

            "svn")
                # TODO
                not_added=
                outside_repo=
                ;;

            "hg")
                # TODO
                not_added=
                outside_repo=
                ;;

            "CVS")
                # TODO
                not_added=
                outside_repo=
                ;;

            "bzr")
                # TODO
                not_added=
                outside_repo=
                ;;

            *) # anything erroneous does the same as no repo
                command rm -vI "$@"
                print_list_if_OK $?
                ;;

        esac

        # remove non-added or external files
        if [[ "$err" =~ "${not_added}" ]]; then

            msg="\n WARNING: Some files were never added to the repository \n Do you wish to remove them anyway? [N/y]"
            if [ $USE_COLORS ]; then printf "\E[41m$msg\E[0m "
            else printf "$msg "; fi

            case $(read L && echo $L) in
                y|Y|yes|Yes|YES)
                    command rm -vI "$@"
                    print_list_if_OK $?
                    ;;
                *)
                    ;;
            esac

        else
            if [[ "$err" =~ "${outside_repo}" ]]; then

                msg="\n WARNING: Some files were outside the repository. \n\n"
                command rm -vI "$@"
                if [ $? == 0 ]; then
                    print_list_if_OK 0
                    if [ $USE_COLORS ]; then printf "\E[41m$msg\E[0m"
                    else printf "$msg"; fi
                fi
            else
                echo "$err"
            fi
        fi

    # not in REPO mode
    else
        command rm -vI "$@"
        print_list_if_OK $?

    fi
}

# move file(s), taking into account current repo mode
# TODO: this needs work; there are more possibilities:
#
#  - source IN  repo, target IN repo
#  - source OUT repo, target OUT repo
#  - source IN  repo, target OUT repo
#  - source OUT repo, target IN  repo
#
# warnings should be issued, files auto-added to repo, etc.
_mv_DONTUSE()
{

    # check if target is in REPO
    local source source_repo
    local target_repo=$(check_repo $(dirname "${@:$#}"))

# TODO!
    ## if that is so, (repo-)move all sources to target
    #if [[ $? == 0 ]]; then
        #for ((i=0; i<$#-1; ++i)); do
            #source="$1" # NOTE: will be shifted
            #source_repo=$(check_repo $(dirname $source))

            #shift
        #done


    ## if the target is NOT a repo, the sources might be
    #else
        #for ((i=0; i<$#-1; ++i)); do
            #source="$1" # NOTE: will be shifted
            #source_repo=$(check_repo $(dirname $source))

            #shift
        #done

    #fi

    # the old, GIT-only way
    if [[ $REPO_MODE == true && $REPO_TYPE == "git" ]]; then

        local match="outside repository"

        local err=$(git mv "$@" 2>&1 1> /dev/null)


        if [ $? != 0 ]; then
            if [[ "$err" =~ "${match}" ]]; then
                command mv -iv "$@"
                if [ $? == 0 ]; then
                    print_list_if_OK $?
                    if [ $USE_COLORS ]; then
                         printf "\n\E[41m WARNING: Target and/or source was outside repository! \n\n\E[0m";
                    else printf "\n WARNING: Target and/or source was outside repository! \n\n"; fi
                fi
            else
                echo $err
            fi
        fi

    else
        command mv -iv "$@"
        print_list_if_OK $?

    fi
}

# Make simlink, taking into account current repo mode
# TODO: needs work...auto-add any new files/dirs, but the 4 different
# forms of ln make this complicated
_ln_DONTUSE()
{
    command ln -s "$@"
    if [ $? == 0 ]; then
        print_list_if_OK 0
        if [ $REPO_MODE == "git" ]; then
        # TODO: add link ($2, but taking into account spaces)
            echo
            echo "REMEMBER TO ADD NEW FILE!!"
            echo
        fi
    fi
}

# copy file(s), taking into account current repo mode
# TODO: this needs work; there are more possibilities:
#
#  - source IN  repo, target IN repo
#  - source OUT repo, target OUT repo
#  - source IN  repo, target OUT repo
#  - source OUT repo, target IN  repo
#
# warnings should be issued, files auto-added to repo, etc.
_cp_DONTUSE()
{
    # REPO mode
    if [[ $REPO_MODE == "git" ]]; then
        # only add copy to repo when
        # - we have exactly 2 arguments
        # - if arg. 1 and 2 are both inside the repo
        if [ $# -gt 2 ]; then
            command cp -ivR "$@"
        else
            command cp -ivR "$@"
            git add "$2" 2> /dev/null
        fi

    # normal mode
    else
        # allow 1-argument copy
        if [ $# == 1 ]; then
            command cp -ivR "$1" "copy_of_$1"

        # normal, n-element copy
        else
            command cp -ivR "$@"
        fi
    fi
    print_list_if_OK $?
}

# touch file, taking into account current repo mode
_touch_DONTUSE()
{
    command touch "$@"
    print_list_if_OK $?
    if [[ $REPO_MODE == true ]]; then
        $REPO_CMD_add "$@"; fi
}

# --------------------------------------------------------------------------------------------------
# Frequently needed functionality
# --------------------------------------------------------------------------------------------------

# copy all relevant bash config files to a different (bash-enabled) system
proliferate_to()
{
    scp ~/.bash_aliases "$@"
    if (( $? == 0 )); then
        scp ~/.bash_functions "$@"
        scp ~/.bashrc "$@"
        scp ~/.dircolors "$@"
        scp ~/.inputrc "$@"
        scp ~/.git_prompt "$@"
        scp ~/.git_completion "$@"
    else
        echo "failed to proliferate Rody's bash madness to remote system."
    fi
}

# Extract some arbitrary archive
ex()
{
    if [[ -f "$1" && -r "$1" ]] ; then
        case "$1" in
            *.tar.bz2)   tar xjvf "$1"   ;;
            *.tar.gz)    tar xzvf "$1"   ;;
            *.bz2)       bunzip2  "$1"   ;;
            *.rar)       rar x    "$1"   ;;
            *.gz)        gunzip   "$1"   ;;
            *.tar)       tar xvf  "$1"   ;;
            *.tbz2)      tar xjvf "$1"   ;;
            *.tgz)       tar xzvf "$1"   ;;
            *.zip)       unzip    "$1"   ;;
            *.Z)         uncompress "$1" ;;
            *.7z)        7z x "$1"       ;;

            *) echo "'$1' cannot be extracted via ex()." ;;
        esac
    else
        echo "'$1' is not a valid, readable file."
    fi
}

# change extentions of files in current dir
changext()
{
    # usage
    if [[ $# != 2 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo USAGE = $0 [.OLDEXT] [.NEWEXT]
        return 0
    fi

    local before after f

    # period is optional
    before=$1; after=$2
    if [ "${before:0:1}" != "." ]; then
        before=".$before"; fi
    if [ "${after:0:1}" != "." ]; then
        after=".$after"; fi

    # loop through file list
    for f in *$before; do
        command mv "$f" "${f%$before}$after"; done

    clear; multicolumn_ls
}

# instant calculator
C() { echo "$@" | command bc -lq; }

# find N largest files in current directory and all subdirectories
#
# Must be aliased in .bash_aliases.
#
# no arguments   : list 10 biggest files
# single argument: list N biggest files
_findbig_DONTUSE()
{

    # parse input arguments
    if [ $# -gt 1 ]; then
        echo "Findbig takes at most 1 argument."; return; fi
    local num
    if [ $# -eq 1 ]; then
        num=$1 # argument is number of files to print
    else
        num=10 # which defaults to 10
    fi

    # initialize some local variables
    local lsout perms dir fcolor file f IFS_=$IFS

    # find proper color used for directories
    if [ $USE_COLORS ]; then
        local dcolor="${ALL_COLORS[di]}"; fi

    # loop through all big files
    IFS=$'\n'
    for f in $(find . -type f -exec /bin/ls -s "{}" \; 2> /dev/null | sort -nr | head -n $num); do

        # formatted ls
        lsout=$(/bin/ls -opgh --time-style=+ "${f#* }")

        # split the string in perms+size, path, and filename
        perms=${lsout%%./*}
        file=${lsout##*/}
        dir=${lsout/$perms/}; dir=${dir/$file/}

        # Print list, taking into account proper file colors
        # TODO: do this the same way as in multicolumn_ls()
        if [ $USE_COLORS ]; then
            local fcolor=${LS_COLORS##*'*'.${file##*.}=};
            fcolor=${fcolor%%:*}
            if [ -z $(echo ${fcolor:0:1} | tr -d "[:alpha:]") ]; then
                fcolor=${LS_COLORS##*no=};
                fcolor=${fcolor%%:*}
            fi
            printf "%s\E[${dcolor#*;}m%s\E[${fcolor#*;}m%s\n\E[0m" $perms $dir $file
        else
            printf "%s%s%s\n" $perms $dir $file
        fi
    done
    IFS=$IFS_
}

# find biggest applications
# FIXME: can't alias this one directly due to {} symbols
_findbig_applications_DONTUSE()
{
    dpkg-query --show --showformat='${Package;-50}\t${Installed-Size}\n' | sort -k 2 -rn | grep -v deinstall | awk '{printf "%.3f MB \t %s\n", $2/(1024),  $1 }' | head -n 10
}

# chroot some environment
chroot_dir()
{
    # Check input
    if [ $# -ne 1 ]; then
        echo "Invalid number of arguments received.              "
        echo "                                                   "
        echo "Usage: $0 [PATH]                                   "
        echo "                                                   "
        echo "Where PATH is a valid dirname to put the chroot in."
        echo "Example:                                           "
        echo "   $0 /media/SYSTEM_DISK/                          "
        echo "                                                   "
        return 1
    fi

    local bind_dirs chroot_path dir i
    bind_dirs=("/proc" "/sys" "/dev" "/dev/pts" "/dev/shm")

    # Mount the essentials to the system
    chroot_path="$1"
    for ((i=0; i<${#bind_dirs[@]}; i++)); do
        if [ ! -d ${chroot_path}${bind_dirs[$i]} ]; then
            mkdir "${chroot_path}${bind_dirs[$i]}"; fi
        sudo mount --bind "${bind_dirs[$i]}" "${chroot_path}${bind_dirs[$i]}"
    done

    # Enter the chroot
    sudo chroot "$chroot_path"
    if [ $? -ne 0 ]; then

        # TODO:
        # # try to give more forgiving error messages
        # cat $tmpErr | grep "Exec format error" > /dev/null
        # if [ $? -eq 0 ]; then
        #    echo "Target architecture differs from host system architecture; do you have QEMU installed?"
        # else
            printf "Could not enter chroot: %s" $(cat $tmpErr)
        # fi
    fi

    # Unmount everything again when chroot exits
    for ((i--; i>=0; i--)); do
        sudo umount "${chroot_path}${bind_dirs[$i]}"; done
}

# gedit ALWAYS in background and immune to terminal closing!
# must be aliased in .bash_aliases
_gedit_DONTUSE() { (/usr/bin/gedit "$@" &) | nohup &> /dev/null; }

# geany ALWAYS in background and immune to terminal closing!
# must be aliased in .bash_aliases
_geany_DONTUSE() { (/usr/local/bin/geany "$@" &) | nohup &> /dev/null; }

# grep all processes in wide-format PS, excluding "grep" itself
psa()
{
    ps auxw | egrep -iT --color=auto "[${1:0:1}]${1:1}"
}

# export hi-res PNG from svg file
# must be aliased in .bash_aliases
pngify()
{
    local svgname pngname;
    for f in "$@"; do
        svgname=$f
        pngname="${svgname%.svg}.png"
        inkscape "$svgname" --export-png=$pngname --export-dpi=250
    done
}



