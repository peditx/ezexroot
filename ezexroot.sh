#!/bin/sh

# Define colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No color

##Scanning
. /etc/openwrt_release

echo -e "${MAGENTA} 
_______           _______  __   __     __    __            __          
|       \         |       \|  \ |  \   |  \  |  \          |  \         
| ▓▓▓▓▓▓▓\ ______ | ▓▓▓▓▓▓▓\\▓▓_| ▓▓_  | ▓▓  | ▓▓ ______  _| ▓▓_        
| ▓▓__/ ▓▓/      \| ▓▓  | ▓▓  \   ▓▓ \  \▓▓\/  ▓▓/      \|   ▓▓ \       
| ▓▓    ▓▓  ▓▓▓▓▓▓\ ▓▓  | ▓▓ ▓▓\▓▓▓▓▓▓   >▓▓  ▓▓|  ▓▓▓▓▓▓\\▓▓▓▓▓▓       
| ▓▓▓▓▓▓▓| ▓▓    ▓▓ ▓▓  | ▓▓ ▓▓ | ▓▓ __ /  ▓▓▓▓\| ▓▓   \▓▓ | ▓▓ __      
| ▓▓     | ▓▓▓▓▓▓▓▓ ▓▓__/ ▓▓ ▓▓ | ▓▓|  \  ▓▓ \▓▓\ ▓▓       | ▓▓|  \     
| ▓▓      \▓▓     \ ▓▓    ▓▓ ▓▓  \▓▓  ▓▓ ▓▓  | ▓▓ ▓▓        \▓▓  ▓▓     
 \▓▓       \▓▓▓▓▓▓▓\▓▓▓▓▓▓▓ \▓▓   \▓▓▓▓ \▓▓   \▓▓\▓▓         \▓▓▓▓      
                                      
                                                    E  X  R  O  O  T ${NC}"
EPOL=`cat /tmp/sysinfo/model`
echo " - Model : $EPOL"
echo " - System Ver : $DISTRIB_RELEASE"
echo " - System Arch : $DISTRIB_ARCH"

# Starting message
echo -e "${CYAN}Running as root...${NC}"
sleep 2
clear

# Variable to log results of each step
RESULT_LOG="Script Results:\n"
OVERALL_RESULT=""
FAILURE=0

# Function to check the success of each step and log the result
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Step $1: Completed Successfully ✅${NC}"
        return 0
    else
        echo -e "${RED}Step $1: Failed ❌${NC}"
        return 1
    fi
}

# Remove previous version of the script if it exists
SCRIPT_PATH="/root/ezxroot.sh"
if [ -f "$SCRIPT_PATH" ]; then
    echo -e "${YELLOW}Found another version of ezxroot.sh. Removing old version...${NC}"
    rm -f "$SCRIPT_PATH"
fi

# Step 1: Update package list and install required packages
echo -e "${BLUE}Updating package list and installing required packages...${NC}"
opkg update && opkg install -y kmod-usb-storage kmod-usb-storage-uas usbutils block-mount kmod-fs-ext4 e2fsprogs parted curl gdisk kmod-usb-storage-extras
RESULT_PACKAGE_INSTALL=$?
check_status "Install Packages"

# Step 2: Detect the first connected USB disk
echo -e "${BLUE}Detecting USB disk...${NC}"
DISK=$(lsblk -o NAME,TRAN | grep usb | awk '{print "/dev/"$1}' | head -n 1)
if [ -z "$DISK" ]; then
    echo -e "${RED}No USB disk detected. Please ensure the device is properly connected.${NC}"
    RESULT_USB_DETECT=1
else
    echo -e "${GREEN}USB disk detected: ${DISK}${NC}"
    RESULT_USB_DETECT=0
fi

# Step 3: Create GPT partition and use full disk space for extroot
if [ $RESULT_USB_DETECT -eq 0 ]; then
    echo -e "${BLUE}Creating GPT partition and formatting for extroot...${NC}"
    parted -s ${DISK} mklabel gpt mkpart primary ext4 0% 100% && mkfs.ext4 -L extroot ${DISK}1
    RESULT_PARTITION=$?
    check_status "Create and Format Partition"
