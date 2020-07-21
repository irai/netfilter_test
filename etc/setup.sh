#!/bin/bash

HOME=/home/netfilter

git config --global user.email "irai852@gmail.com"
git config --global user.name "Irai"
gitprod="https://github.com/irai/netfilter_prod.git"
gittest="https://github.com/irai/netfilter_test.git"

# check router mac and config file for test mode
# return "prod" or "test"
setRuntimeEnvironmentFunction() {
  # get local IP address
  #ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'

  # get default route
  local defaultgw=`route | sed -En 's/default *(([0-9]*\.){3}[0-9]*).*/\1/p'`

  if [[ -n "$defaultgw" ]]; then
    # get mac addr for default route 
    local routermac=`arp | sed -En 's/('$defaultgw') *ether *([a-fA-F0-9:]*).*/\2/p'`

    if [[ -n "$routermac" ]]; then
      local macs="20:0c:c8:23:f7:1a" # FB test env
      if [[ $macs == *"$routermac"* ]]; then
        echo "test"
        return 0
      fi
    fi

    clientTest=`sudo cat $HOME/private/config.yaml | grep 'mode: "test"'`
    if [[ -n "$clientTest" ]]; then
        echo "test"
        return 0
      fi
  fi
  echo "prod"
  return 0
}

# gitPull refresh the git repo
# $1 - repo location
# $2 - repo url
gitPullFunction() {
  local dir=$1
  local repo=$2
  if [ ! -d "$dir" ]; then
    pushd "$(dirname "$dir")"

    git clone $repo
    OK=$?
    popd
    if [ $OK -ne 0 ]; then
      echo "failed to clone $repo"
      rm -rf "$dir"
      return 1
    fi
    return 0
  else
    pushd $dir
    if [ $? -ne 0 ]; then
      echo "invalid git repo $dir"
      return 1
    fi
    git fetch
    if [ $? -ne 0 ]; then
      echo "failed to fetch repo $dir"
      popd
      return 1
    fi
    local gitwork=`git cherry master origin/master`
    if [ $? -ne 0 ]; then
      echo "failed to cherry pick repo $dir"
      popd
      return 1
    fi
    if [ "$gitwork" != "" ]; then
      git merge
      if [ $? -ne 0 ]; then
        echo "failed to merge pick repo $dir"
        popd
        return 1
      fi
    fi
    echo $gitwork
    popd
    return 0
  fi
}


CURMODE="prod"
if [ -f "$HOME/bin/MODE" ]; then
  OK=`cat "$HOME/bin/MODE"`
  if [ "$OK" == "test" ]; then
    CURMODE="test"
  fi
fi

# update main repo
UPDATED=`gitPullFunction $HOME/netfilter_prod $gitprod`
if [ $? -ne 0 ]; then
echo "failed to pull $HOME/netfilter_prod"
exit 1
fi

TARGET=${HOME}/netfilter_prod

# check if we are in testing mode
NEWMODE=`setRuntimeEnvironmentFunction`
if [ "$NEWMODE" == "test" ]; then
  echo "updating test repo"
  UPDATED=`gitPullFunction $HOME/netfilter_test $gittest`
  if [ $? -ne 0 ]; then 
    echo "failed to pull $HOME/netfilter_test"
    exit 1
  fi
  TARGET=${HOME}/netfilter_test
fi

if [ ! -d "$HOME/bin" ]; then
  mkdir $HOME/bin
fi

if [ ! -d "$TARGET" ]; then
  echo "directory $TARGET does not exist"
  exit 1
fi

if [ ! -f "$TARGET/bin/netfilter" ]; then
    echo "new netfilter does not exist $TARGET/bin/netfilter"
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

CURVERSION=`$HOME/bin/netfilter -v`
if [ $? -ne 0 ]; then
  CURVERSION="noversion"
fi

NEWVERSION=`$TARGET/bin/netfilter -v`
if [ $? -ne 0 ]; then
  NEWVERSION="noversion"
fi

if [ "$CURVERSION" == "$NEWVERSION" ] && [ "$CURMODE" == "$NEWMODE" ] && [ "$UPDATED" == "" ]; then
  echo "no changes to netfilter $CURVERSION $CURMODE. exiting..." 
  exit 0
fi

# create new links
#
echo "Configuring netfilter $NEWVERSION in $NEWMODE mode using $TARGET"

rm ${HOME}/bin/netfilter 
ln ${TARGET}/bin/netfilter ${HOME}/bin/netfilter # cannot be symlink so we don't overwrite in next git pull
echo "$NEWMODE" > ${HOME}/bin/MODE

rm -f ${HOME}/bin/netfilter.script
ln -s ${TARGET}/etc/netfilter.script ${HOME}/bin/netfilter.script
rm -f ${HOME}/bin/download.script
ln -s ${TARGET}/etc/download.script ${HOME}/bin/download.script
rm -f ${HOME}/bin/firewall.sh
ln -s ${TARGET}/etc/firewall.sh ${HOME}/bin/firewall.sh


# setup systemd services
#
SYSTEMD_DIR=/etc/systemd/system

sudo rm ${SYSTEMD_DIR}/netfilter.service
sudo ln ${TARGET}/etc/netfilter.service ${SYSTEMD_DIR}/netfilter.service
sudo rm ${SYSTEMD_DIR}/download.service
sudo ln ${TARGET}/etc/download.service ${SYSTEMD_DIR}/download.service
sudo rm ${SYSTEMD_DIR}/download.timer
sudo ln ${TARGET}/etc/download.timer ${SYSTEMD_DIR}/download.timer

# DONT update syslogd with unique mac
loggly=/etc/rsyslog.d/22-loggly.conf
if [ -f "$loggly" ]; then
  sudo rm $loggly
fi
#mac=`ifconfig -a eth0 | awk '/ether/ { print $2 } ' | sed 's/://g'`
#if test -z "$mac"  ; then mac="mac_unknown"; fi
#cat ${TARGET}/etc/22-loggly.conf | sudo sed 's/MAC_ADDRESS/'$mac'/g' > ./tmp.conf
#sudo mv ./tmp.conf /etc/rsyslog.d/22-loggly.conf

sudo /bin/systemctl daemon-reload

sudo systemctl enable rsyslog.service
sudo systemctl enable download.timer
sudo systemctl enable download.service
sudo systemctl enable netfilter.service
#sudo systemctl restart rsyslog.service
sudo systemctl restart netfilter.service
sudo systemctl restart download.timer

