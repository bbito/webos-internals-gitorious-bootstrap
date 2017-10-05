#!/bin/sh

# preware-bootstrap.sh
# version 1.0
#
# Script to install Preware
#
# by Daniel Beames (dBsooner) and Rod Whitby (rwhitby)
#
# Features:
# 1. Mounts the root file system read-write
# 3. Checks if preware is installed and gets current version from feed. Option to reinstall/upgrade if exists.
#
# Changelog:
#
# 0.1 Initial version
# 0.2 Fixed EMULATOR not being defined.
# 0.3 Added $ARCH for Pixi.
# 0.4 Removed "Install Preware?" prompt.
# 0.5 Fixed incorrect order of remounts.
# 0.6 Moved postinst run till after preware install. Postinst of IPKGService kills data. Caused error dl'ing packages.
# 0.7 Updated to support webOS 1.3.5
# 0.8 Rewrote entire portions to fully support 1.3.5 and previous versions simultaneously. Supports two offline root dirs.
# 0.9 Fails over to production feed if user selected Y to alpha and no versions are avail. Added support for alpha Preware.
# 1.0 Updated for Preware 1.0

### VARIABLES

SCRIPTNAME="$(basename $0)"                
LOG=/tmp/${SCRIPTNAME}.log
ARCH=$(uname -m)
if [ "$ARCH" = "armv7l" ] ; then
  EMULATOR=0
  FEED_ARCH=armv7
  PACKAGE_ARCH=arm
elif [ "$ARCH" = "armv6l" ] ; then
  EMULATOR=0
  FEED_ARCH=armv6
  PACKAGE_ARCH=arm
else	
  EMULATOR=1
  FEED_ARCH=i686
  PACKAGE_ARCH=i686
fi

if grep -q /media/cryptofs/apps /etc/palm/luna.conf ; then
  APPS="/media/cryptofs/apps"
else
  APPS="/var"
fi

