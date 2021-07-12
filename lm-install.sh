#!/bin/bash
echo "
This script configures the Abaqus Flexnet License Daemon as a restartable
service on Linux Redhat/CentOS version 6.x or 7.x computers.

The license service will be started by this script and will also be set to
autostart whenever the system boots.

Flexnet license files in the Flexnet directory, current directory, or
specified on the command line will be copied to the appropriate location.

This script may be re-run to update the annual license file.

If you have any questions, please contact support@caelynx.com

"
# Carl Osterwisch, November 2018

error=$(tput setaf 1)ERROR:$(tput sgr 0) || error="ERROR:"
warning=$(tput setab 3)WARNING:$(tput sgr 0) || warning="WARNING:"
note=$(tput setab 2)NOTE:$(tput sgr 0) || warning="NOTE:"

if [ "$(id -u)" -ne 0 ] # {{{1 Got root?
then
    echo $error You must have root permissions to make config changes.
    exit 1
fi

# {{{1 Check for currently running ABAQUSLM license server
for p in $(pidof lmgrd)
do
    exe=$(readlink -f /proc/$p/exe)
    dir=$(dirname $exe)
    if [ -f "$dir/ABAQUSLM" ]
    then
        echo $note Found running ABAQUSLM in $dir
        SIMULIA=$dir
        kill $p
        break
    fi
done

# {{{1 Check for SIMULIA license directory in common locations
# TODO Try to run Abaqus and query its installation directory
for d in $SIMULIA /usr/SIMULIA/License /opt/SIMULIA/License /opt/CAE/SIMULIA/License /usr/SIMULIA /opt/SIMULIA /opt/CAE/SIMULIA
do
    if [ -d "$d" ]
    then
        SIMULIA=$d
        break
    fi
done

test -d "$SIMULIA" || read -rp "Enter base directory to search for license server: " SIMULIA

