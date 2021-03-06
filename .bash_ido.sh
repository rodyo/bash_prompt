#!/usr/bin/env bash

####### bash-ido - Simulate an interactive menu similar to emacs' ido
#
# Authors: <pierre.gaston@gmail.com>
#          <oldenhuis@gmail.com>
# Version: 2.0beta
# CVS: $Id: bash-ido,v 1.18 2010/02/13 14:50:32 pgas Exp $
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with BASH-IDO; see the file COPYING.  If not, write to the
# Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

# Documentation:
# --------------
#
# This is a fairly complex completion script for cd. (For now, i tried
# to make the functions a bit generic so that the menu can be used for
# other completions. Let me know if you need some help or something)
# It mimics what ido-mode does in emacs. It's easier to try than to
# describe, here is a little getting started:
#
# 0) Source this script in your .bashrc (. /path/to/bash-ido)
# 1) Start your cd command, press TAB, type some letters the list of dirs is
#    filtered according to these letters.
# 2) Press RET to select the first dir in the list.
# 3) DEL ie the erase key (usually backspace or ^H), to delete a search letter.
#    When there are no more letters, pressing DEL let you go up one dir.
# 4) C-s or <right> cycles the list to the right, C-r or <left> to the left
# 5) C-g or C-c cancels the completion.
# 6) Typing 2 / will put you in /, typing /~/ will put you in $HOME
# 7) up/M-s and down/M-r allows to navigate in the history
#

# Limitations
# -----------
# * You cannot start completion after a dirname in " " or ' '
#   (actually it's probably possible if you modify COMP_WORDBREAKS)
# * The completion disables and re-enables C-c using stty,
#   if you use another char for intr you need to modify
#   the hard coded value (search for $'\003') this could be found  via stty
#   or a parameter could be defined but how well....tell me if you feel this
#   is needed.
#

# Implementation Notes:
#  ---------------------
# * Not sure what bash version is required. If you encounter any
#   strangeness and your bash version is < 4.0, please tell us
# * It Probably doesn't work too well with some strange filenames.
# * All the functions and variables in this file should be prefixed by ido_
#   to avoid namespace polution
# * Use stty rather than a trap to disable sigint....I couldn't do what
#   I wanted with trap.
# * I chose to use the hardcoded ansi codes rather than tput, it should be
#   a tad faster and reduce the dependencies, if it doesn't work in your
#   terminal please tell me.
#

# List of variables and functions
#
#
# Global vars that exist only in this script's lifetime
# -----------
# ido_menu             -- the list of choices
# ido_f_menu           -- the filtered menu
# ido_search_string    -- the characters typed so far
# ido_result           -- the dirname part of the search
# ido_history_point    -- pointer to the current history entry
# ido_first_entry      -- do things a little differently when first entering the script
# ido_user_home        -- the full home dir; whatever ~user or ~/ expands to
# ido_user_home_abbrev -- the abbreviated form; "~user" or "~/" itself
#
#
# Global, non-local vars (i.e., export-ed)
# -----------
# IDO_ITEMLENGTH   -- total length of each item
# IDO_PROMPTLENGTH -- maximum length of the prompt displayed
# IDO_MINSPACES    -- minimum number of spaces between items
# IDO_HISTORY_SIZE -- maximum dir entries in the history
# IDO_HISTORY_FILE -- file used for persistent history
# IDO_HISTORY      -- list of the directories in the history
# IDO_LINES        -- number of lines used to print the ido menu.
# LINE, COLUMN     -- the current line, column of the cursor
# SHELL_COLORS     -- "yes", "no" or non-existent. Set in bash_rc or .bash_profile
#
#
# Functions
# ---------
# ido_print_menu     -- print the filtered menu
# ido_clear_menu     -- clear the (multiline) menu
# ido_get_col_line   -- get the current line/column
# ido_add_to_history -- add current directory to the history file
# ido_read_history   -- read the history file
# ido_loop           -- the main keyboard event loop
# ido_filter         -- filters the menu
# ido_gen_dir        -- generate the original menu (list of dirs)
# ido_dir            -- entry point
#
#

