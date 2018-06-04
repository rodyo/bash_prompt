#!/usr/bin/env bash

# --------------------------------------------------------------------------------------------------
# Debugging
# --------------------------------------------------------------------------------------------------

# (do the obvious thing to enable this)
# From https://askubuntu.com/a/1001404/75926

if false; then

	# NOTE: (Rody Oldenhuis) get location of function definition:
	# $ declare -F <function name>
	# see https://unix.stackexchange.com/a/322887/20712

	shopt -s extdebug

    local -r fname="~/BASH_DEBUG.LOG"

    # The ultimate debugging prompt
    # see https://stackoverflow.com/questions/17804007/how-to-show-line-number-when-executing-bash-script
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

    exec   > >(tee -ia "$fname")
    exec  2> >(tee -ia "$fname" >& 2)
    exec 19> "$fname"

    export BASH_XTRACEFD=19
    set -x

fi


# --------------------------------------------------------------------------------------------------
# Profiling
# --------------------------------------------------------------------------------------------------

# If/when profiling, surround the function to profile with _START_PROFILING;/_STOP_PROFILING;

declare -i DO_PROFILING=0

_START_PROFILING()
{
    if ! command -v tee   &>/dev/null || \
       ! command -v date  &>/dev/null || \
       ! command -v sed   &>/dev/null || \
       ! command -v paste &>/dev/null
    then
        error "cannot profile: unmet depenencies"
        return 1
    fi

    if [ $DO_PROFILING -eq 1 ]; then
        PS4='+ $(date "+%s.%N")\011 '
        exec 3>&2 2> >(tee /tmp/sample-time.$$.log |
                       sed  -u 's/^.*$/now/' |
                       date -f - "+%s.%N" > /tmp/sample-time.$$.tim)
        set -x
    else
        error "stray _START_PROFILING found"
        return 1
    fi
}