# {{{1 Search for lmgrd and ABAQUSLM together within SIMULIA
echo Searching for Abaqus Flexnet software within "$SIMULIA"
abaquslm=()
while IFS=$'\n' read -r d
do
    lmbin=$(dirname "$d")
    if [ -f "$lmbin/lmgrd" ]
    then
        abaquslm+=("$lmbin")
        lmver=$("$lmbin/lmgrd" -v)
        echo ${#abaquslm[@]} "$lmbin/${lmver%% build*}"
    fi
done < <(find "$SIMULIA" -name ABAQUSLM | sort -r)

case ${#abaquslm[@]} in
    0)
        echo $error Abaqus Flexnet license software was not found.
        exit 1
        ;;
    1)
        LMBIN=${abaquslm[0]}
        echo $note License service will use Flexnet in $LMBIN
        ;;
    *)
        read -rp "Choose number for the license server to use or 0 to abort [1]: " response
        response=${response:-1} # default to 1
        if [ "$response" -ge 1 -a "$response" -le ${#abaquslm[@]} ]
        then
            LMBIN=${abaquslm[(($response-1))]}
        else
            exit 1
        fi
esac

LMADMIN=${LMADMIN:-lmadmin} # {{{1 check for lmadmin user
if id -u "$LMADMIN" >/dev/null 2>&1
then
    echo $note License administrator "$LMADMIN" exists and will be used
else
    echo $note Creating license administrator "$LMADMIN"
    useradd -d /sbin --system --shell /sbin/nologin --comment "License manager" "$LMADMIN" || exit 1
fi
test -n "$USER" && usermod -a -G $LMADMIN $USER # add current user to license admin group

# {{{1 Setup license file directory
echo Setting up the license file directory
licdir=/etc/abaqus-lm
test -d "$licdir" || mkdir --verbose "$licdir"
chmod --verbose 2775 "$licdir" || exit 1
echo $note License files should be stored in $licdir
for f in "$LMBIN"/*.LIC *.LIC "$@"
do
    test -f "$f" && cp --verbose --preserve=timestamps "$f" "$licdir"
done
echo -n "\
This directory will be scanned to find the current Abaqus license.
Please contact support@caelynx.com if you have any trouble.
License file names must end with .LIC
Copy your new license here and then reload the license service to refresh:
" > "$licdir/README"
chmod --verbose 644 "$licdir/README"
chown --verbose --recursive "$LMADMIN:$LMADMIN" "$licdir" || exit 1

# {{{1 Setup log file directory
echo Setting up log file directory
logdir=/var/log/abaqus-lm
test -d "$logdir" || mkdir --verbose "$logdir"
chown --verbose --recursive "$LMADMIN" "$logdir" || exit 1
chmod --verbose --recursive 755 "$logdir" || exit 1

# {{{1 Create helpful symbolic links
test -n "$USER" && su $USER --command "ln --verbose --symbolic --force --no-dereference \"$licdir\" ."
ln --verbose --symbolic --force --no-dereference "$licdir" "$logdir/licenses"
ln --verbose --symbolic --force --no-dereference "$logdir" "$licdir/log"
ln --verbose --symbolic --force --no-dereference "$licdir" "$LMBIN/licenses"
ln --verbose --symbolic --force --no-dereference "$logdir" "$LMBIN/log"

# {{{1 Setup logrotate
logrotate=/etc/logrotate.d/abaqus-lm
if [ -d "$(dirname $logrotate)" ]
then
echo Creating "$logrotate"
echo "\
$logdir/*.log {
    missingok
    notifyempty
    copytruncate
    weekly
    rotate 5
}" >"$logrotate" || exit 1
chmod --verbose 644 "$logrotate"
fi

if pidof systemd >/dev/null # {{{1 systemd system
then
sysd=/etc/systemd/system
service=abaqus-lm.service
test -f "$sysd/$service" && systemctl stop ${service%.*}
echo Creating systemd service "$sysd/$service"
echo "\
[Unit]
Description=Abaqus flexlm license daemon
After=network.target

[Service]
User=$LMADMIN
Environment="FLEXLM_TIMEOUT=1000000"
ExecStart=$LMBIN/lmgrd -z -l +$logdir/lmgrd.log -c $licdir
ExecStop=$LMBIN/lmutil lmdown -q -c $licdir
ExecReload=$LMBIN/lmutil lmreread -c $licdir

[Install]
WantedBy=multi-user.target" >"$sysd/$service" || exit 1
chmod --verbose 664 "$sysd/$service" || exit 1

echo Starting the service $service
systemctl daemon-reload # Parse the new service file
systemctl enable --now $service # Start now and enable on reboot
echo systemctl reload ${service%.*} >>"$licdir/README"

sleep 2
systemctl status $service # Report status of new service

else # {{{1 Assume SysV init
initd=/etc/rc.d/init.d
service=abaqus-lm
test -f "$initd/$service" && service $service stop
echo Creating SysV init script $initd/$service
echo "\
#!/bin/sh
#
# chkconfig: 2345 91 35
# description: Starts and stops the abaqus-lm license daemon

# Source function library.
if [ -f /etc/init.d/functions ] ; then
  . /etc/init.d/functions
elif [ -f /etc/rc.d/init.d/functions ] ; then
  . /etc/rc.d/init.d/functions
else
  exit 1
fi

KIND=abaqus-lm
LM_LICENSE_FILE=$licdir
LMBIN=$LMBIN

start() {
    echo -n \$\"Starting \$KIND services: \"
    FLEXLM_TIMEOUT=1000000
    daemon --user $LMADMIN \$LMBIN/lmgrd -c \$LM_LICENSE_FILE -l +$logdir/lmgrd.log
    return \$?
}

stop() {
    echo -n \$\"Shutting down \$KIND services: \"
    \$LMBIN/lmutil lmdown -c \$LM_LICENSE_FILE -q >/dev/null
    RETVAL=\$?
    [ 0 -eq \$RETVAL ] && success || failure
    return \$RETVAL
}

restart() {
    stop
    start
}

reload() {
    echo -n \$\"Reloading \$LM_LICENSE_FILE directory: \"
    \$LMBIN/lmutil lmreread -c \$LM_LICENSE_FILE >/dev/null
    RETVAL=\$?
    [ 0 -eq \$RETVAL ] && success || failure
    return \$RETVAL
}

status() {
    \$LMBIN/lmutil lmstat -c \$LM_LICENSE_FILE
    return \$?
}

case \"\$1\" in
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
    echo \$\"Usage: \$0 {start|stop|restart|reload|status}\"
    exit 2
esac

exit \$?" >"$initd/$service" || exit 1
chmod --verbose 755 "$initd/$service" || exit 1

chkconfig --add $service
service $service start
echo service $service reload >>"$licdir/README"

sleep 2
service $service status # Report status of new service

fi

# TODO Firewall {{{1

# vim: foldmethod=marker
