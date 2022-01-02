#!/usr/local/bin/bash

set -e

PREFIX=/usr/local
USERNAME=buildkite-agent
HOMEDIR=/var/lib/buildkite-agent
SHUTDOWN_TIMEOUT=300

tmpdir="$(mktemp -d)"

build_url=$(wget -qO - https://api.github.com/repos/buildkite/agent/releases/latest \
	| jq -r '.assets[] | .browser_download_url | match(".*freebsd-amd64.*"; "") | .string')

echo "Downloading and unpacking $build_url to $tmpdir..."
wget -qO - "$build_url" | tar -xf - -C "$tmpdir"

echo "$USERNAME::::::Buildkite Agent:$HOMEDIR:/usr/local/bin/bash:" | adduser -D -f - -w no
install -d -m 0700 -o "$USERNAME" -g "$USERNAME" "$HOMEDIR"

install -o root -g wheel -m 0755 "$tmpdir/buildkite-agent" "$PREFIX/bin/buildkite-agent"

# Create empty hooks/plugins directories.
install -d -o root -g wheel -m 0755 $PREFIX/etc/buildkite-agent/hooks/
install -d -o root -g wheel -m 0755 $PREFIX/etc/buildkite-agent/plugins/

cat << 'EOF' > "$PREFIX/etc/rc.d/buildkite-agent"
#!/bin/sh

# PROVIDE: buildkite_agent
# REQUIRE: LOGIN DAEMON NETWORKING

# Enable this script by adding:
# buildkite_agent_enable="YES"
# ... to /etc/rc.conf

. /etc/rc.subr

name="buildkite_agent"
rcvar="buildkite_agent_enable"
start_cmd="${name}_start"
stop_cmd="${name}_stop"

buildkite_agent_start()
{
	if /usr/local/bin/pidof buildkite-agent > /dev/null
	then
		echo "buildkite-agent is already running" 1>&2
	else
		touch ${buildkite_agent_log}
		chown "${buildkite_agent_user}:wheel" /var/log/buildkite-agent.log
		
		if [ -n "${buildkite_agent_shutdown_timeout}" ]
		then
			nohup /bin/sh -c "/usr/bin/su - '${buildkite_agent_user}' -c 'BUILDKITE_AGENT_DISCONNECT_AFTER_IDLE_TIMEOUT=${buildkite_agent_shutdown_timeout} buildkite-agent start > ${buildkite_agent_log}' && shutdown -p +1 'buildkite-agent exited - shutting down'" &
		else
			/usr/bin/su - "${buildkite_agent_user}" -c "nohup buildkite-agent start > ${buildkite_agent_log} &"
		fi
	fi
}

buildkite_agent_stop()
{
	killall buildkite-agent
}

load_rc_config $name
run_rc_command "$1"
EOF

chmod 0755 "$PREFIX/etc/rc.d/buildkite-agent"

echo buildkite_agent_enable=YES                         >> /etc/rc.conf.local
echo buildkite_agent_user=$USERNAME                     >> /etc/rc.conf.local
echo buildkite_agent_log=/var/log/buildkite-agent.log   >> /etc/rc.conf.local
echo buildkite_agent_shutdown_timeout=$SHUTDOWN_TIMEOUT >> /etc/rc.conf.local

if [ ! -e "/bin/bash" ]
then
	echo "Symlinking /bin/bash to /usr/local/bin/bash"
	ln -s /usr/local/bin/bash /bin/bash
fi

rm -rf "$tmpdir"
