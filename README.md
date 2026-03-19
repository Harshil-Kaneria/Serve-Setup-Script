# 🚀 Ubuntu Server Setup Script

One command. Answer 8 questions. Grab a coffee. Server is production-ready.

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/YOUR_USERNAME/YOUR_REPO@main/setup.sh \
  -o setup.sh && chmod +x setup.sh && sudo bash setup.sh
```

> Replace `YOUR_USERNAME/YOUR_REPO` with your actual GitHub username and repo name.

---

## ⚠️ Built for this stack — wrong tool for anything else

This script is **opinionated**. It's built specifically for:

| Layer | Tech |
|-------|------|
| **Runtime** | Node.js (via NVM) |
| **Framework** | Express / Fastify / any Node HTTP server |
| **Database** | MySQL |
| **ORM / Migrations** | Knex.js |
| **Process manager** | PM2 |
| **Web server** | Nginx (recommended) or Apache |
| **OS** | Ubuntu 20.04 / 22.04 / 24.04 |

**Not for you if you're using:**
- 🦀 Rust / Go / Python / PHP / Java backends
- 🐘 PostgreSQL or MongoDB
- 🐳 Docker / Kubernetes setups
- 🪟 Anything that isn't Ubuntu Linux

---

## Compatibility

| Ubuntu | Status |
|--------|--------|
| 20.04 LTS | ✅ Supported |
| 22.04 LTS | ✅ Supported |
| 24.04 LTS | ✅ Supported — phpMyAdmin installs via direct download (removed from apt on 24+) |

---

## How it works — 3 phases

### Phase 1 — Questions upfront (~5 min)
Everything asked now. Zero interruptions after you confirm.

| # | Question | Default |
|---|----------|---------|
| 1 | Enable swap? How much? | No |
| 2 | Which folders to create + port for each? | None |
| 3 | Web server — Apache or Nginx? | Nginx |
| 4 | Node.js version | `20.19.4` |
| 5 | MySQL root password | — |
| 6 | Extra IPs for phpMyAdmin whitelist | Your current IP only |
| 7 | Enable SSL? Domain + email? | No |
| 8 | Git provider — GitHub / GitLab / Both? | GitHub |

---

### Phase 2 — Fully automated ☕ (~10 min)

| Step | What happens |
|------|-------------|
| Base packages | curl, wget, ufw, fail2ban, git, openssl |
| PHP | Auto-installs, detects exact version, builds correct FPM socket path |
| PEM keypair | Generated for server SSH login — shown once at end, save it |
| SSH hardening | Password login disabled, key-only enforced in `sshd_config` |
| Git SSH key | Separate `ed25519` key for Git only, wired into `~/.ssh/config` |
| Fail2ban | 5 failed SSH attempts → 1hr ban |
| Swap | Optional — created with `swappiness=10` |
| Web server | Apache or Nginx — installed, enabled, started |
| NVM + Node.js | Installed globally, persisted in `/etc/profile.d/nvm.sh` |
| PM2 + Knex | Installed globally via npm, PM2 auto-start on reboot configured |
| Project folders | Created in `/var/www/html/{folder}` with correct permissions |
| Nginx reverse proxy | Auto-config per folder → port you assigned |
| UFW firewall | Opens 22, 80, 443, 8080, + each folder's custom port |
| MySQL | Installed, root password set |
| phpMyAdmin | Installed, IP-whitelisted, Ubuntu version-aware |
| SSL | Optional — Certbot + Let's Encrypt |
| Auto updates | `unattended-upgrades` for security patches |

---

### Phase 3 — Deploy wizard (~3 min)

1. Displays your **Git SSH public key** — pauses while you add it to GitHub/GitLab
2. Auto-tests the SSH connection (`ssh -T git@github.com`)
3. For **each folder**, asks:
   - Git remote URL (blank = skip)
   - Run `npm install --force`? `[y/N]`
4. Clones repos + runs npm install automatically
5. If a clone fails — asks for a corrected URL (no silent skipping)
6. Final summary shows status per folder: ✔ cloned / ⚠ warnings / ✘ failed

---

## Nginx reverse proxy

Each folder gets its own Nginx site config generated automatically:

```
http://YOUR_IP/frontend/  →  localhost:3000
http://YOUR_IP/backend/   →  localhost:3001
http://YOUR_IP/admin/     →  localhost:8000
http://YOUR_IP/ai/        →  localhost:8001
```

Ports are whatever you set during Phase 1 questions.

Config files: `/etc/nginx/sites-available/<folder>`

To edit and apply:
```bash
nano /etc/nginx/sites-available/backend
nginx -t && systemctl reload nginx
```

---

## Two SSH keys — two purposes

| Key | Used for | Path |
|-----|----------|------|
| `server_login.pem` | SSH into server | `/root/.ssh/server_login.pem` |
| `id_ed25519_git` | Git clone / pull only | `/root/.ssh/id_ed25519_git` |

The Git key is scoped to `github.com` / `gitlab.com` only via `~/.ssh/config`.
Server login never uses the Git key, and vice versa.

**Connect to server:**
```bash
chmod 400 server_login.pem
ssh -i server_login.pem root@YOUR_IP
```

---

## phpMyAdmin IP whitelist

phpMyAdmin is **blocked to everyone** except IPs in:
```
/etc/phpmyadmin-allowed-ips.conf
```

Your IP at setup time is added automatically.

**Add a new IP:**
```bash
echo '1.2.3.4' >> /etc/phpmyadmin-allowed-ips.conf
systemctl reload nginx    # or apache2
```

**Access:**
- Nginx → `http://YOUR_IP:8080`
- Apache → `http://YOUR_IP/phpmyadmin`

---

## After the script — per-project steps (~10 min each)

The script handles everything at the server level. Per-project config is yours:

```bash
cd /var/www/html/backend

# 1. Environment (or use AWS Secrets Manager / Vault / whatever you prefer)
cp .env.example .env
nano .env

# 2. Database migrations
npx knex migrate:latest

# 3. Seeders (if needed)
npx knex seed:run

# 4. Start with PM2
pm2 start ecosystem.config.js
pm2 save
```

**Deploy updates (manual pull):**
```bash
cd /var/www/html/backend
git pull
pm2 restart <app-name>
```

---

## Full timeline

| Phase | Who | Time |
|-------|-----|------|
| Answer 8 questions | You | ~5 min |
| Automated server setup | Script ☕ | ~10 min |
| Add SSH key to Git + enter repo URLs | You | ~3 min |
| Clone repos + npm install | Script | ~2–5 min |
| Per-project: env + migrate + PM2 | You | ~10 min/project |
| **Total (1 project)** | | **~30–40 min** |

---

## Ports opened

| Port | Purpose |
|------|---------|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |
| 8080 | phpMyAdmin (Nginx only) |
| Custom | One per folder — set during setup |

---

## Push to GitHub

```bash
git init
git add setup.sh README.md
git commit -m "init: ubuntu server setup"
git branch -M main
git remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

---

> Because life's too short to type `apt install` 14 times.
> Run the script. Go watch a movie. Server's ready by the time the popcorn is. 🍿

---

## License

MIT — use it, fork it, share it.
