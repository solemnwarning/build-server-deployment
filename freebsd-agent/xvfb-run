#!/bin/sh 

#xvfb-run my version for FreeBSD
#12 октября 2010 г. 15:28:26 (MSD)

export PATH='/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin'

i=0
while [ -f /tmp/.X$i-lock ]; do
	i=$(($i + 1))
done

Xvfb :$i &
XVFBPID=$!

env DISPLAY=:$i $@

kill $XVFBPID

exit 0