_STOP_PROFILING()
{
    if [ $DO_PROFILING -eq 1 ]; then
        set +x
        exec 2>&3 3>&-

        printf -- ' %-11s  %-11s   %s\n' "duration" "cumulative" "command" > ~/profile_report.$$.log
        paste <(
            while read -r tim; do
                [ -z "$last" ] && last=${tim//.} && first=${tim//.}
                crt=000000000$((${tim//.}-10#0$last))
                ctot=000000000$((${tim//.}-10#0$first))
                printf -- '%12.9f %12.9f\n' ${crt:0:${#crt}-9}.${crt:${#crt}-9} \
                                         ${ctot:0:${#ctot}-9}.${ctot:${#ctot}-9}
                last=${tim//.}
              done < /tmp/sample-time.$$.tim
            ) /tmp/sample-time.$$.log >> ~/profile_report.$$.log && \
        echo "Profiling report available in '~/profile_report.$$.log'"

    else
        error "stray _STOP_PROFILING found"
        return 1
    fi
}


# --------------------------------------------------------------------------------------------------
# Initialize
# --------------------------------------------------------------------------------------------------

# Original separators
declare -r IFS_ORIGINAL=$IFS


# Location of files
# --------------------------------------------------------------------------------------------------

declare -r  DIRSTACK_FILE="${HOME}/.dirstack"
declare -ir DIRSTACK_COUNTLENGTH=5
declare -ir DIRSTACK_MAXLENGTH=50
declare -r  DIRSTACK_LOCKFILE="${HOME}/.locks/.dirstack"
declare -ir DIRSTACK_LOCKFD=9

# Set up locking; see
# http://stackoverflow.com/a/1985512/1085062

{ mkdir -p "$(dirname "${DIRSTACK_LOCKFILE}")" > /dev/null; } 2>&1
{ rm -f "${DIRSTACK_LOCKFILE}" > /dev/null; } 2>&1
touch "${DIRSTACK_LOCKFILE}"

_dirstack_locker(){ flock "-$1" $DIRSTACK_LOCKFD; }

_lock_dirstack()  { _dirstack_locker e; }
_unlock_dirstack(){ _dirstack_locker u; }

_prepare_locking(){ eval "exec ${DIRSTACK_LOCKFD}>\"${DIRSTACK_LOCKFILE}\""; }

_prepare_locking


# Check for external tools and shell specifics
# --------------------------------------------------------------------------------------------------

declare -i processAcls=0
declare -i haveAwk=0

command -v lsattr &> /dev/null && processAcls=1 || processAcls=0
command -v awk &> /dev/null && haveAwk=1 || haveAwk=0

declare -i haveAllRepoBinaries=0

command -v git &>/dev/null && \
command -v svn &>/dev/null && \
command -v hg &>/dev/null  && \
command -v bzr &>/dev/null && \
haveAllRepoBinaries=1 || haveAllRepoBinaries=0
#TODO: bash native method is virtually always faster...
haveAllRepoBinaries=0

# (Cygwin)
declare -i on_windows=0
[ "$(uname -o)" == "Cygwin" ] && on_windows=1 || on_windows=0


# Create global associative arrays
# --------------------------------

declare -A REPO_COLOR
declare -A ALL_COLORS

declare -i USE_COLORS=0
if [ "$SHELL_COLORS" == "yes" ]; then
    USE_COLORS=1

    IFS=": "
        # shellcheck disable=SC2206
        tmp=($LS_COLORS)
    IFS="$IFS_ORIGINAL"

    keys=("${tmp[@]%%=*}")
    keys=("${keys[@]/\*\./}")
    values=("${tmp[@]##*=}")

    for ((i=0; i<${#keys[@]}; ++i)); do
        ALL_COLORS["${keys[$i]}"]="${values[$i]}"; done

    unset tmp keys values
fi

# Repository info and generic commands
declare -i REPO_MODE=0;
REPO_TYPE=""
REPO_PATH=""

# colors used for different repositories in prompt/prettyprint
REPO_COLOR[svn]=${START_COLORSCHEME}${TXT_BOLD}';'${FG_MAGENTA}${END_COLORSCHEME};    REPO_COLOR[bzr]=${START_COLORSCHEME}${TXT_BOLD}';'${FG_YELLOW}${END_COLORSCHEME}
REPO_COLOR[git]=${START_COLORSCHEME}${TXT_BOLD}';'${FG_RED}${END_COLORSCHEME};        REPO_COLOR[hg]=${START_COLORSCHEME}${TXT_BOLD}';'${FG_CYAN}${END_COLORSCHEME}
REPO_COLOR[---]=${START_COLORSCHEME}${ALL_COLORS[di]}${END_COLORSCHEME}


# error/warning/assert functions
error()
{
    local msg

    # argument
    if [ -n "$1" ]; then
        # shellcheck disable=SC2059
        msg="$(printf -- "$@")"

    # stdin (pipe)
    else
        while read -r msg; do
            error "${msg}"; done
        return 1
    fi

    # Print the message, based on color settings
    if [[ $USE_COLORS == 1 ]]; then
        echo "${START_COLORSCHEME}${TXT_BOLD};${FG_RED}${END_COLORSCHEME}ERROR: ${msg}${RESET_COLORS}" >&2
    else
        error "${msg}" >&2
    fi

    return 1
}

warning()
{
    local msg

    # argument
    if [ -n "$1" ]; then
        # shellcheck disable=SC2059
        msg="$(printf -- "$@")"

    # stdin
    else
        while read -r msg; do
            warning "${msg}"; done
        return 0
    fi

    # Print the message, based on color settings
    if [[ $USE_COLORS == 1 ]]; then
        echo "${START_COLORSCHEME}${TXT_BOLD};${FG_YELLOW}${END_COLORSCHEME}WARNING: ${msg}${RESET_COLORS}"
    else
        echo "WARNING: ${msg}"
    fi

    return 0
}

assert()
{
    if [ "$1" ]; then
        return 0;
    else
        error "${@:2}"
        return 1
    fi
}

infomessage()
{
    local msg

    # argument
    if [ -n "$1" ]; then
        # shellcheck disable=SC2059
        msg="$(printf -- "$@")"

    # stdin
    else
        while read -r msg; do
            infomessage "${msg}"; done
        return 0
    fi

    # Print the message, based on color settings
    if [[ $USE_COLORS == 1 ]]; then
        echo "${START_COLORSCHEME}${TXT_BOLD};${FG_GREEN}${END_COLORSCHEME}INFO: ${msg}${RESET_COLORS}"
    else
        echo "INFO: ${msg}"
    fi

    return 0
}

# Abreviations/descriptive names (use in eval)
readonly to_error="2> >(error)"
readonly dump_except_error="1> /dev/null 2> >(error)"
readonly warning_and_error="1> >(warning) 2> >(error)"


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
    error 'Command not found: "%s".' "$1"
    return 1
}


# --------------------------------------------------------------------------------------------------
# Multicolumn colored filelist
# --------------------------------------------------------------------------------------------------

# TODO: field width of file size field can be a bit more flexible
#   (e.g., we don't ALWAYS need 7 characters...but: difficult if you want to get /dev/ right)
# TODO: show [seq] and ranges for simple sequences, with min/max file size

# FIXME: seems that passing an argument does not work properly
# shellcheck disable=SC2120
multicolumn_ls()
{
    if [[ $haveAwk == 1 ]]; then

        local colorflag=
        if [ $USE_COLORS -eq 1 ]; then
            colorflag="--color"; fi

        # shellcheck disable=SC2016
        # shellcheck disable=SC2028
        command ls -opg --si --group-directories-first --time-style=+ ${colorflag} "$@" | awk -f "$HOME/.awk_functions" -f <( echo -E '

            BEGIN {

                # Parameters
                columnWidth    = 50;
                rowsThreshold  = 25;

                # Counters
                dirs    = 0;    files = 0;    links = 0;
                sockets = 0;    pipes = 0;    doors = 0;
                devices = 0;
            }

            {
                if (FNR == 1) {
                    total = $0;
                    next;
                }

                perms   = $1;
                type    = substr(perms, 1,1);
                if (type == "b" || type == "c") {
                    devices++;

                    sizes[FNR-2] = trim($3 $4);
                    $1=$2=$3=$4="";
                    names[FNR-2] = trim($0);

                }
                else
                {
                    if      (type == "d") dirs++;
                    else if (type == "s") sockets++;
                    else if (type == "p") pipes++;
                    else if (type == "D") doors++;
                    else if (type == "l") links++;
                    else                  files++;

                    sizes[FNR-2] = trim($3);
                    $1=$2=$3="";
                    names[FNR-2] = trim($0);

                }

                acls[FNR-2] = (substr(perms, length(perms),1) == "+");

            }

            END {

                listLength = FNR-1;
                if (listLength == 0) {
                    printf("Empty dir.\n")
                }
                else
                {
                    if (FNR-1 <= rowsThreshold) {
                        for (i=0; i<listLength; ++i)
                            printf("%6s  %s\n", sizes[i], names[i]);
                    }
                    else {
                        maxColumns = int('$COLUMNS'/columnWidth);
                        columns    = min(maxColumns, ceil(listLength/rowsThreshold));
                        rows       = ceil(listLength/columns);

                        for (i=0; i<rows; ++i) {
                            for (j=0; j<columns; ++j)
                            {
                                ind = i+j*rows;
                                if (ind > listLength)
                                    break;

                                printf("%6s", sizes[ind]);
                                if (acls[ind])
                                    printf("+ ");
                                else
                                    printf("  ");

                                if (i+(j+1)*rows > listLength)
                                    printf("%s", truncate_and_alignleft(names[ind],'$COLUMNS'-j*columnWidth-8));
                                else
                                    printf("%s", truncate_and_alignleft(names[ind],columnWidth-8));
                            }
                            printf("\n");
                        }
                    }

                    printf("%s ", total " in")
                    if (dirs    != 0)  if (dirs    ==1) printf "1 directory, "; else printf dirs    " directories, ";
                    if (files   != 0)  if (files   ==1) printf "1 file, "     ; else printf files   " files, "      ;
                    if (links   != 0)  if (links   ==1) printf "1 link, "     ; else printf links   " symlinks, "   ;
                    if (sockets != 0)  if (sockets ==1) printf "1 socket, "   ; else printf sockets " sockets, "    ;
                    if (pipes   != 0)  if (pipes   ==1) printf "1 pipe, "     ; else printf pipes   " pipes, "      ;
                    if (doors   != 0)  if (doors   ==1) printf "1 door, "     ; else printf doors   " doors, "      ;
                    if (devices != 0)  if (devices ==1) printf "1 device, "   ; else printf devices " devices, "    ;
                    printf("\b\b.\n");
                }
            }
        ' ) --

    # Pure bash solution (Slow as CRAP!)
    else

        # preferences
        local -ri maxColumnWidth=35
        local -ri minLines=15

        # derived quantities & declarations
        local -r numColumns=$((COLUMNS/maxColumnWidth))
        local -r maxNameWidth=$((maxColumnWidth-10))

        # get initial file, as stripped down as possible, but including the file sizes.
        # NOTE: arguments to multicolumn_ls() get appended behind the base ls command
        IFS=$'\n'
        # shellcheck disable=2207
        local dirlist=($(command ls -opgh --group-directories-first --time-style=+ --si "$@"))

        # also get the file attribute list (for filesystems that are known to work)
        # FIXME: the order of the output of lsattr is different than that of ls.
        # the elements in the attributes array will therefore not correspond to the elements in the ls array...
        local haveAttrlist=0
        case $(find . -maxdepth 0 -printf %F) in
            ext2|ext3|ext4) haveAttrlist=1 ;;
            # TODO: also cifs and fuse.sshfs etc. --might-- support it, but how to check for this...
        esac

        ( ((${BASH_VERSION:0:1}>=4)) && [ $processAcls -eq 1 ] && if [[ $haveAttrlist == 1 ]]; then
            local -A attrlist
            # shellcheck disable=2207
            local attlist=($(lsattr 2>&1))
            # shellcheck disable=2207
            local attribs=($(echo "${attlist[*]%% *}"))
            # shellcheck disable=2207
            local attnames=($(echo "${attlist[*]##*\.\/}"))
            for ((i=0; i<${#attnames[@]}; i++)); do
                if [[ ${attribs[$i]%%lsattr:*} ]]; then
                    attrlist[${attnames[$i]}]="${attribs[$i]}"; fi
            done
            unset attnames attribs attlist
        fi ) || haveAttrlist=

        # check if any of the arguments was a "file" (and not just an option)
        local haveFiles=false
        while (( "$#" )); do
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
            unset "dirlist[0]"
        fi

        # Compute number of rows to use (equivalent to ceil)
        local numRows=$(( (${#dirlist[@]}+numColumns-1)/numColumns ))
        if [[ $numRows < $minLines ]]; then
            numRows=$minLines; fi

        # Split dirlist up in permissions, filesizes, names, and extentions
        # shellcheck disable=2207
        local perms=($(printf -- '%s\n' "${dirlist[@]}" | awk '{print $1}'))
        # shellcheck disable=2207
        local sizes=($(printf -- '%s\n' "${dirlist[@]}" | awk '{print $3}'))
        # NOTE: awkward yes, but the only way to get all spaces etc. right under ALL circumstances
        # shellcheck disable=2207
        local names=($(printf -- '%s\n' "${dirlist[@]}" | awk '{for(i=4;i<=NF;i++) $(i-3)=$i; if (NF>0)NF=NF-3; print $0}'))
        local extensions
        for ((i=0; i<${#names[@]}; i++)); do
            extensions[$i]=${names[$i]##*\.}
            if [[ ${extensions[$i]} == "${names[$i]}" ]]; then
                extensions[$i]="."; fi
        done

        # Now print the list
        if [[ $USE_COLORS == 1 ]]; then
            # shellcheck disable=2059
            printf -- "$RESET_COLORS"; fi

        local lastColumnWidth ind paint device=0 lastColumn=0 lastsymbol=" "
        local n numDirs=0 numFiles=0 numLinks=0 numDevs=0 numPipes=0 numSockets=0

        for ((i=0; i<numRows; i++)); do
            if [[ ! $i < ${#names[@]} ]]; then break; fi
            for ((j=0; j<numColumns; j++)); do

                device=0
                lastColumn=0
                lastsymbol=" "

                ind=$((i+numRows*j));
                if [[ ! $ind < ${#names[@]} ]]; then
                    break; fi
                if [[ ! $((i+numRows*((j+1)))) < ${#names[@]} ]]; then
                    lastColumn=1; fi

                # we ARE using colors:
                if [[ $USE_COLORS == 1 ]]; then

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
                        n=attrlist[${names[$ind]}]; n=${!n}
                        if [[ ${n//[^i]} ]]; then
                            paint=44\;"$paint"
                            lastsymbol="i";
                        fi
                    fi

                    # truncate name if it is longer than maximum displayable length
                    if [ ${#names[$ind]} -gt $maxNameWidth ] && [ $lastColumn -eq 0 ]; then
                        names[$ind]=${names[$ind]:0:$(($maxNameWidth-3))}"...";
                    elif [[ $lastColumn == 1 ]]; then
                        lastColumnWidth=$((COLUMNS-j*maxColumnWidth-10-3))
                        if [[ ! ${#names[$ind]} < $lastColumnWidth ]]; then
                            names[$ind]=${names[$ind]:0:$lastColumnWidth}"..."; fi
                    fi

                    # and finally, print it:
                    if [[ $device = 1 ]]; then
                        # block/character devices
                        printf -- "%7s${START_COLORSCHEME}${TXT_BOLD};${FG_RED}${END_COLORSCHEME}%s${RESET_COLORS} ${START_COLORSCHEME}${paint}${END_COLORSCHEME}%-*s ${RESET_COLORS}" "${sizes[$ind]}${names[$ind]%% *}" "$lastsymbol" $maxNameWidth "${names[$ind]#* }"
                    else
                        # all others
                        printf -- "%7s${START_COLORSCHEME}${TXT_BOLD};${FG_RED}${END_COLORSCHEME}%s${RESET_COLORS} ${START_COLORSCHEME}${paint}${END_COLORSCHEME}%-*s ${RESET_COLORS}" "${sizes[$ind]}" "$lastsymbol" $maxNameWidth "${names[$ind]}"
                    fi

                # we're NOT using colors:
                else
                    # block/character devices need different treatment
                    case ${perms[$ind]:0:1} in
                        b|c) device=1;;
                    esac
                    if [[ $device == 1 ]]; then
                        printf -- "%7s  %-*s " "${sizes[$ind]}${names[$ind]%% *}" "$maxNameWidth" "${names[$ind]#* }"
                    else
                        printf -- "%7s  %-*s " "${sizes[$ind]}" "$maxNameWidth" "${names[$ind]}"
                    fi
                fi
            done

            printf '\n'

        done

        # finish up
        if [[ $numDirs == 0 ]] && [[ $numFiles == 0 ]] && [[ $numLinks == 0 ]] &&
           [[ $numDevs == 0 ]] && [[ $numPipes == 0 ]] && [[ $numSockets == 0 ]]; then
            echo "Empty dir."

        else
            if [[ $haveFiles == false ]]; then
                printf -- "%s in " "$firstline"
            else
                printf -- "Total "
            fi

            if [[ $numDirs != 0 ]]; then
                printf -- "%d dirs, " $numDirs; fi
            if [[ $numFiles != 0 ]]; then
                printf -- "%d files, " $numFiles; fi
            if [[ $numLinks != 0 ]]; then
                printf -- "%d links, " $numLinks; fi
            if [[ $numDevs != 0 ]]; then
                printf -- "%d devices, " $numDevs; fi
            if [[ $numPipes != 0 ]]; then
                printf -- "%d pipes, " $numPipes; fi
            if [[ $numSockets != 0 ]]; then
                printf -- "%d sockets, " $numSockets; fi

            printf '\b\b.\n'
        fi

        IFS="$IFS_ORIGINAL"

    fi

}


# --------------------------------------------------------------------------------------------------
# Prompt function
# --------------------------------------------------------------------------------------------------

# command executed just PRIOR to showing the prompt
promptcmd()
{
    # NOTE: it is imperative that ALL non-printing characters in PS1 must be enclosed by \[ \].
    # See http://askubuntu.com/questions/24358/

    # NOTE: also, "string" will interpret things like "${..}", but 'string' will leave everything in *literally*.
    #       This is important when constructing the PS1 string, since specials like \u, \W etc. need to remain
    #       literal.

    # NOTE: original in .bashrc:

    #if [ "$SHELL_COLORS" = yes ]; then
    #    # user is root
    #    if [ `id -u` = 0 ]; then
    #        PS1='\[\033[01;31m\]\u@\h\[\033[0m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    #    # non-root user
    #    else
    #        PS1='\[\033[01;32m\]\u@\h\[\033[0m\]:\[\033[01;34m\]\W\[\033[00m\]\$ '
    #    fi
    #else
    #    PS1='\u@\h:\w\$ '
    #fi

    # initialize
    local -ri exitstatus=$?    # exitstatus of previous command
    local ES

    # Username color scheme
    local usrName=""
    if [[ $USE_COLORS == 1 ]]; then
        usrName="$(set_PS1_color "${TXT_BOLD}" "${FG_GREEN}")"; fi

    # hostname color scheme
    local hstName=""
    if [[ $USE_COLORS == 1 ]]; then
        hstName="$(set_PS1_color "${FG_MAGENTA}")"; fi

    # Write previous command to disk
    (history -a &) &> /dev/null

    # Smiley representing previous command exit status
    ES='o_O '
    if [[ $exitstatus == 0 ]]; then
        ES='^_^ '; fi

    if [[ $USE_COLORS == 1 ]]; then
        ES="$(set_PS1_color "${TXT_DIM}" "${FG_GREEN}")""${ES}""$(reset_PS1_color)"; fi

    # Append system time
    ES="$ES"'[\t] '

    # Set new prompt (taking into account repositories)
    case "${REPO_TYPE}" in

        # GIT also lists branch
        "git")
            branch=$(git branch | command grep "*")
            branch="${branch#\* }"
            if [[ $? != 0 ]]; then
                branch="*unknown branch*"; fi

            if [[ $USE_COLORS == 1 ]]; then
                PS1="$ES${usrName}"'\u'"${RESET_COLORS_PS1}"
                PS1="${PS1}@${hstName}"'\h'"${RESET_COLORS_PS1} : "
                PS1="${PS1}"'\['"${REPO_COLOR[git]}"'\]'" [git: ${branch}] : "'\W'"/${RESET_COLORS_PS1} "
                PS1="${PS1}"'\$'" "
            else
                PS1="$ES"'\u@\h : [git: '"${branch}] : "'\W/ \$ ';
            fi
            ;;

        # SVN, Mercurial, Bazhaar
        "svn"|"hg"|"bzr")
            if [[ $USE_COLORS == 1 ]]; then
                PS1="$ES${usrName}"'\u'"${RESET_COLORS_PS1}@${hstName}"'\h'"${RESET_COLORS_PS1} : "'\['"${REPO_COLOR[${REPO_TYPE}]} [${REPO_TYPE}] : "'\W'"/${RESET_COLORS_PS1} "'\$'" "
            else
                PS1="$ES"'\u@\h : ['"${REPO_TYPE}] : "'\W/ \$ ';
            fi
            ;;

        # Normal prompt
        *)  if [[ $USE_COLORS = 1 ]]; then

                local -r dircolor="${START_COLORSCHEME_PS1}${TXT_BOLD};${FG_BLUE}${END_COLORSCHEME_PS1}"

                # non-root user: basename of current dir
                local working_dir='\W'

                # Root
                if [ "$(id -u)" = 0 ]; then
                    # Different color for the username
                    usrName="${START_COLORSCHEME_PS1}${TXT_BOLD};${FG_RED}${END_COLORSCHEME_PS1}"
                    # Show FULL path
                    working_dir='\w'
                fi

                # Build the prompt
                PS1="$ES${usrName}"'\u'"${RESET_COLORS_PS1}@${hstName}"'\h'"${RESET_COLORS_PS1} : ${dircolor}${working_dir}/${RESET_COLORS_PS1} "'\$'" "

            else
                PS1="$ES"'\u@\h : \w/ \$ '
            fi
            ;;
    esac

    # put pretty-printed full path in the upper right corner
    local -r pth="$(prettyprint_dir "$PWD")"
    local -r move_cursor='\E7\E[001;'"$((COLUMNS-${#PWD}-2))H${START_ESCAPE_GROUP}1${END_COLORESCAPE}"
    local -r reset_cursor='\E8'
    if [ $USE_COLORS -eq 1 ]; then
        local -r bracket_open="${START_COLORSCHEME}${FG_GREEN}${END_COLORSCHEME}[${RESET_COLORS}"
        local -r bracket_close="${START_COLORSCHEME}${TXT_BOLD};${FG_GREEN}${END_COLORSCHEME}]${RESET_COLORS}"
    else
        local -r bracket_open="["
        local -r bracket_close="]"
    fi

    # shellcheck disable=SC2059
    printf -- "${move_cursor}${bracket_open}${pth}${bracket_close}${reset_cursor}"

}

# Make this function the function called at each prompt display
export PROMPT_COMMAND=promptcmd


# --------------------------------------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------------------------------------

# Join input arguments into a single string
strjoin()
{
    local -r d="$1"
    shift

    echo -n "$1"
    shift
    printf -- "%s" "${@/#/$d}"
}

# Produce a quoted list, taking into account proper comma placement
quoted_list()
{
    case "$#" in
        0) ;;
        1) echo "\"$1\"" ;;
        2) echo "\"$1\" and \"$2\"" ;;
        *) first="$(strjoin "\", \"" ${@:1:(($#-1))})"
           echo "\"${first}\", and \"${@: -1}\""
           ;;
    esac
}

# trim bash string
trim()
{
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}


# Normalize directory string
# e.g.,  /foo/bar/../baz  ->  /foo/baz
normalize_dir()
{
    readlink -m "$1"
}

# delete single element and re-order array
# usage:  array=($(delete_reorder array[@] 10))
delete_reorder()
{
    if [[ $# != 2 ]]; then
        echo "Usage:  array=($(delete_reorder array[@] [index]))"; fi

    local -ra array=("${!1}")
    local -ri rmindex="$2"

    for ((i=0; i<${#array[@]}; i++)); do
        if [ $i -eq "$rmindex" ]; then
            continue; fi
        echo "${array[$i]}"
    done
}

# Clear
_rbp_clear()
{
    for (( i=0; i<LINES; i++)); do
        printf '\n'"${START_ESCAPE_GROUP}K"; done;
    printf "${START_ESCAPE_GROUP}0;0H"
}

# print dirlist if command exited with code 0
print_list_if_OK()
{
    if [ "$1" == 0 ]; then
        clear
        # shellcheck disable=SC2119
        multicolumn_ls
    fi
}

# pretty print directory:
# - truncate (leading "...") if name is too long
# - colorized according to dircolors and repository info
prettyprint_dir()
{
    # No arguments, no function
    if [[ $# == 0 ]]; then
        return; fi

    local -a repoinfo
    local -ri pwdmaxlen=$((COLUMNS/3))
    local original_pth

    if [[ $USE_COLORS == 1 ]]; then
        original_pth="$(command ls -d "${1/\~/${HOME}}" --color)"
    else
        original_pth="$(command ls -d "${1/\~/${HOME}}")"
    fi

    local pth="${original_pth/${HOME}/~}";


    if [[ $# < 3 ]]; then
        # shellcheck disable=2207
        repoinfo=($(check_repo "$@"))
        if [ ${#repoinfo[@]} -gt 2 ]; then
            repoinfo[1]=$(strjoin "${IFS[0]}" "${repoinfo[@]:1}"); fi
    else
        repoinfo=("$2" "$3")
    fi

    # Color print
    if [[ $USE_COLORS == 1 ]]; then

        # TODO: dependency on AWK; include bash-only version
        if [ $haveAwk ]; then

            if [ "${repoinfo[0]}" != "---" ]; then
                local -r repoCol=${REPO_COLOR[${repoinfo[0]}]};
                local -r repopath="$(dirname "${repoinfo[1]}" 2> /dev/null)"
                pth="${pth/${repopath}/${repopath}$'\033'[0m$repoCol}"
            fi

            # shellcheck disable=SC2016
            echo "${pth}" | awk -f "$HOME/.awk_functions" -f <( echo -E '

                {
                    str    = $0;
                    len    = strlen(str);
                    maxLen = '$pwdmaxlen';
                    if (len > maxLen)
                    {
                        lastColorCode = "";
                        char_count    = 0;
                        counting      = 1;
                        N = split(str, str_chars, "");

                        for (k=0; k<N; ++k)
                        {
                            if (str_chars[k] == "\033") {
                                lastColorCode = "\033";
                                counting = 0; continue;
                            }

                            if (!counting) {
                                lastColorCode = lastColorCode str_chars[k];
                                if (str_chars[k] == "m")
                                    counting = 1;
                                continue;
                            }
                            else
                                char_count++;

                            if (len-char_count+3 <= maxLen) {
                                str = "\033[0m" lastColorCode "..." substr(str,k-1) "\033[0m";
                                break;
                            }
                        }
                    }

                    printf str;

                }
            ' ) --

        else
            echo "$pth"

            # Strip color codes from string:
            # sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g"
            # TODO

        fi

    # non-color print
    else
        local -i pthoffset

        if [ ${#pth} -gt $pwdmaxlen ]; then
            pthoffset=$((${#pth}-pwdmaxlen))
            pth="...${pth:$pthoffset:$pwdmaxlen}"
        fi
        printf -- "%s/" "$pth"
    fi
}


# --------------------------------------------------------------------------------------------------
# Repository-specific functions
# --------------------------------------------------------------------------------------------------

# Get repository command
get_repo_cmd()
{
    alias | grep "alias\s*$@=" | cut -d= -f2 | tr -d \'
}

# Check if given dir(s) is (are) (a) repository(ies)
check_repo()
{
    # TODO: instead of "all or nothing", find out which *specific* repository systems have been installed

    # Usage:
    #     check_repo [dir1] [dir2] ...
    #
    # If arguments are ommitted, only PWD is processed.
    #
    #
    # Output:
    #    [repo type 1] [repo root 1]
    #    [repo type 2] [repo root 2]
    #    ...
    #
    # The string [repo type X] is a 3-character string. Possible values are:
    #    svn: directory is a subversion repository
    #    git: directory is a git repository
    #    hg : directory is a mercurial repository
    #    bzr: directory is a bazaar repository
    #    ---: the given dir is not a repository

    local -a dirs
    local dir

    if [ $# -eq 0 ]; then
        dirs="$PWD"
    else
        dirs=("$@")
    fi

    # All repository systems have been installed; use their native methods to discover
    # where the repository root is located
    if [ $haveAllRepoBinaries -eq 1 ]; then

        local check

        for dir in "${dirs[@]}"; do

            check=$(printf -- "%s " git && command cd "${dir}" && git rev-parse --show-toplevel 2> /dev/null)
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then echo "$check"; continue; fi

            check=$(printf -- "%s " svn && svn info "$dir" 2> /dev/null | awk '/^Working Copy Root Path:/ {print $NF}' && [ "${PIPESTATUS[0]}" -ne 1 ])
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then echo "$check"; continue; fi

            check=$(printf -- "%s  " hg && hg root --cwd "$dir" 2> /dev/null)
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then echo "$check"; continue; fi

            check=$(printf -- "%s " bzr && bzr root "$dir" 2> /dev/null)
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then echo "$check"; continue; fi

            echo "--- [no_repository_found]"

        done

    # Not all repository systems have been installed; use bash to loop through the
    # directory tree in search of a repository identifier
    else

        local -ar slashes=("${dirs[@]//[^\/]/}")
        local -a repotype
        local -a reporoot

        local -r curdir="$PWD"

        local -i i
        local -i j

        # Using repeated cd() is slow; It's faster to append ".." in a loop, and
        # only do 2 calls to cd() to cleanup the dir format
        for (( i=0; i<${#dirs[@]}; ++i )); do

            dir="${dirs[$i]}"

            if [ ! -d "$dir" ]; then
                repotype[$i]="---"
                reporoot[$i]="[dir_removed]"
                continue;
            else
                repotype[$i]="---"
                reporoot[$i]="[no_repository_found]"
            fi

            # NOTE: repeated commands outperform function call by an order of magnitude
            # NOTE: commands without capture "$(...)" outperform commands with capture
            # NOTE: this is also faster than SED'ing the "../" away

            for (( j=${#slashes[$i]}; j>0; --j )); do
                [ -d "$dir/.git" ] && repotype[$i]="git" && cd "$dir" && reporoot[$i]="$PWD" && cd "$curdir" && break;
                [ -d "$dir/.svn" ] && repotype[$i]="svn" && cd "$dir" && reporoot[$i]="$PWD" && cd "$curdir" && break;
                [ -d "$dir/.bzr" ] && repotype[$i]="bzr" && cd "$dir" && reporoot[$i]="$PWD" && cd "$curdir" && break;
                [ -d "$dir/.hg"  ] && repotype[$i]="hg " && cd "$dir" && reporoot[$i]="$PWD" && cd "$curdir" && break;
                dir="$dir/.."
            done

        done

        for (( i=0;i<${#repotype[@]}; ++i )); do
            printf -- '%s %s\n' "${repotype[$i]}" "${reporoot[$i]}"; done
    fi

}


repo_cmd_exit_message()
{
    echo
    infomessage "$@"
    echo
}


# Update all repositories under the current dir
update_all()
{
    local -a rp

    for d in */; do

        rp=($(check_repo "$PWD/$d"))

        (
        cd "${rp[@]:1}"
        updatecmd=$(get_repo_cmd $REPO_CMD_pull)
        eval "$updatecmd" "$dump_except_error"
        )

    done
}

# Enter GIT mode
_enter_GIT()
{
    # set type
    REPO_TYPE="git"
    REPO_MODE=1
    REPO_PATH="$*"

    # Basics
    alias gf="git fetch"                    ;  REPO_CMD_fetch="gf"
    alias gp="git push"                     ;  REPO_CMD_push="gp"
    alias gP="git pull --recurse-submodules";  REPO_CMD_pull="gP"
    alias gc="git commit -am"               ;  REPO_CMD_commit="gc"
    alias gs="git status"                   ;  REPO_CMD_status="gs"
    alias gl="git log --oneline"            ;  REPO_CMD_log="gl"
    alias ga="git add"                      ;  REPO_CMD_add="ga"
    alias grm="git rm"                      ;  REPO_CMD_remove="grm"
    alias gm="git merge"                    ;  REPO_CMD_merge="gm"
    alias gmt="git mergetool"               ;  REPO_CMD_mergetool="gmt"

    alias unlink="git rm --cached"          ;  REPO_CMD_unlink="unlink"        # remove from repository, but keep local
    alias istracked="git ls-files --error-unmatch"
                                               REPO_CMD_trackcheck="istracked" # check whether file is tracked

    alias gco="git checkout"                ;  REPO_CMD_checkout="gco"
    # TODO: (Rody Oldenhuis) missing...
    #complete -o default -o nospace -F _git_checkout gco

    alias gu="git pull && git push"         ;  REPO_CMD_update="gu"
    alias glg="git log --graph --oneline"   ;  REPO_CMD_loggraph="glg"
    alias gg=gitg

    # Tagging
    alias gt="git tag"                      ;  REPO_CMD_tag="gt"
    alias gpt="git push --tags"             ;  REPO_CMD_pushtgs="gpt"

    # Branches
    alias gcb="git diff --name-status"      ;  REPO_CMD_diffnamestatus="gcb"
    alias gbr="git branch -r"               ;  REPO_CMD_branchremote="gbr"
    alias gb="git branch"                   ;  REPO_CMD_branch="gb"
    alias gd="git diff"                     ;  REPO_CMD_diff="gd"

    # Submodules
    alias gam="git submodule add"           ;  REPO_CMD_add_external="gam"
    alias gim="git submodule update --init --recursive";  REPO_CMD_init_external="gim"

}

# Enter SVN mode
_enter_SVN()
{
    # enter SVN mode
    REPO_TYPE="svn"
    REPO_MODE=1
    REPO_PATH="$*"

    # alias everything
    alias su="svn up"           ; REPO_CMD_update="su"
    alias sc="svn commit -m "   ; REPO_CMD_commit="sc"
    alias ss="svn status"       ; REPO_CMD_status="ss"
}

# Enter Mercurial mode
_enter_HG()
{
    # enter GIT mode
    REPO_TYPE="hg"
    REPO_MODE=1
    REPO_PATH="$*"

    # alias everything
    # TODO
}

# Enter Bazaar mode
_enter_BZR()
{
    # enter BZR mode
    REPO_TYPE="bzr"
    REPO_MODE=1
    REPO_PATH="$*"

    # alias everything
    # TODO
}

# leave repository
_leave_repo()
{
    if [[ ! -z $REPO_MODE && $REPO_MODE == 0 ]]; then
        return; fi

    # unalias everything
    for cmd in ${!REPO_CMD_*}; do
        eval unalias ${!cmd}; done

    # reset everything to normal
    PS1=$PS1_
    REPO_PATH=
    REPO_TYPE=
    REPO_MODE=0;

    unset ${!REPO_CMD_*}
}


# --------------------------------------------------------------------------------------------------
# More advanced list functions
# --------------------------------------------------------------------------------------------------

# count and list directory sizes
lds()
{
    local sz
    local f
    local dirs

    clear
    IFS=$'\n'

    # When no argument is given, process all dirs. Otherwise: process only given dirs
    if [ $# -eq 0 ]; then
       dirs=$(ls -Adh1 --time-style=+ -- */ 2> >(error))
    else
       dirs=$(ls -Adh1 --time-style=+ -- ${@/%//} 2> >(error))
    fi

    # find proper color used for directories
    if [[ $USE_COLORS == 1 ]]; then
        local -r color="${ALL_COLORS[di]}"; fi

    # loop through dirlist and parse
    for f in $dirs; do

        # ./ and ../ may still be in the list, despite -A flag (lads(), for example)
        if [[ "$f" == "./" || "$f" == ".//" || "$f" == "../" || "$f" == "..//" ]]; then
            continue; fi

        printf -- 'processing "%s"...\n' "$f"
        sz=$(du -bsh --si "$f" 2> /dev/null);
        sz="${sz%%$'\t'*}"
        tput cuu 1 && tput el

        if [ $USE_COLORS -eq 1 ]; then
            printf -- '%s\t'"${START_COLORSCHEME}${color}${END_COLORSCHEME}"'%s\n'"${RESET_COLORS}"   "$sz" "$f"
        else
            printf -- '%s\t%s\n' "$sz" "$f"
        fi
    done

    IFS="$IFS_ORIGINAL"
}

# count and list directory sizes, including hidden dirs
lads()
{
    lds "*/" ".*/"
}

# display only dirs/files with given octal permissions for current user
lo()
{
    local cmd
    local str
    local -a fs

    # Contruct proper command and display string
    case "$1" in
        0) str="no permissions"              ; cmd=""                                ;; # TODO
        1) str="Executable"                  ; cmd="-executable"                     ;;
        2) str="Writable"                    ; cmd="-writable"                       ;;
        3) str="Writable/executable"         ; cmd="-writable -executable"           ;;
        4) str="Readable"                    ; cmd="-readable"                       ;;
        5) str="Readable/executable"         ; cmd="-readable -executable"           ;;
        6) str="Readable/writable"           ; cmd="-readable -writable"             ;;
        7) str="Readable/writable/executable"; cmd="-readable -writable -executable" ;;

        *) error "Invalid octal permission."
           return 1
           ;;
    esac

    # default: find non-dot files only.
    # when passing 2 args: find also dot-files.
    if [ $# -ne 2 ]; then
        cmd="-name \"[^\\.]*\" "$cmd; fi

    echo "$str files:"

    # the actual find
    IFS=$'\n'
        fs=($(eval find . -maxdepth 1 -type f $cmd))
    IFS="$IFS_ORIGINAL"

    # parse file list and pass on to multicolumn_ls
    if [[ ${#fs[@]} != 0 ]]; then

        # add quotes to all args
        for ((i=0; i<${#fs[@]}; ++i)); do
            fs[$i]=\"${fs[i]#./}\"; done

        # and call (NOTE: eval required for quote expansion)
        eval multicolumn_ls "${fs[@]}"

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

# Save a directory to the dirstack file, and check if its unique
_add_dir_to_stack()
{
    local -r addition="$(normalize_dir "$1")"

    _lock_dirstack

    if [ -e "${DIRSTACK_FILE}" ]
    then
        local dirline dir
        local -i counter
        local -i was_present=0
        local -r tmp="$(mktemp)"

        # Read current dirstack
        IFS=$'\n'
            local -ar stack=($(cat "${DIRSTACK_FILE}"))
        IFS="$IFS_ORIGINAL"

        # - If new directory has already been visited, increment its visits counter
        # - If directory is not found, add it with its visits counter set to 1
        for dirline in "${stack[@]}"; do

            dir="${dirline:((DIRSTACK_COUNTLENGTH+1))}"
            counter="${dirline:0:${DIRSTACK_COUNTLENGTH}}"

            if [ "${addition}" == "${dir}" ]; then
                was_present=1
                printf -- "%${DIRSTACK_COUNTLENGTH}d "'%s\n' $((counter+1)) "${dir}" >> "${tmp}"
            else
                echo "${dirline}" >> "${tmp}"
            fi
        done

        if [[ $was_present == 0 ]]; then
            printf -- "%${DIRSTACK_COUNTLENGTH}d %s"'\n' 1 "${addition}" >> "${tmp}"; fi

        # Sort according to most visits
        sort -r "${tmp}" > "${DIRSTACK_FILE}"
        rm "${tmp}"

        # TODO: (Rody Oldenhuis) this means the newly added dir will be wiped
        # immediately, never giving it a chance to rise up in popularity...
        # If size exceeded, chop off the least popular dirs
        #if [[ $(wc -l < "${DIRSTACK_FILE}") > $DIRSTACK_MAXLENGTH ]]; then
        #    head -$DIRSTACK_MAXLENGTH > "${tmp}"
        #    mv -f "${tmp}" "${DIRSTACK_FILE}"
        #fi

    else
        printf -- "%${DIRSTACK_COUNTLENGTH}d %s\n" 1 "${addition}" > "${DIRSTACK_FILE}"
    fi

    _unlock_dirstack

    # Check if all directories still exist
    ( _check_dirstack & )

    IFS="$IFS_ORIGINAL"
}

# Remove a dir from the stack, if it exists
_remove_dir_from_stack()
{
    # No arguments -- quick exit
    if [[ $# == 0 ]]; then
        return 0; fi

    # No dir stack -- can't remove anything
    if [ ! -e "${DIRSTACK_FILE}" ]; then
        error "No directories in stack."
        return 1
    fi

    _lock_dirstack

    IFS=$'\n'
        local -ar stack=( $(cat "${DIRSTACK_FILE}") )
    IFS="$IFS_ORIGINAL"

    # File present, but empty -- can't remove anything
    if [ ${#stack[@]} -eq 0 ]; then
        error "No directories in stack."
        _unlock_dirstack
        return 1
    fi

    # Recurse for more than one argument
    if [ $# -gt 1 ]
    then
        while (( "$#" )); do
            _remove_dir_from_stack "$1" || break
            shift
        done

    # Single-argument call
    else
        local -i was_present=0
        local -r removal="$1"
        local -r tmp=$(mktemp)

        # Integer argument
        if [[ ${removal} =~ ^[0-9]+$ ]]; then

            # Check it!
            if [[ ${removal} > ${#stack} ]]; then
               error "Requested index (%d) exceeds number of directories in stack (%d)." ${removal} ${#stack}
               _unlock_dirstack
               return 1
            fi

            # Remove it
            for ((i=0; i<${#stack}; ++i)); do
                if [ $i -ne ${removal} ]; then
                    echo "${stack[$i]}" >> "${tmp}"
                else
                    was_present=1
                fi
            done

        # String argument: remove first (partial) match
        else
            local dir
            local -r deletion="$(normalize_dir "${removal}")"

            for dir in "${stack[@]}"; do
                if [[ "${dir:((DIRSTACK_COUNTLENGTH+1))}" != *"${deletion}"* ]]; then
                    echo "${stack[$i]}" >> "${tmp}"
                else
                    was_present=1
                fi
            done
        fi

        if [ $was_present -eq 1 ]; then
            mv "${tmp}" "${DIRSTACK_FILE}"
        else
            warning 'Given string "%s" did not yield a (partial) match in directory stack; nothing changed.' "${removal}"
            rm "${tmp}"
        fi
    fi

    _unlock_dirstack
    IFS="$IFS_ORIGINAL"
}

# Check dirstack file if all directories it contains still exist
_check_dirstack()
{
    if [ -e "${DIRSTACK_FILE}" ]
    then
        local -r tmp=$(mktemp)
        local dir dirline

        # Read current dirstack
        _lock_dirstack

        IFS=$'\n'
            local -ar stack=($(cat "${DIRSTACK_FILE}"))
        IFS="$IFS_ORIGINAL"

        # Loop through all dirs one by one. If they exist, print
        # them into a tempfile
        for dirline in "${stack[@]}"; do
            dir="${dirline:((DIRSTACK_COUNTLENGTH+1))}"
            if [ -e "${dir}" ]; then
                echo "${dirline}" >> "${tmp}"; fi
        done

        # Then overwrite the original dirstack file with the tempfile content
        mv -f "${tmp}" "${DIRSTACK_FILE}"
        _unlock_dirstack
    fi

    IFS="$IFS_ORIGINAL"
}

# Navigate to directory. Check if directory is in a repo
_rbp_cd()
{
    # First cd to given directory

    # Home
    if [[ $# == 0 ]]; then
        cd -- "$HOME" 2> >(error)

    # Previous
    elif [[ $# == 1 && "-" == "$1" ]]; then
        cd - 2> >(error)

    # Help call
    elif [[ $# -ge 1 && "-h" = "$1" || "--help" = "$1" ]]; then
        cd --help
        return 0

    # All others
    else
		cd -- "$@" 2> >(error)
    fi

    # if successful, save to dirstack, display abbreviated dirlist and
    # check if it is a GIT repository
    if [[ $? == 0 ]]; then

        # Save to dirstack file and check if unique
        (_add_dir_to_stack "$PWD" &)

        # Assume we're not going to use any of the repository modes
        _leave_repo

        # Check if we're in a repo. If so, enter a repo mode
        repo=($(check_repo))
        if [[ $? == 0 ]]; then
            case "${repo[0]}" in
                "git") _enter_GIT "${repo[@]:1}" ;;
                "svn") _enter_SVN "${repo[@]:1}" ;;
                "hg")  _enter_HG  "${repo[@]:1}" ;;
                "bzr") _enter_BZR "${repo[@]:1}" ;;
                *) ;;
            esac
        fi

        clear
        multicolumn_ls

    fi
}

# jump dirs via dir-numbers. Inspired by tp_command(), by
# Alvin Alexander (DevDaily.com)
_cdn()
{
    # Remove non-existent dirs from dirstack
    _check_dirstack

    # create initial stack array
    _lock_dirstack
    IFS=$'\n'
        local -a stack=( $(cat "${DIRSTACK_FILE}") )
    IFS="$IFS_ORIGINAL"
    _unlock_dirstack

    # list may be empty
    if [ ${#stack[@]} -eq 0 ]; then
        echo "No directories have been visited yet."
        return
    fi

    # Parse arguments
    local dir dirline
    local -i supress_colors=1
    local -i intarg=-1
    local namearg=

    while (( "$#" )); do
        case "$1" in

            "-c"|"--color"|"--colors")
                supress_colors=0
                ;;

            "-r"|"--remove")
                # Remove all arguments
                _remove_dir_from_stack "${@:2}"
                if [ $? -ne 0 ]; then
                    return $?; fi

                # When still OK, show new list
                _cdn
                return 0
                ;;

            *) if [[ $1 =~ ^[0-9]+$ ]]; then
                    intarg=$1
               else
                    namearg="$1"
               fi
               break
               ;;
        esac
        shift
    done

    # Integer argument provided: go to dir number
    if [ $intarg -ne -1 ]; then
        if [ $intarg -le ${#stack[@]} ]; then
            _cd "${stack[$intarg]:((DIRSTACK_COUNTLENGTH+1))}"
            return 0
        else
            error "given directory index exceeds number of directories visited."
            return 1
        fi

    # String argument provided: Search all dirs in local dir AND dirstack for first partial match
    elif [ -n "$namearg" ]; then

        # Get local dirs
        IFS=$'\n'
            local -ar local_dirs=($(command ls -1bd */ 2> /dev/null))
        IFS="$IFS_ORIGINAL"

        # First check for exact match in local dirs
        if [ ${#local_dirs} -ne 0 ]
        then
            for dir in "${local_dirs[@]}"; do
                if [ "${dir}" = "${namearg}" ]; then
                    _cd "${dir}"
                    return 0
                fi
            done

            # Add local directories to stack
            stack=( "${local_dirs[@]}" "${stack[@]}" )
        fi

        # Otherwise, go for partial mathes in local dirs + dirstack.
        # TODO: prefer matches at the very END of the string
        for dirline in "${stack[@]}"
        do
            # Local dirs have no counter, dirstack dirs do. In the latter case, remove
            # the counter from the variable
            dir="${dirline}"
            if [[ "${dir:0:((DIRSTACK_COUNTLENGTH+1))}" =~ ^[[:space:]]*[0-9]+[[:space:]] ]]; then
                dir="${dirline:((DIRSTACK_COUNTLENGTH+1))}"; fi

            # CD to patially-matched dirname
            if [[ "$dir" == *"${namearg}"* ]]; then
                _cd "${dir}"
                return 0
            fi
        done

        error "no partial match for input string \"%s\".\n"  "${namearg}"
        return 1

    # If no function arguments provided, show list
    else
        IFS=$'\n'

        local -i i
        local -a repos=($(check_repo "${stack[@]}"))
        local -a types=($(echo "${repos[*]}" | cut -f 1  -d " "))
        local -a paths=($(echo "${repos[*]}" | cut -f 2- -d " "))

        IFS="$IFS_ORIGINAL"

        # Colorless
        if [ $supress_colors -eq 1 ]; then

            # Don't pass through prettyprint_dir(), it's faster to just truncate
            # here and print immediately (Cygwin spawning a hundred processes is something
            # Kaspersky does not like -- cdn() will be crawling)
            local -r pwdmaxlen=$(($COLUMNS/3))

            for ((i=0; i<${#repos[@]}; i++)); do

                dir="${stack[$i]:((DIRSTACK_COUNTLENGTH+1))}"

                if [ ${#dir} -gt $pwdmaxlen ]; then
                    dir="...${dir: ((-${pwdmaxlen}-3))}"; fi

                printf -- "%3d: %-${pwdmaxlen}s\n" $i "${dir}"
            done

        # Colored list, taking into account dir/symlink coloring and repo coloring
        else
            for ((i=0; i<${#repos[@]}; i++)); do
                (printf -- "%3d: %s\n" $i "$( prettyprint_dir "${stack[$i]:((DIRSTACK_COUNTLENGTH+1))}" "${types[$i]}" "${paths[$i]}" )" &); done
        fi
    fi
}


# TODO: autocomplete dirs in the stack bash-ido style
# (if none exist in the current path)
_cdn_completer()
{
    local -r cur=${COMP_WORDS[COMP_CWORD]}
    local opts=""

    if [ -e "${DIRSTACK_FILE}" ]
    then
        local dir dirline

        # Read current dirstack
        _lock_dirstack

        # HISTORY COMPLETION
        IFS=$'\n'
            local -a stack=($(cat "${DIRSTACK_FILE}"))
        IFS="$IFS_ORIGINAL"

        for ((i=0; i<${#stack[@]}; ++i)); do
            stack[i]="${stack[i]:((${DIRSTACK_COUNTLENGTH}+1))}"; done
        opts="${stack[@]}"

        # CURRENT DIR COMPLETION
        if [ -z "$cur" ]; then
            cdir="."
        elif [[ "${cur:${#cur} - 1}" == '/' ]]; then
            cdir="$cur"
        else
            cdir=$(command dirname ${cur})
        fi

        for i in $(command ls "$cdir" 2>/dev/null);  do
            opts="$opts $(basename -- "$i" 2>&1 > /dev/null)"
        done

        _unlock_dirstack

    else
        COMPREPLY=()
    fi

    IFS="$IFS_ORIGINAL"



    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0

}
complete -F _cdn_completer -o nospace cdn


# create dir(s), taking into account current repo mode
_rbp_mkdir()
{
    mkdir -p -- "$@" 2> >(error)
    if [[ $? == 0 ]];
    then
        if [[ ! -z $REPO_MODE && $REPO_MODE == 1 ]];
        then
            print_list_if_OK 0

            addcmd=$(get_repo_cmd $REPO_CMD_add)
            if (eval "$addcmd" "$@" "$dump_except_error"); then
                repo_cmd_exit_message "Added \"$*\" to the repository."
            else
                warning "Could not add \"$*\" to the repository."
            fi
        fi
    fi
}

# remove dir(s), taking into account current repo mode
# TODO: not done yet
_rbp_rmdir()
{
    rmdir "$@" 2> >(error)
    print_list_if_OK $?
    (_check_dirstack &)
}

# remove file(s), taking into account current repo mode
_rbp_rm()
{
    # we are in REPO mode
    if [[ ! -z $REPO_MODE && $REPO_MODE -eq 1 ]]; then

        # perform repo-specific delete
        local -r err=$(eval ${REPO_CMD_remove} "$@" 2>&1)
        local not_added
        local outside_repo

        # different repositories issue different errors
        case "$REPO_TYPE" in

            "git")
                not_added="did not match any files"
                outside_repo="outside repository"
                ;;

            "svn")
                # TODO
                not_added=""
                outside_repo=""
                ;;

            "hg")
                # TODO
                not_added=""
                outside_repo=""
                ;;

            "bzr")
                # TODO
                not_added=""
                outside_repo=""
                ;;

            *) # anything erroneous does the same as no repo
                rm -vI "$@" 2> >(error)
                print_list_if_OK $?
                ;;
        esac

        # All was OK
        if [[ -z "$err" ]]; then

            repo_cmd_exit_message "Removed \"$*\" from repository."

        # remove non-added or external files
        elif [[ "$err" =~ ${not_added} ]]; then

            while true; do

                warning "Some files were never added to the repository\nDo you wish to remove them anyway? [N/y] "
                read -rp " " yn

                case "$yn" in

                    [Yy]*)
                        rm -vI "$@" 2> >(error)
                        print_list_if_OK $?
                        break
                        ;;

                    [Nn]*)
                        break
                        ;;

                    *)  echo "Please answer yes or no."
                        ;;
                esac
            done

        else
            if [[ "$err" =~ ${outside_repo} ]]; then
                rm -vI "$@" 2> >(error)
                if [ $? -eq 0 ]; then
                    print_list_if_OK 0
                    warning "Some files were outside the repository."
                fi
            else
                # stderr was not empty, but none of the expected strings; rethrow
                # whatever error git issued
                error "$err"
                return 1
            fi

        fi

    # not in REPO mode
    else
        rm -vI "$@" 2> >(error)
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
_rbp_mv()
{
    # Help call
    if [[ $# -ge 1 && "-h" = "$1" || "--help" = "$1" ]]; then
        mv --help
        return 0
    fi

    # check if target is in REPO
    local source
    local source_repo
    local target_repo=$(check_repo $(dirname "${@:$#}"))

# TODO!
    ## if that is so, (repo-)move all sources to target
    #if [ $? -eq 0 ]; then
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
    if [[ ! -z $REPO_MODE && $REPO_MODE == 1 && $REPO_TYPE == "git" ]]; then

        local match="outside repository"
        local err=$(git mv "$@" 1> /dev/null 2> >(error))

        if [ $? -ne 0 ]; then
            if [[ "$err" =~ "${match}" ]]; then
                mv -iv "$@" 2> >(error)
                if [[ $? == 0 ]]; then
                    print_list_if_OK $?
                    warning "Target and/or source was outside repository";
                fi
            else
                echo $err
            fi
        fi

    else
        mv -iv "$@" 2> >(error)
        print_list_if_OK $?
    fi
}

# Make simlink, taking into account current repo mode
# TODO: needs work...auto-add any new files/dirs, but the 4 different
# forms of ln make this complicated
_rbp_ln()
{
    # Help call
    if [[ $# -ge 1 && "-h" = "$1" || "--help" = "$1" ]]; then
        ln --help
        return 0
    fi

    if (ln -s "$@" 2> >(error))
    then

        print_list_if_OK 0

        if [[ ! -z $REPO_MODE && $REMO_MODE == 1 ]];
        then
            addcmd=$(get_repo_cmd "$REPO_CMD_add")
            if (eval "$addcmd" "$@" "$dump_except_error"); then
                repo_cmd_exit_message "Added new file(s) \"$@\" to the repository."
            else
                warning "Created link(s) \"$@\", but could not add it to the repository."
            fi
        fi
    fi
}

# copy file(s), taking into account current repo mode
_rbp_cp()
{
    # Help call
    if [[ $# -ge 1 && "-h" == "$1" || "--help" == "$1" ]]; then
        cp --help
        return 0
    fi

    local cpcmd
    local -ir nargin=$#

    local -a arglist=("$@")
    local args=''

    # Explicitly quote all arguments (needed because eval())
    for arg in "${arglist[@]}"; do
        args="$args \"$arg\""; done

    # nominal copy command
    cpcmd="rsync -aAHch --info=progress2 ${args}"

    # optional args
    while (( "$#" )); do

        case "$1" in

            # cp -M = cp <file> <destination1> <destination2> ...
            "-M"|"--multiple-destination"|"--multidest")
                cpcmd="echo \"\${@:2:\$nargin}\" | xargs -n1 -P $(nproc --all) -- rsync -aAHch --info=progress2 -- \"\$1\""
                ((nargin--))
                shift
                ;;

            "--")
                ((nargin--))
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done

    # 1-argument copy copies to same destination, with "COPY" appended
    if [[ $nargin == 1 ]]; then
        cp "$1" "$1_COPY"
        print_list_if_OK $?
        return
    fi

    # Attach stderr to error()
    cpcmd="${cpcmd} 2> >(error)"

    # REPO mode
    local -i cmd_ok=0
    if [[ ! -z $REPO_MODE && $REPO_MODE == 1 ]]; then

        #  - source IN  repo, target IN repo   ← git add "target/source"
        #  - source OUT repo, target OUT repo  ← do nothing
        #  - source IN  repo, target OUT repo  ← do nothing
        #  - source OUT repo, target IN  repo  ← git add "target/source"
        #
        #  - source is DIR, target is DIR    ← OK; "source" will be subdir of "target"
        #  - source is FILE, target is DIR   ← OK; "source" will be subdir of "target"
        #  - source is DIR, target is FILE   ← error, with sidenote:
        #  - source is FILE, target is FILE  ← OK, with sidenote:
        #    - there is 1 source             ← simple rename operation
        #    - there are multiple sources    ← ask to make tarball
        #
        #  - source EXISTS, target DOESN'T EXIST         ← OK
        #  - source DOESN'T EXIST, target DOESN'T EXIST  ← error (handled by rsync)
        #  - source DOESN'T EXIST, target EXISTS         ← error (handled by rsync)

        # First, carry out the copy
        if eval "$cpcmd";
        then

            # Then add sources to repository if needed
            local -r target="${arglist[-1]}"
            local -i target_exists=0
            local -i target_in_repo=0
            local -i target_already_tracked=0
            local -i target_is_dir=0

            local    src
            local -i src_is_dir
            local -i src_in_repo

            local -i repocmd_ok
            local -r repo_add=$(get_repo_cmd "$REPO_CMD_add")
            local -r istracked=$(get_repo_cmd "$REPO_CMD_trackcheck")

            if (eval "$istracked" "$target" "$dump_except_error"); then
                target_already_tracked=1;
                target_exists=1;
            fi
            if [[ -d "$target" ]]; then
                target_is_dir=1;
                target_exists=1;
            fi
            if [[ "$REPO_PATH" = *"$target"* ]]; then
                target_in_repo=1
            fi

            echo ""
            for src in "${arglist[@]}"; do

                src_is_dir=0;
                src_in_repo=0;

                if [[ -d "$src" ]]; then
                    src_is_dir=1; fi
                if (eval "$istracked" "$src" "$dump_except_error");
                    then src_in_repo=1; fi

                #  - source IN  repo, target IN repo   ← git add "target/source"
                #  - source OUT repo, target OUT repo  ← do nothing
                #  - source IN  repo, target OUT repo  ← do nothing
                #  - source OUT repo, target IN  repo  ← git add "target/source"

                # TODO: implement the logic as commented above
                if [[ $target_in_repo == 0 ]]; then

                    eval "$repo_add" "$src"* "$dump_except_error"
                    repocmd_ok=$?

                    if $repocmd_ok; then
                        infomessage "Added \"$src\" to the repository."
                    else
                        cmd_ok=1
                        warning "Copied \"$src\", but could not add it to the repository."
                    fi

                fi


            done
            echo ""

        fi

    # normal mode
    else
        eval "$cpcmd"
    fi

    print_list_if_OK "$cmd_ok"
}

# touch file, taking into account current repo mode
_rbp_touch()
{
    if (touch "$@" 1> /dev/null 2> >(error));
    then
        print_list_if_OK 0

        if [[ ! -z $REPO_MODE && $REPO_MODE == 1 ]];
        then
            addcmd=$(get_repo_cmd "$REPO_CMD_add")
            if (eval "$addcmd" "$@" "$dump_except_error"); then
                repo_cmd_exit_message "Added \"$*\" to the repository."
            else
                warning "Created \"$*\", but could not add it to the repository."
            fi
        fi
    fi
}


# --------------------------------------------------------------------------------------------------
# Frequently needed functionality
# --------------------------------------------------------------------------------------------------

# copy all relevant bash config files to a different (bash > 4.0) system
spread_the_madness()
{
    scp ~/.bash_aliases "$@" 2> >(error)
    if [ $? -eq 0 ];
    then
        scp ~/.bash_functions "$@" 2> >(error) && \
        scp ~/.bashrc "$@"         2> >(error) && \
        scp ~/.dircolors "$@"      2> >(error) && \
        scp ~/.inputrc "$@"        2> >(error) && \
        scp ~/.awk_functions "$@"  2> >(error) && \
        scp ~/.git_prompt "$@"     2> >(error) && \
        scp ~/.git_completion "$@" 2> >(error)
    else
        error "failed to proliferate Rody's bash madness to remote system."
        return 1
    fi
}

# Extract some arbitrary archive
extract()
{
    if [[ -f "$1" && -r "$1" ]] ; then
        case "$1" in
            *.tar.bz2) tar xjvf "$1"   2> >(error) ;;
            *.tar.gz)  tar xzvf "$1"   2> >(error) ;;
            *.bz2)     bunzip2  "$1"   2> >(error) ;;
            *.rar)     rar x    "$1"   2> >(error) ;;
            *.gz)      gunzip   "$1"   2> >(error) ;;
            *.tar)     tar xvf  "$1"   2> >(error) ;;
            *.tbz2)    tar xjvf "$1"   2> >(error) ;;
            *.tgz)     tar xzvf "$1"   2> >(error) ;;
            *.zip)     unzip    "$1"   2> >(error) ;;
            *.Z)       uncompress "$1" 2> >(error) ;;
            *.7z)      7z x "$1"       2> >(error) ;;

            *) warning "'%s' cannot be extracted via extract()."  "$1";;
        esac
    else
        error "'%s' is not a valid, readable file." "$1"
        return 1
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

    local before
    local after
    local f

    # period is optional
    before=$1;
    after=$2

    if [ "${before:0:1}" != "." ]; then
        before=".$before"; fi
    if [ "${after:0:1}" != "." ]; then
        after=".$after"; fi

    # loop through file list
    for f in *$before; do
        mv "$f" "${f%$before}$after" 2> >(error); done

    clear
    multicolumn_ls
}

# instant calculator
C() {
    echo "$@" | /usr/local/bin/bc -lq
}

# Generalised manpages
man()
{
    #(from https://unix.stackexchange.com/a/18088)
    case "$(type -t "$1"):$1" in

        # built-in
        builtin:*) help "$1" | "${PAGER:-less}"
                   ;;

        # pattern
        *[[?*]*) help "$1" | "${PAGER:-less}"
                 ;;

        # something else, presumably an external command
        # or options for the man command or a section number
        *) command -p man "$@"
           ;;

    esac
}

# grep all processes in wide-format PS, excluding "grep" itself
psa()
{
    if [[ $# == 0 ]]; then
        return 1; fi

    ps auxw | grep -EiT --color=auto "[${1:0:1}]${1:1}" 2> >(error)
}

# find N largest files in current directory and all subdirectories
#
# Must be aliased in .bash_aliases.
#
# no arguments   : list 10 biggest files
# single argument: list N biggest files
_findbig()
{

    # parse input arguments
    if [ $# -gt 1 ]; then
        error "Findbig takes at most 1 argument.";
        return 1
    fi

    local -i num
    if [ $# -eq 1 ]; then
        num=$1 # argument is number of files to print
    else
        num=10 # which defaults to 10
    fi

    # initialize some local variables
    local lsout perms dir fcolor file f

    # find proper color used for directories
    if [[ $USE_COLORS == 1 ]]; then
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
        if [ $USE_COLORS  -eq 1 ]; then
            local fcolor=${LS_COLORS##*'*'.${file##*.}=};
            fcolor=${fcolor%%:*}
            if [ -z $(echo ${fcolor:0:1} | tr -d "[:alpha:]") ]; then
                fcolor=${LS_COLORS##*no=};
                fcolor=${fcolor%%:*}
            fi
            printf -- "%s\E[${dcolor#*;}m%s\E[${fcolor#*;}m%s\\n${RESET_COLORS}" $perms $dir $file
        else
            printf -- '%s%s%s\n' $perms $dir $file
        fi
    done

    IFS="$IFS_ORIGINAL"
}

# find biggest applications
# must be aliased in .bash_aliases
# FIXME: can't alias this one directly due to {} symbols
_findbig_applications()
{
    dpkg-query --show --showformat='${Package;-50}\t${Installed-Size}\n' | sort -k 2 -rn | grep -v deinstall | awk '{printf "%.3f MB \t %s\n", $2/(1024),  $1 }' | head -n 10
}

# chroot some environment
chroot_dir()
{
    # Check input
    if [ $# -ne 1 ]; then
        error "Invalid number of arguments received.              "
        echo  "                                                   "
        echo  "Usage: $0 [PATH]                                   "
        echo  "                                                   "
        echo  "Where PATH is a valid dirname to put the chroot in."
        echo  "Example:                                           "
        echo  "   $0 /media/SYSTEM_DISK/                          "
        echo  "                                                   "
        return 1
    fi

    local bind_dirs
    local chroot_path
    local -i i

    bind_dirs=("/proc" "/sys" "/dev" "/dev/pts" "/dev/shm")

    # Mount the essentials to the system
    chroot_path="$1"
    for ((i=0; i<${#bind_dirs[@]}; ++i)); do
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
            printf -- "Could not enter chroot: %s" $(cat $tmpErr)
        # fi
    fi

    # Unmount everything again when chroot exits
    for ((; i>=0; --i)); do
        sudo umount "${chroot_path}${bind_dirs[$i]}"; done
}

# gedit, geany and pcmanfm (and windows equivalents):
# ALWAYS in background and immune to terminal closing!
_gedit()
{
    if [[ "$on_windows" == 0 ]]; then
        (gedit "$@" &) | nohup &> /dev/null;
    else
        (notepad "$@" &) | nohup &> /dev/null;
    fi
}

_geany()
{
    if [[ "$on_windows" == 0 ]]; then
        if which geany; then
            (geany "$@" &) | nohup &> /dev/null;
        else
            _gedit
        fi
    else
        if which "notepad++"; then
            (notepad++ "$@" &) | nohup &> /dev/null;
        else
            (notepad "$@" &) | nohup &> /dev/null;
        fi
    fi
}

_pcmanfm()
{
    if [[ "$on_windows" == 0 ]]; then
        (pcmanfm . &) | nohup &> /dev/null;
    else
        if which "TOTALCMD"; then
            (TOTALCMD . &) | nohup &> /dev/null;
        else
            (explorer . &) | nohup &> /dev/null;
        fi
    fi
}

# Queued move
mvq()
{
    if [ $# -lt 2 ]; then
        error "mvq requires at least 2 arguments."
        return 1
    fi

    # TODO: nohup doesn't allow for easy redirection
    #(nohup nice -n 19 mv "$@" 2> >(error) &)
    (nice -n 19 mr "$@" 1> >(warning) 2> >(error) &)
    printf -- 'Moving %s to "%s"...\n'  "$(quoted_list ${@: 1:$(($#-1))})"  "${@: -1}"
}

# Queued copy
cpq()
{
    if [ $# -lt 2 ]; then
        error "cpq requires at least 2 arguments."
        return 1
    fi

    # TODO: nohup doesn't allow for easy redirection
    #(nohup nice -n 19 cp -r "$@" 1> >(warning) 2> >(error) &)
    (nice -n 19 cp -r "$@" 1> >(warning) 2> >(error) &)
    printf -- 'Copying %s to "%s"...\n'  "$(quoted_list ${@: 1:$(($#-1))})"  "${@: -1}"
}

# Multi-source, multi-destination copy/move
_spread()
{
    local cmd="cp"

    local -a sources=()
    local -a targets=()

    local -i collecting_sources=1
    local -i do_repository=0


    # Collect arguments
    while (( "$#" )); do

        case "$1" in

            "-c"|"--copy") cmd="cp" ;;
            "-m"|"--move") cmd="mv" ;;

            "-r"|"--repository") do_repository=1 ;;

            "-s"|"--sources")
                collecting_sources=1
                ;;

            "-t"|"--targets")
                collecting_sources=0
                ;;

            *)  if [[ $collecting_sources == 1 ]]; then
                    sources+=("$1")
                else
                    targets+=("$1")
                fi
                ;;
        esac
        shift
    done

    # Check arguments
    if [[ ${#sources[@]} == 0 ]]; then
        error "No source files/directories given."; return 1; fi
    if [[ ${#sources[@]} == 0 ]]; then
        error "No target files/directories given."; return 1; fi

    # Execute command
    for target in "${targets[@]}"; do

        # Move/copy sources to current target
        if [ $do_repository -eq 1 ]; then
            case $cmd in
                "cp") (_cp "${sources[@]}" "${target}" 1> >(warning) 2> >(error) &); ;;
                "mv") (_mv "${sources[@]}" "${target}" 1> >(warning) 2> >(error) &); ;;
                *)    error "Invalid command: '%s'." "$cmd"
                      return 1
                      ;;
            esac
        else
            case $cmd in
                "cp") cpq "${sources[@]}" "${target}" ;;
                "mv") mvq "${sources[@]}" "${target}" ;;
                *)    error "Invalid command: '%s'." "$cmd"
                      return 1
                      ;;
            esac
        fi

        # Halt on first error
        if [ $? -ne 0 ]; then
            return 1; fi
    done
}

# Multi-source, multi-destination copy
proliferate()
{
    _spread -c "$@"
}
# Multi-source, multi-destination move
spread()
{
    _spread -m "$@"
}


# export hi-res PNG from svg file
svg2png()
{
    if (which inkscape 2>&1 > /dev/null);
    then
        local svgname
        local pngname

        for f in "$@"; do
            svgname=$f
            pngname="${svgname%.svg}.png"
            inkscape "$svgname" --export-png=$pngname --export-dpi=250
        done
    else
        error "$0() needs an installation of inkscape, which doesn't seem to be present on this system."
        return 1
    fi
}

# check validity of XML
check_XML()
{
    for file in "$@"; do
        if (python -c "import sys,xml.dom.minidom as d; d.parse(sys.argv[1])" "$file");
        then
            echo "XML-file $file is valid and well-formed"
        else
            warning "XML-file $file is NOT valid"
        fi
    done
}


# ==================================================
# Github
# ==================================================

new_github_repo()
{
    git init
    git add -- * .gitignore
    git commit -m "First commit"
    git remote add origin git@github.com:rodyo/"${1}".git
    git push -u origin master
}

existing_github_repo()
{
    git remote add origin git@github.com:rodyo/"${1}".git
    git push -u origin master
}

# ==================================================
# GitLab
# ==================================================
# TODO



# ==================================================
# MATLAB / Simulink
# ==================================================

slgrep()
{
    if [ $# = 0 ]; then
        return; fi

    IFS_="$IFS";
    IFS=$'\n';

    for file in $(find . -type f); do

        local filename=$(basename "$file")
        local extension="${filename##*.}"
        filename="${filename%.*}"

        if [ "$extension" = "slx" ]; then
            local result=$(unzip -c "$file" | grep -EiIT --color=always --exclude-dir .svn --exclude-dir .git "$@")
            if [[ ! -z "$result" ]]; then
                printf -- "${START_COLORSCHEME}${FG_MAGENTA}${END_COLORSCHEME}%s${RESET_COLORS}: %s"'\n' "$file" "$result"; fi
        else
            grep -EiIT --color=auto --exclude-dir .svn --exclude-dir .git "$@" "$file" /dev/null
        fi

    done;

    IFS="$IFS_"
}
