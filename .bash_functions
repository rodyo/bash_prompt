
# --------------------------------------------------------------------------------------------------
# Colors are a mess in bash...
# --------------------------------------------------------------------------------------------------

readonly START_COLORSCHEME_PS1="\[\e["
readonly END_COLORSCHEME_PS1="m\]"

readonly START_COLORSCHEME="\e["
readonly END_COLORSCHEME="m"

# (Alias for better clarity)
readonly START_ESCAPE_GROUP="\e["
readonly END_ESCAPE_GROUP="m"

readonly RESET_COLORS="\e[0m"
readonly RESET_COLORS_PS1='\['"${RESET_COLORS}"'\]'


readonly TXT_BOLD="01"
readonly TXT_DIM="02"
readonly TXT_UNDERLINE="04"

readonly FG_BLACK="30"
readonly FG_RED="31"
readonly FG_GREEN="32"
readonly FG_YELLOW="33"
readonly FG_BLUE="34"
readonly FG_MAGENTA="35"
readonly FG_CYAN="36"
readonly FG_LIGHTGRAY="37"
readonly FG_DARKGRAY="90"
readonly FG_LIGHTRED="91"
readonly FG_LIGHTGREEN="92"
readonly FG_LIGHTYELLOW="93"
readonly FG_LIGHTBLUE="94"
readonly FG_LIGHTMAGENTA="95"
readonly FG_LIGHTCYAN="96"
readonly FG_WHITE="97"

readonly BG_BLACK="40"
readonly BG_RED="41"
readonly BG_GREEN="42"
readonly BG_YELLOW="43"
readonly BG_BLUE="44"
readonly BG_MAGENTA="45"
readonly BG_CYAN="46"
readonly BG_LIGHTGRAY="47"
readonly BG_DARKGRAY="100"
readonly BG_LIGHTRED="101"
readonly BG_LIGHTGREEN="102"
readonly BG_LIGHTYELLOW="103"
readonly BG_LIGHTBLUE="104"
readonly BG_LIGHTMAGENTA="105"
readonly BG_LIGHTCYAN="106"
readonly BG_WHITE="107"



# --------------------------------------------------------------------------------------------------
# Profiling
# --------------------------------------------------------------------------------------------------

# If/when profiling, surround the function to profile with _START_PROFILING;/_STOP_PROFILING;

declare -i DO_PROFILING=0

_START_PROFILING()
{
    which tee &>/dev/null && which date &>/dev/null && which sed &>/dev/null which paste &>/dev/null || \
        (error "cannot profile: unmet depenencies" && return)

    if [ $DO_PROFILING -eq 1 ]; then
        PS4='+ $(date "+%s.%N")\011 '
        exec 3>&2 2> >(tee /tmp/sample-time.$$.log |
                       sed  -u 's/^.*$/now/' |
                       date -f - "+%s.%N" > /tmp/sample-time.$$.tim)
        set -x
    else
        error "stray _START_PROFILING found"
    fi
}

