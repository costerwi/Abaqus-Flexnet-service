#!/bin/bash
SIMULIA=${SIMULIA:-/opt/CAE/SIMULIA}
LMADMIN=${LMADMIN:-lmadmin}

if ! [ id -u == 0 ] # {{{1 Check for root
then
    echo ERROR: Must have root permissions to make config changes.
    exit 1
fi

LICENSE=shift
if ! [ -f $LICENSE ]
then
    echo License file not found.
    echo Please provide license path on commandline:
    echo $0 mylicensefile.lic
    exit 1
fi

echo Searching for Abaqus Flexnet software within $SIMULIA # {{{1
abaquslm=( $(find $SIMULIA -name ABAQUSLM) )

for d in ${abaquslm[@]}
do
    if [ -f $(dirname $d)/lmgrd ]
    then
        LMBIN=$(dirname $d)
        echo Found: $LMBIN
        break # stop when lmgrd is found
    fi
done
test -f "$LMBIN/lmgrd" || {
    echo Abaqus Flexnet license software was not found.
    echo You may specify the SIMULIA search directory on command line:
    echo SIMULIA=/my/path/to/SIMULIA $0 mylicensefile.lic
    exit 1 # exit if lmgrd is not found
}

if id -u $LMADMIN >/dev/null # {{{1 check for user
then
    echo License administrator $LMADMIN exists
else
    echo Creating license administrator $LMADMIN
    useradd --system --home-dir /sbin --shell /sbin/nologin --comment "Abaqus license administrator" $LMADMIN || exit 1
fi

echo Creating license file directory
licdir=/etc/abaqus-lm
mkdir --verbose $licdir
chown --verbose $LMADMIN $licdir || exit 1
chmod --verbose 755 $licdir || exit 1
cp --verbose $LICENSE $licdir || exit 1
cat >$licdir/README <<README
This directory will be scanned to find the current Abaqus license.
License files must end with .lic
Please contact support@caelynx.com if you have any trouble.
Copy your new license here and then reload the abaqus-lm service to refresh:
README
chmod --verbose 644 $licdir/README

echo Creating log file directory
logdir=/var/log/abaqus-lm
mkdir --verbose $logdir
chown --verbose $LMADMIN $logdir || exit 1
chmod --verbose 755 $licdir || exit 1

if pidof systemd >/dev/null # {{{1 systemd system
then
service=/etc/systemd/system/abaqus-lm.service
echo Creating systemd service $service

cat >$service <<SERVICE || exit 1
[Unit]
Description=Abaqus flexlm license daemon
After=network.target

[Service]
User=$LMADMIN
ExecStart=$LMBIN/lmgrd -z -l +$logdir/lmgrd.log -c $licdir
ExecStop=$LMBIN/lmdown -q -c $licdir
ExecReload=$LMBIN/lmreread -c $licdir

[Install]
WantedBy=multi-user.target
SERVICE
chmod -v 664 $service || exit 1

echo Starting the service $service
systemctl daemon-reload # Parse the new service file
systemctl enable --now $service # Start now and enable on reboot
echo systemctl reload ${service%.*} >>$logdir/README

else # {{{1 Assume SysV init
service=/etc/rc.d/init.d/abaqus-lm
echo Creating SysV init script $service
cat >$service <<SCRIPT || exit 1
#!/bin/sh
#
# chkconfig: - 91 35
# description: Starts and stops the abaqus-lm license daemon

# Source function library.
if [ -f /etc/init.d/functions ] ; then
  . /etc/init.d/functions
elif [ -f /etc/rc.d/init.d/functions ] ; then
  . /etc/rc.d/init.d/functions
else
  exit 1
fi

KIND="abaqus-lm"
LM_LICENSE_FILE=$licdir
LMBIN=$LMBIN

start() {
    echo -n \$"Starting \$KIND services: "
    daemon --user $LMADMIN \$LMBIN/lmgrd -c \$LM_LICENSE_FILE -l +$logdir/lmgrd.log
    return \$?
}

stop() {
    echo -n \$"Shutting down \$KIND services: "
    \$LMBIN/lmdown -c \$LM_LICENSE_FILE -q >/dev/null
    RETVAL=\$?
    [ 0 -eq \$RETVAL ] && success || failure
    return \$RETVAL
}

restart() {
    stop
    start
}

reload() {
    echo -n \$"Reloading \$LM_LICENSE_FILE directory: "
    \$LMBIN/lmreread -c \$LM_LICENSE_FILE >/dev/null
    RETVAL=\$?
    [ 0 -eq \$RETVAL ] && success || failure
    return \$RETVAL
}

status() {
    \$LMBIN/lmstat -c \$LM_LICENSE_FILE
    return \$?
}

case "\$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    restart
    ;;
  reload)
    reload
    ;;
  status)
    status
    ;;
  *)
    echo \$"Usage: \$0 {start|stop|restart|reload|status}"
    exit 2
esac

exit \$?
SCRIPT
chmod --verbose 755 $service || exit 1

chkconfig --add $(basename $service)
service $(basename $service) start
echo service $(basename $service) reload >>$logdir/README

fi

# {{{1 Setup logrotate
logrotate=/etc/logrotate.d/abaqus-lm
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
chmod --verbose 644 $logrotate || exit 1
fi

# TODO Firewall

# vim: foldmethod=marker