# Changes
# -------
# 2.0b (by Rody)
# * implemented persistent history
# * implemented configurable, multi-line, colored menu
# * the menu hides dot-dirs, except when a dot is explicitly typed
# * whether the script will use coloring depends on global variable SHELL_COLORS
# * ~user/ and ~/ expand correctly, provided ~/user has a dir in /home/
# * Very long dirnames are truncated on display (placing "..." in the middle)
# * ido_dir() now returns the longest valid path upon C-c,
#   instead of just the original letters typed
# * implemented different behavior when first entering ido_dir()
# * cleaned up unneeded variables on exit
# * improved readability;
#   -- commented a lot of Pierre's code I didn't understand on first read :)
#   -- CAPITALIZED all global vars, and explicitly "export" them
# * improved robustness (a few things were left unquoted or un-"2> /dev/null"-ed)
#
#
# 1.0b2 (by Pierre)
# * fixed ../ behaviour
# * fixed TAB behaviour
#
#

#  TODO:
#  -----
#  * other completions (file, command, ..)
#  * support for CDPATH in dir completion?
#  * support for GIT/SVN mode (print RED directories when .git/ is found inside it)
#  * show history list when up/down-arrow pressed.
#    Return to menu when right/left arrows are pressed
#  * update documentation
#  *
#  * once bugs are out, send everything to Pierre (and lookup the forum you got this from)
#

#  BUGS:
#  -----
#  * When we're near the bottom, pressing RETURN will copy the current line...?
#


# ido menu options
IDO_LINES=7         # number of lines used in bash-ido menu
IDO_ITEMLENGTH=35   # total number of cols to use on each menu item
IDO_PROMPTLENGTH=50 # max. length of the displayed prompt
IDO_MINSPACES=5     # minimum number of spaces between items

# ido history options
declare -a IDO_HISTORY      # array containing the history (just initializing)
export IDO_HISTORY_SIZE=250 # maximum dir entries in the history
export IDO_HISTORY_FILE="$HOME/.ido_history" # File used for persistent history.