_STOP_PROFILING()
{
    if [ $DO_PROFILING -eq 1 ]; then
        set +x
        exec 2>&3 3>&-

        printf " %-11s  %-11s   %s\n" "duration" "cumulative" "command" > ~/profile_report.$$.log
        paste <(
            while read tim; do
                [ -z "$last" ] && last=${tim//.} && first=${tim//.}
                crt=000000000$((${tim//.}-10#0$last))
                ctot=000000000$((${tim//.}-10#0$first))
                printf "%12.9f %12.9f\n" ${crt:0:${#crt}-9}.${crt:${#crt}-9} \
                                         ${ctot:0:${#ctot}-9}.${ctot:${#ctot}-9}
                last=${tim//.}
              done < /tmp/sample-time.$$.tim
            ) /tmp/sample-time.$$.log >> ~/profile_report.$$.log && \
        echo "Profiling report available in '~/profile_report.$$.log'"

    else
        error "stray _STOP_PROFILING found"
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
declare -r  DIRSTACK_LOCKFILE="${HOME}/.locks/.dirstack"
declare -ir DIRSTACK_LOCKFD=9

# Set up locking; see
# http://stackoverflow.com/a/1985512/1085062

mkdir -p "$(dirname ${DIRSTACK_LOCKFILE})" 2>&1 1> /dev/null
rm -f "${DIRSTACK_LOCKFILE}" 2>&1 1> /dev/null
touch "${DIRSTACK_LOCKFILE}"

_dirstack_locker()  { flock -$1 $DIRSTACK_LOCKFD; }

_lock_dirstack()    { _dirstack_locker e; }
_unlock_dirstack()  { _dirstack_locker u; }

_prepare_locking()  { eval "exec ${DIRSTACK_LOCKFD}>\"${DIRSTACK_LOCKFILE}\""; }

_prepare_locking


# Check for external tools and shell specifics
# --------------------------------------------------------------------------------------------------

declare -i processAcls=0
declare -i haveAwk=0

command -v lsattr &> /dev/null && processAcls=1 || processAcls=0
command -v awk &> /dev/null && haveAwk=1 || haveAwk=0

declare -i haveAllRepoBinaries=0

which git &>/dev/null && \
which svn &>/dev/null && \
which hg &>/dev/null && \
which bzr &>/dev/null && \
haveAllRepoBinaries=1 || haveAllRepoBinaries=0
#TODO: bash native method is virtually always faster...
haveAllRepoBinaries=0

# (Cygwin)
declare -i atWork=0
[ "$(uname -o)" == "Cygwin" ] && atWork=1 || atWork=0


# Create global associative arrays
# --------------------------------


declare -A REPO_COLOR
declare -A ALL_COLORS

declare -i USE_COLORS=0
if [ "yes" == "$SHELL_COLORS" ]; then
    USE_COLORS=1

    IFS=": "
        tmp=($LS_COLORS)
    IFS="$IFS_ORIGINAL"

    keys=("${tmp[@]%%=*}")
    keys=(${keys[@]/\*\./})
    values=(${tmp[@]##*=})

    for ((i=0; i<${#keys[@]}; ++i)); do
        ALL_COLORS["${keys[$i]}"]="${values[$i]}"; done

    unset tmp keys values
fi

# Repository info and generic commands
declare -i REPO_MODE=0;
REPO_TYPE=""
REPO_PATH=

# colors used for different repositories in prompt/prettyprint
REPO_COLOR[svn]=${START_COLORSCHEME}${TXT_BOLD}';'${FG_MAGENTA}${END_COLORSCHEME};    REPO_COLOR[bzr]=${START_COLORSCHEME}${TXT_BOLD}';'${FG_YELLOW}${END_COLORSCHEME}
REPO_COLOR[git]=${START_COLORSCHEME}${TXT_BOLD}';'${FG_RED}${END_COLORSCHEME};        REPO_COLOR[hg]=${START_COLORSCHEME}${TXT_BOLD}';'${FG_CYAN}${END_COLORSCHEME}
REPO_COLOR[---]=${START_COLORSCHEME}${ALL_COLORS[di]}${END_COLORSCHEME}


# error/warning functions
error()
{
    local msg

    # argument
    if [ -n "$1" ]; then
        msg="$(printf "$@")"

    # stdin
    else
        while read msg; do
            error "${msg}"; done
        return 0
    fi

    # Print the message, based on color settings
    if [ $USE_COLORS -eq 1 ]; then
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
        msg="$(printf "$@")"

    # stdin
    else
        while read msg; do
            warning "${msg}"; done
        return 0
    fi

    # Print the message, based on color settings
    if [ $USE_COLORS -eq 1 ]; then
        echo "${START_COLORSCHEME}${TXT_BOLD};${FG_ORANGE}${END_COLORSCHEME}WARNING: ${msg}${RESET_COLORS}"
    else
        echo "WARNING: ${msg}"
    fi

    return 0
}




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
}


# --------------------------------------------------------------------------------------------------
# Multicolumn colored filelist
# --------------------------------------------------------------------------------------------------

# TODO: field width of file size field can be a bit more flexible
#   (e.g., we don't ALWAYS need 7 characters...but: difficult if you want to get /dev/ right)
# TODO: show [seq] and ranges for simple sequences, with min/max file size

# FIXME: seems that passing an argument does not work properly
# FIXME: breaks when upgrading to Ubuntu 14.04??

multicolumn_ls()
{
    if [ $haveAwk -eq 1 ]; then

        local colorflag=
        if [ $USE_COLORS -eq 1 ]; then
            colorflag="--color"; fi

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
        local -r numColumns=$(($COLUMNS/$maxColumnWidth))
        local -r maxNameWidth=$(($maxColumnWidth-10))

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
            # TODO: also cifs and fuse.sshfs etc. --might-- support it, but how to check for this...
        esac

        ( ((${BASH_VERSION:0:1}>=4)) && [ $processAcls -eq 1 ] && if [ $haveAttrlist -eq 1 ]; then
            local -A attrlist
            local attlist=($(lsattr 2>&1))
            local attribs=($(echo "${attlist[*]%% *}"))
            local attnames=($(echo "${attlist[*]##*\.\/}"))
            for ((i=0; i<${#attnames[@]}; i++)); do
                if [ ${attribs[$i]%%lsattr:*} ]; then
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
        if [ $USE_COLORS -eq 1 ]; then
            printf $RESET_COLORS; fi

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
                if [ $USE_COLORS  -eq 1 ]; then

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
                        printf "%7s${START_COLORSCHEME}${TXT_BOLD};${FG_RED}${END_COLORSCHEME}%s${RESET_COLORS} ${START_COLORSCHEME}${paint}${END_COLORSCHEME}%-*s ${RESET_COLORS}" "${sizes[$ind]}${names[$ind]%% *}" "$lastsymbol" $maxNameWidth "${names[$ind]#* }"
                    else
                        # all others
                        printf "%7s${START_COLORSCHEME}${TXT_BOLD};${FG_RED}${END_COLORSCHEME}%s${RESET_COLORS} ${START_COLORSCHEME}${paint}${END_COLORSCHEME}%-*s ${RESET_COLORS}" "${sizes[$ind]}" "$lastsymbol" $maxNameWidth "${names[$ind]}"
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

    # initialize
    local -ri exitstatus=$?    # exitstatus of previous command
    local ES

    # Username color scheme
    local usrName=""
    if [ $USE_COLORS -eq 1 ]; then
        usrName="${START_COLORSCHEME_PS1}${TXT_BOLD};${FG_GREEN}${END_COLORSCHEME_PS1}"; fi

    # hostname color scheme
    local hstName=""
    if [ $USE_COLORS -eq 1 ]; then
        hstName="${START_COLORSCHEME_PS1}${FG_MAGENTA}${END_COLORSCHEME_PS1}"; fi


    # write previous command to disk
    (history -a &) &> /dev/null

    # Smiley representing previous command exit status
    ES='o_O '
    if [ $exitstatus -eq 0 ]; then
        ES='^_^ '; fi

    if [ $USE_COLORS -eq 1 ]; then
        ES="${START_COLORSCHEME_PS1}${TXT_DIM};${FG_GREEN}${END_COLORSCHEME_PS1}${ES}${RESET_COLORS_PS1}"; fi

    # Append system time
    ES="$ES"'[\t] '


    # Set new prompt (taking into account repositories)
    case "${REPO_TYPE}" in

        # GIT also lists branch
        "git")
            branch=$(git branch | command grep "*")
            branch="${branch#\* }"
            if [ $? -ne 0 ]; then
                branch="*unknown branch*"; fi

            if [ $USE_COLORS -eq 1 ]; then
                PS1="$ES${usrName}"'\u'"${RESET_COLORS_PS1}@${hstName}"'\h'"${RESET_COLORS_PS1} : "'\['"${REPO_COLOR[git]} [git: ${branch}] : "'\W'"/${RESET_COLORS_PS1} "'\$'" "
            else
                PS1="$ES"'\u@\h : [git: '"${branch}] : "'\W/ \$ ';
            fi
            ;;

        # SVN, Mercurial, Bazhaar
        "svn"|"hg"|"bzr")
            if [ $USE_COLORS -eq 1 ]; then
                PS1="$ES${usrName}"'\u'"${RESET_COLORS_PS1}@${hstName}"'\h'"${RESET_COLORS_PS1} : "'\['"${REPO_COLOR[${REPO_TYPE}]} [${REPO_TYPE}] : "'\W'"/${RESET_COLORS_PS1} "'\$'" "
            else
                PS1="$ES"'\u@\h : ['"${REPO_TYPE}] : "'\W/ \$ ';
            fi
            ;;

        # Normal prompt
        *)  if [ $USE_COLORS -eq 1 ]; then

                local -r dircolor="${START_COLORSCHEME_PS1}${TXT_BOLD};${FG_BLUE}${END_COLORSCHEME_PS1}"

                # non-root user: basename of current dir
                local working_dir='\W'

                # Root
                if [ `id -u` = 0 ]; then
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
    local -r move_cursor="\E7\E[001;$(($COLUMNS-${#PWD}-2))H${START_ESCAPE_GROUP}1${END_ESCAPE_GROUP}"
    local -r reset_cursor="\E8"
    if [ $USE_COLORS -eq 1 ]; then
        local -r bracket_open="${START_COLORSCHEME}${FG_GREEN}${END_COLORSCHEME}[${RESET_COLORS}"
        local -r bracket_close="${START_COLORSCHEME}${TXT_BOLD};${FG_GREEN}${END_COLORSCHEME}]${RESET_COLORS}"
    else
        local -r bracket_open="["
        local -r bracket_close="]"
    fi

    printf "${move_cursor}${bracket_open}${pth}${bracket_close}${reset_cursor}"

}

# make this function the function called at each prompt display
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
    printf "%s" "${@/#/$d}"
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
    local var="$@"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}


# Normalize directory string
# e.g.,  /foo/bar/../baz  ->  /foo/baz
normalize_dir()
{
    echo "$(readlink -m "$1")"
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
        if [ $i -eq $rmindex ]; then
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

# pretty print directory:
# - truncate (leading "...") if name is too long
# - colorized according to dircolors and repository info
prettyprint_dir()
{
    # No arguments, no function
    if [ $# -eq 0 ]; then
        return; fi

    local -a repoinfo
    local -ri pwdmaxlen=$(($COLUMNS/3))
    local original_pth

    if [ $USE_COLORS -eq 1 ]; then
        original_pth="$(command ls -d "${1/\~/${HOME}}" --color)"
    else
        original_pth="$(command ls -d "${1/\~/${HOME}}")"
    fi

    local pth="${original_pth/${HOME}/~}";


    if [ $# -lt 3 ]; then
        repoinfo=($(check_repo "$@"))
        if [ ${#repoinfo[@]} -gt 2 ]; then
            repoinfo[1]=$(strjoin "${IFS[0]}" "${repoinfo[@]:1}"); fi
    else
        repoinfo=("$2" "$3")
    fi

    # Color print
    if [ $USE_COLORS -eq 1 ]; then

        # TODO: dependency on AWK; include bash-only version
        if [ $haveAwk ]; then

            if [ "${repoinfo[0]}" != "---" ]; then
                local -r repoCol=${REPO_COLOR[${repoinfo[0]}]};
                local -r repopath="$(dirname "${repoinfo[1]}" 2> /dev/null)"
                pth="${pth/${repopath}/${repopath}$'\033'[0m$repoCol}"
            fi

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
            pthoffset=$((${#pth}-$pwdmaxlen))
            pth="...${pth:$pthoffset:$pwdmaxlen}"
        fi
        printf "$pth/"
    fi
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

            check=$(printf "%s " git && command cd "${dir}" && git rev-parse --show-toplevel 2> /dev/null)
            if [ $? -eq 0 ]; then echo "$check"; continue; fi

            check=$(printf "%s " svn && svn info "$dir" 2> /dev/null | awk '/^Working Copy Root Path:/ {print $NF}' && [ ${PIPESTATUS[0]} -ne 1 ])
            if [ $? -eq 0 ]; then echo "$check"; continue; fi

            check=$(printf "%s  " hg && hg root --cwd "$dir" 2> /dev/null)
            if [ $? -eq 0 ]; then echo "$check"; continue; fi

            check=$(printf "%s " bzr && bzr root "$dir" 2> /dev/null) ||
            if [ $? -eq 0 ]; then echo "$check"; continue; fi

            echo "--- [no_repository_found]"

        done

    # Not all repository systems have been installed; use bash to loop through the
    # directory tree in search of a repository identifier
    else

        local -ar slashes=("${dirs[@]//[^\/]/}")
        local -a repotype
        local -a reporoot

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
            # NOTE: ...the main speed problem on the LuxSpace machine is Kaspersky :(
            for (( j=${#slashes[$i]}; j>0; --j )); do
                [ -d "$dir/.git" ] && repotype[$i]="git" && cd "$dir" && reporoot[$i]="$PWD" && cd "$curdir" && break;
                [ -d "$dir/.svn" ] && repotype[$i]="svn" && cd "$dir" && reporoot[$i]="$PWD" && cd "$curdir" && break;
                [ -d "$dir/.bzr" ] && repotype[$i]="bzr" && cd "$dir" && reporoot[$i]="$PWD" && cd "$curdir" && break;
                [ -d "$dir/.hg"  ] && repotype[$i]="hg " && cd "$dir" && reporoot[$i]="$PWD" && cd "$curdir" && break;
                dir="$dir/.."
            done

        done

        for (( i=0;i<${#repotype[@]}; ++i )); do
            printf "%s %s\n" "${repotype[$i]} ${reporoot[$i]}"; done
    fi

}


# Update all repositories under the current dir
# TODO: also update git submodules, svn externals, etc.
update_all()
{
    local -a rp

    for d in */; do

        rp=($(check_repo "$PWD/$d"))

        cd "${rp[@]:1}"

        case "${rp[0]}" in
            "svn") svn update ;;
            "git") git pull   ;;
            "hg")  hg update  ;;
            "bzr") bzr update ;;
            *)  warning "Don't know how to update repository."
                ;;
        esac

        cd ..

    done
}

# Enter GIT mode
__enter_GIT()
{
    # set type
    REPO_TYPE="git"
    REPO_MODE=1
    REPO_PATH="$@"

    # alias everything
    alias gf="git fetch"                   ;  REPO_CMD_fetch="gf"
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
__enter_SVN()
{
    # enter SVN mode
    REPO_TYPE="svn"
    REPO_MODE=1
    REPO_PATH="$@"

    # alias everything
    alias su="svn up"           ; REPO_CMD_update="su"
    alias sc="svn commit -m "   ; REPO_CMD_commit="sc"
    alias ss="svn status"       ; REPO_CMD_status="ss"
}

# Enter Mercurial mode
__enter_HG()
{
    # enter GIT mode
    REPO_TYPE="hg"
    REPO_MODE=1
    REPO_PATH="$@"

    # alias everything
    # TODO
}

# Enter Bazaar mode
__enter_BZR()
{
    # enter BZR mode
    REPO_TYPE="bzr"
    REPO_MODE=1
    REPO_PATH="$@"

    # alias everything
    # TODO
}

# leave any and all repositories
__leave_repos()
{
    if [ $REPO_MODE -eq 0 ]; then
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
       dirs=$(command ls -dh1 --time-style=+ */ 2> /dev/null)
    else
       dirs=$(command ls -dh1 --time-style=+ "${@/%//}" 2> /dev/null)
    fi

    if [ $USE_COLORS  -eq 1 ]
    then
        # find proper color used for directories
        local -r color="${ALL_COLORS[di]}"

        # loop through dirlist and parse
        for f in $dirs; do
            sz=$(du -bsh --si $f 2> /dev/null);
            sz=${sz%%$'\t'*}
            printf "$sz\t\E[${color#*;}m\E[${color%;*}m$f\n${RESET_COLORS}"
        done

    else
        for f in $dirs; do
            sz=$(du -bsh --si $f 2> /dev/null);
            sz=${sz%%$'\t'*}
            printf "$sz\t$f\n"
        done
    fi

    IFS="$IFS_ORIGINAL"
}

# count and list directory sizes, including hidden dirs
lads()
{
    local sz
    local f
    local dirs

    clear
    IFS=$'\n'

    # When no argument is given, process all dirs and dot-dirs.
    # Otherwise: process only given dirs
    if [ $# -eq 0 ]; then
        dirs=$(command ls -dh1 --time-style=+ */ .*/ 2> /dev/null)
    else
        dirs=$(command ls -dh1 --time-style=+ "${@/%//}" 2> /dev/null)
    fi

    if [ $USE_COLORS  -eq 1 ]
    then
        # find proper color used for directories
        local -r color="${ALL_COLORS[di]}"

        # loop through dirlist and parse
        for f in $dirs; do
            sz=$(du -bsh --si $f 2> /dev/null);
            sz=${sz%%$'\t'*}
            printf "$sz\t\E[${color#*;}m\E[${color%;*}m$f\n${RESET_COLORS}"
        done

    else
        for f in $dirs; do
            sz=$(du -bsh --si $f 2> /dev/null);
            sz=${sz%%$'\t'*}
            printf "$sz\t$f\n"
        done
    fi

    IFS="$IFS_ORIGINAL"
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

        *) error "Invalid octal permission."; return 1 ;;
    esac

    # default: find non-dot files only.
    # when passing 2 args: find also dot-files.
    if [ $# -ne 2 ]; then
        cmd="-name \"[^\.]*\" "$cmd; fi

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

# Save a directory to the dirstack file, and check if its unique
__add_dir_to_stack()
{
    local -r addition="$(normalize_dir "$1")"

    _lock_dirstack

    if [ -e "${DIRSTACK_FILE}" ]
    then
        local dirline dir
        local -i counter
        local -i was_present=0
        local -r tmp=$(mktemp)

        # Read current dirstack
        IFS=$'\n'
            local -ar stack=($(cat "${DIRSTACK_FILE}"))
        IFS="$IFS_ORIGINAL"

        # - If new directory has already been visited, increment its visits counter
        # - If directory is not found, add it with its visits counter set to 1
        for dirline in "${stack[@]}"; do

            dir="${dirline:((${DIRSTACK_COUNTLENGTH}+1))}"
            counter="${dirline:0:${DIRSTACK_COUNTLENGTH}}"

            if [ "${addition}" == "${dir}" ]; then
                was_present=1
                printf "%${DIRSTACK_COUNTLENGTH}d %s\n"   $(($counter+1))   "${dir}"   >> "${tmp}"
            else
                echo "${dirline}" >> "${tmp}"
            fi
        done

        if [ $was_present -eq 0 ]; then
            printf "%${DIRSTACK_COUNTLENGTH}d %s\n" 1 "${addition}" >> "${tmp}"; fi

        # Sort according to most visits, and finish up
        sort -r "${tmp}" > "${DIRSTACK_FILE}"
        rm "${tmp}"

    else
        printf "%${DIRSTACK_COUNTLENGTH}d %s\n" 1 "${addition}" > "${DIRSTACK_FILE}"
    fi

    _unlock_dirstack

    # Check if all directories still exist
    ( __check_dirstack & )

    IFS="$IFS_ORIGINAL"
}

# Remove a dir from the stack, if it exists
__remove_dir_from_stack()
{
    # No arguments -- quick exit
    if [ $# -eq 0 ]; then
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
            __remove_dir_from_stack "$1" || break
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
            if [ ${removal} -gt ${#stack} ]; then
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
                if [[ "${dir:((${DIRSTACK_COUNTLENGTH}+1))}" != *"${deletion}"* ]]; then
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
__check_dirstack()
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
            dir="${dirline:((${DIRSTACK_COUNTLENGTH}+1))}"
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
_cd_DONTUSE()
{
    # first cd to given directory
    # NOTE: use "--" to allow dirnames like "+package" or "-some-dir"

    # Home
    if [ $# -eq 0 ]; then
        builtin cd -- "$HOME" 2> >(error)

    # Previous
    elif [[ $# -eq 1 && "-" = "$1" ]]; then
        builtin cd 2> >(error)

    # Help call
    elif [[ $# -ge 1 && "-h" = "$1" || "--help" = "$1" ]]; then
        builtin cd --help
        return 0

    # All others
    else
        builtin cd -- "$@" 2> >(error)
    fi

    # if successful, save to dirstack, display abbreviated dirlist and
    # check if it is a GIT repository
    if [ $? -eq 0 ]; then

        # Save to dirstack file and check if unique
        (__add_dir_to_stack "$PWD" &)

        # Assume we're not going to use any of the repository modes
        __leave_repos

        # Check if we're in a repo. If so, enter a repo mode
        repo=($(check_repo))
        if [ $? -eq 0 ]; then
            case "${repo[0]}" in
                "git") __enter_GIT "${repo[@]:1}" ;;
                "svn") __enter_SVN "${repo[@]:1}" ;;
                "hg")  __enter_HG  "${repo[@]:1}" ;;
                "bzr") __enter_BZR "${repo[@]:1}" ;;
                *) ;;
            esac
        fi

        clear
        multicolumn_ls

    fi
}

# jump dirs via dir-numbers
# TODO: autocomplete dirs in the stack bash-ido style (if none exist in the current path)
_cdn_DONTUSE()
{
    # Remove non-existent dirs from dirstack
    __check_dirstack

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
                __remove_dir_from_stack "${@:2}"
                if [ $? -ne 0 ]; then
                    return $?; fi

                # When still OK, show new list
                _cdn_DONTUSE
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
            _cd_DONTUSE "${stack[$intarg]:((${DIRSTACK_COUNTLENGTH}+1))}"
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
                    _cd_DONTUSE "${dir}"
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
            if [[ "${dir:0:((${DIRSTACK_COUNTLENGTH}+1))}" =~ ^[[:space:]]*[0-9]+[[:space:]] ]]; then
                dir="${dirline:((${DIRSTACK_COUNTLENGTH}+1))}"; fi

            # CD to patially-matched dirname
            if [[ "$dir" == *"${namearg}"* ]]; then
                _cd_DONTUSE "${dir}"
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

                dir="${stack[$i]:((${DIRSTACK_COUNTLENGTH}+1))}"

                if [ ${#dir} -gt $pwdmaxlen ]; then
                    dir="...${dir: ((-${pwdmaxlen}-3))}"; fi

                printf "%3d: %-${pwdmaxlen}s\n" $i "${dir}"
            done

        # Colored
        else
            for ((i=0; i<${#repos[@]}; i++)); do
                (printf "%3d: %s\n" $i "$( prettyprint_dir "${stack[$i]}" "${types[$i]}" "${paths[$i]}" )" &); done
        fi
    fi
}


# TODO: autocomplete dirs in the stack bash-ido style (if none exist in the current path)
_cdn_completer()
{
    # TODO
    exit 0
}
#complete -F _cdn_completer -o nospace cdn


# create dir(s), taking into account current repo mode
_mkdir_DONTUSE()
{
    command mkdir -p "$@" 2> >(error)
    if [ $? -eq 0 ]; then
        if [ $REPO_MODE -eq 1 ]; then
            eval $REPO_CMD_add "$@"; fi
        print_list_if_OK 0
    fi
}

# remove dir(s), taking into account current repo mode
# TODO: not done yet
_rmdir_DONTUSE()
{
    command rmdir "$@" 2> >(error)
    print_list_if_OK $?
    ( __check_dirstack & )
}

# remove file(s), taking into account current repo mode
_rm_DONTUSE()
{
    # we are in REPO mode
    if [ $REPO_MODE -eq 1 ]; then

        # perform repo-specific delete
        local -r err=$(eval ${REPO_CMD_remove} "$@" 2>&1 1> /dev/null)

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

            "bzr")
                # TODO
                not_added=
                outside_repo=
                ;;

            *) # anything erroneous does the same as no repo
                command rm -vI "$@" 2> >(error)
                print_list_if_OK $?
                ;;

        esac

        # remove non-added or external files
        if [[ "$err" =~ "${not_added}" ]]; then

            warning "Some files were never added to the repository \n Do you wish to remove them anyway? [N/y]"

            case $(read L && echo $L) in
                y|Y|yes|Yes|YES)
                    command rm -vI "$@" 2> >(error)
                    print_list_if_OK $?
                    ;;
                *)
                    ;;
            esac

        else
            if [[ "$err" =~ "${outside_repo}" ]]; then
                command rm -vI "$@" 2> >(error)
                if [ $? -eq 0 ]; then
                    print_list_if_OK 0
                    warning "Some files were outside the repository."
                fi
            else
                error "$err"
            fi
        fi

    # not in REPO mode
    else
        command rm -vI "$@" 2> >(error)
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
    # Help call
    if [[ $# -ge 1 && "-h" = "$1" || "--help" = "$1" ]]; then
        command mv --help
        return 0
    fi

    # check if target is in REPO
    local source source_repo
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
    if [ $REPO_MODE -eq 1 -a $REPO_TYPE == "git" ]; then

        local match="outside repository"

        local err=$(git mv "$@" 1> /dev/null 2> >(error))


        if [ $? -ne 0 ]; then
            if [[ "$err" =~ "${match}" ]]; then
                command mv -iv "$@" 2> >(error)
                if [ $? -eq 0 ]; then
                    print_list_if_OK $?
                    warning "Target and/or source was outside repository";
                fi
            else
                echo $err
            fi
        fi

    else
        command mv -iv "$@" 2> >(error)
        print_list_if_OK $?

    fi
}

# Make simlink, taking into account current repo mode
# TODO: needs work...auto-add any new files/dirs, but the 4 different
# forms of ln make this complicated
_ln_DONTUSE()
{
    # Help call
    if [[ $# -ge 1 && "-h" = "$1" || "--help" = "$1" ]]; then
        command ln --help
        return 0
    fi

    command ln -s "$@" 2> >(error)
    if [ $? -eq 0 ]; then
        print_list_if_OK 0
        if [ $REPO_TYPE == "git" ]; then
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
    # Help call
    if [[ $# -ge 1 && "-h" = "$1" || "--help" = "$1" ]]; then
        command cp --help
        return 0
    fi

    local cpcmd
    local -i nargin=$#

    #cpcmd="command cp -ivR $@"
    cpcmd="rsync -aAHch --info=progress2 $@"

    # optional args
    while (( "$#" )); do

        case "$1" in

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


    # allow 1-argument copy
    if [ $nargin -eq 1 ]; then
        _cp_DONTUSE "$1" "copy_of_$1"
        return
    fi

    # Attach stderr to error()
    cpcmd="${cpcmd} 2> >(error)"

    # REPO mode
    if [[ $REPO_TYPE == "git" ]]; then

        # only add copy to repo when
        # - we have exactly 2 arguments
        # - if arg. 1 and 2 are both inside the repo

        eval "$cpcmd"

        if [ $nargin -eq 2 ]; then
            git add "$2" 2> >(error); fi


    # normal mode
    else
        eval "$cpcmd"
    fi

    print_list_if_OK $?
}

# touch file, taking into account current repo mode
_touch_DONTUSE()
{
    command touch "$@" 2> >(error)
    print_list_if_OK $?
    if [ $REPO_MODE -eq 1 ]; then
        $REPO_CMD_add "$@"; fi
}

# --------------------------------------------------------------------------------------------------
# Frequently needed functionality
# --------------------------------------------------------------------------------------------------

# copy all relevant bash config files to a different (bash > 4.0) system
spread_the_madness()
{
    scp ~/.bash_aliases "$@" 2> >(error)
    if [ $? -eq 0 ]; then
        scp ~/.bash_functions "$@" 2> >(error) && \
        scp ~/.bashrc "$@"         2> >(error) && \
        scp ~/.dircolors "$@"      2> >(error) && \
        scp ~/.inputrc "$@"        2> >(error) && \
        scp ~/.awk_functions "$@"  2> >(error) && \
        scp ~/.git_prompt "$@"     2> >(error) && \
        scp ~/.git_completion "$@" 2> >(error)
    else
        error "failed to proliferate Rody's bash madness to remote system."
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
        command mv "$f" "${f%$before}$after" 2> >(error); done

    clear
    multicolumn_ls
}

# instant calculator
C() {
    echo "$@" | /usr/local/bin/bc -lq
}

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
        error "Findbig takes at most 1 argument."; return; fi

    local -i num
    if [ $# -eq 1 ]; then
        num=$1 # argument is number of files to print
    else
        num=10 # which defaults to 10
    fi

    # initialize some local variables
    local lsout perms dir fcolor file f

    # find proper color used for directories
    if [ $USE_COLORS  -eq 1 ]; then
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
            printf "%s\E[${dcolor#*;}m%s\E[${fcolor#*;}m%s\n${RESET_COLORS}" $perms $dir $file
        else
            printf "%s%s%s\n" $perms $dir $file
        fi
    done

    IFS="$IFS_ORIGINAL"
}

# find biggest applications
# must be aliased in .bash_aliases
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
            printf "Could not enter chroot: %s" $(cat $tmpErr)
        # fi
    fi

    # Unmount everything again when chroot exits
    for ((; i>=0; --i)); do
        sudo umount "${chroot_path}${bind_dirs[$i]}"; done
}

# gedit ALWAYS in background and immune to terminal closing!
# must be aliased in .bash_aliases
_gedit_DONTUSE()
{
    if [ $atWork -eq 0 ]; then
        (gedit "$@" &) | nohup &> /dev/null;
    else
        (notepad "$@" &) | nohup &> /dev/null;
    fi
}


# grep all processes in wide-format PS, excluding "grep" itself
psa()
{
    ps auxw | egrep -iT --color=auto "[${1:0:1}]${1:1}" 2> >(error)
}


# Queued move
mvq()
{
    if [ $# -lt 2 ]; then
        error "mv requires at least 2 arguments."
        return 1
    fi

    # TODO: nohup doesn't allow for easy redirection
    #(nohup nice -n 19 mv "$@" 2> >(error) &)
    (nice -n 19 cp -r "$@" 1> >(warning) 2> >(error) &)
    printf 'Moving %s to "%s"...\n'  "$(quoted_list ${@: 1:$(($#-1))})"  "${@: -1}"
}

# Queued copy
cpq()
{
    if [ $# -lt 2 ]; then
        error "cp requires at least 2 arguments."
        return 1
    fi

    # TODO: nohup doesn't allow for easy redirection
    #(nohup nice -n 19 cp -r "$@" 1> >(warning) 2> >(error) &)
    (nice -n 19 cp -r "$@" 1> >(warning) 2> >(error) &)
    printf 'Copying %s to "%s"...\n'  "$(quoted_list ${@: 1:$(($#-1))})"  "${@: -1}"
}

# Multi-source, multi-destination copy/move
__spread()
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

            *)  if [ $collecting_sources -eq 1 ]; then
                    sources+=("$1")
                else
                    targets+=("$1")
                fi
                ;;
        esac
        shift
    done

    # Check arguments
    if [ ${#sources[@]} -eq 0 ]; then
        error "No source files/directories given."; return 1; fi
    if [ ${#sources[@]} -eq 0 ]; then
        error "No target files/directories given."; return 1; fi

    # Execute command
    for target in "${targets[@]}"; do

        # Move/copy sources to current target
        if [ $do_repository -eq 1 ]; then
            case $cmd in
                "cp") (_cp_DONTUSE "${sources[@]}" "${target}" 1> >(warning) 2> >(error) &); ;;
                "mv") (_mv_DONTUSE "${sources[@]}" "${target}" 1> >(warning) 2> >(error) &); ;;
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
    __spread -c $@
}
# Multi-source, multi-destination move
spread()
{
    __spread -m $@
}


# export hi-res PNG from svg file
svg2png()
{
    local svgname pngname;
    for f in "$@"; do
        svgname=$f
        pngname="${svgname%.svg}.png"
        inkscape "$svgname" --export-png=$pngname --export-dpi=250
    done
}


# check validity of XML
check_XML()
{
    for file in "$@"; do
        python -c "import sys,xml.dom.minidom as d; d.parse(sys.argv[1])" "$file" &&
            echo "XML-file $file is valid and well-formed" ||
            warning "XML-file $file is NOT valid"
    done
}


# ==================================================
# Github
# ==================================================

new_github_repo()
{
    git init
    git add * .gitignore
    git commit -m "First commit"
    git remote add origin git@github.com:rodyo/"${1}".git
    git push -u origin master
}

existing_github_repo()
{
    git remote add origin git@github.com:rodyo/"${1}".git
    git push -u origin master
}




