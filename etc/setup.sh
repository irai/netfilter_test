#!/bin/bash

HOME=/home/netfilter

setRuntimeEnvironmentFunction() {
  MODE="prod"
  # get local IP address
  #ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'

  # get default route
  DEFAULTGW=`route | sed -En 's/default *(([0-9]*\.){3}[0-9]*).*/\1/p'`

  if [[ -n "$DEFAULTGW" ]]; then
    # get mac addr for default route 
    ROUTERMAC=`arp | sed -En 's/('$DEFAULTGW') *ether *([a-fA-F0-9:]*).*/\2/p'`

    if [[ -n "$ROUTERMAC" ]]; then
      macs="20:0c:c8:23:f7:1a" # FB test env
      if [[ $macs == *"$ROUTERMAC"* ]]; then
        MODE="test"
        return
      fi
    fi

    clientTest=`sudo cat $HOME/private/config.yaml | grep 'mode: "test"'`
    if [[ -n "$clientTest" ]]; then
        MODE="test"
      fi
  fi
}

gitPullFunction() {
  git config --global user.email "irai852@gmail.com"
  git config --global user.name "Irai"
  git fetch
  work=`git cherry master origin/master`
  if [ "$work" != "" ]; then
    echo "netfilter update available - installing"
    git merge
  fi
}

# get latest
gitPullFunction
if [ $? -ne 0 ]; then
  echo "nothing to do; exiting"
  #exit 0
fi

# prod or test
setRuntimeEnvironmentFunction

LATEST=${HOME}/netfilter_bin/$MODE
if [ ! -d "$LATEST" ]; then
  echo "directory $LATEST does not exist"
  exit 1
fi

if [ ! -f "$LATEST/netfilter" ]; then
    echo "new netfilter does not exist $LATEST/netfilter"
    exit 1
fi

# current version 
if [ ! -f "$HOME/bin/netfilter" ] && [ ! -L "$HOME/bin/netfilter" ]; then
    echo "current netfilter does not exist $HOME/bin/netfilter"
    exit 1
fi
# Convert symlink to link if needed
if [ -L "$HOME/bin/netfilter" ]; then
  cp --remove-destination `sudo readlink $HOME/bin/netfilter` $HOME/bin/netfilter
fi

NEWVERSION=`$LATEST/netfilter -v`
if [ $? -ne 0 ]; then
  NEWVERSION="noversion"
fi

CURVERSION=`$HOME/bin/netfilter -v`
if [ $? -ne 0 ]; then
  CURVERSION="noversion"
fi

if [[ "$CURVERSION" == "$NEWVERSION" ]]; then
  echo "no changes to netfilter $CURVERSION" 
  exit 0
fi

if [ ! -d "$HOME/bin" ]; then
  mkdir $HOME/bin
fi

# create new links
#
echo "Configuring netfilter $NEWVERSION in $MODE mode ($LATEST)"

rm ${HOME}/bin/netfilter 
ln ${LATEST}/netfilter ${HOME}/bin/netfilter

rm ${HOME}/bin/netfilter.script
ln -s ${LATEST}/netfilter.script ${HOME}/bin/netfilter.script

rm ${HOME}/bin/download.script
ln -s ${LATEST}/download.script ${HOME}/bin/download.script

rm ${HOME}/bin/firewall.sh
ln -s ${LATEST}/firewall.sh ${HOME}/bin/firewall.sh


# setup systemd services
#
SYSTEMD_DIR=/etc/systemd/system

sudo rm ${SYSTEMD_DIR}/netfilter.service
sudo ln ${LATEST}/netfilter.service ${SYSTEMD_DIR}/netfilter.service

sudo rm ${SYSTEMD_DIR}/download.service
sudo ln ${LATEST}/download.service ${SYSTEMD_DIR}/download.service
sudo rm ${SYSTEMD_DIR}/download.timer
sudo ln ${LATEST}/download.timer ${SYSTEMD_DIR}/download.timer

# DONT update syslogd with unique mac
loggly=/etc/rsyslog.d/22-loggly.conf
if [ -f "$loggly" ]; then
  sudo rm $loggly
fi
#mac=`ifconfig -a eth0 | awk '/ether/ { print $2 } ' | sed 's/://g'`
#if test -z "$mac"  ; then mac="mac_unknown"; fi
#cat ${LATEST}/22-loggly.conf | sudo sed 's/MAC_ADDRESS/'$mac'/g' > ./tmp.conf
#sudo mv ./tmp.conf /etc/rsyslog.d/22-loggly.conf

sudo /bin/systemctl daemon-reload

sudo systemctl enable rsyslog.service
sudo systemctl enable download.timer
sudo systemctl enable download.service
sudo systemctl enable netfilter.service
#sudo systemctl restart rsyslog.service
sudo systemctl restart netfilter.service
sudo systemctl restart download.timer

