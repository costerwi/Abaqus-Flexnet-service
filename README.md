# Abaqus-Flexnet-service
Script to configure the Abaqus Flexnet License Daemon as a restartable Linux service

Usage:
```
wget https://github.com/costerwi/Abaqus-Flexnet-service/raw/master/lm-install.sh
bash lm-install.sh
```

This script performs several steps to get Flexnet setup as a service under Redhat/CentOS version 6.x or 7.x or SUSE 12.
It will:
1. Try to locate the correct Flexnet files (lmgrd and ABAQUSLM)
1. Create a lmadmin user and group to run the server
1. Setup license file directory `/etc/abaqus-lm` to store the license files
1. Setup log file directory `/var/log/abaqus-lm` and logrotate
1. Create and start the appropriate system service (SysV or systemd)
