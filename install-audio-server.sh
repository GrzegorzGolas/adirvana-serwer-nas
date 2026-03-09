#!/usr/bin/env bash
set -Eeuo pipefail

# Audio Server bootstrap for Debian RT
# Target: Audirvana Core + Diretta renderer endpoint + SMB/NFS music storage
#
# IMPORTANT
# - Review variables below before running.
# - Run as root.
# - This script assumes Debian-based system.
# - Some steps still require manual review (GRUB, Audirvana package/source, Diretta target side).

############################################
# USER VARIABLES
############################################
HOSTNAME_NEW="audio-server"
AUDIO_USER="audirvana"
AUDIO_GROUP="audirvana"
MUSIC_MOUNT="/mnt/music"
MUSIC_LIBRARY_DIR="/mnt/music/Music"
AUDIRVANA_BIN="/opt/audirvana/studio/audirvanaStudio"
AUDIRVANA_SERVICE_NAME="audirvanaStudio.service"
NIC_IFACE="eno1"
SERVER_IP_CIDR="10.0.0.200/24"
DEFAULT_GW="10.0.0.1"
DNS1="1.1.1.1"
DNS2="8.8.8.8"

# Optional: set to 1 if you want the script to configure a static IP using systemd-networkd.
CONFIGURE_STATIC_IP=0

# Optional: set to 1 if ethtool tweaks should be persisted via systemd service.
CONFIGURE_NIC_TUNING=1

############################################
# INTERNALS
############################################
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SYSCTL_FILE="/etc/sysctl.d/99-audio-server.conf"
GRUB_FILE="/etc/default/grub"
AUDIRVANA_SERVICE_FILE="/etc/systemd/system/${AUDIRVANA_SERVICE_NAME}"
NIC_SERVICE_FILE="/etc/systemd/system/audio-nic-tuning.service"
NETWORK_FILE="/etc/systemd/network/20-${NIC_IFACE}.network"
SMB_CONF_SNIPPET="/etc/samba/smb.conf.d/audio-music.conf"
NFS_EXPORTS_FILE="/etc/exports.d/audio-music.exports"

KERNEL_CMDLINE_APPEND=(
  intel_pstate=disable
  isolcpus=2,3
  nohz_full=2,3
  rcu_nocbs=2,3
  intel_idle.max_cstate=1
  processor.max_cstate=1
  nosoftlockup
  mitigations=off
  nosmt
  noibrs
  noibpb
  spectre_v2=off
  l1tf=off
  mds=off
  tsx=on
  no_stf_barrier
  nopti
  ipv6.disable=1
)

