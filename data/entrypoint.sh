#!/bin/bash

if [ -n "$authorized_keys" ] && [ ! -f /root/.ssh/authorized_keys ]; then printenv authorized_keys > /root/.ssh/authorized_keys; fi
if [ -n "$password" ] && passwd --status | grep -q 'L'; then echo "root:$password" | chpasswd ; fi
unset authorized_keys
unset password
/usr/sbin/sshd -D
