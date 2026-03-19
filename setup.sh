#!/bin/bash

# ============================================================
#  Ubuntu Server Configuration Script  v3.0
#  - Per-section error handling (no global set -e)
#  - PHP-FPM version auto-detected
#  - phpMyAdmin auto-installs on Ubuntu 22/24 via direct download
#  - Nginx reverse proxy auto-configured per folder + port
#  - All questions upfront, fully automated after
# ============================================================

# ───────────────────────────────────────────────
#  Colors & Helpers
# ───────────────────────────────────────────────
RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m';  BOLD='\033[1m';      DIM='\033[2m';  RESET='\033[0m'
BLUE='\033[0;34m';  MAGENTA='\033[0;35m'

info()    { echo -e "  ${CYAN}→${RESET}  $*"; }
success() { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
fatal()   { echo -e "\n  ${RED}✘  FATAL:${RESET} $*\n"; exit 1; }
section() {
  echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║  $*${RESET}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${RESET}\n"
}
divider() { echo -e "${DIM}  ──────────────────────────────────────────────${RESET}"; }

# Run a command silently — warn on failure but never kill the script
safe_run() {
  local DESC="$1"; shift
  if "$@" > /dev/null 2>&1; then
    success "$DESC"
  else
    warn "$DESC — failed (non-fatal, continuing)"
  fi
}

# ───────────────────────────────────────────────
#  Root check
# ───────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  fatal "Run as root:  sudo bash server-setup.sh"
fi

# ───────────────────────────────────────────────
#  Detect Ubuntu version
# ───────────────────────────────────────────────
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "22.04")
UBUNTU_MAJOR=$(echo "$UBUNTU_VERSION" | cut -d. -f1)

# ───────────────────────────────────────────────
#  Banner
# ───────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat <<'BANNER'

   ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗
   ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
   ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
   ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
   ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
   ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝

        Ubuntu Server Setup  —  v3.0
        Answer a few questions, then grab a coffee ☕

BANNER
echo -e "${RESET}"
echo -e "  ${DIM}Detected Ubuntu $UBUNTU_VERSION${RESET}\n"

# ============================================================
#  PHASE 1 — ALL QUESTIONS UPFRONT
# ============================================================
section "Phase 1 — Configuration Questions"
echo -e "  Answer everything now. Fully automated after this.\n"
divider

# ── Q1: Swap ────────────────────────────────────────────────
echo -e "\n  ${BOLD}[1/8] Swap Space${RESET}"
echo -e "       Recommended if RAM < 4 GB"
read -rp "       Enable swap? [y/N]: " SWAP_ENABLED
SWAP_ENABLED="${SWAP_ENABLED:-n}"
SWAP_SIZE=""
if [[ "$SWAP_ENABLED" =~ ^[Yy]$ ]]; then
  read -rp "       Swap size (e.g. 2G, 4G) [default: 2G]: " SWAP_SIZE
  SWAP_SIZE="${SWAP_SIZE:-2G}"
fi
divider

# ── Q2: Folders + Ports ─────────────────────────────────────
echo -e "\n  ${BOLD}[2/8] Project Folders + Ports${RESET}  (in /var/www/html)"
echo -e "       Select folders to create:\n"
echo -e "       ${CYAN}a)${RESET} frontend"
echo -e "       ${CYAN}b)${RESET} backend"
echo -e "       ${CYAN}c)${RESET} admin"
echo -e "       ${CYAN}d)${RESET} ai"
echo -e "       ${CYAN}e)${RESET} all of the above"
echo ""
read -rp "       Enter choices (e.g. a b c  or  e): " -a FOLDER_CHOICES

SELECTED_FOLDERS=()
for CHOICE in "${FOLDER_CHOICES[@]}"; do
  case "$CHOICE" in
    a) SELECTED_FOLDERS+=("frontend") ;;
    b) SELECTED_FOLDERS+=("backend") ;;
    c) SELECTED_FOLDERS+=("admin") ;;
    d) SELECTED_FOLDERS+=("ai") ;;
    e) SELECTED_FOLDERS=("frontend" "backend" "admin" "ai"); break ;;
  esac
done

declare -A FOLDER_PORT
declare -A DEFAULT_PORTS
DEFAULT_PORTS=([frontend]=3000 [backend]=3001 [admin]=8000 [ai]=8001)

if [[ ${#SELECTED_FOLDERS[@]} -gt 0 ]]; then
  echo -e "\n  ${DIM}Assign a port for each folder (Nginx proxies to it):${RESET}"
  for FOLDER in "${SELECTED_FOLDERS[@]}"; do
    DEF="${DEFAULT_PORTS[$FOLDER]:-3000}"
    read -rp "       Port for $FOLDER [default: $DEF]: " P
    FOLDER_PORT["$FOLDER"]="${P:-$DEF}"
  done
else
  warn "No folders selected — skipping folder creation and proxy."
fi
divider

# ── Q3: Web Server ───────────────────────────────────────────
echo -e "\n  ${BOLD}[3/8] Web Server${RESET}"
echo -e "       ${CYAN}1)${RESET} Apache"
echo -e "       ${CYAN}2)${RESET} Nginx  ${DIM}(recommended)${RESET}"
echo ""
read -rp "       Choose [1/2, default: 2]: " WEB_CHOICE
WEB_CHOICE="${WEB_CHOICE:-2}"
case "$WEB_CHOICE" in
  1) WEB_SERVER="apache" ;;
  2) WEB_SERVER="nginx" ;;
  *) fatal "Invalid — re-run and enter 1 or 2." ;;
