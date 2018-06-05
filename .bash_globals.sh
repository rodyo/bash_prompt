#!/usr/bin/env bash

# General
export NUM_PROCESSORS=$(nproc --all)
export PS1_=$PS1;     # save it to be able to reset it

# repository-mode
export GIT_MODE=false # "GIT mode" on or not
export SVN_MODE=false # "SVN mode" on or not
export REPO_PATH=     # path where repository is located

# Colored man-pages
if [[ "$SHELL_COLORS" == yes ]]; then
    export LESS_TERMCAP_mb=$'\E[01;31m'       # begin blinking
    export LESS_TERMCAP_md=$'\E[01;38;5;74m'  # begin bold
    export LESS_TERMCAP_me=$'\E[0m'           # end mode
    export LESS_TERMCAP_se=$'\E[0m'           # end standout-mode
    export LESS_TERMCAP_so=$'\E[38;5;246m'    # begin standout-mode - info box export LESS_TERMCAP_ue=$'\E[0m' # end underline
    export LESS_TERMCAP_us=$'\E[04;38;5;146m' # begin underline
fi
