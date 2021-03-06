#!/bin/bash
set -e -x
# This script is now being modified for Bosh deployment

### BEGIN INIT INFO
# Provides:          influxd
# Required-Start:    $all
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start the InfluxDB process
### END INIT INFO

# If you modify this, please make sure to also edit influxdb.service

# Command-line options that can be set in /etc/default/influxdb.  These will override
# any config file values.

JOB_NAME=influxdb

RUN_DIR=/var/vcap/sys/run/$JOB_NAME
LOG_DIR=/var/vcap/sys/log/$JOB_NAME
PIDFILE=$RUN_DIR/$JOB_NAME.pid

DEFAULT=/etc/default/influxdb

mkdir -p $RUN_DIR $LOG_DIR
chown -R vcap:vcap $RUN_DIR $LOG_DIR
exec 1>> $LOG_DIR/$JOB_NAME.stdout.log
exec 2>> $LOG_DIR/$JOB_NAME.stderr.log

#Create the data folder, where InfluxDB will store data
mkdir -p /var/vcap/store/influxdb
chown -R vcap:vcap /var/vcap/store/influxdb

# Daemon options
INFLUXD_OPTS=

# Process name ( For display )
NAME=influxdb

# User and group
#default: influxdb but trying vcap
USER=vcap
GROUP=vcap

# Check for sudo or root privileges before continuing
#if [ "$UID" != "0" ]; then
#    echo "You must be root to run this script"
#    exit 1
#fi

# Daemon name, where is the actual executable If the daemon is not
# there, then exit.
#DAEMON=/usr/bin/influxd
DAEMON=/var/vcap/jobs/influxdb/packages/influxdb/usr/bin/influxd
if [ ! -x $DAEMON ]; then
    echo "Executable $DAEMON does not exist!"
    exit 5
fi

# Configuration file
#CONFIG=/etc/influxdb/influxdb.conf
CONFIG=/var/vcap/jobs/influxdb/config/influxdb.conf

# PID file for the daemon - DEFINED ABOVE
#PIDFILE=/var/run/influxdb/influxd.pid
PIDDIR=`dirname $PIDFILE`
if [ ! -d "$PIDDIR" ]; then
    mkdir -p $PIDDIR
#    chown $USER:$GROUP $PIDDIR
fi
chown $USER:$GROUP $PIDDIR

# Max open files
OPEN_FILE_LIMIT=65536

if [ -r /lib/lsb/init-functions ]; then
    source /lib/lsb/init-functions
fi

# Logging
#if [ -z "$STDOUT" ]; then
#    STDOUT=/dev/null
#fi

#if [ ! -f "$STDOUT" ]; then
#    mkdir -p $(dirname $STDOUT)
#fi

#if [ -z "$STDERR" ]; then
#    STDERR=/var/log/influxdb/influxd.log
#fi

#if [ ! -f "$STDERR" ]; then
#    mkdir -p $(dirname $STDERR)
#fi

#$STDOUT=$LOG_DIR/$JOB_NAME.stdout.log
#$STDERR=$LOG_DIR/$JOB_NAME.stderr.log

# Override init script variables with DEFAULT values
#if [ -r $DEFAULT ]; then
#    source $DEFAULT
#fi

function log_failure_msg() {
    echo "$@" "[ FAILED ]"
}

function log_success_msg() {
    echo "$@" "[ OK ]"
}