log() { printf '\n[INFO] %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*"; }
die() { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this script as root."
}

require_debian() {
  [[ -f /etc/debian_version ]] || die "This script targets Debian-based systems only."
}

append_kernel_arg_if_missing() {
  local arg="$1"
  if ! grep -Eq "(^|[[:space:]])${arg//./\\.}($|[[:space:]])" /proc/cmdline 2>/dev/null && \
     ! grep -Eq "(^|[[:space:]])${arg//./\\.}($|[[:space:]])" "$GRUB_FILE"; then
    GRUB_CMDLINE_LINUX_DEFAULT=$(awk -F'"' '/^GRUB_CMDLINE_LINUX_DEFAULT=/{print $2}' "$GRUB_FILE")
    sed -i "s#^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"#GRUB_CMDLINE_LINUX_DEFAULT=\"${GRUB_CMDLINE_LINUX_DEFAULT} ${arg}\"#" "$GRUB_FILE"
  fi
}

install_packages() {
  log "Installing base packages"
  apt-get update
  apt-get install -y \
    ca-certificates curl wget gnupg lsb-release sudo nano vim git jq \
    avahi-daemon ethtool procps irqbalance \
    samba nfs-kernel-server \
    inotify-tools acl \
    linux-image-rt-amd64 linux-headers-rt-amd64 || true

  # irqbalance is installed for tooling compatibility, but disabled for deterministic audio setup.
  systemctl disable --now irqbalance || true
}

configure_hostname() {
  log "Configuring hostname"
  hostnamectl set-hostname "$HOSTNAME_NEW"
}

create_audio_user() {
  if ! id "$AUDIO_USER" >/dev/null 2>&1; then
    log "Creating service user: $AUDIO_USER"
    useradd --system --create-home --shell /usr/sbin/nologin "$AUDIO_USER"
  fi
}

configure_directories() {
  log "Creating music directories"
  mkdir -p "$MUSIC_LIBRARY_DIR"
  chown -R "$AUDIO_USER":"$AUDIO_GROUP" "$MUSIC_MOUNT" || true
}

configure_sysctl() {
  log "Writing sysctl tuning: $SYSCTL_FILE"
  cat > "$SYSCTL_FILE" <<SYSCTL
# Audio server tuning
net.core.default_qdisc = fq
net.core.netdev_max_backlog = 250
net.core.netdev_budget = 150
net.core.busy_poll = 50
net.core.busy_read = 50
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_tso_win_divisor = 8
vm.swappiness = 1
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
kernel.sched_rt_runtime_us = -1
kernel.timer_migration = 0
kernel.watchdog = 0
kernel.nmi_watchdog = 0
fs.inotify.max_user_watches = 524288
SYSCTL

  sysctl --system
}

configure_grub() {
  [[ -f "$GRUB_FILE" ]] || die "Missing $GRUB_FILE"
  log "Appending kernel boot parameters in GRUB"
  for arg in "${KERNEL_CMDLINE_APPEND[@]}"; do
    append_kernel_arg_if_missing "$arg"
  done

  if command -v update-grub >/dev/null 2>&1; then
    update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
  else
    warn "Could not find update-grub/grub-mkconfig. Update GRUB manually."
  fi
}

configure_avahi() {
  log "Enabling Avahi"
  systemctl enable --now avahi-daemon
}

configure_audirvana_service() {
  log "Writing Audirvana systemd service"
  cat > "$AUDIRVANA_SERVICE_FILE" <<SERVICE
[Unit]
Description=Run audirvanaStudio
After=network.target avahi-daemon.service
Wants=avahi-daemon.service

[Service]
User=${AUDIO_USER}
Group=${AUDIO_GROUP}
ExecStart=${AUDIRVANA_BIN} --server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable "$AUDIRVANA_SERVICE_NAME"

  if [[ -x "$AUDIRVANA_BIN" ]]; then
    systemctl restart "$AUDIRVANA_SERVICE_NAME"
  else
    warn "Audirvana binary not found at $AUDIRVANA_BIN. Install Audirvana, then start the service manually."
  fi
}

configure_smb() {
  log "Configuring SMB share"
  mkdir -p /etc/samba/smb.conf.d
  if ! grep -q "include = /etc/samba/smb.conf.d/*.conf" /etc/samba/smb.conf; then
    printf '\ninclude = /etc/samba/smb.conf.d/*.conf\n' >> /etc/samba/smb.conf
  fi

  cat > "$SMB_CONF_SNIPPET" <<SMB
[music]
   path = ${MUSIC_LIBRARY_DIR}
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0664
   directory mask = 0775
SMB

  testparm -s >/dev/null
  systemctl enable --now smbd
}

configure_nfs() {
  log "Configuring NFS export"
  mkdir -p /etc/exports.d
  cat > "$NFS_EXPORTS_FILE" <<NFS
${MUSIC_LIBRARY_DIR} 10.0.0.0/24(rw,sync,no_subtree_check)
NFS
  exportfs -ra
  systemctl enable --now nfs-kernel-server
}

configure_static_ip() {
  [[ "$CONFIGURE_STATIC_IP" -eq 1 ]] || { warn "Skipping static IP configuration"; return 0; }
  log "Configuring static IP for ${NIC_IFACE} via systemd-networkd"
  mkdir -p /etc/systemd/network
  cat > "$NETWORK_FILE" <<NET
[Match]
Name=${NIC_IFACE}

[Network]
Address=${SERVER_IP_CIDR}
Gateway=${DEFAULT_GW}
DNS=${DNS1}
DNS=${DNS2}
NET
  systemctl enable --now systemd-networkd
  systemctl restart systemd-networkd
}

configure_nic_tuning() {
  [[ "$CONFIGURE_NIC_TUNING" -eq 1 ]] || { warn "Skipping NIC tuning persistence"; return 0; }
  log "Creating persistent NIC tuning service"
  cat > "$NIC_SERVICE_FILE" <<SERVICE
[Unit]
Description=Audio NIC tuning for ${NIC_IFACE}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K ${NIC_IFACE} tso off gso off gro off rx off tx off || true
ExecStart=/usr/sbin/ethtool --set-eee ${NIC_IFACE} eee off || true
ExecStart=/usr/sbin/ethtool -G ${NIC_IFACE} rx 256 tx 256 || true
ExecStart=/usr/sbin/ethtool -C ${NIC_IFACE} rx-usecs 0 || true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable --now audio-nic-tuning.service
}

print_post_install() {
  cat <<POST

============================================================
POST-INSTALL CHECKLIST
============================================================
1. Reboot the server to activate RT kernel and GRUB cmdline.
2. Verify kernel:
   uname -r
   cat /proc/cmdline
3. Verify sysctl:
   sysctl net.core.default_qdisc
   sysctl kernel.sched_rt_runtime_us
4. Verify NIC tuning:
   ethtool -k ${NIC_IFACE}
   ethtool --show-eee ${NIC_IFACE}
   ethtool -g ${NIC_IFACE}
   ethtool -c ${NIC_IFACE}
5. Verify Audirvana service:
   systemctl status ${AUDIRVANA_SERVICE_NAME}
6. Verify Avahi and file services:
   systemctl status avahi-daemon smbd nfs-kernel-server
7. Install Audirvana binary at:
   ${AUDIRVANA_BIN}
   if not already present.
8. Configure Diretta target separately on renderer side.

IMPORTANT
- This script does not install Diretta target software.
- This script does not set BIOS options.
- This script does not validate your exact Audirvana package source.
============================================================
POST
}

main() {
  require_root
  require_debian
  install_packages
  configure_hostname
  create_audio_user
  configure_directories
  configure_sysctl
  configure_grub
  configure_avahi
  configure_audirvana_service
  configure_smb
  configure_nfs
  configure_static_ip
  configure_nic_tuning
  print_post_install
}

main "$@"