else
    RESULT_PARTITION=1
fi

# Step 4: Configure extroot in fstab
if [ $RESULT_PARTITION -eq 0 ]; then
    echo -e "${MAGENTA}Configuring extroot in fstab...${NC}"
    UUID=$(blkid -s UUID -o value ${DISK}1)
    MOUNT=$(block info | grep -o -e 'MOUNT="\S*/overlay"')
    uci -q delete fstab.extroot && uci set fstab.extroot="mount" && uci set fstab.extroot.uuid="${UUID}" && uci set fstab.extroot.target="${MOUNT}" && uci commit fstab
    RESULT_FSTAB_CONFIG=$?
    check_status "Configure extroot in fstab"
else
    RESULT_FSTAB_CONFIG=1
fi

# Step 5: Copy overlay files to USB
if [ $RESULT_FSTAB_CONFIG -eq 0 ]; then
    echo -e "${BLUE}Copying overlay files to USB...${NC}"
    mount ${DISK}1 /mnt && tar -C ${MOUNT} -cvf - . | tar -C /mnt -xf -
    RESULT_COPY_OVERLAY=$?
    check_status "Copy Overlay to USB"
else
    RESULT_COPY_OVERLAY=1
fi

# Step 6: Configure fstab for writable root mount
if [ $RESULT_COPY_OVERLAY -eq 0 ]; then
    echo -e "${MAGENTA}Configuring writable mount in fstab...${NC}"
    DEVICE=$(block info | grep -o -e '/dev/\S*' | grep -E "${DISK}1" -A 1 | tail -n 1)
    uci -q delete fstab.rwm && uci set fstab.rwm="mount" && uci set fstab.rwm.device="${DEVICE}" && uci set fstab.rwm.target="/rwm" && uci commit fstab
    RESULT_RW_CONFIG=$?
    check_status "Configure writable mount in fstab"
else
    RESULT_RW_CONFIG=1
fi

# Display results of each step separately at the end
clear
echo -e "${CYAN}Script Results:${NC}"

# Check final status and reboot
if [ $RESULT_PACKAGE_INSTALL -eq 0 ]; then
    echo -e "${GREEN}Packages installed successfully ✅${NC}"
else
    echo -e "${RED}Package installation failed ❌${NC}"
fi

if [ $RESULT_USB_DETECT -eq 0 ]; then
    echo -e "${GREEN}USB detected successfully ✅${NC}"
else
    echo -e "${RED}USB detection failed ❌${NC}"
fi

if [ $RESULT_PARTITION -eq 0 ]; then
    echo -e "${GREEN}Partition created and formatted successfully ✅${NC}"
else
    echo -e "${RED}Partition creation failed ❌${NC}"
fi

if [ $RESULT_FSTAB_CONFIG -eq 0 ]; then
    echo -e "${GREEN}Extroot configured in fstab successfully ✅${NC}"
else
    echo -e "${RED}Extroot configuration in fstab failed ❌${NC}"
fi

if [ $RESULT_COPY_OVERLAY -eq 0 ]; then
    echo -e "${GREEN}Overlay files copied successfully ✅${NC}"
else
    echo -e "${RED}Overlay file copy failed ❌${NC}"
fi

if [ $RESULT_RW_CONFIG -eq 0 ]; then
    echo -e "${GREEN}Writable mount configured in fstab successfully ✅${NC}"
else
    echo -e "${RED}Writable mount configuration failed ❌${NC}"
fi

# Check overall status before rebooting
if [ $RESULT_PACKAGE_INSTALL -eq 0 ] && [ $RESULT_USB_DETECT -eq 0 ] && [ $RESULT_PARTITION -eq 0 ] && [ $RESULT_FSTAB_CONFIG -eq 0 ] && [ $RESULT_COPY_OVERLAY -eq 0 ] && [ $RESULT_RW_CONFIG -eq 0 ]; then
    echo -e "${CYAN}All steps completed successfully. Rebooting...${NC}"
    # reboot
else
    echo -e "${RED}Some steps failed. Please check the configurations.${NC}"
fi