function start() {
    # Check if config file exist
    if [ ! -r $CONFIG ]; then
        log_failure_msg "config file $CONFIG doesn't exist (or you don't have permission to view)"
        exit 4
    fi

    # Check that the PID file exists, and check the actual status of process
    if [ -f $PIDFILE ]; then
        PID="$(cat $PIDFILE)"
        if kill -0 "$PID" &>/dev/null; then
            # Process is already up
            log_success_msg "$NAME process is already running"
            return 0
        fi
    else

      #some recommendation for PISFILE to be check if there is a problem
      #echo 1 >> $PIDFILE
      #echo $$ > $PIDFILE

        su -s /bin/sh -c "touch $PIDFILE" $USER &>/dev/null
        if [ $? -ne 0 ]; then
            log_failure_msg "$PIDFILE not writable, check permissions"
            exit 5
        fi
    fi

    # Bump the file limits, before launching the daemon. These will
    # carry over to launched processes.
    ulimit -n $OPEN_FILE_LIMIT
    if [ $? -ne 0 ]; then
        log_failure_msg "Unable to set ulimit to $OPEN_FILE_LIMIT"
        exit 1
    fi

    # Launch process
    echo "Starting $NAME..."
    if which start-stop-daemon &>/dev/null; then
        start-stop-daemon \
            --chuid $GROUP:$USER \
            --start \
            --quiet \
            --pidfile $PIDFILE \
            --exec $DAEMON \
            -- \
            -pidfile $PIDFILE \
            -config $CONFIG \
            $INFLUXD_OPTS &
            #>>$STDOUT 2>>$STDERR &

            # Above is starting the dservice
            # Tell monit that everything is ok :)
            #


            # exec somecommand \
            #  >>  $LOG_DIR/web_ui.stdout.log \
            #  2>> $LOG_DIR/web_ui.stderr.log
            #start-stop-daemon --chuid vcap:vcap --start --quiet --pidfile /var/vcap/sys/run/influxdb/influxdb.pid --exec /var/vcap/jobs/influxdb/packages/influxdb/usr/bin/influxd -- -pidfile /var/vcap/sys/run/influxdb/influxdb.pid -config /var/vcap/jobs/influxdb/config/influxdb.conf
    else
        local CMD="$DAEMON -pidfile $PIDFILE -config $CONFIG $INFLUXD_OPTS >>$STDOUT 2>>$STDERR &"
        su -s /bin/sh -c "$CMD" $USER
    fi

    # Sleep to verify process is still up
    sleep 1
    if [ -f $PIDFILE ]; then
        # PIDFILE exists
        if kill -0 $(cat $PIDFILE) &>/dev/null; then
            # PID up, service running
            log_success_msg "$NAME process was started"
            return 0
        fi
    fi
    log_failure_msg "$NAME process was unable to start"
    exit 1




}

function stop() {
    # Stop the daemon.
    if [ -f $PIDFILE ]; then
        local PID="$(cat $PIDFILE)"
        if kill -0 $PID &>/dev/null; then
            echo "Stopping $NAME..."
            # Process still up, send SIGTERM and remove PIDFILE
            kill -s SIGTERM $PID &>/dev/null && rm -f "$PIDFILE" &>/dev/null
            while true; do
                # Enter loop to ensure process is stopped
                kill -0 $PID &>/dev/null
                if [ "$?" != "0" ]; then
                    # Process stopped, break from loop
                    log_success_msg "$NAME process was stopped"
                    return 0
                fi

                # Process still up after signal, sleep and wait
                sleep 1
                n=$(expr $n + 1)
                if [ $n -eq 30 ]; then
                    # After 30 seconds, send SIGKILL
                    echo "Timeout exceeded, sending SIGKILL..."
                    kill -s SIGKILL $PID &>/dev/null
                elif [ $? -eq 40 ]; then
                    # After 40 seconds, error out
                    log_failure_msg "could not stop $NAME process"
                    exit 1
                fi
            done
        fi
    fi
    log_success_msg "$NAME process already stopped"


    #kill -9 `cat $PIDFILE`
    # rm -f $PIDFILE
}

function restart() {
    # Restart the daemon.
    stop
    start
}

function status() {
    # Check the status of the process.
    if [ -f $PIDFILE ]; then
        PID="$(cat $PIDFILE)"
        if kill -0 $PID &>/dev/null; then
            log_success_msg "$NAME process is running"
            exit 0
        fi
    fi
    log_failure_msg "$NAME process is not running"
    exit 1
}

case $1 in
    start)
        start
        ;;

    stop)
        stop
        ;;

    restart)
        restart
        ;;

    status)
        status
        ;;

    version)
        $DAEMON version
        ;;

    *)
        # For invalid arguments, print the usage message.
        echo "Usage: $0 {start|stop|restart|status|version}"
        exit 2
        ;;
esac