esac
divider

# ── Q4: Node.js version ─────────────────────────────────────
DEFAULT_NODE="20.19.4"
echo -e "\n  ${BOLD}[4/8] Node.js Version${RESET}"
read -rp "       Node version [default: $DEFAULT_NODE]: " NODE_VERSION
NODE_VERSION="${NODE_VERSION:-$DEFAULT_NODE}"
divider

# ── Q5: MySQL password ──────────────────────────────────────
echo -e "\n  ${BOLD}[5/8] MySQL Root Password${RESET}"
while true; do
  read -rsp "       Enter password: " DB_PASS; echo
  read -rsp "       Confirm password: " DB_PASS2; echo
  [[ "$DB_PASS" == "$DB_PASS2" ]] && break
  warn "Passwords do not match — try again."
done
divider

# ── Q6: phpMyAdmin IP whitelist ──────────────────────────────
echo -e "\n  ${BOLD}[6/8] phpMyAdmin IP Whitelist${RESET}"
echo -e "       Your current IP will be added automatically."
echo -e "       Add more IPs (space-separated) or press Enter to skip."
read -rp "       Extra IPs: " EXTRA_IPS_INPUT
EXTRA_IPS=()
for IP in $EXTRA_IPS_INPUT; do EXTRA_IPS+=("$IP"); done
divider

# ── Q7: SSL ──────────────────────────────────────────────────
echo -e "\n  ${BOLD}[7/8] SSL Certificate (Let's Encrypt — Free)${RESET}"
read -rp "       Enable SSL? [y/N]: " SSL_ENABLED
SSL_ENABLED="${SSL_ENABLED:-n}"
DOMAIN=""
SSL_EMAIL=""
if [[ "$SSL_ENABLED" =~ ^[Yy]$ ]]; then
  read -rp "       Domain (e.g. example.com): " DOMAIN
  read -rp "       Email for renewal notices: " SSL_EMAIL
fi
divider

# ── Q8: Git provider ─────────────────────────────────────────
echo -e "\n  ${BOLD}[8/8] Git Provider${RESET}"
echo -e "       ${CYAN}1)${RESET} GitHub"
echo -e "       ${CYAN}2)${RESET} GitLab"
echo -e "       ${CYAN}3)${RESET} Both"
read -rp "       Choose [1/2/3, default: 1]: " GIT_PROVIDER
GIT_PROVIDER="${GIT_PROVIDER:-1}"
divider

