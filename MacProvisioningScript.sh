#!/bin/bash

if [[ $UID -ne 0 ]]; then
	echo "This script needs to be run as root (with sudo)"
	exit 1
fi

echo "[I] Beginning local provisioning now"

read -p "[!] Enter a name for this device: " DEVNAME
systemsetup -setcomputername "$DEVNAME"
scutil --set HostName "$DEVNAME"
echo "[I] Creating a standard user account"
CONFIRM="n"
while [ "$CONFIRM" != "y" ] ; do
	echo "[!] Enter username to create (e.g. jsmith):"
	read -p "Username: " USERNAME
	echo "[!] Enter user's full name (e.g. John Smith):"
	read -p "Real Name: " REALNAME
	echo "[!] Please provide an initial log-in password"
	read -p "Password: " PASS
	echo "[!] Please provide a disk encryption password"
	echo "[ ] This could include a second-factor password entry token component"
	read -p "Disk Password: " DISKPASS
	echo " "
	echo "[?] Are the following details correct?"
	echo "	Username:		$USERNAME"
	echo "	Real Name:		$REALNAME"
	echo "	Password:		$PASS"
	echo "	Disk Password:	$DISKPASS"
	read -p "[y/n]: " CONFIRM
done

echo "[I] Creating user $USERNAME"

MAXID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -ug | tail -1)
USERID=$((MAXID+1))
DISKID=$((MAXID+2))

dscl . -create /Users/$USERNAME
dscl . -create /Users/$USERNAME RealName "$REALNAME"
dscl . -passwd /Users/$USERNAME $PASS
dscl . -create /Users/$USERNAME UserShell /bin/bash
dscl . -create /Users/$USERNAME NFSHomeDirectory /Users/$USERNAME
dscl . -create /Users/$USERNAME PrimaryGroupID 20
dscl . -create /Users/$USERNAME UniqueID "$USERID"

cp -R /System/Library/User\ Template/English.lproj /Users/$USERNAME
chown -R $USERNAME:staff /Users/$USERNAME
chmod go-rx /Users/$USERNAME

echo "[I] Enabling FileVault2 full disk encryption"
dscl . -create /Users/filevault
dscl . -create /Users/filevault RealName "Disk Encryption Password"
dscl . -passwd /Users/filevault $DISKPASS
dscl . -create /Users/filevault UserShell /usr/bin/false
dscl . -create /Users/filevault UniqueID "$DISKID"

# Add user to filevault user list
defaults write com.apple.loginwindow HiddenUsersList -array-add filevault
# show new user in filevault login screen
defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -int 1
DISKPASS=$DISKPASS expect -c 'spawn /usr/bin/fdesetup enable -user filevault; expect ":"; send "$env(DISKPASS)\n"; expect eof'
pmset destroyfvkeyonstandby 1 hibernatemode 25

echo "[I] Disabling IPv6"
networksetup -setv6off Wi-Fi >/dev/null
networksetup -setv6off Ethernet >/dev/null

echo "[I] Disabling infrared receiver"
defaults write com.apple.driver.AppleIRController DeviceEnabled -bool FALSE

echo "[I] Enabling scheduled updates"
softwareupdate --schedule on

echo "[I] Disabling password hints on lock screen"
defaults write com.apple.loginwindow RetriesUntilHint -int 0

echo "[I] Enabling password-protected screen lock after 5 minutes"
systemsetup -setdisplaysleep 5
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

echo "[I] Enabling firewall"
/usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode on
/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned on
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

echo "[I] Launching firmware password utility (this may take a moment)"
diskutil mount Recovery\ HD
RECOVERY=$(hdiutil attach /Volumes/Recovery\ HD/com.apple.recovery.boot/BaseSystem.dmg | grep -i Base | cut -f 3)
open "$RECOVERY/Applications/Utilities/Firmware Password Utility.app"
echo "[!] Follow the prompts on the utility to set a strong unique firmware password"
echo "[!] Press enter when done"
read DONE
