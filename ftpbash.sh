#!/bin/bash

# ==========================================
# FTP User Setup Script for /var/www/html
# ==========================================

# 1. CHECK FOR ROOT
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root."
   exit 1
fi

# 2. INPUT VARIABLES
if [ -z "$1" ]; then
    read -p "Enter the new FTP username: " FTP_USER
else
    FTP_USER=$1
fi

if [ -z "$2" ]; then
    read -s -p "Enter the FTP password: " FTP_PASS
    echo
else
    FTP_PASS=$2
fi

TARGET_DIR="/var/www/html"

echo "--------------------------------------------------"
echo "Setting up user '$FTP_USER' for directory '$TARGET_DIR'"
echo "--------------------------------------------------"

# 3. INSTALL VSFTPD (If not installed)
if ! command -v vsftpd &> /dev/null; then
    echo "[*] Installing vsftpd..."
    apt-get update
    apt-get install vsftpd -y
else
    echo "[*] vsftpd is already installed."
fi

# 4. CONFIGURE VSFTPD
CONFIG_FILE="/etc/vsftpd.conf"
echo "[*] Configuring $CONFIG_FILE..."

# Backup original config
cp $CONFIG_FILE "$CONFIG_FILE.bak.$(date +%F_%T)"

# Helper function to uncomment or append config lines
set_config() {
    local key="$1"
    local value="$2"
    if grep -q "^$key" "$CONFIG_FILE"; then
        sed -i "s/^$key=.*/$key=$value/" "$CONFIG_FILE"
    elif grep -q "^#$key" "$CONFIG_FILE"; then
        sed -i "s/^#$key=.*/$key=$value/" "$CONFIG_FILE"
    else
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
}

# Apply necessary settings
set_config "anonymous_enable" "NO"
set_config "local_enable" "YES"
set_config "write_enable" "YES"
set_config "chroot_local_user" "YES"
# Set umask to 002 so created files are 775 (group writable)
set_config "local_umask" "002" 

# Fix for writable chroot root error
if ! grep -q "allow_writeable_chroot=YES" "$CONFIG_FILE"; then
    echo "allow_writeable_chroot=YES" >> "$CONFIG_FILE"
fi

# 5. CREATE OR UPDATE USER
if id "$FTP_USER" &>/dev/null; then
    echo "[*] User $FTP_USER already exists. Modifying..."
    usermod -d "$TARGET_DIR" -aG www-data "$FTP_USER"
else
    echo "[*] Creating user $FTP_USER..."
    # -d: Home dir, -s: Shell (bash), -G: Secondary group
    useradd -d "$TARGET_DIR" -s /bin/bash -G www-data "$FTP_USER"
fi

# Set password
echo "$FTP_USER:$FTP_PASS" | chpasswd
echo "[*] Password set for $FTP_USER."

# 6. FIX PERMISSIONS (The Critical Part)
echo "[*] Applying permissions to $TARGET_DIR..."

# Ensure the directory exists
mkdir -p "$TARGET_DIR"

# 1. Change ownership: 
# User is Owner (allows chmod), Group is www-data (allows web server access)
chown -R "$FTP_USER:www-data" "$TARGET_DIR"

# 2. Set directory permissions to 775 (rwxrwxr-x)
# User: RWX, Group: RWX, Others: RX
chmod -R 775 "$TARGET_DIR"

# 3. Set the SGID (Set Group ID) bit
# This ensures any NEW file created inherits the 'www-data' group
# rather than the user's primary group.
chmod g+s "$TARGET_DIR"
find "$TARGET_DIR" -type d -exec chmod g+s {} +

echo "[*] Permissions set: Owner=$FTP_USER, Group=www-data, Mode=775 + SGID"

# 7. RESTART SERVICE
echo "[*] Restarting vsftpd service..."
systemctl restart vsftpd

echo "--------------------------------------------------"
echo "Setup Complete!"
echo "User: $FTP_USER"
echo "Folder: $TARGET_DIR"
echo "Note: Files uploaded will automatically inherit group 'www-data'."
echo "--------------------------------------------------"
