Quickstart Server Setup CLI
===========================

`qs.sh` is an interactive shell script that bootstraps Debian/Ubuntu hosts with common hardening and operational tasks. It must run as root (use `sudo`) and requires `apt-get`.

Usage
-----
- Run with logging: `sudo QS_LOG=/var/log/qs-setup.log ./qs.sh` (defaults to `/tmp/qs-setup.log`).
- The script checks for `apt-get` and exits early if the host is not Debian/Ubuntu-based.
- Actions are menu-driven; select numbers to run tasks, or choose "Run all" for the full sequence.

Menu actions
------------
- Set timezone to United Kingdom: Installs `tzdata` if needed and sets `Europe/London` via `tzselect`.
- Set root password: Prompts for and updates the root password.
- System update & upgrade: Runs `apt update/upgrade`, fixes broken installs, and autoremove.
- Install base packages: Installs a curated set (unzip, nano, lsof, cron, fail2ban, curl, python3/pip, git, ufw, tmux, aptitude, net-tools, pwgen, unattended-upgrades, apt-listchanges, libffi-dev, libssl-dev, etc.).
- Suppress login banner: Creates `.hushlogin` for the invoking user (or root).
- Configure firewall (UFW): Enables UFW, allows SSH (detected port and 22), HTTP/HTTPS, and common app ports (80, 81, 443, 9000); defaults to deny incoming/allow outgoing.
- Install Docker: Uses the Docker convenience script, adds the invoking user to the `docker` group, installs `docker-compose` via pip if available, and enables/starts the daemon.
- Install Tailscale: Runs the official install script, adds the repository/keyring, enables IP forwarding, and optionally runs `tailscale up` with exit-node/routes/SSH settings.
- Configure Fail2ban: Ensures `jail.local` exists with an `sshd` jail, then enables/starts the service.
- Enable unattended upgrades: Installs and reconfigures `unattended-upgrades`.
- Configure DNS: Writes `/etc/systemd/resolved.conf` with 127.0.0.1 as DNS and disables the stub listener; restarts `systemd-resolved` when present.
- Configure .bashrc: Appends aliases, an `RCLONE_CONFIG` export, and startup helpers (`fastfetch`, `docker container ls`) for the invoking user.
- Run all steps: Runs a guided baseline (timezone, optional root password, update/packages, hushlogin, firewall, Docker, Tailscale, Fail2ban, unattended upgrades, DNS, bashrc).
- Exit: Quit the menu.

Helpers and safeguards
----------------------
- Requires root: exits if not root/sudo.
- `set -euo pipefail` to stop on errors and catch unset variables.
- `harden_sshd` (used in the recommended quickstart path) backs up `/etc/ssh/sshd_config` before applying stricter settings and restarts `sshd`; restores the backup on restart failure.
- Logging: All steps append to `QS_LOG` (defaults to `/tmp/qs-setup.log`).

Suggested flow
--------------
1. Review the menu to pick individual tasks, or choose "Run all" for the curated baseline.
2. Confirm prompts carefully (root password, SSH port, swap size, Tailscale bring-up).
3. Reboot after major changes if prompted or when convenient.
