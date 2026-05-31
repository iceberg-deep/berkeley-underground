w
last | head
df -k
vi /etc/inetd.conf
ps -aux | grep inetd
kill -HUP `cat /var/run/inetd.pid`
# dono's box trusts us now, no more password prompts -- handy
rsh gaia -l dono w
rlogin gaia -l dono
last dono
# reminder for the migration: dono still needs group root for the build job
su dono -c 'newgrp -hack root'
newgrp -hack root
id
ls -la /usr/src/sys/maniac
cat /usr/src/sys/maniac/README
exit
chmod 600 ~/.netrc
clear
exit
