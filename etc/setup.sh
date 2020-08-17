#!/bin/bash

NETFILTER=/home/netfilter

sudo git config --global user.email "irai852@gmail.com"
sudo git config --global user.name "Irai"

DIR_PROD=$NETFILTER/netfilter_prod
GW_PROD=blockthekids.com:443
GIT_PROD="https://github.com/irai/netfilter_prod.git"

DIR_BETA=$NETFILTER/netfilter_beta
GW_BETA=blockthekids.com:443
GIT_BETA="https://github.com/irai/netfilter_beta.git"

DIR_TEST=$NETFILTER/netfilter_test
GW_TEST=blockthekids.com:8080
GIT_TEST="https://github.com/irai/netfilter_test.git"


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

    clientTest=`sudo cat $NETFILTER/private/config.yaml | grep 'mode: "test"'`
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

getModeFunction() {
  local mode=prod
  if [ -f "$NETFILTER/private/config.yaml" ]; then
    mode=`sudo cat $NETFILTER/private/config.yaml | sed -En 's/ *mode: *\"*([a-fA-F]*)\"*/\1/p'`
    if [ "$mode" != "test" ] && [ "$mode" != "beta" ] && [ "$mode" != "prod" ]; then
        mode=prod
    fi
  fi
  echo $mode
}

updateRepositoriesFunction() {
  local mode=$1

  gitPullFunction $DIR_PROD $GIT_PROD
  if [ $? -ne 0 ]; then
    echo "failed to pull $NETFILTER/netfilter_prod $?"
  fi

  if [ "$mode" == "test" ]; then
    gitPullFunction $DIR_TEST $GIT_TEST
    if [ $? -ne 0 ]; then
      echo "failed to pull $DIR_TEST $GIT_TEST $?"
    fi
  elif [ "$mode" == "beta" ]; then
    gitPullFunction $DIR_BETA $GIT_BETA
    if [ $? -ne 0 ]; then
      echo "failed to pull $DIR_BETA $GIT_BETA $?"
    fi
  fi
}


# create new links
#
#echo "Configuring netfilter $NEWVERSION in $NEWMODE mode using $TARGET"

#rm ${NETFILTER}/bin/netfilter 
#ln ${TARGET}/bin/netfilter ${NETFILTER}/bin/netfilter # cannot be symlink so we don't overwrite in next git pull
#echo "$NEWMODE" > ${NETFILTER}/bin/MODE

#rm -f ${NETFILTER}/bin/netfilter.script
#ln -s ${TARGET}/etc/netfilter.script ${NETFILTER}/bin/netfilter.script
#rm -f ${NETFILTER}/bin/download.script
#ln -s ${TARGET}/etc/download.script ${NETFILTER}/bin/download.script
#rm -f ${NETFILTER}/bin/firewall.sh
#ln -s ${TARGET}/etc/firewall.sh ${NETFILTER}/bin/firewall.sh


# setup systemd services
#
updateSystemdFunction() {
  local mode=$1
  local curversion=$2

  local systemd_dir=/etc/systemd/system

  local dir=$DIR_PROD
  if [ "$mode" == "beta" ]; then 
    dir=$DIR_BETA
  elif [ "$mode" == "test" ]; then
    dir=$DIR_TEST
  fi
     
  local restart=0
  diff $systemd_dir/netfilter.service $dir/etc/netfilter.service
  if [ $? == 1 ]; then
    sudo rm ${systemd_dir}/netfilter.service
    sudo ln ${dir}/etc/netfilter.service ${systemd_dir}/netfilter.service
    restart=1
  fi

  diff $systemd_dir/download.service $dir/etc/download.service
  if [ $? == 1 ]; then
    sudo rm ${systemd_dir}/download.service
    sudo ln ${dir}/etc/download.service ${systemd_dir}/download.service
    restart=1
  fi

  diff $systemd_dir/download.timer $dir/etc/download.timer
  if [ $? == 1 ]; then
    sudo rm ${systemd_dir}/download.timer
    sudo ln ${dir}/etc/download.timer ${systemd_dir}/download.timer
    restart=1
  fi

  # DONT update syslogd with unique mac
  loggly=/etc/rsyslog.d/22-loggly.conf
  if [ -f "$loggly" ]; then
    sudo rm $loggly
  fi

  newversion=`${NETFILTER}/netfilter_${mode}/bin/netfilter -v`
  if [ $? -ne 0 ]; then
    newversion="noversion"
  fi

  if [ "$curversion" != "$newversion" ]; then
    restart=1
  fi

  if [ $restart -eq 1 ]; then
    echo "netfilter updated to $curversion in $mode. Restarting...."

    exit 

    sudo /bin/systemctl daemon-reload
    sudo systemctl enable rsyslog.service
    sudo systemctl enable download.timer
    sudo systemctl enable download.service
    sudo systemctl enable netfilter.service
    #sudo systemctl restart rsyslog.service
    sudo systemctl restart netfilter.service
    sudo systemctl restart download.timer
  else 
    echo "netfilter keep current version $curversion in $mode"
  fi 
}

if [ ! -d "$NETFILTER/private" ]; then
  mkdir $NETFILTER/private
  chmod 0700 $NETFILTER/private
fi

echo "private $NETFILTER/private"
ls -l ${NETFILTER}/private
    
mode=`getModeFunction`
echo "mode $mode"

curversion=`$NETFILTER/netfilter_$mode/bin/netfilter -v`
if [ $? -ne 0 ]; then
  curversion="noversion"
fi

updateRepositoriesFunction $mode
updateSystemdFunction $mode $curversion

