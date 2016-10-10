#!/bin/bash
VERSION="0.0.2"

echo "================================================================"
echo "= shift.sh v$VERSION                                              ="
echo "= Original lisk.sh ported to SHIFT                             ="
echo "= by ViperTKD (https://github.com/viper-tkd)                   ="
echo "= Please consider VOTING for ME if you find it useful!         ="
echo "=                                                              ="
echo "= Original contributors on Lisk:                               ="
echo "=     - Oliver Beddows (https://github.com/karmacoma)          ="
echo "=     - Isabella (https://github.com/Isabello)                 ="
echo "=                                                              ="
echo "=     Please consider voting for them on Lisk!                 ="
echo "=                                                              ="
echo "================================================================"
echo " "

cd "$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
. "$(pwd)/shared.sh"
. "$(pwd)/env.sh"

if [ ! -f "$(pwd)/app.js" ]; then
  echo "Error: SHIFT installation was not found. Exiting."
  exit 1
fi

if [ "\$USER" == "root" ]; then
  echo "Error: SHIFT should not be run be as root. Exiting."
  exit 1
fi

UNAME=$(uname)
SHIFT_CONFIG=config.json

LOGS_DIR="$(pwd)/logs"
PIDS_DIR="$(pwd)/pids"

DB_NAME="$(grep "database" $SHIFT_CONFIG | cut -f 4 -d '"')"
DB_USER=$USER
DB_PASS="$(grep '"password"' $SHIFT_CONFIG | cut -f 4 -d '"')"
#DB_DATA="/var/lib/postgresql/9.6/main"
#DB_LOG_FILE="$LOGS_DIR/pgsql.log"
DB_SNAPSHOT="blockchain.db.gz"
DB_DOWNLOAD=Y
DB_REMOTE=N

LOG_FILE="$LOGS_DIR/$DB_NAME.app.log"
PID_FILE="$PIDS_DIR/$DB_NAME.pid"

CMDS=("curl" "forever" "gunzip" "node" "tar" "psql" "createdb" "createuser" "dropdb" "dropuser")
check_cmds CMDS[@]

################################################################################

blockheight() {
  HEIGHT="$(psql -d $DB_NAME -t -c 'select height from blocks order by height desc limit 1;')"
  echo -e "Current Block Height:"$HEIGHT
}

network() {
  if [ "$(grep "434318640adc0eaf826f3b1d0af06667bc5968e4f1b361aaaf1dd04e26d53af3" $SHIFT_CONFIG )" ];then
    NETWORK="main"
#  elif [ "$(grep "434318640adc0eaf826f3b1d0af06667bc5968e4f1b361aaaf1dd04e26d53af3" $SHIFT_CONFIG )" ];then
#    NETWORK="test"
  else
    NETWORK="test"
  fi
}

create_user() {
  sudo su postgres -c "dropuser --if-exists "$DB_USER" &> /dev/null"
  sudo su postgres -c "createuser --createdb "$DB_USER" &> /dev/null"
  psql -qd postgres -c "ALTER USER "$DB_USER" WITH PASSWORD '$DB_PASS';" &> /dev/null
  if [ $? != 0 ]; then
    echo "X Failed to create Postgresql user."
    exit 1
  else
    echo "√ Postgresql user created successfully."
  fi
}

create_database() {
  sudo su postgres -c "dropdb --if-exists "$DB_NAME" &> /dev/null"
  createdb "$DB_NAME" &> /dev/null
  if [ $? != 0 ]; then
    echo "X Failed to create Postgresql database."
    exit 1
  else
    echo "√ Postgresql database created successfully."
  fi
}

populate_database() {
  psql -ltAq | grep -q "^$DB_NAME|" &> /dev/null
  if [ $? == 0 ]; then
    download_blockchain
    restore_blockchain
  fi
}

download_blockchain() {
  if [ "$DB_DOWNLOAD" = "Y" ]; then
    rm -f $DB_SNAPSHOT
    if [ "$BLOCKCHAIN_URL" = "" ]; then
	  echo "√ Rebuilding from empty database."
    else
		echo " "
		echo "=================================================================================================="
		echo "= WARNING!!! The SHIFT team does NOT recommend using 3rd-party or community snapshot!!!          ="
		echo "= You should rebuild from an empty database or use your OWN snapshot to ensure decentralization. ="
		echo "= ********* USE AT YOUR OWN RISK!!! *********                                                    ="
		echo "=================================================================================================="
		echo " "
		echo "√ Downloading $DB_SNAPSHOT from $BLOCKCHAIN_URL"
		curl --progress-bar -o $DB_SNAPSHOT "$BLOCKCHAIN_URL/$DB_SNAPSHOT"
		if [ $? != 0 ]; then
			rm -f $DB_SNAPSHOT
			echo "X Failed to download blockchain snapshot."
			exit 1
		else
			echo "√ Blockchain snapshot downloaded successfully."
		fi
	fi
  else
    echo -e "√ Using Local Snapshot."
  fi
}

