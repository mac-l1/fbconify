#!/bin/bash
#set -x

# show_parameterimages by mac-l1
#
# script to show accessable parameter images
# for rockchip bootable SD cards /dev/mmcblk0 and /dev/mmcblk1 
# and for accessable parameter partition at /dev/block/mtd/by-name/parameter
#
# tested for firefly, use at your own risk as raw disk access is done
#
# cheers! mac-l1

show_parameterimage() {
DISK=$1
DISKNAME=`echo $DISK|sed 's/\//_/g'`
PARIMG_OLD=parameter"${DISKNAME}".old.img
PARIMG_TMP=parameter"${DISKNAME}".tmp.img
PARTXT=parameter"${DISKNAME}"
PARIMG_NEW=parameter"${DISKNAME}".new.img

# check if device exists
if ! [ -e $DISK ]; then
  printf "%s\n" "device ${DISK} doesnt exist; cant show anything"
  return
fi

echo parameter image of $DISK:

rm -rf $PARIMG_OLD $PARIMG_NEW $PARIMG_TMP $PARTXT

# check for SD card
if [ `echo $DISK|grep mmcblk|wc -l` == "0" ]; then
  SEEK=0 # no SD card so assume normal parameter partition
else
  SEEK=$((0x2000)) # SD card has fixed offset of 0x2000 times 512 bytes
fi

# get first sector
sudo dd status=none conv=sync,fsync if=$DISK of=$PARIMG_TMP skip=$SEEK count=1 bs=512

# validate for parameter.img
if [ `dd status=none if=$PARIMG_TMP count=4 bs=1` != "PARM" ]; then
  printf "%s\n" "device ${DISK} doesnt have a valid parameter img; cant show it!" 
  return
fi

echo 'ibase=16; '`xxd -u -ps -l 2 -s 4 $PARIMG_TMP |sed 's/\(..\)\(..\)/\2\1/'` | sed 's/$/+12/' | bc | xargs -I {} sudo dd status=none conv=sync,fsync conv=sync,fsync bs=1 skip=`expr $SEEK \* 512` count={} if=$DISK of=$PARIMG_OLD
rm -rf $PARIMG_TMP

# strip header (8 bytes) and crc (last 4 bytes)
echo 'ibase=16; '`xxd -u -ps -l 2 -s 4 $PARIMG_OLD |sed 's/\(..\)\(..\)/\2\1/'` | bc | xargs -I {} dd status=none bs=1 skip=8 count={} if=$PARIMG_OLD of=$PARTXT

cat $PARTXT
echo
}

show_parameterimage /dev/mmcblk0 # probably internal flash mem/ SD card
show_parameterimage /dev/mmcblk1 # most likely external SD card
show_parameterimage /dev/block/mtd/by-name/parameter # most likely internal nand flash

exit
