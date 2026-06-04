#!/bin/bash
# Configures a permanent SMB mount for //izbkingston/towbin.data at /mnt/towbin.data
# using systemd automount, so the share mounts on first access and the WSL
# startup "mount -a failed" race condition is avoided.
# Must be run with sudo.

# ── Constants ────────────────────────────────────────────────────────────────
SHARE="//izbkingston/towbin.data"
MOUNT_POINT="/mnt/towbin.data"
CRED_FILE="/etc/samba/credentials_towbin"
FSTAB="/etc/fstab"
FSTAB_MARKER="# towbin.data SMB mount (systemd automount)"
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

    # Key options:
    #   noauto              -> WSL's startup "mount -a" skips this line (fixes the race)
    #   x-systemd.automount -> systemd creates an automount unit; the share is mounted
    #                          on first access (e.g. `ls /mnt/towbin.data`)
    #   x-systemd.idle-timeout=600  -> unmount after 10 min idle (saves resources / handles
    #                                  network drops gracefully; share remounts on next access)
    #   x-systemd.mount-timeout=30  -> give the actual mount up to 30s to complete
    #   _netdev,nofail      -> belt-and-braces; treat as network device, don't fail boot
    local opts="credentials=${CRED_FILE},uid=${uid},gid=${gid},iocharset=utf8,vers=3.0,nofail,_netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=30"
    local fstab_line="${SHARE}  ${MOUNT_POINT}  cifs  ${opts}  0  0"

    if grep -qP "^\S+\s+${MOUNT_POINT}\s+" "$FSTAB"; then
        # An entry exists — check whether it's already the systemd-automount version
        if grep -P "^\S+\s+${MOUNT_POINT}\s+" "$FSTAB" | grep -q 'x-systemd.automount'; then
            info "fstab entry for $MOUNT_POINT already uses systemd automount. No changes."
            return
        fi

        warn "An older fstab entry for $MOUNT_POINT exists without systemd automount."
        warn "This is the likely cause of the 'mount -a failed' message at WSL startup."
        read -rp "Replace it with the improved entry? [Y/n]: " yn
        yn="${yn:-Y}"
        if [[ ! "$yn" =~ ^[Yy]$ ]]; then
            warn "Keeping existing entry. You can edit $FSTAB manually."
            return
        fi

        local backup="${FSTAB}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$FSTAB" "$backup"
        info "Backed up $FSTAB to $backup."

        # Remove the old mount line (use | as sed delimiter since path contains /)
        sed -i -E "\|^[^[:space:]]+[[:space:]]+${MOUNT_POINT}[[:space:]]+|d" "$FSTAB"
        # Also remove the stale marker comment from the original script, if present
        sed -i "\|^# towbin.data SMB mount$|d" "$FSTAB"
        sed -i "\|^${FSTAB_MARKER}$|d" "$FSTAB"

        printf '\n%s\n%s\n' "$FSTAB_MARKER" "$fstab_line" >> "$FSTAB"
        success "Replaced fstab entry with systemd automount version (uid=$uid, gid=$gid)."
        return
    fi

    local backup="${FSTAB}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$FSTAB" "$backup"
    info "Backed up $FSTAB to $backup."

    printf '\n%s\n%s\n' "$FSTAB_MARKER" "$fstab_line" >> "$FSTAB"
    success "Added fstab entry (uid=$uid, gid=$gid)."
}

# ── /etc/wsl.conf ────────────────────────────────────────────────────────────
# We need systemd enabled for x-systemd.automount to work.
configure_wsl_conf() {
    SYSTEMD_NEWLY_ENABLED=0

    touch "$WSL_CONF"

    if grep -qE '^\s*systemd\s*=\s*true' "$WSL_CONF"; then
        info "systemd is already enabled in $WSL_CONF."
    elif grep -q '^\[boot\]' "$WSL_CONF"; then
        if grep -qE '^\s*systemd\s*=' "$WSL_CONF"; then
            # Existing systemd= line set to something other than true — flip it
            sed -i -E 's/^\s*systemd\s*=.*/systemd = true/' "$WSL_CONF"
            success "Set 'systemd = true' in existing [boot] section of $WSL_CONF."
        else
            # [boot] exists but no systemd line — insert one right after the header
            sed -i '/^\[boot\]/a systemd = true' "$WSL_CONF"
            success "Added 'systemd = true' under [boot] in $WSL_CONF."
        fi
        SYSTEMD_NEWLY_ENABLED=1
    else
        cat >> "$WSL_CONF" <<'EOF'

[boot]
# Enable systemd so x-systemd.automount units (used by the towbin.data SMB
# share in /etc/fstab) work. Required for on-demand mounting that avoids
# the startup race where networking isn't ready when WSL runs `mount -a`.
systemd = true
EOF
        success "Added [boot] systemd=true to $WSL_CONF."
        SYSTEMD_NEWLY_ENABLED=1
    fi

    # Heads-up if the older 'command = mount -a' line is still there.
    if grep -q 'mount -a' "$WSL_CONF"; then
        info "Note: '$WSL_CONF' still has 'command = mount -a' from a previous run."
        info "It's now harmless (our entry is noauto), but you can remove it if you like."
    fi
}

# ── Test mount ───────────────────────────────────────────────────────────────
test_mount() {
    echo
    info "Attempting to mount $SHARE now..."

    # If systemd is already running, reload so it picks up the new fstab entry
    # and registers the automount unit immediately.
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
        systemctl daemon-reload || true
    fi

    # Explicit mount works regardless of `noauto` (noauto only affects `mount -a`).
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
        warn "  - systemd was just enabled and WSL hasn't been restarted yet"
        warn "The fstab entry is in place; after 'wsl --shutdown' (from Windows)"
        warn "and a fresh WSL start, the share will auto-mount on first access."
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo "=================================================="
    echo "  SMB Mount Setup — towbin.data (systemd automount)"
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

    if [[ "${SYSTEMD_NEWLY_ENABLED:-0}" -eq 1 ]]; then
        echo "  IMPORTANT: systemd was just enabled in $WSL_CONF."
        echo "  From a Windows PowerShell / CMD, run:"
        echo
        echo "      wsl --shutdown"
        echo
        echo "  Then re-open your WSL terminal. The startup 'mount -a failed'"
        echo "  message will be gone, and the share will mount automatically the"
        echo "  first time you access $MOUNT_POINT (e.g. 'ls $MOUNT_POINT')."
    else
        echo "  The share will mount automatically the first time you access"
        echo "  $MOUNT_POINT (e.g. 'ls $MOUNT_POINT')."
    fi
    echo
    echo "  To update credentials, just run this script again with sudo."
    echo "=================================================="
}

main "$@"