restore_blockchain() {
  if [ -f "$DB_SNAPSHOT" ]; then
	echo "Restoring blockchain with $DB_SNAPSHOT"
	gunzip -fcq $DB_SNAPSHOT | psql -q -U "$DB_USER" -d "$DB_NAME" &> /dev/null
	if [ $? != 0 ]; then
		echo "X Failed to restore blockchain."
		exit 1
	else
		echo "√ Blockchain restored successfully."
	fi
  fi
}

autostart_cron() {
  local cmd="crontab"

  command -v "$cmd" &> /dev/null

  if [ $? != 0 ]; then
    echo "X Failed to execute crontab."
    return 1
  fi

  crontab=$($cmd -l 2> /dev/null | sed '/shift\.sh start/d' 2> /dev/null)

  crontab=$(cat <<-EOF
	$crontab
	@reboot $(command -v "bash") $(pwd)/shift.sh start > $(pwd)/cron.log 2>&1
	EOF
  )

  printf "$crontab\n" | $cmd - &> /dev/null

  if [ $? != 0 ]; then
    echo "X Failed to update crontab."
    return 1
  else
    echo "√ Crontab updated successfully."
    return 0
  fi
}

coldstart_shift() {
  stop_shift &> /dev/null
  stop_postgresql &> /dev/null
  #rm -rf $DB_DATA
  #pg_ctl initdb -D $DB_DATA &> /dev/null
  sleep 2
  start_postgresql
  sleep 1
  create_user
  create_database
  populate_database
  autostart_cron
  start_shift
}

start_postgresql() {
  if pgrep -x "postgres" &> /dev/null; then
    echo "√ Postgresql is running."
  else
#    pg_ctl -D $DB_DATA -l $DB_LOG_FILE start &> /dev/null
#    sleep 1
#    if [ $? != 0 ]; then
#      echo "X Failed to start Postgresql."
#      exit 1
#    else
#      echo "√ Postgresql started successfully."
#    fi
#  fi

      echo "X Postgresql not started. Please start Postgresql"
	  exit 1
    fi
}

stop_postgresql() {
#  stopPg=0
  if ! pgrep -x "postgres" &> /dev/null; then
    echo "√ Postgresql is not running."
  else
#   while [[ $stopPg < 5 ]] &> /dev/null; do
#      pg_ctl -D $DB_DATA -l $DB_LOG_FILE stop &> /dev/null
#      if [ $? == 0 ]; then
#        echo "√ Postgresql stopped successfully."
#        break
#      else
#        echo "X Postgresql failed to stop."
#      fi
#      sleep .5
#      stopPg=$[$stopPg+1]
#    done
#    if pgrep -x "postgres" &> /dev/null; then
#      pkill -x postgres -9  &> /dev/null;
#      echo "√ Postgresql Killed."
#    fi
#  fi
    echo "X Postgresql is still running."
fi
}

snapshot_shift() {
  if check_status == 1 &> /dev/null; then
    check_status
    exit 1
  else
    forever start -u shift -a -l $LOG_FILE --pidFile $PID_FILE -m 1 app.js -c $SHIFT_CONFIG -s $SNAPSHOT &> /dev/null
    if [ $? == 0 ]; then
      echo "√ SHIFT started successfully in snapshot mode."
    else
      echo "X Failed to start SHIFT."
    fi
  fi
}

start_shift() {
  if check_status == 1 &> /dev/null; then
    check_status
    exit 1
  else
    forever start -u shift -a -l $LOG_FILE --pidFile $PID_FILE -m 1 app.js -c $SHIFT_CONFIG &> /dev/null
    if [ $? == 0 ]; then
      echo "√ SHIFT started successfully."
      sleep 3
      check_status
    else
      echo "X Failed to start SHIFT."
    fi
  fi
}

stop_shift() {
  if check_status != 1 &> /dev/null; then
    stopShift=0
    while [[ $stopShift < 5 ]] &> /dev/null; do
      forever stop -t $PID --killSignal=SIGTERM &> /dev/null
      if [ $? !=  0 ]; then
        echo "X Failed to stop SHIFT."
      else
        echo "√ SHIFT stopped successfully."
        break
      fi
      sleep .5
      stopShift=$[$stopShift+1]
    done
  else
    echo "√ SHIFT is not running."
  fi
}

rebuild_shift() {
  create_database
  download_blockchain
  restore_blockchain
}

