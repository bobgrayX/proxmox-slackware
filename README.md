# Proxmox-Slackware

This code is patch for PVE-LXC Perl module to allow Proxmox 8 UI creating Slackware VMs and Containers.
This is pure Perl code. There are two existing files modified and one new package with Slackware specific functions added as a template.

1. This file contains modification in only one line. There is a new OS added to to the list of recognizable distros.
```console
    ~/:$ /usr/share/perl5/PVE/LXC/Config.pm
```
2. This file contains few new lines which are related to the use of new Slackware template package.
```console
    ~/:$ /usr/share/perl5/PVE/LXC/Setup.pm
```
3. This is the template file with Slackware specific functions.
```console
    ~/:$ /usr/share/perl5/PVE/LXC/Sertup/Slackware.pm
```
