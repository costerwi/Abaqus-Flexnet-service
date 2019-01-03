#!/bin/bash
cat << INTRO
This script configures the Abaqus Flexnet License Daemon as a restartable
service on Linux computers.

The service will be started by this script and will also be set to autostart
whenever the system boots.

If you have any questions, please contact support@caelynx.com

INTRO

error=$(tput setaf 1)ERROR:$(tput sgr 0) || error="ERROR:"
warning=$(tput setab 3)WARNING:$(tput sgr 0) || warning="WARNING:"

if [ $(id -u) -ne 0 ] # {{{1 Got root?
then
    echo $error You must have root permissions to make config changes.
    exit 1
fi

LICENSE=$1 # {{{1 Check for existence license file
test -f "$LICENSE" || read -p "Enter license file name: " LICENSE
if [ ! -f $LICENSE ]
then
    echo License file "$LICENSE" not found.
    exit 1
fi

# {{{1 Check format of license file
if grep -q "VENDOR ABAQUSLM" "$LICENSE"
then
    echo $LICENSE includes the following features:
    grep FEATURE "$LICENSE"
else
    echo $warning $LICENSE does not appear to be a Flexnet license file.
    echo You may have received a DSLS license or there may be other problems.
    #TODO check for DSLS and add support for DSLS license server
    read -p "Continue? [y]/n " response
    test "$response" = "n" && exit 1
fi
echo

# {{{1 Check if currently running
if lmgrd_pid=($(pidof lmgrd))
then
    echo $warning There is already a Flexnet license server running:
    ps -p "${lmgrd_pid[@]}" -o pid,cmd
    #TODO get the base directory of this running lmgrd
    echo
    read -p "Continue installing this service? [y]/n " response
    test "$response" = "n" && exit 1
fi

# {{{1 Check for SIMULIA in common locations
for d in $SIMULIA /usr/SIMULIA/License /usr/SIMULIA /opt/CAE/SIMULIA
do
    if [ -d "$d" ]
    then
        SIMULIA=$d
        break
    fi
done

test -d $SIMULIA || read -p "Enter base directory to search for license server: " SIMULIA

# {{{1 Search for lmgrd and ABAQUSLM within SIMULIA
echo Searching for Abaqus Flexnet software within $SIMULIA
abaquslm=( $(find $SIMULIA -name ABAQUSLM | sort -r) )

for d in ${abaquslm[@]}
do
    if [ -f $(dirname $d)/lmgrd ]
    then
        echo Found: $d
        read -p "Use this instance? [y]/n " response
        test "$response" = "n" && continue
        LMBIN=$(dirname $d)
        break # stop when lmgrd is found
    fi
done
test -f "$LMBIN/lmgrd" || {
    echo $error Abaqus Flexnet license software was not found.
    exit 1 # exit if lmgrd is not found
}

LMADMIN=${LMADMIN:-lmadmin} # {{{1 check for user
if id -u $LMADMIN >/dev/null 2>&1
then
    echo License administrator $LMADMIN exists and will be used
else
    echo Creating license administrator $LMADMIN
    useradd --system --home-dir /sbin --shell /sbin/nologin --comment "Abaqus license administrator" $LMADMIN || exit 1
fi

# {{{1 Setup license file directory
echo Setting up the license file directory
licdir=/etc/abaqus-lm
test -d $licdir || mkdir --verbose $licdir
chmod --verbose 2755 $licdir || exit 1
cp --verbose $LICENSE $licdir || exit 1
cat >$licdir/README <<README
This directory will be scanned to find the current Abaqus license.
Please contact support@caelynx.com if you have any trouble.
License files must end with .lic
Copy your new license here and then reload the abaqus-lm service to refresh:
README
chmod --verbose 644 $licdir/README
chown --verbose --recursive $LMADMIN.$LMADMIN $licdir || exit 1

# {{{1 Setup log file rotate
echo Setting up log file directory
logdir=/var/log/abaqus-lm
test -d $logdir || mkdir --verbose $logdir
chown --verbose $LMADMIN $logdir || exit 1
chmod --verbose 755 $licdir || exit 1

if pidof systemd >/dev/null # {{{1 systemd system
then
sysd=/etc/systemd/system
service=abaqus-lm.service
echo Creating systemd service $sysd/$service

cat >$sysd/$service <<SERVICE || exit 1
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
chmod --verbose 664 $sysd/$service || exit 1

echo Starting the service $service
systemctl daemon-reload # Parse the new service file
systemctl enable --now $service # Start now and enable on reboot
echo systemctl reload ${service%.*} >>$licdir/README

else # {{{1 Assume SysV init
initd=/etc/rc.d/init.d
service=abaqus-lm
echo Creating SysV init script $initd/$service
cat >$initd/$service <<SCRIPT || exit 1
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
chmod --verbose 755 $initd/$service || exit 1

chkconfig --add $service
service $service start
echo service $service reload >>$licdir/README

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

# TODO Firewall {{{1

# vim: foldmethod=marker