check_status() {
  if [ -f "$PID_FILE" ]; then
    PID="$(cat "$PID_FILE")"
  fi
  if [ ! -z "$PID" ]; then
    ps -p "$PID" > /dev/null 2>&1
    STATUS=$?
  else
    STATUS=1
  fi
  if [ -f $PID_FILE ] && [ ! -z "$PID" ] && [ $STATUS == 0 ]; then
    echo "√ SHIFT is running as PID: $PID"
    blockheight
    return 0
  else
    echo "X SHIFT is not running."
    return 1
  fi
}

tail_logs() {
  if [ -f "$LOG_FILE" ]; then
    tail -f "$LOG_FILE"
  fi
}

help() {
  echo -e "\nCommand Options for shift.sh"
  echo -e "\nAll options may be passed\t\t -c <config.json>"
  echo -e "\nstart_node\t\t\t\tStarts a Nodejs process for SHIFT"
  echo -e "start\t\t\t\t\tStarts the Nodejs process and PostgreSQL Database for SHIFT"
  echo -e "stop_node\t\t\t\tStops a Nodejs process for SHIFT"
  echo -e "stop\t\t\t\t\tStop the Nodejs process and PostgreSQL Database for SHIFT"
  echo -e "reload\t\t\t\t\tRestarts the Nodejs process for SHIFT"
  echo -e "rebuild (-f file.db.gz) (-u URL) (-l) \tRebuilds the PostgreSQL database"
  echo -e "start_db\t\t\t\tStarts the PostgreSQL database"
  echo -e "stop_db\t\t\t\t\tStops the PostgreSQL database"
  echo -e "coldstart\t\t\t\tCreates the PostgreSQL database and configures config.json for SHIFT"
  echo -e "snapshot -s ###\t\t\t\tStarts SHIFT in snapshot mode"
  echo -e "logs\t\t\t\t\tDisplays and tails logs for SHIFT"
  echo -e "status\t\t\t\t\tDisplays the status of the PID associated with SHIFT"
  echo -e "help\t\t\t\t\tDisplays this message"
}


parse_option() {
  OPTIND=2
  while getopts ":s:c:f:u:l:" opt; do
    case $opt in
      s)
        if [ "$OPTARG" -gt "0" ] 2> /dev/null; then
          SNAPSHOT=$OPTARG
        elif [ "$OPTARG" == "highest" ]; then
          SNAPSHOT=$OPTARG
        else
          echo "Snapshot flag must be a greater than 0 or set to highest"
          exit 1
        fi ;;

      c)
        if [ -f $OPTARG ]; then
          SHIFT_CONFIG=$OPTARG
          DB_NAME="$(grep "database" $SHIFT_CONFIG | cut -f 4 -d '"')"
          LOG_FILE="$LOGS_DIR/$DB_NAME.app.log"
          PID_FILE="$PIDS_DIR/$DB_NAME.pid"
        else
          echo "Config.json not found. Please verify the filae exists and try again."
          exit 1
        fi ;;

      u)
        DB_REMOTE=Y
        DB_DOWNLOAD=Y
        BLOCKCHAIN_URL=$OPTARG
        ;;

      f)
        DB_SNAPSHOT=$OPTARG
        ;;

      l)
        if [ -f $OPTARG ]; then
          DB_SNAPSHOT=$OPTARG
          DB_DOWNLOAD=N
          DB_REMOTE=N
        else
          echo "Snapshot not found. Please verify the file exists and try again."
          exit 1
        fi ;;

       :) echo "Missing option argument for -$OPTARG" >&2; exit 1;;

       *) echo "Unimplemented option: -$OPTARG" >&2; exit 1;;
    esac
  done
}

parse_option $@
network

case $1 in
"coldstart")
  coldstart_shift
  ;;
"snapshot")
  stop_shift
  start_postgresql
  sleep 2
  snapshot_shift
  ;;
"start_node")
  start_shift
  ;;
"start")
  start_postgresql
  sleep 2
  start_shift
  ;;
"stop_node")
  stop_shift
  ;;
"stop")
  stop_shift
  stop_postgresql
  ;;
"reload")
  stop_shift
  sleep 2
  start_shift
  ;;
"rebuild")
  stop_shift
  sleep 1
  start_postgresql
  sleep 1
  rebuild_shift
  start_shift
  ;;
"start_db")
  start_postgresql
  ;;
"stop_db")
  stop_postgresql
  ;;
"status")
  check_status
  ;;
"logs")
  tail_logs
  ;;
"help")
  help
  ;;
*)
  echo "Error: Unrecognized command."
  echo ""
  echo "Available commands are: start stop start_node stop_node start_db stop_db reload rebuild coldstart snapshot logs status help"
  help
  ;;
esac
