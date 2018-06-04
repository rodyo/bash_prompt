#!/usr/bin/env bash

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
alias tree='find . | sed -e "s/[^-][^\/]*\//  │/g; s/│\([^ ]\)/├─\1/"'

# FS manipulation & navigation
alias cdn=_cdn
alias cd=_rbp_cd  # TODO: breaks autocomplete???
alias dc=_rbp_cd
#alias mv=_rbp_mv  # TODO: off, until it's finished
#alias cp=_rbp_cp  #
alias rm=_rbp_rm
alias ln=_rbp_ln
alias touch=_rbp_touch
alias mkdir=_rbp_mkdir
alias rmdir=_rbp_rmdir
alias shred="shred -uz -n 4"
alias rmrf="rm -rf"
alias ged=_gedit
alias not=_gedit

# one-letter shorts
alias c="clear"
alias clc='printf "\033c"'
alias C='printf "\033c"'
alias x=exit
alias q=exit
alias n="nano -w"
alias m="make -j$NUM_PROCESSORS"
alias r=xdg-open
alias t="top -d 1"
alias p=_pcmanfm
alias g=_geany
alias npp=_geany
alias n++=_geany
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
alias dropbox="cd ~/Dropbox/"
alias work="cd ~/e/Work/"

# various
alias clear="_rbp_clear"
alias forget="history -c; clear"
alias findbig=_findbig
alias findfile="find . -type f -iname "
alias newpaper=". newpaper.sh"
alias sysupdate="sudo apt-get update; sudo apt-get -y dist-upgrade"
alias remove_old_kernels="dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs sudo apt-get -y purge"
alias findbig_applications=_findbig_applications
alias install="sudo apt-get -y install"
alias zipit="gzip -9 *"
alias zipall="gzip -9r *"
alias unzipit="gunzip *"
alias unzipall="gunzip -r *"
alias gzip="gzip -9"
alias fstab="sgedit /etc/fstab"
alias bc="/bin/bc -lq"
alias df="df -ThH"
alias top10="ps -eo pcpu,pid,user,args | sort -k 1 -r | head -10"
alias locate="locate -i"
alias grep="egrep -iIT --color=auto --exclude-dir .svn --exclude-dir .git"
alias egrep=grep
alias catbare='/bin/egrep -v "^#\|^[[:space:]]*$"'
alias rebash=". ~/.bashrc"

# Home
alias ssh_mediabox="ssh -p 2021 media@rastawern.no-ip.org"
alias ssh_heaven="ssh -p 2022 rody@rastawern.no-ip.org"
alias ssh_hell="ssh -p 2022 rody@rastawern.no-ip.org"
alias ssh_rivka="ssh -p 2023 rivka@rastawern.no-ip.org"


# MATLAB
MATLAB_BASE="/usr/local/MATLAB/"
MATLAB="/usr/local/bin/matlab"

alias matlab_2014="${MATLAB_BASE}/R2014a/bin/matlab -desktop &"
alias matlab_2017="${MATLAB_BASE}/R2017a/bin/matlab -desktop &"

alias matlab="$MATLAB -desktop &"
alias matlabinline="$MATLAB -nodesktop -nojvm -nosplash"
alias matlabrun="$MATLAB -r"


# python
alias ipython="ipython -pylab"

# ispace
alias ssh_tinker="ssh ispace@ispace-08"
