# Secret Poll - Turnkey Deployment Script

## Overview

The `deploy.sh` script provides a completely automated, foolproof deployment solution for the Secret Poll application. It's designed to work in **ANY** server environment without breaking existing infrastructure.

## Key Features

### 🛡️ Infrastructure Protection
- Comprehensive system compatibility checks
- Automatic detection of existing services (Nginx, Apache, MongoDB, Docker, etc.)
- Port conflict detection and resolution
- Backup and rollback capabilities
- Zero-impact deployment options

### 🚀 Multiple Deployment Strategies
1. **Docker Isolated** - Complete isolation from existing services
2. **Docker Standard** - Optimized Docker deployment
3. **Manual Integration** - Integrates with existing infrastructure  
4. **Portable** - Non-root, user-directory installation
5. **Custom** - Full manual control for advanced users

### 🔧 Smart Configuration
- Interactive configuration wizard
- Automatic SSL certificate generation (Let's Encrypt)
- Multiple database options (new/existing MongoDB)
- Web server integration (Nginx/Apache)
- Firewall and security setup

### 📊 Management Tools
- Status monitoring commands
- Automated backup system
- Health checking
- Update and restart scripts
- Comprehensive logging

## Quick Start

### Prerequisites
- Linux server (Ubuntu/Debian preferred, CentOS/RHEL supported)
- Root access (sudo)
- Internet connection
- Domain name (optional, can use IP address)

### Basic Usage

```bash
# Clone the repository
git clone https://github.com/KiiTuNp/voteapp.git
cd voteapp

# Make the script executable
chmod +x scripts/deploy.sh

# Run the deployment
sudo scripts/deploy.sh
```

The script will:
1. Analyze your system
2. Detect any conflicts
3. Recommend the best deployment strategy
4. Guide you through configuration (with the GitHub repo as default)
5. Deploy the application automatically

## Deployment Strategies Explained

### 1. Docker Isolated (Recommended for servers with existing services)
- Runs in completely isolated Docker containers
- Uses custom ports to avoid conflicts
- Zero impact on existing infrastructure
- Easiest rollback
- Best for production servers with existing services

**When to use:**
- Server already runs web services
- Port conflicts detected
- Want maximum isolation
- Need easy rollback capability

### 2. Docker Standard
- Standard Docker deployment using ports 80/443
- Optimal performance and resource usage
- Industry-standard configuration
- Requires resolving any port conflicts

**When to use:**
- Clean server with no conflicts
- Want optimal performance
- Prefer standard configuration

### 3. Manual Integration
- Integrates with existing Nginx/Apache
- Uses existing MongoDB if available
- Minimal system changes
- Good for environments with established infrastructure

**When to use:**
- Want to use existing web server
- Have existing database setup
- Prefer traditional deployment
- Need fine-grained control

### 4. Portable Installation
- Installs in user directory
- Uses high ports to avoid conflicts
- Minimal system impact
- Good for shared hosting

**When to use:**
- Shared hosting environment
- No root access after initial setup
- Development/testing
- Want minimal system footprint

### 5. Custom Configuration
- Complete manual control
- Advanced users only
- Configure every aspect
- Maximum flexibility

**When to use:**
- Have specific requirements
- Need non-standard configuration
- Experienced system administrator
- Complex environment

## Configuration Options

### Domain Setup
- Domain name or IP address
- Optional WWW subdomain
- SSL certificate generation
- Multi-domain support

### SSL Configuration
- Automatic Let's Encrypt certificates
- Existing certificate integration
- Self-signed certificates
- HTTP-only deployment

### Database Options
- New MongoDB installation
- Existing MongoDB integration
- Remote MongoDB connection
- Docker MongoDB container

### Security Features
- Firewall configuration
- Rate limiting
- Security headers
- Fail2ban integration (optional)

## Management Commands

After deployment, you'll have access to these management commands:

```bash
# Check application status
secret-poll-status

# Restart the application
secret-poll-restart

# Stop the application
secret-poll-stop

# View logs
secret-poll-logs

# Update the application
secret-poll-update

# Create backup
secret-poll-backup
```

## Conflict Resolution

The script automatically detects and resolves common conflicts:

### Port Conflicts
- **Port 80/443**: Offers alternative ports or integration options
- **Port 8001**: Automatically finds available port
- **Port 27017**: Option to use existing MongoDB or different port

### Service Conflicts
- **Nginx/Apache**: Integration or isolation options
- **MongoDB**: Use existing or install new instance
- **Docker**: Use existing or install fresh

### Resolution Options
1. **Use different ports** - Automatic port assignment
2. **Service integration** - Configure virtual hosts/proxies
3. **Service isolation** - Docker containers with custom networks
4. **Stop conflicting services** - With user confirmation
5. **Skip conflicting features** - Disable features that conflict

## Rollback and Recovery

### Automatic Backup
- System configuration backup before deployment
- Application state backup
- Automatic rollback script generation

### Rollback Process
```bash
# Automatic rollback
/opt/secret-poll-rollback/rollback.sh

# Manual rollback steps are documented in the backup directory
```

### Recovery Options
- Complete system restore
- Selective service restoration
- Configuration-only rollback
- Data preservation options

## System Requirements

### Minimum Requirements
- 1GB RAM
- 2GB free disk space
- Linux kernel 3.10+
- Internet connectivity

### Recommended Requirements
- 2GB+ RAM
- 5GB+ free disk space
- Modern Linux distribution
- Dedicated IP/domain

### Supported Operating Systems
- **Fully Supported**: Ubuntu 18.04+, Debian 9+
- **Supported**: CentOS 7+, RHEL 7+, Fedora 30+
- **Experimental**: Other Linux distributions

## Troubleshooting

### Common Issues

#### Permission Errors
```bash
# Ensure running as root
sudo ./deploy.sh
```

#### Port Conflicts
The script automatically detects and resolves port conflicts. Choose the isolation option if you want zero impact on existing services.

#### SSL Certificate Issues
```bash
# Check domain DNS
dig yourdomain.com

# Verify firewall allows port 80
ufw status
```

#### Docker Issues
```bash
# Check Docker status
docker info

# Restart Docker
sudo systemctl restart docker
```

### Getting Help

1. **Check the status**: `secret-poll-status`
2. **View logs**: `secret-poll-logs`
3. **Check deployment log**: `/var/log/secret-poll-deploy.log`
4. **Use rollback**: `/opt/secret-poll-rollback/rollback.sh`

### Log Locations
- **Deployment log**: `/var/log/secret-poll-deploy.log`
- **Application logs**: `/var/log/secret-poll/`
- **System logs**: `journalctl -u nginx` (or relevant service)

## Advanced Configuration

### Custom Environment Variables
Edit the generated `.env` files in the application directory:
- `backend/.env` - Backend configuration
- `frontend/.env` - Frontend configuration

### Custom Nginx Configuration
For Docker deployments, edit `nginx.conf` in the application directory.

For manual deployments, edit `/etc/nginx/sites-available/secret-poll`.

### Resource Limits
Docker deployments include automatic resource limits. Adjust in the `docker-compose.yml` file if needed.

### Monitoring Setup
The script creates basic monitoring tools. For advanced monitoring, integrate with:
- Prometheus + Grafana
- ELK Stack
- Custom monitoring solutions

## Security Considerations

### Default Security Features
- HTTPS/SSL encryption
- Security headers
- Rate limiting
- Firewall configuration
- Non-root container execution

### Additional Security Recommendations
- Regular system updates
- Strong database passwords
- VPN access for administration
- Regular security audits
- Backup encryption

## Performance Optimization

### Docker Deployments
- Resource limits are pre-configured
- Use SSD storage for better performance
- Consider Docker Swarm for scaling

### Manual Deployments
- PM2 clustering is enabled
- Nginx optimization included
- Database indexing recommended

### Monitoring Performance
```bash
# System resources
secret-poll-status

# Application metrics
curl https://yourdomain.com/api/health

# Docker stats (if applicable)
docker stats
```

## Backup and Disaster Recovery

### Automated Backups
- Database dumps
- Configuration backups
- Application state backups
- Automatic retention (7 days default)

### Manual Backup
```bash
secret-poll-backup
```

### Disaster Recovery Plan
1. Stop the application
2. Restore from backup
3. Update DNS if needed
4. Start the application
5. Verify functionality

## Support and Contributing

### Getting Support
- Check the main README.md
- Review deployment logs
- Use the management commands
- Create system status reports

### Contributing
This deployment script is part of the Secret Poll project. Contributions welcome!

---

## Quick Reference

### Essential Commands
```bash
# Deploy
sudo ./deploy.sh

# Status
secret-poll-status

# Restart
secret-poll-restart

# Backup
secret-poll-backup

# Rollback
/opt/secret-poll-rollback/rollback.sh
```

### Important Paths
- **Application**: `/opt/secret-poll/`
- **Logs**: `/var/log/secret-poll-deploy.log`
- **Backups**: `/opt/secret-poll-backups/`
- **Rollback**: `/opt/secret-poll-rollback/`

---

**Secret Poll Deployment Script** - Foolproof deployment that works everywhere! 🚀