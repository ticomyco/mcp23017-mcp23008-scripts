#!/bin/bash
# Tested on Raspbian "buster" on a Raspberry Pi 4B

# This bash script can be used to enable/disable the individual relays on the
# MCP23017 or MCP23008 I/O expander chip on an I2C bus, 
# when all of its GPIO pins are configured as outputs, and  
# then fed through a bank of appropriate NPN transistors or a Darlington array
# such as the ULN2803a and a supplemental power supply to drive the relay coil
# in a low-active configuration (common positive rail, switching each relay to 
# sink its ground current throught the driver Darlington array transistor). 
# This script will control either an MCP23008 or *one* bank of an MCP23017 at 
# a time, and you must change the IODIR and OLAT variables below to match your
# chosen configuration. 

# Because the MCP23017 has 16 output pins, it is necessary to use two ULN2803a
# Darlington array chips because they are 8-channel devices, whereas the 
# MCP23008 only has 8 output pins and thus needs only a single ULN2803a. 

# The VSS pin on the MCP23017 should be tied to the ground on the raspberry pi,
# as well as the ground pin (9) on the ULN2803a Darlington array. 
# The VDD pin on the MCP23017 should be connected to a +3.3V source, however 
# the Darlington array should have its supplemental power supply (either +5V or
# +12V or +24V as appropriate for the relay coils) connected with a shared
#  ground to the MCP23017 and RPi, however the positive +5/12/24V rail 
# connected to the relay coils and the COM pin (10) on the ULN2803a chip.

# Note that the MCP23017 must have its RESET pin (18) connected to a +3.3V 
# source for it to function. 

#Permission to use, copy, modify, and/or distribute this software for any purpose
#with or without fee is hereby granted.

#THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
#REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
#FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
#INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
#OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
#TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
#THIS SOFTWARE.

# The MCP23017 must first be initialized to have its pins set as outputs, and
# and are disabled by default. 

# This script assumes that the 
# Requires package "i2c-tools" (apt-get install i2c-tools), a working i2c bus,
#  and assumes user running the script has write permissions to /dev/i2c-1 etc

# This script has very little error checking or sanity checks built-in, however
#  the use of a state file to keep track of which relays are currently enabled
#  and the use of a lock file to prevent this script from being run more than 
#  once simultaneously should make it safe to use with a system such as Mycodo
#  which theoretically could attempt to call this script with different commands#  simultaneously. 

ADDR="0x20"  # i2c address of MCP23017 chip - configure pins A0,A1,A2 to be high
	     # or low to set address between 0x20 and 0x27
	     # test with  'i2cdetect -y 1' if using bus 1)
BUS=19	     # i2c bus number -- list available buses with 'i2cdetect -l'

# SET this lockfile name to be unique for each MCP23017 you wish to control.
LOCKFILE=/tmp/mcp23017relay.lock

# Set the IODIR register to configure pins as outputs. If using MCP23017 Bank A,
# then IODIRA is 0x00, or if Bank B, IODIRB is 0x01
# If using an MCP23008 then IODIR is only 0x00. 
IODIR="0x00"

# Set the OLAT register to control pin states. If using MCP23017 Bank A, 
# then OLATA is at 0x14, or if using Bank B then OLATB is at 0x15
# If using MCP23008 then OLAT is 0x0A
OLAT="0x14"

ALLOFF="00"  # hex value for i2cset command to turn all relays off
ALLON="FF"   # hex value to turn all relays on

# Commands are: ./mcp23017_relay_v1.sh init on   # turn all relays on
#               ./mcp23017_relay_v1.sh init off  # turn all relays off

# Attempt to obtain a lock before continuing, wait up to 2 seconds
exec 100> $LOCKFILE || exit 1
flock -w 2 100 || exit 1
trap 'rm -f $LOCKFILE' EXIT

if (( $# != 2 )); then
	echo "Need two arguments! Proper usage: $0 (init|relay#) (on|off)"
	echo "Examples: "
	echo " $0 init on  # Initialize IODirection and set all relays on"
	echo " $0 3 off    # set relay#3 off"
	echo " $0 5 on     # set relay#5 on"
	exit 1
else
  case "$1" in
    "init") #initialize  all relays off or on and set IO Direction as out

	# set the IODIR register for the pins to be outputs:
	/usr/sbin/i2cset -y $BUS $ADDR $IODIR 0x00

	case "$2" in
  	   "on")
		# Need to write byte to i2c address 
		/usr/sbin/i2cset -y $BUS $ADDR $OLAT 0x$ALLON
		;;
          "off")
		/usr/sbin/i2cset -y $BUS $ADDR $OLAT 0x$ALLOFF
		;;
       	  *) 
		echo "invalid parameter! must be on or off"
		exit 1
	       	;;
	esac # end "init" case
	;;
    0|1|2|3|4|5|6|7) # enable/disable individual relays
	#check IODIR has been set appropriately:
	declare -i MYIODIR=$(/usr/sbin/i2cget -y $BUS $ADDR $IODIR)
        if [ "$MYIODIR" -eq "0" ]; then
	    declare -i STATE=$(/usr/sbin/i2cget -y $BUS $ADDR $OLAT)
	    #echo $STATE
	     # Create a positive bit mask for the relay we wish to change
	     (( AMASK =  2 ** $1  ))
     	     case $2 in 
		"on") 
		    # use an OR with a positive bit mask to enable only the
		    # bit for the desired relay and leave others unmodified
		    (( STATE |= $((AMASK)) ))
		    printf -v HEXSTATESTR '%x' $STATE # need to make a text
		        # string of the new state in order to call i2cset:
		    /usr/sbin/i2cset -y $BUS $ADDR $OLAT 0x$HEXSTATESTR
		    ;; # done enabling a relay
		"off")
		    # use an AND with a negated bit mask to disable only the
		    #  bit for the desired relay and leave others unmodified
		    (( STATE &= $((~ AMASK & 255)) ))
		    printf -v HEXSTATESTR '%x' $STATE # need to make a text
		        # string of the new state in order to call i2cset:
		    /usr/sbin/i2cset -y $BUS $ADDR $OLAT 0x$HEXSTATESTR
		    ;;
		*)
		    echo "error! only on or off allowed! run $0 to see examples"
		    exit 1
		esac # end case for individual relays	
	else # IODIR not set correctly!
	    echo "Error! must run script first with init on or off to initialize outputs."
	    exit 1
	fi 
	;;
     *) # shouldn't end up here
	echo "error! First parameter must be either init or output number 0-7"
	exit 1
     esac # end case for first level parameters
fi # end check if script was called with 2 parameters
