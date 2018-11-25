#!/bin/bash
SIMULIA=${SIMULIA:-/opt/CAE/SIMULIA}
daemonuser=abaqus-lm

echo Searching for license daemon within $SIMULIA # {{{1
abaquslm=( $(find $SIMULIA -name ABAQUSLM) )

for d in ${abaquslm[@]}
do
    if [ -f $(dirname $d)/lmgrd ]
    then
       lmgrd=$d/lmgrd
       break # stop when lmgrd is found
    fi
done
test -f "$lmgrd" || {
    echo lmgrd was not found with ABAQUSLM
    exit 1 # exit if lmgrd is not found
}
echo Found ${lmgrd}

if ! [ id -u == 0 ] # {{{1 Check for root
then
    echo ERROR: Must have root permissions to make config changes.
    exit 1
fi

echo Creating log file directory
logdir=/var/log/$daemonuser
mkdir -v $logdir || exit 1

if id -u $daemonuser >/dev/null # {{{1 check for user
then
    echo User $daemonuser exists
else
    echo Creating daemon user $daemonuser
    useradd --system --home-dir $logdir --shell /sbin/nologin $daemonuser
fi
chown -v $daemonuser $logdir || exit 1

if pidof systemd >/dev/null # {{{1 systemd system
then
service=/etc/systemd/system/$daemonuser.service
echo Creating systemd service $service

cat >$service <<SERVICE || exit 1
[Unit]
Description=Abaqus flexlm license daemon
After=network.target

[Service]
User=$daemonuser
ExecStart=$lmgrd -z -l +$logdir/${daemonuser}.log -c $license

[Install]
WantedBy=multi-user.target
SERVICE
chmod -v 664 $service || exit 1

echo Starting the service $service
systemctl daemon-reload # Parse the new service file
systemctl enable --now $service # Start now and enable on reboot

else # {{{1 Assume SysV init
script=/etc/rc.d/init.d/$daemonuser
echo Creating SysV init script $script
cat >$script <<SCRIPT || exit 1
SCRIPT

popd
fi

# {{{1 Setup logrotate
logrotate=/etc/logrotate.d/$daemonuser
if [ -d $(dirname $logrotate) ]
then
echo Creating $logrotate
cat >$logrotate <<LOGROTATE || exit 1
$logdir/*.log {
    missingok
    notifyempty
    sharedscripts
    delaycompress
    endscript
}
LOGROTATE
chmod -v 611 $logrotate || exit 1
fi

# vim: foldmethod=marker
