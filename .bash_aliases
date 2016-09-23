# Customized
#
# * .bashrc
# * .dircolors
# * .inputrc
# * .bash_aliases
# * .bash_functions
#
# by
#
# Rody Oldenhuis
# oldenhuis@gmail.com


# First some exports
export GIT_MODE=false             # "GIT mode" on or not
export SVN_MODE=false             # "SVN mode" on or not
export REPO_PATH=                 # path where repository is located
PS1_=$PS1;                        # save it to reset it when changed below

# global vars
NUM_PROCESSORS=$(cat /proc/cpuinfo | command grep processor | wc -l)

# exports for colored man-pages
if [ "$color_prompt" = yes ]; then
    export LESS_TERMCAP_mb=$'\E[01;31m'       # begin blinking
    export LESS_TERMCAP_md=$'\E[01;38;5;74m'  # begin bold
    export LESS_TERMCAP_me=$'\E[0m'           # end mode
    export LESS_TERMCAP_se=$'\E[0m'           # end standout-mode
    export LESS_TERMCAP_so=$'\E[38;5;246m'    # begin standout-mode - info box export LESS_TERMCAP_ue=$'\E[0m' # end underline
    export LESS_TERMCAP_us=$'\E[04;38;5;146m' # begin underline
fi



# clear function
# TODO: this belongs in .bash_functions...but, then all the list aliases therein get screwed up
_clear_DONTUSE(){
    for (( i=0; i<$LINES; i++)); do
        printf "\n%*s\r" $COLUMNS " ";
    done;
    printf "\E[1;${COLUMN}H"
}
alias clear=_clear_DONTUSE

# bash-ido
# By <pierre.gaston@gmail.com>
# and <oldenhuis@gmail.com>
#if [ -f ~/.bash_ido ]; then
#    source ~/.bash_ido; fi

# custom functions
# By <oldenhuis@gmail.com>
if [ -f ~/.bash_functions ]; then
    source ~/.bash_functions; fi

# teleport command
# By Alvin Alexander (devdaily.com)
#if [ -f ~/.tp_command ]; then
#    source ~/.tp_command; fi

# list-aliases
alias ls="clear; ls --color=auto --si"
alias ld="ls -odgh --time-style=+ */"
alias ll="clear; ls -lh --group-directories-first"
alias lad="ld .*/"
alias first="ls -t | tail -1"
alias last="ls -t | head -1"
alias l="clear; multicolumn_ls"
alias lS="l -S"
alias la="l -A"
alias laS="l -AS"
#alias tree='find . -type d | sed -e "s/[^-][^\/]*\//  |/g;s/|\([^ ]\)/|-\1/"'
alias tree='find . | sed -e "s/[^-][^\/]*\//  │/g; s/│\([^ ]\)/├─\1/"'

# FS manipulation & navigation
alias cdn=_cdn_DONTUSE
alias cd=_cd_DONTUSE
alias dc=_cd_DONTUSE
alias mv=_mv_DONTUSE
alias rm=_rm_DONTUSE
alias cp=_cp_DONTUSE
alias ln=_ln_DONTUSE
alias touch=_touch_DONTUSE
alias mkdir=_mkdir_DONTUSE
alias rmdir=_rmdir_DONTUSE
alias shred="shred -uz -n 36"
alias rmrf="rm -rf"
alias ged=_gedit_DONTUSE
alias not=_gedit_DONTUSE
alias sged="gksudo _gedit_DONTUSE"

# Bind completion of "cd" to "ido_dir()"
# TODO: work out bugs
# TODO: make it work better
#complete -F ido_dir -o nospace cdd


# one-letter shorts
alias c=clear
alias clc='printf "\033c"'
alias C='printf "\033c"'
alias x=exit
alias q=exit
alias n="nano -w"
alias m="make -j$NUM_PROCESSORS"
alias r=xdg-open
alias t="top -d 1"
alias p="pcmanfm . &"
alias g=_geany_DONTUSE
alias d="cd ~/Desktop/"
alias s="cd ~/Desktop/sandbox/"
alias h="history"

# cd aliases
alias cd..="cd .."
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ..2="cd ..."
alias ..3="cd ...."
alias ..4="cd ....."
alias ..5="cd ../../../../.."
alias ..6="cd ../../../../../.."

# hotdirs
alias doc="cd ~/Documents/"
alias work="cd ~/Desktop/Work/"
alias hh="cd ~/Desktop/Work/Heinrich\ Hertz/trunk/Software/"

# various
alias forget="history -c; clear"
alias findbig=_findbig_DONTUSE
alias newpaper=". newpaper.sh"
alias sysupdate="sudo apt-get update; sudo apt-get -y dist-upgrade"
alias remove_old_kernels="dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs sudo apt-get -y purge"
alias findbig_applications=_findbig_applications_DONTUSE
alias install="sudo apt-get -y install"
alias zipit="gzip -9 *"
alias zipall="gzip -9r *"
alias unzipit="gunzip *"
alias unzipall="gunzip -r *"
alias gzip="gzip -9"
alias fstab="sgedit /etc/fstab"
alias bc="/bin/bc -lq"
alias df="df -ThH"
#alias psa="ps auxw | command egrep -iT --color=auto"
alias top10="ps -eo pcpu,pid,user,args | sort -k 1 -r | head -10"
alias locate="locate -i"
alias grep="egrep -iIT --color=auto --exclude-dir .svn --exclude-dir .git"
alias egrep=grep
alias catbare='/bin/egrep -v "^#\|^[[:space:]]*$"'
alias rebash=". ~/.bashrc"

# todo.txt
alias todo="~/.todo/todo.sh -d ~/.todo/todo.cfg"
complete -F _todo todo

# matlab
alias matlab="/bin/matlab -nojvm -nosplash"
alias matlabfull="/bin/matlab -desktop &"
alias matlabinline="/bin/matlab -nodesktop -nojvm -nosplash"
alias matlabrun="/bin/matlab -r"

# python
alias ipython="ipython -pylab"

# WORK
alias sshimulus="ssh simulus@simulus_box"
alias cdss="cd ~/SIMULUS_5/SIMSAT4-Kernel/"
alias cded="cd ~/Desktop/Work/EDRS/Software"
