#!/bin/bash
### BEGIN INIT INFO
# Provides:          influx-enterprise
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start the Influx-Enterprise service at boot time
### END INIT INFO

# Script sleeps for START_TIMEOUT seconds after calling start to
# validate the process started correctly
START_TIMEOUT=2

# Script to execute when starting
SCRIPT="/usr/bin/influx-enterprise"
# Options to pass to the script on startup
SCRIPT_OPTS="run -c /etc/influx-enterprise/influx-enterprise.conf"

# User to run the process under
RUNAS=influx-enterprise

# PID file for process
PIDFILE=/var/run/influx-enterprise.pid
# Where to redirect logging to
LOGFILE=/var/log/influx-enterprise/influx-enterprise.log
ERRLOGFILE=/var/log/influx-enterprise/influx-enterprise.log

start() {
    if [[ -f $PIDFILE ]]; then
        # PIDFILE exists
        if kill -0 $(cat $PIDFILE) &>/dev/null; then
            # PID up, service running
            echo '[OK] Service already running.' >&2
            return 0
        fi
    fi
    local CMD="$SCRIPT $SCRIPT_OPTS 1>> \"$LOGFILE\" 2>> \"$ERRLOGFILE\" & echo \$!"
    su -s /bin/sh -c "$CMD" $RUNAS > "$PIDFILE"
    sleep $START_TIMEOUT
    if [[ -f $PIDFILE ]]; then
        # PIDFILE exists
        if kill -0 $(cat $PIDFILE) &>/dev/null; then
            # PID up, service running
            echo '[OK] Service successfully started.' >&2
            return 0
        fi
    fi
    echo '[ERROR] Could not start service.' >&2
    return 1
}

status() {
    if [[ -f $PIDFILE ]]; then
        # PIDFILE exists
        if ps -p $(cat $PIDFILE) &>/dev/null; then
            # PID up, service running
            echo '[OK] Service running.' >&2
            return 0
        fi
    fi
    echo '[ERROR] Service not running.' >&2
    return 1
}

stop() {
    if [[ -f $PIDFILE ]]; then
        # PIDFILE still exists
        if kill -0 $(cat $PIDFILE) &>/dev/null; then
            # PID still up
            kill -15 $(cat $PIDFILE) &>/dev/null && rm -f "$PIDFILE" &>/dev/null
            if [[ "$?" = "0" ]]; then
                # Successful stop
                echo '[OK] Service stopped.' >&2
                return 0
            else
                # Unsuccessful stop
                echo '[ERROR] Could not stop service.' >&2
                return 1
            fi
        fi
    fi
    echo "[OK] Service already stopped."
    return 0
}

case "$1" in
    start)
        if [[ "$UID" != "0" ]]; then
            echo "[ERROR] Permission denied."
            exit 1
        fi
        start
        ;;
    status)
        status
        ;;
    stop)
        if [[ "$UID" != "0" ]]; then
            echo "[ERROR] Permission denied."
            exit 1
        fi
        stop
        ;;
    restart)
        stop
        start
        ;;
    *)
        echo "Usage: $0 {start|status|stop|restart}"
        esac
