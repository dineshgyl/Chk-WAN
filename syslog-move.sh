#!/bin/sh

#===============================================================================
#
# Moves syslog between internal flash memory and USB drive or scans a log for BOOT errors and custom action messages.
#
#          Called as the last line of init-start preferably after 180sec sleep delay!!!!
#                 and as last line of services-stop
#
#	Jan 2017 http://pastebin.com/embed_js/M0qUATyj
#
#
#   e.g.   syslog-move.sh   [help|-h|status| file_name | reset ]
#
#
#          syslog-move.sh
#                            If '/tmp/BOOTINPROGRESS' exists, moves syslog to USB '/tmp/mnt/$MOUNTED/Syslog/syslog.log'
#          syslog-move.sh    reset
#                            Moves syslog back to '/tmp/syslog.log' (flash memory)
#          syslog-move.sh    /tmp/mnt/$MOUNTED/Syslog/syslog.log-20170125-153049-BOOT.txt
#                            Scans file for 'abnormal messages and custom messages and creates 'BOOT_Errors.txt' & 'MyCustomActions.txt' 
#          syslog-move.sh    help
#                            This help information

#	e.g. init-start
#
#		#!/bin/sh
#		/usr/bin/logger -s -t "($(basename $0))" $$ "Martineau $MYROUTER BOOT in progress... [$@]" 
#		# NOTE: Can't use Flash drive /tmp/mnt/$MYROUTER/ 'cos it hasn't been mounted yet :-(
#		# 'flock' is probably a better solution rather than the 'echo' ;-)
#		HARDWARE_MODEL=$(nvram get productid)
#		MYROUTER=$(nvram get computer_name)
#		BUILDNO=$(nvram get buildno)
#		EXTENDNO=$(nvram get extendno)
#		echo $$"-"`date` > /tmp/BOOTINPROGRESS	
#		rm /tmp/SHUTDOWNINPROGRESS
#		# Should be sufficient to cover physical BOOT process?
#		logger -st "($(basename $0))" $$ "Paused for 3 mins....."
#		sleep 180
#		# Call custom scripts/commands here e.g. cifs.sh / cru etc. here
#		/usr/bin/logger -st "($(basename $0))" $$ "Martineau" $MYROUTER "BOOT Completed Firmware build" $BUILDNO $EXTENDNO "[$@]"
#		# Move Syslog to USB Flash drive
#		/jffs/scripts/syslog-move.sh
#		rm /tmp/BOOTINPROGRESS
#
#	e.g. services-stop
#
#		#!/bin/sh
#		/usr/bin/logger -st "($(basename $0))" $$ "Martineau Services cleanup in progress... [$@]"
#		MYROUTER=$(nvram get computer_name)
#		# NOTE: Could use Flash drive /tmp/mnt/$MYROUTER/ 
#		# 'flock' is probably a better solution rather than the 'echo'
#		echo $$"-"`date` > /tmp/SHUTDOWNINPROGRESS							# Will be deleted by init-start
#		/usr/bin/logger -st "($(basename $0))" $$ "Stopping rstats....."
#		service stop_rstats
#		/usr/bin/logger -st "($(basename $0))" $$ "Stopping cstats....."
#		service stop_cstats
#		# Call custom scripts/commands here e.g. Entware '/rc.unslung' etc. here
#		# At this point no further logger statements are recorded in Syslog?
#		#    so spoof a logger message!
#		echo `date "+%b   %d %T"` $MYROUTER "Spoof.logger (services-stop): Martineau Services shutdown cleanup complete."  >> /tmp/syslog.log
#		echo `date "+%b   %d %T"` $MYROUTER "Spoof.logger (services-stop): Saving syslog before Reboot..... "  >> /tmp/syslog.log
#		/usr/bin/logger -st "($(basename $0))" $$ "Saving Syslog before Reboot..... "
#		/jffs/scripts/syslog-move.sh
#		exit 0 
#
GetLocationSTATUS () {
	# Identify media for current disposition of dataset i.e. is /tmp/syslog.log a link to USB?
	local ORG="?"
	if [[ -L "$SOURCE" ]];then
		#DEST="RAM"
		local WHERE="USB"
		local TEXT="is on"
	else
		#DEST="USB"
		local WHERE="RAM"
		local TEXT="is in"
	fi
	if [ -z $1 ];then
		logger -st "($(basename $0))" $$ $MYROUTER "Syslog '"$SOURCE"'" $TEXT $WHERE
	fi
	echo $WHERE
}
# Print between line beginning with'#==' to first blank line inclusive
ShowHelp() {
	awk '/^#==/{f=1} f{print; if (!NF) exit}' $0
}

# Help required?
if [ "$1" = "-h" ] || [ "$1" = "help" ]; then
   ShowHelp									# Show help
   exit 0
fi

SDx="sda1"											# Default - Change for sdb1 etc.

DEV_MOUNT=`df | grep -F "$SDx" | awk '{print $6}'`
if [ -z $DEV_MOUNT ];then
	logger -st "($(basename $0))" $$ "***ERROR '/dev/"$SDx"' mount point not found!"
	echo -e "\a"
	exit 99
fi

SOURCE="/tmp/syslog.log"							# Original source of the syslog in Router flash memory
SYSLOG=$DEV_MOUNT"/Syslog/syslog.log"				# Destination of the syslog on USB disk
ORIGINAL=$(GetLocationSTATUS)						# Current physical location of syslog.log
DEST="USB"											# Default target destination

ERRORFILE=$DEV_MOUNT"/Syslog/BOOT_Errors.txt"				# Results of scanning log for 'abnormal' messages
MYCUSTOMFILE=$DEV_MOUNT"/Syslog/MyCustomActions.txt"		# Results of scanning log for 'custom action' events

