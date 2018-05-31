#!/usr/bin/env bash

# disable pango (improves rendering in FireFox)
export MOZ_DISABLE_PANGO=1

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# bugfix
declare -x TERM=xterm

# All shell options I like
BASH_MAJOR_VERSION=${BASH_VERSION:0:1}
BASH_MINOR_VERSION=${BASH_VERSION:2:1}

if (( $BASH_MAJOR_VERSION >= 4)); then
    shopt -s autocd       # interpret commands like 'home' as 'cd /home'
    shopt -s cdspell      # correct small typos in typed dirnames
    shopt -s checkjobs    # check for any running jobs on shell exit
    shopt -u compat40     # compatibility mode w/ bash 4.0
    shopt -s dirspell     # spelling corrections on directory names to match a glob.
    shopt -u dotglob      # include .-directories in pathname expansion
    shopt -u globstar     # use recursive globbing (**, match this dir and all subdirs)

    if (($BASH_MINOR_VERSION > 1 )); then
        shopt -u compat41 # compatibility mode w/ bash 4.1
    fi
fi

if (($BASH_MINOR_VERSION > 1 )); then
    shopt -u compat31     # compatibility mode w/ bash 3.1
fi
if (($BASH_MINOR_VERSION > 2 )); then
    shopt -u compat32     # compatibility mode w/ bash 3.2
fi

shopt -u cdable_vars
shopt -u checkhash
shopt -s checkwinsize     # refresh COLUMNS and LINES after each command
shopt -s cmdhist          # try to store multiline commands as single entry in history
shopt -u execfail         # do not exit on failure of "exec" command
shopt -s expand_aliases   # expand aliases.
shopt -u extdebug         # enable stuff for bash debugging
shopt -s extglob          # enable extended pattern matching features
shopt -s extquote         # perform quoting when parameter matching
shopt -u failglob         # issue an error message when failing to find parameter match
shopt -s force_fignore    # use ignore list when parameter matching
shopt -s gnu_errfmt       # use standard GNU error format
shopt -s histappend       # append to history, not overwrite
shopt -u histreedit
shopt -u histverify
shopt -s hostcomplete     # complete also hostnames
shopt -u huponexit        # send HUP to all jobs upon exit
shopt -s interactive_comments # allow comments in interactive shell
#shopt -u lastpipe       #
shopt -s lithist          # use multiline commands from history
shopt -u mailwarn         # display warning when mail is checked
shopt -u no_empty_cmd_completion
shopt -s nocaseglob       # perform case-insensitive filename matching
shopt -u nocasematch      # perform case-insensitive pattern matching
shopt -u nullglob         # return null-string (instead of pattern itself) when no matches are found
shopt -s progcomp         # enable programmable completion
shopt -s promptvars       # do parameter expansion, command substitution, arithmetic expansion, quote removal
shopt -u shift_verbose    # print error message when shifting beyond array limit
shopt -s sourcepath       # use PATH variable to find file being sourced
shopt -s xpg_echo         # enable 'echo -e' (escape seqs.) by default


# Don't put duplicate lines in the history. See bash(1) for more options
# Don't overwrite GNU Midnight Commander's setting of `ignorespace'.
HISTCONTROL=$HISTCONTROL${HISTCONTROL+,}ignoredups
# ... or force ignoredups and ignorespace
HISTCONTROL=ignoreboth

# make "less" more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set a fancy prompt (non-color, unless we know we want color)
SHELL_COLORS=
case "$TERM" in
    xterm-color)
        SHELL_COLORS=yes
        ;;
esac


# uncomment for a colored prompt, if the terminal has the capability
force_shell_colors=yes

if [ -n "$force_shell_colors" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 &> /dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        SHELL_COLORS=yes
    else
        SHELL_COLORS=
    fi
fi

if [ "$SHELL_COLORS" = yes ]; then
    # user is root
    if [ `id -u` = 0 ]; then
        PS1='\[\033[01;31m\]\u@\h\[\033[0m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    # non-root user
    else
        PS1='\[\033[01;32m\]\u@\h\[\033[0m\]:\[\033[01;34m\]\W\[\033[00m\]\$ '
    fi
else
    PS1='\u@\h:\w\$ '
fi
unset force_shell_colors


# If this is an xterm set the title to user@host:dir
case "$TERM" in
    xterm*|rxvt*)
#        PS1="\[\e]0;\u@\h: \W\a\]$PS1"
        ;;
    *)
        ;;
esac

# enable color support
if [ "$SHELL_COLORS" = yes ]; then
    if [ -x /usr/bin/dircolors ]; then
        test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    fi
fi
export SHELL_COLORS


# Enable programmable completion features
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    source /etc/bash_completion; fi

# Enable git-specific completions and prompt options
if [ -f ~/.git_completion ]; then
    source ~/.git_completion; fi

if [ -f ~/.git_prompt ]; then
    source ~/.git_prompt
    export GIT_PS1_SHOWDIRTYSTATE="yes"
    export GIT_PS1_SHOWSTASHSTATE="yes"
    export GIT_PS1_SHOWUPSTREAM="auto"
fi

# Enable svn-specific completions and prompt options
# TODO

# Enable CVS-specific completions and prompt options
# TODO

# Enable mercurial-specific completions and prompt options
# TODO

# Enable bazaar-specific completions and prompt options
# TODO


# Default editor
export EDITOR=nano

# Keyboard shortcut definitions
export INPUTRC=~/.inputrc


# TODO: (Rody Oldenhuis) offload this to some other file
# {

# First some exports
export GIT_MODE=false # "GIT mode" on or not
export SVN_MODE=false # "SVN mode" on or not
export REPO_PATH=     # path where repository is located
PS1_=$PS1;            # save it to reset it when changed below

# global vars
NUM_PROCESSORS=$(nproc --all)

# exports for colored man-pages
if [[ "$SHELL_COLORS" == yes ]]; then
    export LESS_TERMCAP_mb=$'\E[01;31m'       # begin blinking
    export LESS_TERMCAP_md=$'\E[01;38;5;74m'  # begin bold
    export LESS_TERMCAP_me=$'\E[0m'           # end mode
    export LESS_TERMCAP_se=$'\E[0m'           # end standout-mode
    export LESS_TERMCAP_so=$'\E[38;5;246m'    # begin standout-mode - info box export LESS_TERMCAP_ue=$'\E[0m' # end underline
    export LESS_TERMCAP_us=$'\E[04;38;5;146m' # begin underline
fi

# SSH agent (useful on CygWin)
if [[ -z "$SSH_AUTH_SOCK" ]]; then
    eval $(ssh-agent) 2>&1 > /dev/null
    trap "kill $SSH_AGENT_PID" 0
fi

# }


# Custom functions
# By <oldenhuis@gmail.com>
_have_fcn=0
if [ -f ~/.bash_functions ];
then
    if [ -f ~/.bash_functions ];
    then
        source ~/.bash_ansicodes
        source ~/.bash_functions
        _check_dirstack
        _have_fcn=1
    else
        echo "Can't find one or more of .bash_function's dependencies!"
    fi
fi

# Alias definitions
if [ -f ~/.bash_aliases ];
then
    source ~/.bash_aliases;
else
    echo "Can't find .bash_aliases!"
fi

# bash ido
if [ -f ~/.bash_ido ];
then
    source ~/.bash_ido;
else
    echo "Can't find .bash_ido!"
fi

# Ultimate debugging prompt
# see https://stackoverflow.com/questions/17804007/how-to-show-line-number-when-executing-bash-script
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# We're done; do an LS
if [[ _have_fcn == 1 ]]; then
    multicolumn_ls; fi
unset _have_fcn




