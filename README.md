Quickstart Server Setup CLI
===========================

`qs.sh` is an interactive shell script that bootstraps Debian/Ubuntu hosts with common hardening and operational tasks. It must run as root (use `sudo`) and requires `apt-get`.

Usage
-----
- Run with logging: `sudo QS_LOG=/var/log/qs-setup.log ./qs.sh` (defaults to `/tmp/qs-setup.log`).
- The script checks for `apt-get` and exits early if the host is not Debian/Ubuntu-based.
- A preflight check runs up front (root, `apt-get`, `systemctl`, `curl`) and logs detected cloud provider (AWS/GCP/OCI/unknown).
- Logging now includes timestamp, host, and sudo user context for easier auditing.
- Actions are menu-driven; select numbers to run tasks, or choose "Run all" for the full sequence.

Menu actions
------------
- Set timezone to United Kingdom: Installs `tzdata` if needed and sets `Europe/London` via `tzselect`.
- Set root password: Prompts for and updates the root password.
- System update & upgrade: Runs `apt update/upgrade`, fixes broken installs, and autoremove.
- Install base packages: Installs a curated set (unzip, nano, lsof, cron, cloud-guest-utils, fail2ban, curl, python3/pip, git, ufw, tmux, aptitude, net-tools, pwgen, unattended-upgrades, apt-listchanges, libffi-dev, libssl-dev, etc.) and then installs Fastfetch from its GitHub release (`fastfetch-linux-{amd64|aarch64}.deb`) when available.
- Suppress login banner: Creates `.hushlogin` for the invoking user (or root).
- Configure firewall (UFW): Enables UFW, allows SSH (detected port and 22), HTTP/HTTPS, and common app ports (80, 81, 443, 9000); defaults to deny incoming/allow outgoing. Warns on cloud VMs before changing firewall rules and logs `ufw status`.
- Install Docker: Skips reinstall if Docker already exists; otherwise uses the Docker convenience script, adds the invoking user to the `docker` group, attempts the `docker-compose` plugin/binary via apt (no pip on externally managed Python), enables/starts the daemon, and logs engine info.
- Install Tailscale: Runs the official install script, adds the repository/keyring, enables IP forwarding, and optionally runs `tailscale up` with exit-node/routes/SSH settings.
- Configure Fail2ban: Ensures `jail.local` exists with an `sshd` jail, then enables/starts the service and logs `fail2ban-client status sshd`.
- Enable unattended upgrades: Installs and reconfigures `unattended-upgrades` and confirms service enablement.
- Configure DNS: Backs up `/etc/systemd/resolved.conf` (if present), writes a new config with 127.0.0.1 DNS and disabled stub listener, and restarts `systemd-resolved` when present.
- Configure .bashrc: Appends aliases, an `RCLONE_CONFIG` export, and startup helpers (`fastfetch`, `docker container ls`) for the invoking user.
- Run all steps: Runs a guided baseline (timezone, optional root password, update/packages, hushlogin, firewall, Docker, Tailscale, Fail2ban, unattended upgrades, DNS, bashrc) and prints a system summary.
- Rollback QS changes: Best-effort restore of SSH config (from `.qs.bak`), DNS config, swapfile, UFW state (optional), `.bashrc` aliases, and `.hushlogin`.
- Exit: Quit the menu.

Helpers and safeguards
----------------------
- Requires root: exits if not root/sudo.
- `set -euo pipefail` to stop on errors and catch unset variables.
- `harden_sshd` (used in the recommended quickstart path) backs up `/etc/ssh/sshd_config` before applying stricter settings and restarts `sshd`; restores the backup on restart failure.
- Logging: All steps append to `QS_LOG` (defaults to `/tmp/qs-setup.log`).
- Input validation: SSH port prompts are validated to `1-65535`; swap size prompts are limited to `1-64` GB with sane defaults.
- Cloud guard: Network-impacting steps prompt for confirmation on detected cloud providers to avoid conflicts with cloud firewalls.
- DNS safety: `/etc/systemd/resolved.conf` is backed up before rewrite and can be restored via rollback.

Suggested flow
--------------
1. Review the menu to pick individual tasks, or choose "Run all" for the curated baseline.
2. Confirm prompts carefully (root password, SSH port, swap size, Tailscale bring-up).
3. Reboot after major changes if prompted or when convenient.
