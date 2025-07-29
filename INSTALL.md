# 🚀 Secret Poll - Installation Guide

## Quick Installation

### Requirements
- Ubuntu/Debian server (18.04+)
- Root access (sudo)
- Domain name or IP address

### One-Command Installation

```bash
sudo python3 install.py
```

### What the installer does:
1. ✅ **System Check** - Verifies requirements and resources
2. ✅ **Dependencies** - Installs Python, Node.js, MongoDB
3. ✅ **Web Server** - Configures Nginx or Apache
4. ✅ **SSL Certificates** - Automatic Let's Encrypt setup
5. ✅ **Application** - Builds and configures Secret Poll
6. ✅ **Services** - Creates systemd services for auto-start
7. ✅ **Security** - Applies security headers and configurations

### Installation Process

The installer will ask you for:

1. **Domain/IP Address**
   ```
   Domain or IP address (e.g., poll.yourdomain.com): your-domain.com
   ```

2. **SSL Certificate** (for domains only)
   ```
   Enable SSL with Let's Encrypt? [Y/n]: Y
   Email for SSL certificates: admin@your-domain.com
   ```

3. **Web Server Choice**
   ```
   Web server options:
   1. Nginx (Recommended)
   2. Apache  
   3. Standalone (No reverse proxy)
   Choose web server [1-3] (default: 1): 1
   ```

4. **Environment Type**
   ```
   Environment [production/staging] (default: production): production
   ```

5. **Installation Directory**
   ```
   Installation directory (default: /opt/secret-poll): /opt/secret-poll
   ```

### After Installation

Your application will be available at:
- **HTTPS**: `https://your-domain.com/`
- **HTTP**: `http://your-domain.com/` (redirects to HTTPS)
- **API**: `https://your-domain.com/api/health`

### Management Commands

```bash
# Check status
/opt/secret-poll/status.sh

# View logs  
/opt/secret-poll/logs.sh

# Restart services
/opt/secret-poll/restart.sh

# Service management
systemctl status secret-poll
systemctl restart secret-poll
```

### File Locations

- **Application**: `/opt/secret-poll/`
- **Configuration**: `/opt/secret-poll/backend/.env` and `/opt/secret-poll/frontend/.env`
- **Logs**: `journalctl -u secret-poll`
- **Web Server Config**: `/etc/nginx/sites-enabled/secret-poll` (Nginx)
- **SSL Certificates**: `/etc/letsencrypt/live/your-domain.com/`

### Troubleshooting

**Application not starting:**
```bash
systemctl status secret-poll
journalctl -u secret-poll -f
```

**Web server issues:**
```bash
nginx -t  # Test configuration
systemctl status nginx
```

**Database issues:**
```bash
systemctl status mongodb
```

**SSL certificate issues:**
```bash
certbot certificates
certbot renew --dry-run
```

### Security

The installer automatically configures:
- ✅ HTTPS with Let's Encrypt
- ✅ Security headers (HSTS, XSS protection, etc.)
- ✅ Firewall rules (if UFW is available)
- ✅ Service isolation with dedicated user
- ✅ Automatic SSL certificate renewal

### Support

- **GitHub**: https://github.com/KiiTuNp/voteapp
- **Issues**: https://github.com/KiiTuNp/voteapp/issues
- **Logs**: Check `/var/log/secret-poll-install.log` for installation logs

---

## Development Installation

For local development:

```bash
# Clone repository
git clone https://github.com/KiiTuNp/voteapp.git
cd voteapp

# Backend
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python server.py

# Frontend (new terminal)
cd frontend
npm install
npm start
```

Access at: http://localhost:3000

---

**Made with ❤️ for secure polling needs**