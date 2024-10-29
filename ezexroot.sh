#!/bin/sh

# تعریف رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # بدون رنگ

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

# پیام شروع
echo -e "${CYAN}Running as root...${NC}"
sleep 2
clear

# متغیر گزارش برای ذخیره نتایج هر مرحله
RESULT_LOG="Script Results:\n"
OVERALL_RESULT=""
FAILURE=0

# تابع بررسی موفقیت هر مرحله و ثبت نتیجه
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Step $1: Completed Successfully ✅${NC}"
        return 0
    else
        echo -e "${RED}Step $1: Failed ❌${NC}"
        return 1
    fi
}

# حذف نسخه قبلی اسکریپت در صورت وجود
SCRIPT_PATH="/root/ezxroot.sh"
if [ -f "$SCRIPT_PATH" ]; then
    echo -e "${YELLOW}Found another version of ezxroot.sh. Removing old version...${NC}"
    rm -f "$SCRIPT_PATH"
fi

# مرحله 1: به‌روزرسانی لیست بسته‌ها و نصب بسته‌های لازم
echo -e "${BLUE}Updating package list and installing required packages...${NC}"
opkg update && opkg install -y kmod-usb-storage kmod-usb-storage-uas usbutils block-mount kmod-fs-ext4 e2fsprogs parted curl gdisk kmod-usb-storage-extras
RESULT_PACKAGE_INSTALL=$?
check_status "Install Packages"

# مرحله 2: شناسایی اولین دیسک USB متصل‌شده
echo -e "${BLUE}Detecting USB disk...${NC}"
DISK=$(lsblk -o NAME,TRAN | grep usb | awk '{print "/dev/"$1}' | head -n 1)
if [ -z "$DISK" ]; then
    echo -e "${RED}No USB disk detected. Please ensure the device is properly connected.${NC}"
    RESULT_USB_DETECT=1
else
    echo -e "${GREEN}USB disk detected: ${DISK}${NC}"
    RESULT_USB_DETECT=0
fi

# مرحله 3: ایجاد پارتیشن GPT و استفاده از کل فضای دیسک برای extroot
if [ $RESULT_USB_DETECT -eq 0 ]; then
    echo -e "${BLUE}Creating GPT partition and formatting for extroot...${NC}"
    parted -s ${DISK} mklabel gpt mkpart primary ext4 0% 100% && mkfs.ext4 -L extroot ${DISK}1
    RESULT_PARTITION=$?
    check_status "Create and Format Partition"
else
    RESULT_PARTITION=1
fi

# مرحله 4: تنظیمات extroot در fstab
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

# مرحله 5: کپی کردن فایل‌های overlay به USB
if [ $RESULT_FSTAB_CONFIG -eq 0 ]; then
    echo -e "${BLUE}Copying overlay files to USB...${NC}"
    mount ${DISK}1 /mnt && tar -C ${MOUNT} -cvf - . | tar -C /mnt -xf -
    RESULT_COPY_OVERLAY=$?
    check_status "Copy Overlay to USB"
else
    RESULT_COPY_OVERLAY=1
fi

# مرحله 6: تنظیمات fstab برای پیکربندی root mount writable
if [ $RESULT_COPY_OVERLAY -eq 0 ]; then
    echo -e "${MAGENTA}Configuring writable mount in fstab...${NC}"
    DEVICE=$(block info | grep -o -e '/dev/\S*' | grep -E "${DISK}1" -A 1 | tail -n 1)
    uci -q delete fstab.rwm && uci set fstab.rwm="mount" && uci set fstab.rwm.device="${DEVICE}" && uci set fstab.rwm.target="/rwm" && uci commit fstab
    RESULT_RW_CONFIG=$?
    check_status "Configure writable mount in fstab"
else
    RESULT_RW_CONFIG=1
fi

# نمایش نتایج مراحل به تفکیک در انتها
clear
echo -e "${CYAN}Script Results:${NC}"

# بررسی وضعیت نهایی و راه‌اندازی مجدد سیستم
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

# بررسی وضعیت نهایی و راه‌اندازی مجدد سیستم
if [ $RESULT_PACKAGE_INSTALL -eq 0 ] && [ $RESULT_USB_DETECT -eq 0 ] && [ $RESULT_PARTITION -eq 0 ] && [ $RESULT_FSTAB_CONFIG -eq 0 ] && [ $RESULT_COPY_OVERLAY -eq 0 ] && [ $RESULT_RW_CONFIG -eq 0 ]; then
    echo -e "${CYAN}All steps completed successfully. Rebooting...${NC}"
    # reboot
else
    echo -e "${RED}Some steps failed. Please check the configurations.${NC}"
fi
