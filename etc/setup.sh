#!/bin/bash

getModeFunction() {
  local mode=prod
  if [ -f "$NETFILTER/private/config.yaml" ]; then
    mode=`cat $NETFILTER/private/config.yaml | sed -En 's/ *mode: *\"*([a-fA-F]*)\"*/\1/p'`
    if [ "$mode" != "test" ] && [ "$mode" != "beta" ] && [ "$mode" != "prod" ]; then
        mode=prod
    fi
  fi
  echo $mode
}

# setup systemd services
#
setup() {

  local systemd_dir=/etc/systemd/system

  if [ ! -d "$NETFILTER/bin" ]; then
    mkdir $NETFILTER/bin
    chmod 0770 $NETFILTER/bin
  fi

  local mode=`getModeFunction`
  local dir=$NETFILTER/netfilter_${mode}

  # fail to prod if not available
  #
  if [ ! -d "$dir" ]; then
    mode=prod
    dir=$NETFILTER/netfilter_prod
  fi

  local restart=0
  diff -q ${systemd_dir}/netfilter.service ${dir}/etc/netfilter.service
  if [ $? != 0 ]; then
    rm -f ${systemd_dir}/netfilter.service
    ln ${dir}/etc/netfilter.service ${systemd_dir}/netfilter.service
    restart=1
  fi

  diff -q $NETFILTER/bin/setup.sh ${dir}/etc/setup.sh
  if [ $? != 0 ]; then
    rm -f ${NETFILTER}/bin/setup.sh
    cp ${dir}/etc/setup.sh ${NETFILTER}/bin/setup.sh
    chmod +x ${NETFILTER}/bin/setup.sh
    restart=1
  fi

  rm -f ${systemd_dir}/netfilter.script # no longer needed
  rm -f ${dir}/bin/netfilter.script # no longer needed
  #diff -q ${systemd_dir}/netfilter.script ${dir}/etc/netfilter.script
  #if [ $? != 0 ]; then
    #rm -f ${systemd_dir}/netfilter.script
    #cp ${dir}/etc/netfilter.service ${systemd_dir}/netfilter.script
    #restart=1
  #fi


  diff -q ${systemd_dir}/netfilter.download.service ${dir}/etc/netfilter.download.service
  if [ $? != 0 ]; then
    rm -f ${systemd_dir}/download.service # cleanup old service
    rm -f ${systemd_dir}/netfilter.download.service
    cp ${dir}/etc/netfilter.download.service ${systemd_dir}/netfilter.download.service
    restart=1
  fi

  diff -q $NETFILTER/bin/netfilter.download.script ${dir}/etc/netfilter.download.script
  if [ $? != 0 ]; then
    rm -f ${NETFILTER}/bin/netfilter.download.script
    cp ${dir}/etc/netfilter.download.script ${NETFILTER}/bin/netfilter.download.script
    chmod +x ${NETFILTER}/bin/netfilter.download.script
    restart=1
  fi

  diff -q ${systemd_dir}/netfilter.download.timer ${dir}/etc/netfilter.download.timer
  if [ $? != 0 ]; then
    rm -f ${systemd_dir}/download.timer # remove old service
    rm -f ${systemd_dir}/netfilter.download.timer
    cp ${dir}/etc/netfilter.download.timer ${systemd_dir}/netfilter.download.timer
    restart=1
  fi

  diff -q $NETFILTER/bin/firewall.sh ${dir}/etc/firewall.sh
  if [ $? != 0 ]; then
    rm -f ${NETFILTER}/bin/firewall.sh
    cp ${dir}/etc/firewall.sh ${NETFILTER}/bin/firewall.sh
    restart=1
  fi

  # DONT update syslogd with unique mac
  loggly=/etc/rsyslog.d/22-loggly.conf
  rm -f $loggly # remove old file

  local curversion=`$NETFILTER/bin/netfilter -v`
  if [ $? -ne 0 ]; then
    curversion="noversion"
  fi

  local newversion=`${NETFILTER}/netfilter_${mode}/bin/netfilter -v`
  if [ $? -ne 0 ]; then
    newversion="noversion"
  fi

  if [ "$curversion" != "$newversion" ]; then
    cp ${NETFILTER}/netfilter_${mode}/bin/netfilter ${NETFILTER}/bin/netfilter
    restart=1
  fi

  if [ $restart -eq 1 ]; then
    echo "netfilter updated to $curversion in $mode. Restarting...."
    /bin/systemctl daemon-reload
    systemctl enable rsyslog.service
    systemctl enable netfilter.download.timer
    systemctl enable netfilter.download.service
    systemctl enable netfilter.service
    systemctl restart netfilter.service
    systemctl restart netfilter.download.timer
    #systemctl restart rsyslog.service
  else 
    echo "netfilter keep current version $curversion in $mode"
  fi 
}

#
# Setup netfilter
#
NETFILTER=/home/netfilter

if [ ! -d "$NETFILTER/private" ]; then
  mkdir $NETFILTER/private
  chmod 0700 $NETFILTER/private
fi

case $1 in
  setup)  "$1" ;;
  *) 
    # August 2020
    # handle old download system where setup.sh would be called with no parameters
    # run download script 
    if [ -d $NETFILTER/netfilter_prod ]; then
      pushd $NETFILTER/netfilter_prod
      git pull
      popd
    fi
    if [ -d $NETFILTER/netfilter_test ]; then
      pushd $NETFILTER/netfilter_test
      git pull
      popd
    fi
    setup
  ;;
esac
