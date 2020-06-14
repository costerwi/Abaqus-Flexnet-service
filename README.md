# Abaqus-Flexnet-service
Script to configure the Abaqus Flexnet License Daemon as a restartable service

Usage:
```
./lm-install.sh
```

This script performs several steps to get Flexnet setup as a service under Redhat/CentOS version 6.x or 7.x.
It will:
1. Try to locate the correct Flexnet files
1. Create a lmadmin user to run the server
1. Setup license file directory `/etc/abaqus-lm` to store the license files
1. Setup log file directory `/var/log/abaqus-lm` and logrotate
1. Create and start the appropriate system service (SysV or systemd)
