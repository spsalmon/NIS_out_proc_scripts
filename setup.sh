#!/bin/bash
# Configures a permanent SMB mount for //izbkingston/towbin.data at /mnt/towbin.data
# Must be run with sudo.

# ── Constants ────────────────────────────────────────────────────────────────
SHARE="//izbkingston/towbin.data"
MOUNT_POINT="/mnt/towbin.data"
CRED_FILE="/etc/samba/credentials_towbin"
FSTAB="/etc/fstab"
FSTAB_MARKER="# towbin.data SMB mount"
WSL_CONF="/etc/wsl.conf"

# ── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
error()   { echo "[ERROR] $*" >&2; exit 1; }

# ── Require root ─────────────────────────────────────────────────────────────
require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Please use: sudo $0"
    fi
}

# ── Dependency check ─────────────────────────────────────────────────────────
check_cifs_utils() {
    if dpkg -s cifs-utils &>/dev/null; then
        success "cifs-utils is already installed."
    else
        warn "cifs-utils is not installed."
        read -rp "Install it now? [Y/n]: " yn
        yn="${yn:-Y}"
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            apt-get update -qq && apt-get install -y cifs-utils \
                || error "Failed to install cifs-utils. Please install it manually and re-run."
            success "cifs-utils installed."
        else
            error "cifs-utils is required. Aborting."
        fi
    fi
}

# ── Credential collection ────────────────────────────────────────────────────
collect_credentials() {
    echo
    echo "Please enter your university credentials for the SMB share."
    echo "These will be stored securely in $CRED_FILE (readable by root only)."
    echo

    read -rp "  Username: " SMB_USER
    if [[ -z "$SMB_USER" ]]; then
        error "Username cannot be empty."
    fi

    read -rsp "  Password: " SMB_PASS
    echo
    if [[ -z "$SMB_PASS" ]]; then
        error "Password cannot be empty."
    fi

    read -rsp "  Confirm password: " SMB_PASS2
    echo
    if [[ "$SMB_PASS" != "$SMB_PASS2" ]]; then
        error "Passwords do not match. Please re-run the script."
    fi
}

# ── Write credentials file ───────────────────────────────────────────────────
write_credentials() {
    mkdir -p "$(dirname "$CRED_FILE")"

    local tmp
    tmp=$(mktemp /etc/samba/.credentials_tmp.XXXXXX)
    chmod 600 "$tmp"

    printf 'username=%s\npassword=%s\n' "$SMB_USER" "$SMB_PASS" > "$tmp"

    mv "$tmp" "$CRED_FILE"
    chown root:root "$CRED_FILE"
    chmod 600 "$CRED_FILE"

    success "Credentials saved to $CRED_FILE (mode 0600, root only)."

    unset SMB_PASS SMB_PASS2
}

# ── Mount point ──────────────────────────────────────────────────────────────
create_mount_point() {
    if [[ -d "$MOUNT_POINT" ]]; then
        info "Mount point $MOUNT_POINT already exists."
    else
        mkdir -p "$MOUNT_POINT"
        success "Created mount point $MOUNT_POINT."
    fi
}

# ── /etc/fstab ───────────────────────────────────────────────────────────────
add_fstab_entry() {
    local uid="${SUDO_UID:-1000}"
    local gid="${SUDO_GID:-1000}"

    local fstab_line="${SHARE}  ${MOUNT_POINT}  cifs  credentials=${CRED_FILE},uid=${uid},gid=${gid},iocharset=utf8,vers=3.0,nofail,_netdev  0  0"

    if grep -qP "^\S+\s+${MOUNT_POINT}\s+" "$FSTAB"; then
        warn "An fstab entry for $MOUNT_POINT already exists. Skipping."
        warn "If you need to update it, edit $FSTAB manually."
        return
    fi

    local backup="${FSTAB}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$FSTAB" "$backup"
    info "Backed up $FSTAB to $backup."

    printf '\n%s\n%s\n' "$FSTAB_MARKER" "$fstab_line" >> "$FSTAB"
    success "Added fstab entry (uid=$uid, gid=$gid)."
}

# ── /etc/wsl.conf ────────────────────────────────────────────────────────────
configure_wsl_conf() {
    if grep -q '^\[boot\]' "$WSL_CONF" 2>/dev/null; then
        if grep -q 'mount -a' "$WSL_CONF" 2>/dev/null; then
            info "$WSL_CONF already has 'mount -a' in [boot]. No changes needed."
        else
            warn "[boot] section exists in $WSL_CONF but has no 'mount -a'."
            warn "Please add the following line under [boot] manually:"
            warn "  command = mount -a"
        fi
    else
        cat >> "$WSL_CONF" <<'EOF'

[boot]
# Auto-mount fstab entries (including SMB shares) when WSL starts
command = mount -a
EOF
        success "Added [boot] command to $WSL_CONF so the share mounts on WSL start."
    fi
}

# ── Test mount ───────────────────────────────────────────────────────────────
test_mount() {
    echo
    info "Attempting to mount $SHARE now..."
    if mount "$MOUNT_POINT" 2>&1; then
        success "Share mounted successfully at $MOUNT_POINT."
        echo
        info "Contents of $MOUNT_POINT:"
        ls "$MOUNT_POINT" || true
    else
        warn "Mount attempt failed. This can happen if:"
        warn "  - The university network / VPN is not active"
        warn "  - The credentials are incorrect"
        warn "  - The server is temporarily unreachable"
        warn "The fstab entry is still in place; the share will mount automatically"
        warn "on the next WSL start (once the network is available)."
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo "=================================================="
    echo "  SMB Mount Setup — towbin.data"
    echo "=================================================="

    require_root
    check_cifs_utils
    collect_credentials
    write_credentials
    create_mount_point
    add_fstab_entry
    configure_wsl_conf
    test_mount

    echo
    echo "=================================================="
    success "Setup complete!"
    echo
    echo "  Share:       $SHARE"
    echo "  Mount point: $MOUNT_POINT"
    echo "  Credentials: $CRED_FILE (root-only)"
    echo
    echo "  To update credentials, just run this script again with sudo."
    echo "=================================================="
}

main "$@"