# Here because we need the global variables set!
if [ "$1" == "status" ];then
	echo " "
	ORIGINAL=$(GetLocationSTATUS "?")
	# Confirm
	ls -l $SOURCE
	exit 0
fi

logger -st "($(basename $0))" $$ "Syslog Housekeeping starting....." [$@] 

NOW=$(date +"%Y%m%d-%H%M%S")    # current date and time

# Explicit request to revert back to flash memory (as used in services-stop @ REBOOT shutdown)
if [ "$1" == "reset" ];then
	DEST="RAM"
fi

if [ -z $1 ] || [ "$1" == "reset" ] ; then
	
	# True REBOOT in progress? see init-start
	if [ -e /tmp/BOOTINPROGRESS  ]; then
		logger -st "($(basename $0))" $$ "Boot-in-Progress '/tmp/BOOTINPROGRESS' detected."
		if [ -f $SYSLOG ];then
			logger -st "($(basename $0))" $$ "Renaming previous USB '"$SYSLOG"' to '"$SYSLOG-$NOW"'"
			mv $SYSLOG $SYSLOG-${NOW}_shutdown.txt			# Rename previous USB syslog
		fi
		logger -st "($(basename $0))" $$ "Creating '"$SYSLOG-$NOW-BOOT.raw"'"
		killall syslogd
		sleep 1
		cp $SOURCE $SYSLOG-$NOW-BOOT.raw		# copy current physical /tmp syslog to the new location
		rm $SOURCE
		# Remove all duplicated 'shutdown' lines - they are always incomplete anyway?
		logger -st "($(basename $0))" $$ "Editing '"$SYSLOG-$NOW-BOOT.raw"' -> '"$SYSLOG-$NOW-BOOT.txt"'"
		RC=$(sed -n '/^May/,$p' $SYSLOG-$NOW"-BOOT.raw" > $SYSLOG-$NOW"-BOOT.txt")	# i.e. upto 'May  5 01:05:09 kernel: klogd started: BusyBox v1.25.1 (2024-11-17 14:17:59 EST)'
		rm $SYSLOG-$NOW-BOOT.raw
		SCANTHIS=$SYSLOG-$NOW-BOOT.txt
	else
		logger -st "($(basename $0))" $$ "Creating '"$SYSLOG-$NOW.txt"'"
		#killall syslogd
		sleep 1
		cp $SOURCE $SYSLOG-$NOW.txt				# copy current /tmp/syslog.log to the new location
		rm $SOURCE
		SCANTHIS=$SYSLOG-$NOW.txt
	fi

	killall syslogd

	# Start SYSLOG on the USB disk with infinite size i.e. no GDG creation if no ARG supplied
	if [ "$DEST" == "USB" ];then
		if [ "$ORIGINAL" == "RAM" ];then
			ACTION="moved to"
		else
			ACTION="retained on"
		fi
		logger -st "($(basename $0))" $$ "Syslog" $ACTION "USB drive '"$SYSLOG"'"
		CMD="syslogd -O $SYSLOG -s 0"
		$CMD
	else
		logger -st "($(basename $0))" $$ "Syslog reset to internal flash memory '"$SOURCE"'"   # display OK message
		CMD="syslogd -O $SOURCE"
		$CMD					# Put it back where ASUS expect its to be ? /tmp/syslog.log in internal memory
	fi

	if [ "$?" -ne 0 ]; then    # check for error
		logger -st "($(basename $0))" $$ "***ERROR rc=" $? "'"$CMD"'"
		exit $?
	fi

	if [ "$DEST" == "USB" ];then
		# Allow Router GUI to see the Syslog!!!!! otherwise it shows it empty!!!
		rm $SOURCE 2> /dev/null
		CMD="ln -s $SYSLOG $SOURCE"
		$CMD          # create a symbolic link from the original syslog to the USB one

		if [ "$?" -ne 0 ]; then
			logger -st "($(basename $0))" $$ "**ERROR rc=" $? "'"$CMD"'"
			echo -e "\a"
		fi
	fi
	
	# Confirm????
	#ls -l $SOURCE

else
	SCANTHIS=$DEV_MOUNT"/Syslog/$1"							# Scan filename provided
fi


#if [ -e /tmp/BOOTINPROGRESS  ]; then
	# Scan the BOOT log for errors i.e. literal 'ERROR' or 'FAILED' or 'ABORT' case insensitive
	logger -st "($(basename $0))" $$ "SYSLOG 'abnormal' message scanning: '" $SCANTHIS"'"
	echo "Scanning '"$SCANTHIS"'" > $ERRORFILE
	ERROR_LINE_CNT=`grep -c -E -i "ERROR|FAILED|ABORT" $SCANTHIS`
	#logger -st "($(basename $0))" $$ "**DEBUG ERROR_LINE_CNT="$ERROR_LINE_CNT
	if [ "$ERROR_LINE_CNT" -gt 0 ]; then
		echo -e "\a"
		logger -st "($(basename $0))" $$ "Scan of '"$SCANTHIS"' found" $ERROR_LINE_CNT "errors"
		RC=`grep -iE "ERROR|FAILED|ABORT" $SCANTHIS >> $ERRORFILE`
		echo 
	else
		echo "Nothing 'abnormal' - ERROR or FAILED or ABORT found." >> $ERRORFILE
	fi
	# Scan the log for my custom script actions...
	logger -st "($(basename $0))" $$ "SYSLOG 'custom action' message scanning: '"$SCANTHIS"'"
	CUSTOM_LINE_CNT=`grep -E "\):" $SCANTHIS | grep -vE "]:|kernel:"  > $MYCUSTOMFILE`
#fi

logger -st "($(basename $0))" $$ "Syslog Housekeeping complete for '"$SCANTHIS"'" 
	
exit 0