# ── Pre-flight summary ───────────────────────────────────────
echo -e "\n${BOLD}${GREEN}  ✅  All answers collected! Here's your config:${RESET}\n"
echo -e "     Swap        :  ${SWAP_ENABLED^^} ${SWAP_SIZE}"
echo -e "     Web server  :  $WEB_SERVER"
echo -e "     Node.js     :  $NODE_VERSION"
echo -e "     MySQL pass  :  ••••••••"
echo -e "     Extra IPs   :  ${EXTRA_IPS[*]:-none (current IP only)}"
echo -e "     SSL         :  ${SSL_ENABLED^^} ${DOMAIN}"
echo -e "     Git         :  $(case $GIT_PROVIDER in 1) echo GitHub;; 2) echo GitLab;; 3) echo "GitHub + GitLab";; esac)"
if [[ ${#SELECTED_FOLDERS[@]} -gt 0 ]]; then
  echo -e "     Folders:"
  for F in "${SELECTED_FOLDERS[@]}"; do
    echo -e "       ${DIM}$F  →  port ${FOLDER_PORT[$F]}${RESET}"
  done
else
  echo -e "     Folders     :  none"
fi
echo ""
read -rp "  ☕  Confirm and start? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-y}"
[[ "$CONFIRM" =~ ^[Nn]$ ]] && echo "Aborted." && exit 0

# ============================================================
#  PHASE 2 — FULLY AUTOMATED
# ============================================================
clear
section "Phase 2 — Automated Installation"
echo -e "  ${DIM}Go grab that coffee — we'll handle everything.${RESET}\n"

# ── Base packages ────────────────────────────────────────────
info "Updating system packages..."
apt-get update -qq 2>/dev/null || warn "apt update had warnings"
apt-get install -y curl wget ufw fail2ban unattended-upgrades \
  software-properties-common gnupg2 openssl git \
  > /dev/null 2>&1 || warn "Some base packages failed to install"
success "Base packages ready"

# ── PHP (install early so we know the version + socket) ─────
info "Installing PHP and detecting version..."
apt-get install -y php php-cli php-fpm php-mbstring php-zip \
  php-gd php-json php-curl php-xml php-mysql > /dev/null 2>&1 || true

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "")
if [[ -z "$PHP_VERSION" ]]; then
  # Fallback: scan for installed fpm socket
  PHP_VERSION=$(find /run/php/ -name "php*-fpm.sock" 2>/dev/null \
    | head -1 | grep -oP '\d+\.\d+' || echo "8.1")
fi
PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
success "PHP $PHP_VERSION — socket: $PHP_FPM_SOCK"

# ───────────────────────────────────────────────
#  PEM KEY
# ───────────────────────────────────────────────
info "Generating PEM keypair for server login..."
PEM_DIR="/root/.ssh"
PEM_KEY="$PEM_DIR/server_login"
mkdir -p "$PEM_DIR" && chmod 700 "$PEM_DIR"

if ssh-keygen -t rsa -b 4096 -f "$PEM_KEY" -N "" -C "server-pem-login" > /dev/null 2>&1; then
  openssl rsa -in "$PEM_KEY" -outform PEM -out "$PEM_KEY.pem" 2>/dev/null || true
  chmod 400 "$PEM_KEY.pem" 2>/dev/null || true
  cat "$PEM_KEY.pub" >> "$PEM_DIR/authorized_keys"
  chmod 600 "$PEM_DIR/authorized_keys"
  success "PEM keypair at $PEM_KEY.pem"
else
  warn "PEM key generation failed — add your key manually"
fi

# ───────────────────────────────────────────────
#  GIT SSH KEY
# ───────────────────────────────────────────────
info "Generating dedicated Git SSH key..."
GIT_KEY="/root/.ssh/id_ed25519_git"
if ssh-keygen -t ed25519 -C "git-deploy-key" -f "$GIT_KEY" -N "" > /dev/null 2>&1; then
  SSH_CFG="/root/.ssh/config"
  touch "$SSH_CFG" && chmod 600 "$SSH_CFG"
  if [[ "$GIT_PROVIDER" == "1" || "$GIT_PROVIDER" == "3" ]]; then
    grep -q "Host github.com" "$SSH_CFG" 2>/dev/null || cat >> "$SSH_CFG" <<SSHCONF

Host github.com
    IdentityFile $GIT_KEY
    IdentitiesOnly yes
SSHCONF
  fi
  if [[ "$GIT_PROVIDER" == "2" || "$GIT_PROVIDER" == "3" ]]; then
    grep -q "Host gitlab.com" "$SSH_CFG" 2>/dev/null || cat >> "$SSH_CFG" <<SSHCONF

Host gitlab.com
    IdentityFile $GIT_KEY
    IdentitiesOnly yes
SSHCONF
  fi
  success "Git SSH key generated"
else
  warn "Git SSH key generation failed"
fi

# ───────────────────────────────────────────────
#  SSH HARDENING
# ───────────────────────────────────────────────
info "Hardening SSH..."
SSH_CONFIG="/etc/ssh/sshd_config"
cp "$SSH_CONFIG" "${SSH_CONFIG}.bak" 2>/dev/null || true
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG"
if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
  success "SSH hardened — password login disabled"
else
  warn "SSH restart failed — check /etc/ssh/sshd_config"
fi

# ───────────────────────────────────────────────
#  FAIL2BAN
# ───────────────────────────────────────────────
info "Configuring Fail2ban..."
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(syslog_backend)s
F2B
safe_run "Fail2ban started" systemctl restart fail2ban

# ───────────────────────────────────────────────
#  SWAP
# ───────────────────────────────────────────────
if [[ "$SWAP_ENABLED" =~ ^[Yy]$ ]]; then
  info "Creating ${SWAP_SIZE} swap..."
  if swapon --show | grep -q '/swapfile'; then
    warn "Swap already exists — skipping"
  else
    if fallocate -l "$SWAP_SIZE" /swapfile 2>/dev/null && \
       chmod 600 /swapfile && \
       mkswap /swapfile > /dev/null && \
       swapon /swapfile; then
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
      echo 'vm.swappiness=10' >> /etc/sysctl.conf
      sysctl -p > /dev/null 2>&1 || true
      success "Swap ${SWAP_SIZE} enabled"
    else
      warn "Swap creation failed"
    fi
  fi
fi

# ───────────────────────────────────────────────
#  WEB SERVER
# ───────────────────────────────────────────────
info "Installing $WEB_SERVER..."
if [[ "$WEB_SERVER" == "apache" ]]; then
  if apt-get install -y apache2 > /dev/null 2>&1; then
    a2enmod rewrite proxy proxy_http headers > /dev/null 2>&1 || true
    safe_run "Apache enabled + started" systemctl enable apache2
    systemctl start apache2 2>/dev/null || true
    success "Apache installed"
  else
    warn "Apache install failed"
  fi
else
  if apt-get install -y nginx > /dev/null 2>&1; then
    safe_run "Nginx enabled" systemctl enable nginx
    systemctl start nginx 2>/dev/null || true
    success "Nginx installed"
  else
    warn "Nginx install failed"
  fi
fi

# ───────────────────────────────────────────────
#  NVM + NODE
# ───────────────────────────────────────────────
info "Installing NVM..."
NVM_DIR="/root/.nvm"
export NVM_DIR

if [[ ! -d "$NVM_DIR" ]]; then
  if curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh \
      | bash > /dev/null 2>&1; then
    success "NVM installed"
  else
    warn "NVM install failed"
  fi
fi

[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null || true

if command -v nvm &>/dev/null; then
  info "Installing Node.js $NODE_VERSION..."
  if nvm install "$NODE_VERSION" > /dev/null 2>&1; then
    nvm alias default "$NODE_VERSION" > /dev/null 2>&1 || true
    nvm use default > /dev/null 2>&1 || true
    success "Node.js $(node -v 2>/dev/null || echo $NODE_VERSION) set as default"
  else
    warn "Node.js install failed"
  fi
else
  warn "NVM not available — Node.js not installed"
fi

cat > /etc/profile.d/nvm.sh <<'NVMPROFILE'
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
NVMPROFILE
chmod +x /etc/profile.d/nvm.sh

# ───────────────────────────────────────────────
#  PM2 + KNEX
# ───────────────────────────────────────────────
if command -v npm &>/dev/null; then
  info "Installing PM2 and Knex globally..."
  if npm install -g pm2 knex > /dev/null 2>&1; then
    pm2 startup systemd -u root --hp /root > /dev/null 2>&1 || true
    PM2_VER=$(pm2 -v 2>/dev/null || echo "installed")
    success "PM2 $PM2_VER and Knex installed globally"
  else
    warn "PM2/Knex install failed"
  fi
else
  warn "npm not available — skipping PM2 and Knex"
fi

# ───────────────────────────────────────────────
#  PROJECT FOLDERS
# ───────────────────────────────────────────────
WEB_ROOT="/var/www/html"
PROXY_PORTS=()
if [[ ${#SELECTED_FOLDERS[@]} -gt 0 ]]; then
  info "Creating project folders..."
  for FOLDER in "${SELECTED_FOLDERS[@]}"; do
    TARGET="$WEB_ROOT/$FOLDER"
    mkdir -p "$TARGET"
    touch "$TARGET/.gitkeep"
    PROXY_PORTS+=("${FOLDER_PORT[$FOLDER]}")
    success "Created $TARGET (proxy → :${FOLDER_PORT[$FOLDER]})"
  done
  chown -R www-data:www-data "$WEB_ROOT"
  chmod -R 755 "$WEB_ROOT"
fi

# ───────────────────────────────────────────────
#  NGINX REVERSE PROXY — per folder
# ───────────────────────────────────────────────
if [[ "$WEB_SERVER" == "nginx" && ${#SELECTED_FOLDERS[@]} -gt 0 ]]; then
  info "Writing Nginx reverse proxy configs..."

  for FOLDER in "${SELECTED_FOLDERS[@]}"; do
    PORT="${FOLDER_PORT[$FOLDER]}"
    CONF="/etc/nginx/sites-available/$FOLDER"

    cat > "$CONF" <<NGINXPROXY
server {
    listen 80;
    server_name _;

    # ── $FOLDER proxy → port $PORT ──
    location /$FOLDER/ {
        proxy_pass          http://127.0.0.1:${PORT}/;
        proxy_http_version  1.1;
        proxy_set_header    Upgrade \$http_upgrade;
        proxy_set_header    Connection 'upgrade';
        proxy_set_header    Host \$host;
        proxy_set_header    X-Real-IP \$remote_addr;
        proxy_set_header    X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto \$scheme;
        proxy_cache_bypass  \$http_upgrade;
        proxy_read_timeout  60s;
        proxy_connect_timeout 10s;
    }
}
NGINXPROXY

    ln -sf "$CONF" "/etc/nginx/sites-enabled/$FOLDER" 2>/dev/null || true
    success "Proxy config: /$FOLDER → :$PORT"
  done

  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

  if nginx -t > /dev/null 2>&1; then
    safe_run "Nginx reloaded with proxy configs" systemctl reload nginx
  else
    warn "Nginx config test failed — check /etc/nginx/sites-available/"
    nginx -t 2>&1 | sed 's/^/     /'
  fi

elif [[ "$WEB_SERVER" == "apache" && ${#SELECTED_FOLDERS[@]} -gt 0 ]]; then
  info "Writing Apache reverse proxy configs..."
  a2enmod proxy proxy_http > /dev/null 2>&1 || true

  for FOLDER in "${SELECTED_FOLDERS[@]}"; do
    PORT="${FOLDER_PORT[$FOLDER]}"
    CONF="/etc/apache2/sites-available/$FOLDER.conf"

    cat > "$CONF" <<APACHEPROXY
<VirtualHost *:80>
    ServerName _
    ProxyPreserveHost On
    ProxyRequests Off

    ProxyPass        /$FOLDER/ http://127.0.0.1:${PORT}/
    ProxyPassReverse /$FOLDER/ http://127.0.0.1:${PORT}/

    <Proxy http://127.0.0.1:${PORT}/>
        Require all granted
    </Proxy>
</VirtualHost>
APACHEPROXY

    a2ensite "$FOLDER" > /dev/null 2>&1 || true
    success "Proxy config: /$FOLDER → :$PORT"
  done

  if apache2ctl configtest > /dev/null 2>&1; then
    safe_run "Apache reloaded" systemctl reload apache2
  else
    warn "Apache config test failed"
  fi
fi

# ───────────────────────────────────────────────
#  FIREWALL
# ───────────────────────────────────────────────
info "Configuring UFW firewall..."
ufw --force reset > /dev/null 2>&1 || true
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow OpenSSH > /dev/null 2>&1

if [[ "$WEB_SERVER" == "apache" ]]; then
  ufw allow 'Apache Full' > /dev/null 2>&1 || ufw allow 80/tcp > /dev/null 2>&1
else
  ufw allow 'Nginx Full' > /dev/null 2>&1 || ufw allow 80/tcp > /dev/null 2>&1
fi

OPENED_PORTS=("22" "80" "443")
for PORT in "${PROXY_PORTS[@]}"; do
  ufw allow "$PORT/tcp" > /dev/null 2>&1
  OPENED_PORTS+=("$PORT")
done

ufw --force enable > /dev/null 2>&1
success "UFW enabled — open: ${OPENED_PORTS[*]}"

# ───────────────────────────────────────────────
#  MYSQL
# ───────────────────────────────────────────────
info "Installing MySQL Server..."
PMA_INSTALLED=false
PMA_URL="not installed"
WHITELIST_FILE="/etc/phpmyadmin-allowed-ips.conf"

if apt-get install -y mysql-server > /dev/null 2>&1; then
  systemctl enable mysql > /dev/null 2>&1 || true
  systemctl start mysql 2>/dev/null || true
  if mysql --user=root 2>/dev/null <<MYSQL_SETUP
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';
FLUSH PRIVILEGES;
MYSQL_SETUP
  then
    success "MySQL installed and root password set"
  else
    warn "MySQL root password setup failed — run mysql_secure_installation manually"
  fi
else
  warn "MySQL installation failed"
fi

# ───────────────────────────────────────────────
#  phpMyAdmin — Ubuntu version-aware
# ───────────────────────────────────────────────
info "Installing phpMyAdmin (Ubuntu $UBUNTU_VERSION)..."
PMA_INSTALL_DIR="/usr/share/phpmyadmin"

# Start php-fpm first (needed for both install methods)
systemctl start "php${PHP_VERSION}-fpm" 2>/dev/null || \
  systemctl start php-fpm 2>/dev/null || true
systemctl enable "php${PHP_VERSION}-fpm" 2>/dev/null || true

if [[ "$UBUNTU_MAJOR" -le 22 ]]; then
  # ── Ubuntu 20/22: try apt first ──
  debconf-set-selections <<PRESEED 2>/dev/null
phpmyadmin phpmyadmin/reconfigure-webserver multiselect $WEB_SERVER
phpmyadmin phpmyadmin/dbconfig-install boolean true
phpmyadmin phpmyadmin/db/app-user string phpmyadmin
phpmyadmin phpmyadmin/db/app-pass password ${DB_PASS}
phpmyadmin phpmyadmin/app-password-confirm password ${DB_PASS}
phpmyadmin phpmyadmin/mysql/admin-pass password ${DB_PASS}
phpmyadmin phpmyadmin/mysql/app-pass password ${DB_PASS}
PRESEED

  if DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin > /dev/null 2>&1; then
    PMA_INSTALLED=true
    success "phpMyAdmin installed via apt"
  else
    warn "apt install failed — trying direct download..."
  fi
fi

if [[ "$PMA_INSTALLED" == false ]]; then
  # ── Ubuntu 24+ or apt fallback: direct download ──
  info "Downloading phpMyAdmin directly..."
  PMA_VERSION=$(curl -fsSL --max-time 10 \
    https://www.phpmyadmin.net/home_page/version.txt 2>/dev/null \
    | head -1 | tr -d '[:space:]')
  PMA_VERSION="${PMA_VERSION:-5.2.1}"

  PMA_TAR="phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz"
  PMA_DL_URL="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/${PMA_TAR}"

  if curl -fsSL --max-time 60 "$PMA_DL_URL" -o "/tmp/$PMA_TAR" 2>/dev/null; then
    mkdir -p /tmp/pma_extract
    if tar -xzf "/tmp/$PMA_TAR" -C /tmp/pma_extract/ > /dev/null 2>&1; then
      EXTRACTED=$(find /tmp/pma_extract -maxdepth 1 -name "phpMyAdmin-*" -type d | head -1)
      if [[ -n "$EXTRACTED" ]]; then
        rm -rf "$PMA_INSTALL_DIR"
        mv "$EXTRACTED" "$PMA_INSTALL_DIR"
        # Write config with random blowfish secret
        cp "$PMA_INSTALL_DIR/config.sample.inc.php" \
           "$PMA_INSTALL_DIR/config.inc.php" 2>/dev/null || true
        BLOWFISH=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
        sed -i "s/\(\\\$cfg\['blowfish_secret'\] = \)''/\1'$BLOWFISH'/" \
          "$PMA_INSTALL_DIR/config.inc.php" 2>/dev/null || true
        chown -R www-data:www-data "$PMA_INSTALL_DIR"
        rm -rf "/tmp/$PMA_TAR" /tmp/pma_extract
        PMA_INSTALLED=true
        success "phpMyAdmin $PMA_VERSION installed via direct download"
      else
        warn "phpMyAdmin extraction failed"
      fi
    else
      warn "phpMyAdmin tar extraction failed"
    fi
  else
    warn "phpMyAdmin download failed — install manually later"
  fi
fi

# ── IP Whitelist + web server config for phpMyAdmin ──
if [[ "$PMA_INSTALLED" == true ]]; then
  # Detect current IP
  CURRENT_IP=$(echo "$SSH_CLIENT" | awk '{print $1}' 2>/dev/null || \
    who am i 2>/dev/null | awk '{print $5}' | tr -d '()' || echo "")

  cat > "$WHITELIST_FILE" <<WLHEADER
# phpMyAdmin IP Whitelist
# One IP per line. Comments start with #
# After editing run: systemctl reload $WEB_SERVER
WLHEADER
  [[ -n "$CURRENT_IP" ]] && echo "$CURRENT_IP  # added at setup" >> "$WHITELIST_FILE"
  for IP in "${EXTRA_IPS[@]}"; do echo "$IP" >> "$WHITELIST_FILE"; done

  # Build allow block helpers
  _nginx_allow() {
    grep -v '^#' "$WHITELIST_FILE" | grep -v '^$' | \
      awk '{print "    allow "$1";"}' 2>/dev/null
  }
  _apache_allow() {
    grep -v '^#' "$WHITELIST_FILE" | grep -v '^$' | \
      awk '{print "        Require ip "$1}' 2>/dev/null
  }

  if [[ "$WEB_SERVER" == "nginx" ]]; then
    cat > /etc/nginx/conf.d/phpmyadmin.conf <<NGINXPMA
server {
    listen 8080;
    server_name _;
    root $PMA_INSTALL_DIR;
    index index.php index.html;

    # IP Whitelist — edit $WHITELIST_FILE then: systemctl reload nginx
$(_nginx_allow)
    deny all;

    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCK};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    location ~ /\.(ht|git) { deny all; }
}
NGINXPMA

    ufw allow 8080/tcp > /dev/null 2>&1
    if nginx -t > /dev/null 2>&1; then
      safe_run "Nginx reloaded for phpMyAdmin" systemctl reload nginx
    else
      warn "Nginx config error for phpMyAdmin"
      nginx -t 2>&1 | sed 's/^/     /'
    fi
    PMA_URL="http://YOUR_IP:8080"

  else
    # Apache
    cat > /etc/apache2/conf-available/phpmyadmin.conf <<APACHEPMA
Alias /phpmyadmin $PMA_INSTALL_DIR
<Directory $PMA_INSTALL_DIR>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    <RequireAny>
$(_apache_allow)
    </RequireAny>
</Directory>
<Directory $PMA_INSTALL_DIR/libraries>
    Require all denied
</Directory>
APACHEPMA
    a2enconf phpmyadmin > /dev/null 2>&1 || true
    phpenmod mbstring 2>/dev/null || true
    safe_run "Apache reloaded for phpMyAdmin" systemctl reload apache2
    PMA_URL="http://YOUR_IP/phpmyadmin"
  fi

  success "phpMyAdmin at $PMA_URL — IP-restricted"
fi

# ───────────────────────────────────────────────
#  SSL
# ───────────────────────────────────────────────
if [[ "$SSL_ENABLED" =~ ^[Yy]$ && -n "$DOMAIN" ]]; then
  info "Installing Certbot for $DOMAIN..."
  if apt-get install -y certbot > /dev/null 2>&1; then
    if [[ "$WEB_SERVER" == "nginx" ]]; then
      apt-get install -y python3-certbot-nginx > /dev/null 2>&1 || true
      if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
          -m "$SSL_EMAIL" --redirect 2>/dev/null; then
        success "SSL installed for $DOMAIN"
      else
        warn "SSL failed — ensure DNS points to this server"
      fi
    else
      apt-get install -y python3-certbot-apache > /dev/null 2>&1 || true
      if certbot --apache -d "$DOMAIN" --non-interactive --agree-tos \
          -m "$SSL_EMAIL" --redirect 2>/dev/null; then
        success "SSL installed for $DOMAIN"
      else
        warn "SSL failed — ensure DNS points to this server"
      fi
    fi
  else
    warn "Certbot install failed"
  fi
fi

# ───────────────────────────────────────────────
#  AUTO SECURITY UPDATES
# ───────────────────────────────────────────────
info "Enabling automatic security updates..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades-custom <<'AUTOUPDATE'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
AUTOUPDATE
safe_run "Auto-updates enabled" systemctl enable unattended-upgrades

# ============================================================
#  SHOW PEM KEY  (before deploy wizard so user can save it)
# ============================================================
clear
echo -e "${BOLD}${GREEN}"
cat <<'DONE'

  ╔═══════════════════════════════════════════════════════╗
  ║           ☕  Setup Complete — Welcome Back!           ║
  ╚═══════════════════════════════════════════════════════╝

DONE
echo -e "${RESET}"

section "PEM Key — Save This NOW (shown once only)"
echo -e "  ${YELLOW}Copy this and save as server_login.pem on your local machine${RESET}\n"
if [[ -f "$PEM_KEY.pem" ]]; then
  cat "$PEM_KEY.pem"
else
  warn "PEM key not found at $PEM_KEY.pem"
fi
echo ""
echo -e "  ${BOLD}Connect later:${RESET}"
echo -e "  ${CYAN}  chmod 400 server_login.pem && ssh -i server_login.pem root@YOUR_IP${RESET}"
echo ""
read -rp "  Have you saved the PEM key? Press Enter to continue... " _SAVED

# ============================================================
#  PHASE 3 — DEPLOY WIZARD
# ============================================================
section "Phase 3 — Git SSH Key + Code Deploy"

echo -e "  ${YELLOW}Add this public key to your Git provider:${RESET}"
echo -e "  ${DIM}GitHub → Settings → SSH and GPG keys → New SSH key${RESET}"
echo -e "  ${DIM}GitLab → Preferences → SSH Keys → Add new key${RESET}\n"
if [[ -f "${GIT_KEY}.pub" ]]; then
  echo -e "${BOLD}${CYAN}  $(cat "${GIT_KEY}.pub")${RESET}\n"
else
  warn "Git public key not found at ${GIT_KEY}.pub"
fi

echo -e "  ${BOLD}Once added, press Enter to test the connection...${RESET}"
read -rp "" _WAIT

info "Testing Git SSH connection..."
SSH_TEST=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
  -T git@github.com 2>&1 || true)
if echo "$SSH_TEST" | grep -qi "successfully authenticated\|Welcome to GitLab"; then
  success "Git SSH connection verified!"
else
  warn "Auto-verify inconclusive — output: $SSH_TEST"
  echo -e "  Test manually: ${CYAN}ssh -T git@github.com${RESET}"
  read -rp "  Continue anyway? [Y/n]: " CONT
  [[ "${CONT:-y}" =~ ^[Nn]$ ]] && exit 0
fi

# ── Clone + npm install per folder ──────────────────────────
DEPLOY_LOG=()

if [[ ${#SELECTED_FOLDERS[@]} -eq 0 ]]; then
  warn "No folders selected — skipping deploy."
else
  echo -e "\n  ${DIM}Leave URL blank to skip a folder.${RESET}\n"

  declare -A FOLDER_REMOTE
  declare -A FOLDER_NPM

  for FOLDER in "${SELECTED_FOLDERS[@]}"; do
    divider
    echo -e "\n  ${BOLD}${CYAN}[$FOLDER]${RESET}  ${DIM}(port ${FOLDER_PORT[$FOLDER]})${RESET}"
    read -rp "  Git remote URL: " REMOTE_URL
    FOLDER_REMOTE["$FOLDER"]="$REMOTE_URL"
    if [[ -n "$REMOTE_URL" ]]; then
      read -rp "  Run npm install --force? [y/N]: " RUN_NPM
      FOLDER_NPM["$FOLDER"]="${RUN_NPM:-n}"
    fi
  done

  echo ""
  divider
  echo -e "\n${BOLD}${GREEN}  Cloning repositories...${RESET}\n"

  export NVM_DIR="/root/.nvm"
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" 2>/dev/null || true

  for FOLDER in "${SELECTED_FOLDERS[@]}"; do
    REMOTE="${FOLDER_REMOTE[$FOLDER]:-}"
    TARGET="$WEB_ROOT/$FOLDER"
    NPM_FLAG="${FOLDER_NPM[$FOLDER]:-n}"

    if [[ -z "$REMOTE" ]]; then
      warn "[$FOLDER] Skipped — no URL"
      DEPLOY_LOG+=("${YELLOW}⚠${RESET}  $FOLDER → skipped")
      continue
    fi

    echo -e "\n  ${BOLD}Deploying $FOLDER...${RESET}"
    rm -f "$TARGET/.gitkeep"

    CLONE_OK=false
    for ATTEMPT in 1 2; do
      if git clone "$REMOTE" "$TARGET" 2>&1 | sed 's/^/     /'; then
        CLONE_OK=true; break
      else
        if [[ $ATTEMPT -eq 1 ]]; then
          warn "Clone failed — enter a different URL or press Enter to skip"
          read -rp "  New URL: " NEW_URL
          if [[ -n "$NEW_URL" ]]; then
            REMOTE="$NEW_URL"
            rm -rf "$TARGET" 2>/dev/null
            mkdir -p "$TARGET"
          else
            break
          fi
        fi
      fi
    done

    if [[ "$CLONE_OK" == true ]]; then
      chown -R www-data:www-data "$TARGET"
      success "[$FOLDER] Cloned successfully"

      if [[ "$NPM_FLAG" =~ ^[Yy]$ ]]; then
        info "[$FOLDER] npm install --force..."
        cd "$TARGET"
        if npm install --force 2>&1 | tail -3 | sed 's/^/     /'; then
          success "[$FOLDER] npm install done"
          DEPLOY_LOG+=("${GREEN}✔${RESET}  $FOLDER → cloned + npm install")
        else
          warn "[$FOLDER] npm install had errors"
          DEPLOY_LOG+=("${YELLOW}⚠${RESET}  $FOLDER → cloned, npm errors")
        fi
        cd - > /dev/null
      else
        DEPLOY_LOG+=("${GREEN}✔${RESET}  $FOLDER → cloned")
      fi
    else
      warn "[$FOLDER] Clone failed — add code manually later"
      DEPLOY_LOG+=("${RED}✘${RESET}  $FOLDER → clone failed")
    fi
  done
fi

# ============================================================
#  FINAL SUMMARY
# ============================================================
clear
echo -e "${BOLD}${GREEN}"
cat <<'DONE'

  ╔══════════════════════════════════════════════════════════╗
  ║        🚀  Server Setup & Deploy Complete!               ║
  ╚══════════════════════════════════════════════════════════╝

DONE
echo -e "${RESET}"

section "Nginx Proxy Map"
if [[ ${#SELECTED_FOLDERS[@]} -gt 0 ]]; then
  echo -e "  ${DIM}http://YOUR_IP/<folder>  →  localhost:<port>${RESET}\n"
  for FOLDER in "${SELECTED_FOLDERS[@]}"; do
    echo -e "  ${GREEN}✔${RESET}  /$FOLDER  →  :${FOLDER_PORT[$FOLDER]}"
    echo -e "       ${DIM}config: /etc/$WEB_SERVER/sites-available/$FOLDER${RESET}"
  done
else
  echo -e "  ${DIM}No proxy configured.${RESET}"
fi

section "phpMyAdmin"
echo -e "  ${BOLD}URL:${RESET}              $PMA_URL"
echo -e "  ${BOLD}Whitelist file:${RESET}   $WHITELIST_FILE\n"
echo -e "  Add a new IP:"
echo -e "  ${CYAN}  echo '1.2.3.4' >> $WHITELIST_FILE && systemctl reload $WEB_SERVER${RESET}"

section "Deploy Results"
if [[ ${#DEPLOY_LOG[@]} -gt 0 ]]; then
  for ENTRY in "${DEPLOY_LOG[@]}"; do echo -e "  $ENTRY"; done
else
  echo -e "  ${DIM}No folders deployed.${RESET}"
fi

section "Server Summary"
echo -e "  ${GREEN}✔${RESET}  Ubuntu          →  $UBUNTU_VERSION"
echo -e "  ${GREEN}✔${RESET}  PHP             →  $PHP_VERSION"
echo -e "  ${GREEN}✔${RESET}  PEM login       →  $PEM_KEY.pem"
echo -e "  ${GREEN}✔${RESET}  Git SSH key     →  $GIT_KEY"
echo -e "  ${GREEN}✔${RESET}  SSH hardened    →  key-only login"
echo -e "  ${GREEN}✔${RESET}  Fail2ban        →  5 attempts → 1hr ban"
[[ "$SWAP_ENABLED" =~ ^[Yy]$ ]] && \
echo -e "  ${GREEN}✔${RESET}  Swap            →  $SWAP_SIZE"
echo -e "  ${GREEN}✔${RESET}  Web server      →  $WEB_SERVER"
echo -e "  ${GREEN}✔${RESET}  Node.js         →  $NODE_VERSION via NVM"
echo -e "  ${GREEN}✔${RESET}  PM2 + Knex      →  installed globally"
[[ ${#SELECTED_FOLDERS[@]} -gt 0 ]] && \
echo -e "  ${GREEN}✔${RESET}  Proxy configs   →  /etc/$WEB_SERVER/sites-available/"
echo -e "  ${GREEN}✔${RESET}  Firewall        →  ${OPENED_PORTS[*]}"
echo -e "  ${GREEN}✔${RESET}  MySQL           →  running"
echo -e "  ${GREEN}✔${RESET}  phpMyAdmin      →  $PMA_URL"
[[ "$SSL_ENABLED" =~ ^[Yy]$ && -n "$DOMAIN" ]] && \
echo -e "  ${GREEN}✔${RESET}  SSL             →  $DOMAIN"
echo -e "  ${GREEN}✔${RESET}  Auto updates    →  enabled"
echo ""
echo -e "  ${BOLD}Manual pull workflow:${RESET}"
echo -e "  ${CYAN}  cd /var/www/html/<folder>${RESET}"
echo -e "  ${CYAN}  git pull && pm2 restart <app-name>${RESET}"
echo ""
echo -e "${BOLD}${MAGENTA}  Happy shipping! 🎉${RESET}\n"
