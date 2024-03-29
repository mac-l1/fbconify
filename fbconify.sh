#!/bin/bash
#set -x

# fbconify by mac-l1
#
# script to disable/enable fbcon in kernel command line 
# for rockchip bootable memory cards /dev/mmcblk0 and /dev/mmcblk1 
# and for accessable parameter partition at /dev/block/mtd/by-name/parameter
#
# tested for firefly, use at your own risk as raw disk access is done
#
# cheers! mac-l1

# parse args
AUTO=""; if [ $(echo $@|grep -w "auto"|wc -l) != "0" ]; then AUTO=auto; fi

# make sure rkcrc is available
if ! [ -x rkcrc ]; then
  if ! [ -x "$(command -v gcc)" ]; then
    sudo apt-get install gcc
  fi
  if ! [ -x "$(command -v wget)" ]; then
    sudo apt-get install wget
  fi

  rm -rf rkcrc.* rkflashtool.* version.*
  wget https://github.com/linux-rockchip/rkflashtool/raw/master/rkcrc.c
  wget https://github.com/linux-rockchip/rkflashtool/raw/master/rkcrc.h
  wget https://github.com/linux-rockchip/rkflashtool/raw/master/rkflashtool.h
  wget https://github.com/linux-rockchip/rkflashtool/raw/master/version.h

  gcc -o rkcrc rkcrc.c -O2 -W -Wall
fi

fbconify() {
DISK=$1
DISKNAME=`echo $DISK|sed 's/\//_/g'`
PARIMG_OLD=parameter"${DISKNAME}".old.img
PARIMG_TMP=parameter"${DISKNAME}".tmp.img
PARTXT=parameter"${DISKNAME}"
PARIMG_NEW=parameter"${DISKNAME}".new.img

# check if device exists
if ! [ -e $DISK ]; then
  printf "%s\n" "device ${DISK} doesnt exist; cant fbconify"
  return
fi

if [ "$AUTO" = "auto" ]; then 
  echo fbconifying $DISK ...
else
  # ask to proceed
  echo -n fbconify $DISK
  read -p ' ? (Y/N) ' -n 1 -r
  echo    # (optional) move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    echo fbconifying $DISK ...
  else 
    return
  fi
fi

rm -rf $PARIMG_OLD $PARIMG_NEW $PARIMG_TMP $PARTXT

# check for SD card
if [ `echo $DISK|grep mmcblk|wc -l` == "0" ]; then
  SEEK=0 # no SD card so assume normal parameter partition
else
  SEEK=$((0x2000)) # SD card has fixed offset of 0x2000 times 512 bytes
fi

# get first sector
sudo dd conv=sync,fsync if=$DISK of=$PARIMG_TMP skip=$SEEK count=1 #bs=512

# validate for parameter.img
if [ `dd if=$PARIMG_TMP count=4 bs=1` != "PARM" ]; then
  printf "%s\n" "device ${DISK} doesnt have a valid parameter img; cant fbconify" 
  return
fi

# backup parameter.img
echo "backup original parameter.img ... "
echo 'ibase=16; '`xxd -u -ps -l 2 -s 4 $PARIMG_TMP |sed 's/\(..\)\(..\)/\2\1/'` | sed 's/$/+12/' | bc | xargs -I {} sudo dd conv=sync,fsync conv=sync,fsync bs=1 skip=`expr $SEEK \* 512` count={} if=$DISK of=$PARIMG_OLD
rm -rf $PARIMG_TMP
echo "done"

echo -n "add fbcon to parameter text file ... "
# strip header (8 bytes) and crc (last 4 bytes)
echo 'ibase=16; '`xxd -u -ps -l 2 -s 4 $PARIMG_OLD |sed 's/\(..\)\(..\)/\2\1/'` | bc | xargs -I {} dd status=none bs=1 skip=8 count={} if=$PARIMG_OLD of=$PARTXT

# if fbcon is not yet specified
if [ `grep "fbcon" $PARTXT | wc -l` == "0" ]; then
  # then add fbcon to disable framebuffer console
  sed -i 's/CMDLINE:/CMDLINE:fbcon=vc:64-63 /g' $PARTXT
  echo "done"
else
  if [ "$AUTO" != "auto" ]; then 
    echo
    echo -n "fbcon was already added! remove it"
    read -p ' ? (Y/N) ' -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
      sed -i 's/fbcon=vc:64-63 //g' $PARTXT
      echo done
    else
      echo not done
      return
    fi
  fi
fi

echo -n "generate new parameter img file ..."
./rkcrc -p  $PARTXT $PARIMG_NEW
echo "done"

if [ "$AUTO" = "auto" ]; then 
  echo copy to $DISK ...
else
  echo -n copy fbconified parameter img file to $DISK
  read -p ' ? (Y/N) ' -n 1 -r
  echo    # (optional) move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    echo copy to $DISK ...
  else
    return
  fi
fi

sudo dd conv=sync,fsync of=$DISK if=$PARIMG_NEW seek=$SEEK #bs=512
echo done

return
}

fbconify /dev/mmcblk0 # probably internal flash mem/ SD card
fbconify /dev/mmcblk1 # most likely external SD card
fbconify /dev/block/mtd/by-name/parameter # most likely internal nand flash

exit
