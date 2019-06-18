#!/usr/bin/env bash

# -------------------------------------------------------------------------
# General
# -------------------------------------------------------------------------

readonly START_ESCAPE_GROUP='\e['


# -------------------------------------------------------------------------
# Colors
# -------------------------------------------------------------------------

# ...are a mess in bash.

readonly START_COLORSCHEME_PS1='\[\e['
readonly END_COLORSCHEME_PS1='m\]'

readonly START_COLORSCHEME="$START_ESCAPE_GROUP"
readonly END_COLORSCHEME="m"
readonly END_COLORESCAPE="m"

readonly RESET_COLORS='\e[0m'
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

# few helper functions
set_color()
{
    if [[ ! $# < 4 ]]; then
        error "set_color() takes max. 3 input arguments."; return; fi

    local args="${@//[[:digit:]]/}"
    args="${args//[[:space:]]/}"
    if [[ -n "${args}" ]]; then
        error "set_color() accepts only integer input.";  return; fi

    local codes=("$@")
    local -i i

    for ((i=1; i<$#; ++i)); do
        codes[0]="${codes[0]};${codes[i]}";
        unset codes[i]
    done

    printf "${START_COLORSCHEME}${codes}${END_COLORSCHEME}"
}

reset_colors()
{
    if [[ $# != 0 ]]; then
        error "reset_colors() takes no input arguments.";  return; fi

    printf "${RESET_COLORS}"
}


set_PS1_color()
{
    if [[ ! $# < 4 ]]; then
        error "set_PS1_color() takes max. 3 input arguments."; return; fi

    local args="${@//[[:digit:]]/}"
    args="${args//[[:space:]]/}"
    if [[ -n "${args}" ]]; then
        error "set_PS1_color() accepts only integer input."; return; fi

    local codes=("$@")
    local -i i

    for ((i=1; i<$#; ++i)); do
        codes[0]="${codes[0]};${codes[i]}";
        unset codes[i]
    done

    printf "${START_COLORSCHEME_PS1}${codes}${END_COLORSCHEME_PS1}"
}

reset_PS1_color()
{
    if [[ $# != 0 ]]; then
        error "reset_PS1_color() takes no input arguments."; return; fi

    printf "${RESET_COLORS_PS1}"
}


# -------------------------------------------------------------------------
# Cursor movement
# -------------------------------------------------------------------------

readonly POSITION_CURSOR="H"

readonly MOVE_CURSOR_UP="A"
readonly MOVE_CURSOR_DOWN="B"
readonly MOVE_CURSOR_RIGHT="C"
readonly MOVE_CURSOR_LEFT="D"

readonly MOVE_CURSOR_FORWARD="${MOVE_CURSOR_RIGHT}"
readonly MOVE_CURSOR_BACKWARD="${MOVE_CURSOR_LEFT}"

readonly ERASE_TO_END_OF_LINE="K"

readonly SAVE_CURSOR_POSITION="S"
readonly RESTORE_CURSOR_POSITION="U"

# few helper functions
_cursor_mover()
{
    printf "${START_ESCAPE_GROUP}$@"
}

_move_cursor()
{
    if [[ $# != 2 ]]; then
        error "_move_cursor() requires 2 input arguments."; return; fi

    local arg="${2//[[:digit:]]/}"
    arg="${arg//[[:space:]]/}"
    if [[ -n "${args}" ]]; then
        error "_move_cursor() accepts only integer input."; return; fi

    _cursor_mover "$2$1"
}

position_cursor()
{
    if [[ $# != 2 ]]; then
        error "position_cursor() requires 2 input arguments."; return; fi

    local arg="${2//[[:digit:]]/}"
    arg="${arg//[[:space:]]/}"
    if [[ -n "${args}" ]]; then
        error "position_cursor() accepts only integer input."; return; fi

    _cursor_mover "$1;$2${POSITION_CURSOR}"
}

move_cursor_up()    { _move_cursor "${MOVE_CURSOR_UP}"    "$@"; }
move_cursor_down()  { _move_cursor "${MOVE_CURSOR_DOWN}"  "$@"; }
move_cursor_left()  { _move_cursor "${MOVE_CURSOR_LEFT}"  "$@"; }
move_cursor_right() { _move_cursor "${MOVE_CURSOR_RIGHT}" "$@"; }

erase_to_end_of_line()
{
    if [[ $# != 0 ]];
    then
        error "erase_to_end_of_line() takes no input arguments.";
        return;
    fi

    _cursor_mover "${ERASE_TO_END_OF_LINE}"
}

save_cursor_position()
{
    if [[ $# != 0 ]];
    then
        error "save_cursor_position() takes no input arguments.";
        return;
    fi

    _cursor_mover "${SAVE_CURSOR_POSITION}"
}

restore_cursor_position()
{
    if [[ $# != 0 ]];
    then
        error "restore_cursor_position() takes no input arguments.";
        return;
    fi

    _cursor_mover "${RESTORE_CURSOR_POSITION}"
}


