#!/usr/bin/env bash
# Quickstart server setup CLI for Debian/Ubuntu hosts.
# Provides a simple menu to run common bootstrap tasks.

set -euo pipefail

LOG_FILE="${QS_LOG:-/tmp/qs-setup.log}"
SUPPORTED_PKGS=(
  unzip
  nano
  lsof
  cron
  fail2ban
  libffi-dev
  libssl-dev
  curl
  python3-dev
  git
  python3
  python3-pip
  ufw
  tmux
  aptitude
  net-tools
  pwgen
  unattended-upgrades
  apt-listchanges
)

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "This script must run as root (or via sudo)." >&2
    exit 1
  fi
}

require_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get not found; this quickstart targets Debian/Ubuntu-based systems." >&2
    exit 1
  fi
}

log() {
  local msg="$*"
  printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "${msg}" | tee -a "${LOG_FILE}"
}

confirm() {
  local prompt="${1:-Proceed? [y/N]} "
  read -r -p "${prompt}" reply
  [[ "${reply}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

pause() {
  read -rp "Press Enter to continue..." _
}

update_system() {
  log "Updating package index..."
  apt update
  log "Upgrading packages..."
  DEBIAN_FRONTEND=noninteractive apt upgrade -y
  log "Fixing broken installs (if any)..."
  DEBIAN_FRONTEND=noninteractive apt --fix-broken install -y
  log "Removing unused packages..."
  DEBIAN_FRONTEND=noninteractive apt autoremove -y
}

install_packages() {
  require_apt
  log "Installing requested packages: ${SUPPORTED_PKGS[*]}"
  DEBIAN_FRONTEND=noninteractive apt install -y "${SUPPORTED_PKGS[@]}"
  log "Package installation complete."
}

hush_login() {
  require_root
  local target_user="${SUDO_USER:-root}"
  local target_home
  target_home="$(eval echo "~${target_user}")"
  if [[ -z "${target_home}" || ! -d "${target_home}" ]]; then
    log "Could not resolve home for ${target_user}; defaulting to /root."
    target_home="/root"
  fi
  touch "${target_home}/.hushlogin"
  log "Created ${target_home}/.hushlogin to suppress login messages."
}

create_deploy_user() {
  require_root
  local username
  read -r -p "Enter deploy username [deploy]: " username
  username="${username:-deploy}"

  if id -u "${username}" >/dev/null 2>&1; then
    log "User ${username} already exists."
  else
    log "Creating user ${username} with sudo privileges..."
    adduser --disabled-password --gecos "" "${username}"
    usermod -aG sudo "${username}"
  fi

  local ssh_key
  read -r -p "Paste an SSH public key for ${username} (leave blank to skip): " ssh_key
  if [[ -n "${ssh_key}" ]]; then
    local ssh_dir="/home/${username}/.ssh"
    mkdir -p "${ssh_dir}"
    printf "%s\n" "${ssh_key}" >> "${ssh_dir}/authorized_keys"
    chmod 700 "${ssh_dir}"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${username}:${username}" "${ssh_dir}"
    log "SSH key added for ${username}."
  else
    log "No SSH key provided; skipped."
  fi
}

setup_firewall() {
  require_apt
  log "Configuring UFW firewall..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y ufw

  local ssh_port
  ssh_port="$(get_ssh_port)"
  ufw allow "${ssh_port}"/tcp
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 81/tcp
  ufw allow 9000/tcp
  ufw allow 443/tcp
  ufw default deny incoming
  ufw default allow outgoing
  ufw --force enable
  log "UFW enabled with ports 22, ${ssh_port}, 80, 81, 443, 9000 allowed."
}

get_ssh_port() {
  local port
  port="$(grep -E '^[[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config | awk '{print $2}' | tail -n1)"
  echo "${port:-22}"
}

harden_sshd() {
  require_root
  local ssh_port
  ssh_port="$(get_ssh_port)"
  read -r -p "SSH port to keep [${ssh_port}]: " entered_port
  ssh_port="${entered_port:-${ssh_port}}"

  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.qs.bak
  log "Backup created at /etc/ssh/sshd_config.qs.bak"

  # Apply hardened settings.
  sed -i -e "s/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/" \
    -e "s/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin no/" \
    -e "s/^[#[:space:]]*Port.*/Port ${ssh_port}/" \
    -e "s/^[#[:space:]]*ClientAliveInterval.*/ClientAliveInterval 300/" \
    -e "s/^[#[:space:]]*ClientAliveCountMax.*/ClientAliveCountMax 2/" /etc/ssh/sshd_config

  if systemctl restart ssh >/dev/null 2>&1; then
    log "sshd restarted with hardened settings (port ${ssh_port})."
  else
    log "Failed to restart sshd; restoring backup."
    cp /etc/ssh/sshd_config.qs.bak /etc/ssh/sshd_config
    systemctl restart ssh || true
  fi
}

set_root_password() {
  require_root
  local password confirm
  read -rsp "Enter new root password: " password
  echo
  read -rsp "Confirm new root password: " confirm
  echo
  if [[ "${password}" != "${confirm}" ]]; then
    log "Passwords do not match. Aborting password change."
    return
  fi
  echo "root:${password}" | chpasswd
  log "Root password updated."
}

install_docker() {
  require_apt
  if ! command -v curl >/dev/null 2>&1; then
    log "Installing curl (required to fetch Docker installer)..."
    DEBIAN_FRONTEND=noninteractive apt install -y curl
  fi

  log "Installing Docker via test.docker.com convenience script..."
  local installer="/tmp/get-docker.sh"
  curl -fsSL test.docker.com -o "${installer}"
  sh "${installer}"

  local target_user="${SUDO_USER:-root}"
  if id -u "${target_user}" >/dev/null 2>&1; then
    usermod -aG docker "${target_user}"
    log "User ${target_user} added to docker group (logout/login required)."
  else
    log "User ${target_user} not found; skipped group addition."
  fi

  if command -v pip3 >/dev/null 2>&1; then
    pip3 install docker-compose
    log "docker-compose installed via pip3."
  else
    log "pip3 not found; skipped docker-compose installation."
  fi

  systemctl enable docker
  systemctl start docker
  rm -f "${installer}"
  log "Docker installation complete."
}

install_tailscale() {
  require_root
  if ! command -v curl >/dev/null 2>&1; then
    log "Installing curl (required to fetch Tailscale installer)..."
    DEBIAN_FRONTEND=noninteractive apt install -y curl
  fi

  # Resolve distro codename for repo selection.
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
  fi
  local distro_id="${ID:-ubuntu}"
  local distro_codename="${VERSION_CODENAME:-}"
  if [[ -z "${distro_codename}" ]]; then
    distro_codename="$(lsb_release -cs 2>/dev/null || echo focal)"
  fi

  log "Installing Tailscale via convenience script..."
  curl -fsSL https://tailscale.com/install.sh | sh

  log "Adding Tailscale apt repo and keyring..."
  curl -fsSL "https://pkgs.tailscale.com/stable/${distro_id}/${distro_codename}.noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  curl -fsSL "https://pkgs.tailscale.com/stable/${distro_id}/${distro_codename}.tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list >/dev/null

  log "Enabling IP forwarding for exit node..."
  echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
  echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
  sysctl -p /etc/sysctl.d/99-tailscale.conf
  echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
  echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.conf
  sysctl -p /etc/sysctl.conf

  if confirm "Run 'tailscale up' now (requires logged-in auth context)? [y/N] "; then
    log "Bringing up Tailscale with exit-node and routes..."
    tailscale up --advertise-exit-node --ssh --accept-routes=true --accept-risk=lose-ssh --advertise-routes=10.0.0.0/24,169.254.169.254/32 --accept-dns=true
    log "Tailscale setup complete."
  else
    log "Skipped 'tailscale up'; run it manually after login."
  fi
}

configure_fail2ban() {
  require_root
  log "Preparing Fail2ban configuration..."
  (
    cd /etc/fail2ban
    head -n 20 jail.conf || true
    [[ -f jail.local ]] || cp jail.conf jail.local
    ls /etc/fail2ban/filter.d || true
  )
  if ! grep -q '^\[sshd\]' /etc/fail2ban/jail.local 2>/dev/null; then
    cat <<'EOF' >> /etc/fail2ban/jail.local

[sshd]
backend=systemd
enabled=true
EOF
    log "Appended sshd jail to jail.local."
  else
    log "sshd jail already present; leaving jail.local unchanged."
  fi
  systemctl enable fail2ban
  systemctl start fail2ban
  log "Fail2ban configured and started."
}

configure_dns() {
  require_root
  log "Writing /etc/systemd/resolved.conf with local DNS and disabled stub listener..."
  cat >/etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=127.0.0.1
#FallbackDNS=
#Domains=
#DNSSEC=no
#DNSOverTLS=no
#MulticastDNS=no
#LLMNR=no
#Cache=no-negative
#CacheFromLocalhost=no
DNSStubListener=no
#DNSStubListenerExtra=
#ReadEtcHosts=yes
#ResolveUnicastSingleLabel=no
EOF
  if systemctl list-unit-files | grep -q '^systemd-resolved.service'; then
    if [[ -f /run/systemd/resolve/resolv.conf ]]; then
      ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    fi
    systemctl restart systemd-resolved || true
    log "systemd-resolved restarted."
  else
    log "systemd-resolved not present; leaving /etc/resolv.conf untouched."
  fi
}

configure_bashrc() {
  require_root
  local target_user="${SUDO_USER:-root}"
  local target_home
  target_home="$(eval echo "~${target_user}")"
  if [[ -z "${target_home}" || ! -d "${target_home}" ]]; then
    log "Could not resolve home for ${target_user}; defaulting to /root."
    target_home="/root"
  fi

  local bashrc="${target_home}/.bashrc"
  local marker="# QS_SETUP_ALIASES"

  if grep -q "${marker}" "${bashrc}" 2>/dev/null; then
    log ".bashrc already contains quickstart aliases block; skipping."
    return
  fi

  cat >> "${bashrc}" <<'EOF'

# QS_SETUP_ALIASES
# aliases
alias update="sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo aptitude safe-upgrade -y && sudo apt --fix-missing install && sudo reboot"
alias reboot="sudo reboot"

# environmental variables
RCLONE_CONFIG=/home/ubuntu/rclone/.rclone.conf
export RCLONE_CONFIG

# startup
command -v fastfetch >/dev/null 2>&1 && fastfetch
command -v docker >/dev/null 2>&1 && docker container ls
# END_QS_SETUP_ALIASES
EOF

  log "Appended aliases/environment/startup block to ${bashrc} for ${target_user}."
}

run_all_steps() {
  set_timezone_uk
  if confirm "Set root password during run-all? [y/N] "; then
    set_root_password
  else
    log "Skipped root password in run-all."
  fi
  update_system
  install_packages
  hush_login
  setup_firewall
  install_docker
  install_tailscale
  configure_fail2ban
  setup_unattended_upgrades
  configure_dns
  configure_bashrc
  log "All selected steps completed."
}

set_timezone_uk() {
  require_apt
  if ! command -v tzselect >/dev/null 2>&1; then
    log "Installing tzdata to provide tzselect..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata
  fi

  log "Selecting Europe -> United Kingdom -> London via tzselect..."
  # Feed known choices to tzselect and extract the TZ value.
  local tz
  tz=$(printf 'Europe\nUnited Kingdom\nLondon\n' | TZ=UTC tzselect 2>/dev/null | awk -F"'" '/^TZ=/{print $2}' || true)
  tz="${tz:-Europe/London}"
  timedatectl set-timezone "${tz}"
  log "Timezone set to ${tz}."
  timedatectl status | head -n5
}

setup_swap() {
  local size
  read -r -p "Swap size in GB [2]: " size
  size="${size:-2}"

  if swapon --show | grep -q 'file'; then
    log "Swap already configured; skipping."
    return
  fi

  log "Creating ${size}G swapfile at /swapfile..."
  fallocate -l "${size}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  if ! grep -q "^/swapfile" /etc/fstab; then
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
  fi
  log "Swap configured and active."
}

setup_unattended_upgrades() {
  require_apt
  log "Enabling unattended-upgrades..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
  dpkg-reconfigure -plow unattended-upgrades
  log "Unattended upgrades enabled."
}

system_summary() {
  echo "=== System summary ==="
  hostnamectl
  echo "----------------------"
  timedatectl status | head -n5
  echo "----------------------"
  df -h /
  echo "----------------------"
  swapon --show || true
  echo "----------------------"
  ufw status verbose || true
  echo "----------------------"
  systemctl is-active --quiet docker && docker info --format 'Docker: {{.ServerVersion}}' || echo "Docker not running"
}

run_recommended_quickstart() {
  if ! confirm "Run the recommended baseline tasks (update, packages, user, firewall, ssh hardening)? [y/N] "; then
    return
  fi
  update_system
  install_packages
  create_deploy_user
  harden_sshd
  setup_firewall
  setup_unattended_upgrades
  log "Baseline quickstart complete."
}

menu() {
  while true; do
    clear
    cat <<'EOF'
=============================
 Quickstart Server Setup CLI
=============================
1) Set timezone to United Kingdom (tzselect)
2) Set root password (prompt)
3) System update & upgrade
4) Install base packages
5) Suppress login banner (.hushlogin)
6) Configure firewall (UFW)
7) Install Docker
8) Install Tailscale (exit node + routes)
9) Configure Fail2ban
10) Enable unattended upgrades
11) Configure DNS (resolved.conf)
12) Configure .bashrc (aliases/env/startup)
13) Run all steps
0) Exit
EOF
    read -rp "Choose an option: " choice
    case "${choice}" in
      1) set_timezone_uk ;;
      2) set_root_password ;;
      3) update_system ;;
      4) install_packages ;;
      5) hush_login ;;
      6) setup_firewall ;;
      7) install_docker ;;
      8) install_tailscale ;;
      9) configure_fail2ban ;;
      10) setup_unattended_upgrades ;;
      11) configure_dns ;;
      12) configure_bashrc ;;
      13) run_all_steps ;;
      0) log "Exiting."; exit 0 ;;
      *) echo "Invalid choice." ;;
    esac
    pause
  done
}

main() {
  require_root
  require_apt
  log "Logging to ${LOG_FILE}"
  menu
}

main "$@"
