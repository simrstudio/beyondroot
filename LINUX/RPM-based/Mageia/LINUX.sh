#!/bin/bash

# Contact: Matti Kosola <matti.kosola@jollamobile.com>
#
#
# Copyright (c) 2019, Jolla Ltd.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
# * Neither the name of the <organization> nor the
# names of its contributors may be used to endorse or promote products
# derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -e

function check_fastboot {
  FASTBOOT_BIN_NAME=$1
  if [ -f "$FASTBOOT_BIN_NAME" ]; then
    chmod 755 $FASTBOOT_BIN_NAME
    # Ensure that the binary that is found can be executed fine
    if ./$FASTBOOT_BIN_NAME help &>/dev/null; then
      FASTBOOT_BIN_PATH="./"
      return 0
    fi
  fi
  return 1
}

UNAME=$(uname)

OS_VERSION=

case $UNAME in
  Linux)
    echo "Detected Linux"
    ;;
  *)
    echo "Failed to detect operating system!"
    exit 1
    ;;
esac

FASTBOOT_BIN_PATH=
FASTBOOT_BIN_NAME=

if ! check_fastboot "fastboot-$UNAME-$OS_VERSION" ; then
  if ! check_fastboot "fastboot-$UNAME"; then
    # In case we didn't provide functional fastboot binary to the system
    # lets check that one is found from the system.
    if ! which fastboot &>/dev/null; then
      echo "No 'fastboot' found in \$PATH. To install fastboot, use:"
      echo "    Debian/Ubuntu/ALT: sudo apt-get install android-tools-fastboot"
      echo "    Fedora/Redhat/CentOS:  yum install android-tools"
      echo "	Mageia/OpenMandriva/:  urpmi android-tools"
      echo "	Arch:  pacman -Syu android-tools"
      echo ""
      exit 1
    else
      FASTBOOT_BIN_NAME=fastboot
    fi
  fi
fi

echo "Searching device to flash.."
IFS=$'\n'
FASTBOOTCMD_NO_DEVICE="${FASTBOOT_BIN_PATH}${FASTBOOT_BIN_NAME}"

FASTBOOT_DEVICES=$($FASTBOOTCMD_NO_DEVICE devices |cut -d$'\t' -f1)

if [ -z "$FASTBOOT_DEVICES" ]; then
  echo "No device that can be flashed found. Please connect your device in fastboot mode before running this script."
  exit 1
fi

SERIALNUMBERS=
count=0
for SERIALNO in $FASTBOOT_DEVICES; do
  PRODUCT=$($FASTBOOTCMD_NO_DEVICE -s $SERIALNO getvar product 2>&1 | head -n1 | cut -d ' ' -f2)

  if [ ! -z "$(echo $PRODUCT | grep -e "H4113" -e "H4133")" ]; then
    SERIALNUMBERS="$SERIALNO $SERIALNUMBERS"
    ((++count))
  fi
done
IFS=" "

echo "Found $count devices: $SERIALNUMBERS"

if [ $count -ne 1 ]; then
  echo "Incorrect number of devices connected. Make sure there is exactly one device connected in fastboot mode."
  exit 1
fi

TARGET_SERIALNO=$SERIALNUMBERS

FASTBOOTCMD="${FASTBOOT_BIN_PATH}${FASTBOOT_BIN_NAME} -s $TARGET_SERIALNO $FASTBOOTEXTRAOPTS"

echo "Fastboot command: $FASTBOOTCMD"

ANDROIDVERSION=$($FASTBOOTCMD getvar version-baseband 2>&1 | head -n1)

FIRMWAREVERSION=$(echo $ANDROIDVERSION | cut -d ' ' -f2 | cut -d '_' -f2)

echo "Your device firmware version identifier is $FIRMWAREVERSION"

if [ "$($FASTBOOTCMD getvar secure 2>&1 | head -n1 | cut -d ' ' -f2 )" == "yes" ]; then
  echo; echo "This device has not been unlocked, but you need that for flashing."
  echo "Please go to https://developer.sony.com/develop/open-devices/get-started/unlock-bootloader/ and see instructions how to unlock your device."
  echo;
  exit 1;
fi

if [ -z ${BINARY_PATH} ]; then
  BINARY_PATH=./
fi

if [ -z ${SAILFISH_IMAGE_PATH} ]; then
  SAILFISH_IMAGE_PATH=./
fi

IMAGES=(
"boot_a ${SAILFISH_IMAGE_PATH}hybris-boot.img"
"boot_b ${SAILFISH_IMAGE_PATH}hybris-boot.img"
"userdata ${SAILFISH_IMAGE_PATH}sailfish.img001"
"system_b ${SAILFISH_IMAGE_PATH}fimage.img001"
"vendor_a ${SAILFISH_IMAGE_PATH}vendor.img001"
"vendor_b ${SAILFISH_IMAGE_PATH}vendor.img001"
)

if [ "$UNAME" = "Darwin" ]; then
  # macOS doesn't have md5sum so lets use md5 there.
  while read -r line; do
    md5=$(echo $line | awk '{ print $1 }')
    filename=$(echo $line | awk '{ print $2 }')
    md5calc=$(md5 $filename | cut -d '=' -f2 | tr -d '[:space:]')
    if [ "$md5" != "$md5calc" ]; then
      echo; echo "md5 sum does not match on file: $filename ($md5 vs $md5calc). Please re-download the package again."
      echo;
      exit 1;
    fi
  done < md5.lst
else
  if [ "$(md5sum -c md5.lst --status;echo $?)" -eq "1" ]; then
    echo; echo "md5sum does not match, please download the package again."
    echo;
    exit 1;
  fi
fi

FLASHCMD="$FASTBOOTCMD flash"

for IMAGE in "${IMAGES[@]}"; do
  read partition ifile <<< $IMAGE
  if [ ! -e ${ifile} ]; then
    echo "Image binary missing: ${ifile}."
    exit 1
  fi
done

if [ -z ${BLOB_BIN_PATH} ]; then
  BLOB_BIN_PATH=./
fi

BLOBS=""
for b in $(ls -1 ${BLOB_BIN_PATH}/*_{v16,v17}_nile.img 2>/dev/null); do
  if [ -n "$BLOBS" ]; then
   echo; echo More than one supported Sony Vendor image was found in this directory.
   echo Please remove any additional files.
   echo
   exit 1
  fi
  BLOBS=$b
done

if [ -z $BLOBS ]; then
  echo; echo "The supported Sony Vendor partition image wasn't found in the current directory."
  echo Please download it from
  echo https://developer.sony.com/develop/open-devices/downloads/software-binaries/
  echo Ensure you download the supported version of the image found under:
  echo '"Software binaries for AOSP Oreo (Android 8.1) - Kernel 4.4 - Nile"'
  echo and unzip it into this directory.
  echo Note: information on which versions are supported is written in our Sailfish X
  echo installation instructions online https://jolla.com/sailfishxinstall
  echo
  exit 1
fi

for IMAGE in "${IMAGES[@]}"; do
  read partition ifile <<< $IMAGE
  echo "Flashing $partition partition.."
  $FLASHCMD $partition $ifile
done

echo "Flashing oem partition.."
$FLASHCMD oem_a $BLOBS

echo
echo "Flashing completed."
echo
echo "Remove the USB cable and bootup the device by pressing powerkey."
echo