# Get the current cursor line and column
ido_get_col_line()
{
    # Easier said than done:
    local pos old_settings
    old_settings=$(stty -g)
    stty raw -echo min 0
    printf "\E[6n" > /dev/tty
    read -r -d R -a pos
    stty $old_settings
    pos=${pos##*[}
    LINE=${pos%%;*}   # the current line
    COLUMN=${pos##*;} # the current column
}


# Clear the ido menu
ido_clear_menu()
{
    # clear current line, reset all color attributes
    printf "\E[0m\E[$LINE;${COLUMN}H%*s" $((COLUMNS-COLUMN+1)) " "

    # clear the IDO_LINES
    for (( i=0; i<=$IDO_LINES; i++ )); do
        printf '\n%*s' $COLUMNS " "; done

    # we're near the bottom
    if [ $((LINE+IDO_LINES+1)) -ge $LINES ]; then
        LINE=$((LINES-IDO_LINES-1)); fi

    # put the cursor back
    printf "\E[$LINE;${COLUMN}H"
}


# print the filtered menu
ido_print_f_menu()
{
    # Prints the directories on max. 4 lines
    local prompt
    local menu
    local ido_f_menu_printed
    local ido_result_printed
    local cur
    local IFS_="$IFS"
    local ind=0
    local i=0
    local j=0
    local maxcols=$((COLUMNS/IDO_ITEMLENGTH)) # cols (depends on actual screen width)

    # are we to use colors?
    if [ -v SHELL_COLORS ]; then
        # get proper colors used for directories
        local dcolor dattr
        dcolor=${LS_COLORS##*:di=};
        dcolor=${dcolor%%:*}
        dattr=${dcolor%%;*}
        dcolor=${dcolor##*;}
    fi

    # replace any homedirs with their correct tilde-abbreviations
    ido_result_printed=$ido_result
    for i in "${!ido_user_home_abbrev[@]}"; do
        ido_result_printed=${ido_result_printed/#${ido_user_home[i]}/${ido_user_home_abbrev[i]}}; done

    # (dir) + (match or typed characters)
    prompt=${ido_result_printed}${ido_search_string}
    # limit its length. Show the first half and the last half, and "..." in the middle
    if [ ${#prompt} -gt $IDO_PROMPTLENGTH ]; then
        prompt=${prompt:0:(($IDO_PROMPTLENGTH/2-1))}...${prompt:((${#prompt}-$IDO_PROMPTLENGTH/2+1)):${#prompt}}; fi

    # clear the menu
    ido_clear_menu

    # if menu is non-empty, format it and print it
    if [ ${#ido_f_menu[@]} -gt 0 ]; then

        # If using colors, set proper dircolor
        local color_start=""
        local color_stop=""
        if [ -v SHELL_COLORS ]; then
            color_start="\E[${dattr}m\E[${dcolor}m";
            color_stop="\E[0m"
        fi

        # We have to sort items by column, but print by row:
        for ((i=0; i<((IDO_LINES-1)); i++)); do

            # first clear the current line
            printf '\n%*s\r' $COLUMNS " "

            # print the row
            for ((j=0; j<((maxcols-1)); j++)); do

                # current index into ido_f_menu
                ind=$((i + j*IDO_LINES))

                # possibly quick exit
                if [ $ind -gt ${#ido_f_menu[@]} ]; then
                    break; fi

                # extract current item (and loose the counter)
                cur=${ido_f_menu[$ind]#* };

                # limit its length
                if [ ${#cur} -gt $((IDO_ITEMLENGTH-IDO_MINSPACES)) ]; then
                    cur="${cur:0:$((IDO_ITEMLENGTH-IDO_MINSPACES-3))}..."; fi

                # append to row to be printed
                if [[ $i -eq $((IDO_LINES-1)) && $j -eq $((maxcols-1)) ]]; then
                    printf "..."
                else
                    printf "${color_start}%s${color_stop}%*s" "$cur" $((IDO_ITEMLENGTH-${#cur})) " "
                fi

            done # j - columns
        done # i - rows

        # Finish the job properly
        printf "\E[0m\E[$LINE;${COLUMN}H%*s\E[$LINE;${COLUMN}H%s" \
            $((COLUMNS-COLUMN-1)) " " "$prompt"

    # if it is empty, print no-match
    else
        ido_clear_menu
        printf "\n%s\E[$LINE;${COLUMN}H%s" "[*No match*]" "$prompt"
    fi
}


# filter the menu generated with ido_gen_dir()
ido_filter()
{
    # initialize
    local i=0 start trans_i quoted show_dot_dirs=0
    start=${ido_f_menu[i]%% *}
    unset ido_f_menu

    # generate the search list, and determine if we have to show dot-dirs
    if [[ "$ido_search_string" ]]; then
        printf -v quoted "%q" "$ido_search_string"
        if [[ "${ido_search_string:0:2}" != "./" && "${ido_search_string:0:1}" == "." ]]; then
            show_dot_dirs=1; fi
    else
        quoted=""
    fi

    # now apply filter
    for i in "${!ido_menu[@]}"; do
        trans_i=$(((i+start)%${#ido_menu[@]}))
        if [[ "${ido_menu[trans_i],,}" = *"${quoted,,}"* && \
            ($show_dot_dirs -eq 1 || \
            "${ido_menu[trans_i]:0:2}" == "./" || \
            "${ido_menu[trans_i]:0:1}" != ".") ]]; then # TODO: regex?

            ido_f_menu+=( "$trans_i ${ido_menu[trans_i]}" );
        fi
    done
}

# add current dir to history file
# Adopted from i_addToHistory() found in tp_command(), by
# Alvin Alexander (DevDaily.com)
ido_add_to_history()
{
    # initialize
    local i dupeIndex=-1
    local resultDir="${ido_result%./}"

    # insert the new dir in the last+1 position of the array
    IDO_HISTORY[((${#IDO_HISTORY[@]}))]="$resultDir"

    # check if this grew the array beyond its allowed size
    if [ ${#IDO_HISTORY[@]} -gt $IDO_HISTORY_SIZE ]; then
        # remove only the first (=oldest) element
        unset IDO_HISTORY[0]
    fi

    # check if the history file is read/writeable
    if [[ -w "$IDO_HISTORY_FILE" && -r "$IDO_HISTORY_FILE" ]]; then

        # Now write these entries back out to the history file.
        # Also check for dupes in the process
        command rm -f "$IDO_HISTORY_FILE" 2> /dev/null
        for (( i=0; i < ${#IDO_HISTORY[@]}; i++ )); do

            # no duplicate: write to file
            if [ "$resultDir" != "${IDO_HISTORY[i]}" ]; then
                echo "${IDO_HISTORY[i]}" >> "$IDO_HISTORY_FILE"

            # duplicate: remember index
            else
                if [ $((i+1)) -ne ${#IDO_HISTORY[@]} ]; then
                    dupeIndex=$i;
                else
                    echo "${IDO_HISTORY[i]}" >> "$IDO_HISTORY_FILE"
                fi
            fi
        done

        # now remove the dupe from the IDO_HISTORY
        if [[ $dupeIndex != -1 ]]; then
            unset IDO_HISTORY[dupeIndex]; fi

    fi
}


# Load contents of history file into IDO_HISTORY var
# Adopted from i_load_dirlist() found in tp_command(), by
# Alvin Alexander (DevDaily.com)
ido_read_history()
{
    # check if the file is actually there
    if [ -f "$IDO_HISTORY_FILE" ];
    then
        local -i jj=0
        IDO_HISTORY=
        while read line; do
            IDO_HISTORY[jj]="$line"
            ((jj++))
        done < "$IDO_HISTORY_FILE"

    # if it's not there, create it
    else
        command touch "$IDO_HISTORY_FILE"
        return;
    fi
}


# keyboard event loop
ido_loop()
{
    local REPLY
    local c

    while : ; do

        # if this is the first time round, and there is only one match, use it
        if [[ $ido_first_entry == 1 ]]; then
            ido_first_entry=0
            if [[ ${#ido_f_menu[@]} == 1 ]]; then
                ido_result="${ido_result}${ido_f_menu[0]#* }"; return 255; fi
        fi

        ido_print_f_menu >&2
        unset c

        ido_filter

        # loop to read the escape sequences
        while : ; do
            IFS= read -d '' -r -s -n 1
            case $REPLY in
                $'\E')
                    c+=$REPLY
                    ;;

                \[|O)
                    c+=$REPLY
                    if ((${#c} == 1)); then
                        break; fi
                    ;;

                *)
                    c+=$REPLY
                    break
                    ;;
            esac
        done

        # handle the different escape sequences
        case $c in

            # RET
            $'\n'|$'\t')
                ido_result="${ido_result}${ido_f_menu[0]#* }"
                return 0
                ;;

            # /
            / )
                case $ido_search_string in
                    ..)
                        ido_result+="../"
                        ;;

                    \~)
                        ido_result="$HOME/"
                        ;;

                    ?*)
                        ido_result="${ido_result}${ido_f_menu[0]#* }"
                        ;;

                    *)
                        ido_result=/
                        ;;

                esac
                return 0
                ;;

            # DEL aka ^? or ^h
            '$\b'|$'\177')
                if [[ $ido_search_string ]]; then
                    ido_search_string="${ido_search_string%?}"
                    ido_filter
                else
                    ido_result+="../"
                    return 0
                fi
                ;;

            # C-g | C-c
            $'\a' | $'\003')
                return 2
                ;;

            # <right> | C-s
            $'\E[C'|$'\EOC'|$'\023')
                if ((${#ido_f_menu[@]}>1)); then
                    ido_f_menu=("${ido_f_menu[@]:1}"  "${ido_f_menu[0]}"); fi
                ;;

            # <left> | C-r
            $'\E[D'|$'\EOD'|$'\022')
                if ((${#ido_f_menu[@]}>1)); then
                    ido_f_menu=("${ido_f_menu[${#ido_f_menu[@]}-1]}"
                                "${ido_f_menu[@]:0:${#ido_f_menu[@]}-1}"); fi
                ;;

            # <down> | M-r
            $'\E[B'|$'\EOB'|$'\367'|$'\Er')
                if ((ido_history_point>1)); then
                    ido_history_point=$((ido_history_point-1))
                    ido_result="${IDO_HISTORY[ido_history_point]%/}/"
                    ido_search_string=""
                    return 0

                else
                    printf "\a" >&2
                fi
                ;;

            # <up> | M-s
            $'\E[A'|$'\EOA'|$'\362'|$'\Es')
                if (((ido_history_point+1)< ${#IDO_HISTORY[@]})); then
                    ido_history_point=$((ido_history_point+1))
                    ido_result="${IDO_HISTORY[ido_history_point]%/}"/
                    ido_search_string=""
                    return 0
                else
                    printf "\a" >&2
                fi
                ;;

            [[:print:]])
                ido_search_string+=$REPLY
                ido_filter
                ;;

            *)
                printf "\a" >&2
                ;;
        esac
    done
}


# Generate the original menu (complete list of dirs)
ido_gen_dir()
{
    local IFS_=$IFS
    unset ido_menu
    IFS=$'\n' read -r -d '' -a ido_menu < <(IFS=" ";shopt -s nullglob;\
        eval builtin cd "$ido_result" 2> /dev/null && printf -- "%q\n" ./ */ ..?*/ .[!.]*/)

    if [[ $ido_search_string ]]; then
        ido_filter
    else
        local i e
        unset ido_f_menu
        for e in "${ido_menu[@]}"; do
            ido_f_menu[i]="$i $e"
            ((i++))
        done
    fi
    IFS=$IFS_
}


# Entry point
ido_dir()
{
    # initialize
    local cwd=$(pwd)  # don't use $PWD; it's been modified in $PROMPT_COMMAND
    ido_first_entry=1 # first entry into bash ido
    ido_result=${COMP_WORDS[COMP_CWORD]} # get letters typed so far

    # ...
    if [[ "$ido_result" == \$* ]]; then
        if [[ "$ido_result" == */* ]]; then
            local temp
            temp=${ido_result%%/*}
            temp=${temp#?}
            ido_result=${!temp}/${ido_result#*/}
        else
            COMPREPLY=( $( compgen -v -P '$' -- "${ido_result#$}" ) )
            return 0
        fi
    fi

    # initialize some more
    stty intr undef
    local i status ido_final_result
    unset ido_f_menu ido_search_string ido_history_point
    status=0

    # get the current line/column
    # (used in ido_print_menu)
    ido_get_col_line
    COLUMN=$((COLUMN-${#ido_result}))

    # get user home dirs, and proper abbreviations thereof
    # NOTE: it is better to do this in here, to maintain proper
    # behavior when a "useradd" or "userdel" or similar is issued
    ido_user_home=($(command ls -b1d /home/*/))
    ido_user_home_abbrev=($(builtin cd /home/ && command ls -b1d */))
    for i in "${!ido_user_home_abbrev[@]}"; do
        ido_user_home[i]=${ido_user_home[i]/%\//}
        ido_user_home_abbrev[i]=${ido_user_home_abbrev[i]/%\//}
        if [[ ${ido_user_home[i]} = $HOME ]]; then
             ido_user_home_abbrev[i]="~"
        else ido_user_home_abbrev[i]=~${ido_user_home_abbrev[i]}; fi # note the tilde :)
    done

    # handle tilde-expansions
    # NOTE: the promptstring displayed will differ from $ido_result)
    if [ "${ido_result:0:1}" = "~" ]; then
        for i in "${!ido_user_home_abbrev[@]}"; do
            ido_result=${ido_result/#${ido_user_home_abbrev[i]}/${ido_user_home[i]}}; done
    fi

    # initialize ido_result
    case $ido_result in
        ''|./)
            ido_result=$cwd/
            ;;

        */*)
            ido_search_string=${ido_result##*/}
            ido_result=${ido_result%/*}/
            ido_result=${ido_result/#~\//$HOME/}
            if [[ ! -d ${ido_result} ]]; then
                printf "\a\nNo Such Directory: %s\n" "${ido_result}" >&2
                status=1
            fi
            ;;

        *)
            ido_search_string=$ido_result
            ido_result=$cwd/
            ;;

    esac

    # normalize (i.e., remove the // and other foo/../bar)
    ido_result=$(builtin cd "$ido_result" 2> /dev/null && cwd=$(pwd) && printf "%q" "${cwd%/}/")
    while [[ $status = 0 && $ido_result != */./ ]]; do

        # hmm this part is dir specific...TB generalized..
        case $ido_result in
            # order is important, the last case covers the first ones
            /../)
                ido_result=/
                ;;

            \~/../)
                ido_result=${HOME%/*}/
                ;;

            */../)
                ido_result=${ido_result%/*/../}/
                ;;
        esac

        ido_gen_dir
        ido_loop; status=$?
        ido_search_string=""

        # break if match is unique, and this is the first pass
        if [[ status == 255 ]]; then
            break; fi

    done

    # clean up display
    ido_clear_menu;   # clear the menu
    stty intr $'\003' # reset C-c
    kill -WINCH $$    # force bash to redraw

    # give the ido_result to bash
    ido_result=${ido_result/$cwd/.}   # NOTE: (Rody Oldenhuis) strip the current path, if applicable
    ido_final_result=${ido_result%./}

    # add this result to history
    if [[ $status == 0 ]]; then
        ido_add_to_history; fi

    # unset all local,global vars
    unset ido_menu ido_f_menu ido_user_home ido_user_home_abbrev
    unset ido_first_entry ido_search_string ido_result ido_history_point

    # and return
    COMPREPLY[0]="$ido_final_result"
    return $status
}


# make sure the history file is expanded
IDO_HISTORY_FILE=$(echo $IDO_HISTORY_FILE)
typeset -r IDO_HISTORY_FILE

# read the history file when first sourcing this script
if [ ${#IDO_HISTORY[@]} -eq 0 ]; then
    ido_read_history; fi

complete -F ido_dir -o nospace cdd
alias cdd=cd