# Clean up any obsolete or broken lists
rm -f $APPS/usr/lib/ipkg/lists/*

### END of VARIABLES

### FUNCTIONS

# Name:        log
# Arguments:   Message
# Description: logs Message to $LOG
log() {
  echo "$@" >> $LOG
}


# Name:        yesno
# Arguments:   Question
# Description: Asks a yes/no Question, returns 1 for yes, 0 for no
yesno() {
  IN=""
  until [ -n "$IN" ] ; do
    read -p "${@} " IN
    case "$IN" in
      y|Y|yes|YES)  return 1;;
      n|N|no|NO)    return 0;;
      *)            IN="";;
    esac
  done
}


# Name:        error
# Arguments:   Message
# Description: Displays FAILED followed by Message
  error() {
  echo "FAILED"
  log "ERROR: ${@}"
  echo "$@"
  echo
  echo "Please paste the contents of ${LOG} to http://webos.pastebin.com/"
  echo "and seek help in the IRC channel #webos-internals."
  echo
  echo "To view ${LOG}, type:"
  echo
  echo "cat ${LOG}"
  echo
  echo
  return 1
}

# Name:        ipkgversion_check
# Arguments:   Package
# Description: Checks if $PKG is installed, returns 0 for not installed, 1 for current, or 2 for diff.
ipkgversion_check() {
  PKG=$1
  log "Checking $PKG version"
  cd /tmp 
  rm -f /tmp/org.webosinternals.Packages*
  wget http://ipkg.preware.net/feeds/webos-internals/${FEED_URL}/Packages.gz -O /tmp/org.webosinternals.Packages.gz >> "$LOG" 2>&1 \
    && gunzip /tmp/org.webosinternals.Packages.gz >> "$LOG" 2>&1
  PKG_VER_CURRENT=$(awk 'BEGIN { RS = ""}; /^Package: '$PKG'\n/ {print}' /tmp/org.webosinternals.Packages | awk '/^Version:/ {print $2}')
  if [ ! "$PKG_VER_CURRENT" -a "${FEED_URL}" = "testing/${FEED_ARCH}" ] ; then
    rm -f /tmp/org.webosinternals.Packages*
    FEED_URL=${FEED_ARCH}
    wget http://ipkg.preware.net/feeds/webos-internals/${FEED_URL}/Packages.gz -O /tmp/org.webosinternals.Packages.gz >> "$LOG" 2>&1 \
      && gunzip /tmp/org.webosinternals.Packages.gz >> "$LOG" 2>&1
    PKG_VER_CURRENT=$(awk 'BEGIN { RS = ""}; /^Package: '$PKG'\n/ {print}' /tmp/org.webosinternals.Packages | awk '/^Version:/ {print $2}')
  fi
  if [ -e "/var/usr/lib/ipkg/info/$PKG.control" ] ; then
    PKG_VER_INSTALLED=$(awk 'BEGIN { RS = "" }; /^Package: '$PKG'\n/ {print}' /var/usr/lib/ipkg/info/$PKG.control | awk '/^Version:/ {print $2}')
    if [ "$PKG_VER_INSTALLED" = "$PKG_VER_CURRENT" ] ; then           
      # Installed to /var and current
      RETURN="1"
    else
      # Installed to /var and not current
      RETURN="2"
    fi
  elif [ "$APPS" = "/media/cryptofs/apps" -a -e "/media/cryptofs/apps/usr/lib/ipkg/info/$PKG.control" ] ; then
    PKG_VER_INSTALLED=$(awk 'BEGIN { RS = "" }; /^Package: '$PKG'\n/ {print}' /media/cryptofs/apps/usr/lib/ipkg/info/$PKG.control | awk '/^Version:/ {print $2}')
    if [ "$PKG_VER_INSTALLED" = "$PKG_VER_CURRENT" ] ; then
      # Installed to cryptofs and not current
      RETURN="3"
    else
      # Installed to cryptofs and current
      RETURN="4"
    fi
  else
    # Not Installed
    RETURN="5"
  fi
  log "$RETURN"
  log "INSTALLED: $PKG_VER_INSTALLED"
  log "PKG_VER_CURRENT: $PKG_VER_CURRENT"
  return "$RETURN"
}

# Name:        dopreware
# Arguments:   none
# Description: Installs preware
dopreware() {
  ipkgversion_check org.webosinternals.preware
  PREWAREVERSION_RETURN="$?"
  case "$PREWAREVERSION_RETURN" in
    1) IPKG_OFFLINE_ROOT="/var" ;;
    2) IPKG_OFFLINE_ROOT="/var" ;;
    3) IPKG_OFFLINE_ROOT="/media/cryptofs/apps" ;;
    4) IPKG_OFFLINE_ROOT="/media/cryptofs/apps" ;;
    5)
if grep -q /media/cryptofs/apps /etc/palm/luna.conf ; then
  IPKG_OFFLINE_ROOT="/media/cryptofs/apps"
else
  IPKG_OFFLINE_ROOT="/var"
fi
;;
    *) error "Could not determine IPKG_OFFLINE_ROOT" || return 1 ;;
  esac
  if [ ! "$PREWAREVERSION_RETURN" -eq 5 ] ; then
    log "org.webosinternals.preware v${PKG_VER_INSTALLED} already installed"
    echo
    echo "org.webosinternals.preware v${PKG_VER_INSTALLED} already installed"
    yesno "Would you like to replace it with v${PKG_VER_CURRENT}?"
    if [ "$?" -eq 0 ] ; then
      return 0
    else
      /usr/bin/ipkg -o $IPKG_OFFLINE_ROOT remove org.webosinternals.preware >> "$LOG" 2>&1 \
        || error "Failed to remove org.webosinternals.preware" || return 1
    fi
  fi
  log "Installing org.webosinternals.preware v${PKG_VER_CURRENT}: "
  echo -n "Installing org.webosinternal.preware v${PKG_VER_CURRENT}: "
  cd /tmp || error "Failed to change directory to /tmp" || return 1
  rm -f /tmp/org.webosinternals.preware_${PKG_VER_CURRENT}_${PACKAGE_ARCH}.ipk
  wget http://ipkg.preware.org/feeds/webos-internals/${FEED_URL}/org.webosinternals.preware_${PKG_VER_CURRENT}_${PACKAGE_ARCH}.ipk >> "$LOG" 2>&1 \
    || error "Failed to download org.webosinternals.preware_${PKG_VER_CURRENT}_${PACKAGE_ARCH}.ipk" || return 1
  /usr/bin/ipkg -o $APPS install ./org.webosinternals.preware_${PKG_VER_CURRENT}_${PACKAGE_ARCH}.ipk >> "$LOG" 2>&1 \
    || error "Failed to install /tmp/org.webosinternals.preware_${PKG_VER_CURRENT}_${PACKAGE_ARCH}.ipk" || return 1
  log "OK"
  echo "OK"
}


### END FUNCTIONS

echo "Starting installation..."
# Include Testing Feed (Alpha versions)?
yesno "Would you like to include any alpha Preware releases for this install/update? [Y/N] "
if [ "$?" -eq 1 ] ; then
  FEED_URL=testing/${FEED_ARCH}
else
  FEED_URL=${FEED_ARCH}
fi

# Mount the root fs rw
if [ "$EMULATOR" = 0 ] ; then
  log "Mounting the root file system read-write: "
  echo -n "Mounting the root file system read-write: "
  mount -o rw,remount / >> "$LOG" 2>&1 || error "Failed to mount / read/write" || exit 1
  log "OK"
  echo "OK"
fi

dopreware
PREWARE_STATUS="$?"
if [ "$PREWARE_STATUS" -eq 0 ] ; then
  log "Rescanning Luna: "
  echo -n "Rescanning Luna: "
  luna-send -n 1 palm://com.palm.applicationManager/rescan {} >> "$LOG" 2>&1 || exit 1
  log "OK"
  echo "OK"
  log "Running org.webosinternals.preware.postinst: "
  echo
  echo -n "Running org.webosinternals.preware.postinst: "
  IPKG_OFFLINE_ROOT=$APPS sh $APPS/usr/lib/ipkg/info/org.webosinternals.preware.postinst >> "$LOG" 2>&1 \
  || error "Failed to run $APPS/usr/lib/ipkg/info/org.webosinternals.preware.postinst" || echo "Failed!"
  log "OK"
  echo "OK"
fi

if [ "$EMULATOR" = 0 ] ; then
  log "Mounting the root file system read-only: "
  echo
  echo -n "Mounting the root file system read-only: "
  mount -o ro,remount / >> "$LOG" 2>&1 || error "Failed to mount / read/write" || exit 1
  log "OK"
  echo "OK"
fi

log "Setup Complete!"
echo "Setup Complete!"
echo
