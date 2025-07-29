#!/bin/bash

# =============================================================================
# Secret Poll - Interactive Deployment Script
# =============================================================================
# This script automates the complete deployment of the Secret Poll application
# on any Linux server with a single command.
#
# Usage: ./deploy.sh
# 
# Features:
# - Automatic system preparation
# - Interactive configuration
# - Docker or manual deployment options
# - SSL certificate setup
# - Production-ready configuration
# - Comprehensive error handling
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/opt/secret-poll"
LOG_FILE="/var/log/secret-poll-deploy.log"
DOCKER_COMPOSE_VERSION="v2.20.0"
NODE_VERSION="18"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

print_header() {
    echo -e "${PURPLE}"
    echo "============================================================================="
    echo "$1"
    echo "============================================================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_action() {
    echo "$(date): $1" >> "$LOG_FILE"
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$default" == "y" ]]; then
        echo -e "${YELLOW}$message [Y/n]:${NC} "
    else
        echo -e "${YELLOW}$message [y/N]:${NC} "
    fi
    
    read -r response
    response=${response:-$default}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local secret="$3"
    local value
    
    if [[ "$secret" == "true" ]]; then
        echo -e "${CYAN}$prompt${NC}"
        if [[ -n "$default" ]]; then
            echo -e "${YELLOW}(default: $default)${NC}"
        fi
        echo -n "> "
        read -s value
        echo
    else
        if [[ -n "$default" ]]; then
            echo -e "${CYAN}$prompt${NC} ${YELLOW}(default: $default)${NC}"
        else
            echo -e "${CYAN}$prompt${NC}"
        fi
        echo -n "> "
        read -r value
    fi
    
    echo "${value:-$default}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root. Please run with sudo."
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS. This script supports Ubuntu/Debian systems."
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        print_warning "This script is optimized for Ubuntu/Debian. Proceeding anyway..."
    fi
    
    print_info "Detected OS: $PRETTY_NAME"
}

# =============================================================================
# SYSTEM PREPARATION
# =============================================================================

update_system() {
    print_step "Updating system packages..."
    apt-get update -y >> "$LOG_FILE" 2>&1
    apt-get upgrade -y >> "$LOG_FILE" 2>&1
    apt-get install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release >> "$LOG_FILE" 2>&1
    print_success "System updated successfully"
}

install_docker() {
    print_step "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc >> "$LOG_FILE" 2>&1 || true
    
    # Install Docker
    curl -fsSL https://get.docker.com | sh >> "$LOG_FILE" 2>&1
    systemctl enable docker >> "$LOG_FILE" 2>&1
    systemctl start docker >> "$LOG_FILE" 2>&1
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose >> "$LOG_FILE" 2>&1
    chmod +x /usr/local/bin/docker-compose
    
    # Add current user to docker group if not root
    if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER"
    fi
    
    print_success "Docker installed successfully"
    docker --version
    docker-compose --version
}

install_manual_dependencies() {
    print_step "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - >> "$LOG_FILE" 2>&1
    apt-get install -y nodejs >> "$LOG_FILE" 2>&1
    
    print_step "Installing Python and dependencies..."
    apt-get install -y python3 python3-pip python3-venv python3-dev build-essential >> "$LOG_FILE" 2>&1
    
    print_step "Installing MongoDB..."
    wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - >> "$LOG_FILE" 2>&1
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list >> "$LOG_FILE" 2>&1
    apt-get update >> "$LOG_FILE" 2>&1
    apt-get install -y mongodb-org >> "$LOG_FILE" 2>&1
    systemctl enable mongod
    systemctl start mongod
    
    print_step "Installing Nginx..."
    apt-get install -y nginx >> "$LOG_FILE" 2>&1
    systemctl enable nginx
    
    print_step "Installing PM2..."
    npm install -g pm2 >> "$LOG_FILE" 2>&1
    
    print_success "Manual dependencies installed successfully"
}

setup_firewall() {
    print_step "Configuring firewall..."
    
    # Install ufw if not present
    apt-get install -y ufw >> "$LOG_FILE" 2>&1
    
    # Reset firewall rules
    ufw --force reset >> "$LOG_FILE" 2>&1
    
    # Set default policies
    ufw default deny incoming >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1
    
    # Allow essential services
    ufw allow 22/tcp >> "$LOG_FILE" 2>&1  # SSH
    ufw allow 80/tcp >> "$LOG_FILE" 2>&1  # HTTP
    ufw allow 443/tcp >> "$LOG_FILE" 2>&1 # HTTPS
    
    # Enable firewall
    ufw --force enable >> "$LOG_FILE" 2>&1
    
    print_success "Firewall configured successfully"
}

# =============================================================================
# CONFIGURATION
# =============================================================================

collect_configuration() {
    print_header "CONFIGURATION SETUP"
    
    echo -e "${CYAN}Please provide the following configuration details:${NC}\n"
    
    # Deployment method
    echo -e "${YELLOW}Choose deployment method:${NC}"
    echo "1) Docker (Recommended - Easier and more reliable)"
    echo "2) Manual (Direct installation on server)"
    echo
    DEPLOYMENT_METHOD=$(prompt_input "Enter your choice (1 or 2)" "1")
    
    if [[ "$DEPLOYMENT_METHOD" == "1" ]]; then
        DEPLOYMENT_TYPE="docker"
        print_info "Selected: Docker deployment"
    else
        DEPLOYMENT_TYPE="manual"
        print_info "Selected: Manual deployment"
    fi
    
    echo
    
    # Domain configuration
    DOMAIN=$(prompt_input "Enter your domain name (e.g., poll.yourdomain.com)" "")
    while [[ -z "$DOMAIN" ]]; do
        print_error "Domain name is required!"
        DOMAIN=$(prompt_input "Enter your domain name (e.g., poll.yourdomain.com)" "")
    done
    
    WWW_DOMAIN="www.$DOMAIN"
    USE_WWW=$(confirm_action "Include www.$DOMAIN? (Recommended)" "y")
    
    # SSL Configuration
    echo
    USE_SSL=$(confirm_action "Set up SSL certificate with Let's Encrypt? (Recommended for production)" "y")
    
    if [[ "$USE_SSL" == true ]]; then
        ADMIN_EMAIL=$(prompt_input "Enter email for SSL certificate notifications" "")
        while [[ -z "$ADMIN_EMAIL" || ! "$ADMIN_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
            print_error "Valid email address is required for SSL setup!"
            ADMIN_EMAIL=$(prompt_input "Enter email for SSL certificate notifications" "")
        done
    fi
    
    # Database configuration
    echo
    if [[ "$DEPLOYMENT_TYPE" == "manual" ]]; then
        DB_NAME=$(prompt_input "MongoDB database name" "poll_app")
        DB_HOST=$(prompt_input "MongoDB host" "localhost")
        DB_PORT=$(prompt_input "MongoDB port" "27017")
        MONGO_URL="mongodb://${DB_HOST}:${DB_PORT}/${DB_NAME}"
    else
        DB_NAME="poll_app"
        MONGO_URL="mongodb://mongodb:27017/${DB_NAME}"
    fi
    
    # Application configuration
    echo
    APP_PORT=$(prompt_input "Backend application port" "8001")
    FRONTEND_PORT=$(prompt_input "Frontend application port (only for manual deployment)" "3000")
    
    # Repository configuration
    echo
    DEFAULT_REPO="https://github.com/KiiTuNp/voteapp.git"
    REPO_URL=$(prompt_input "Git repository URL" "$DEFAULT_REPO")
    
    if [[ -n "$REPO_URL" ]]; then
        DEPLOY_BRANCH=$(prompt_input "Git branch to deploy" "main")
    fi
    
    # Resource limits (for Docker)
    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        echo
        MEMORY_LIMIT=$(prompt_input "Memory limit for containers (e.g., 512m, 1g)" "1g")
        CPU_LIMIT=$(prompt_input "CPU limit for containers (e.g., 0.5, 1.0)" "1.0")
    fi
    
    # Environment
    echo
    ENVIRONMENT=$(prompt_input "Environment (production/staging/development)" "production")
    
    # Summary
    echo
    print_header "CONFIGURATION SUMMARY"
    echo -e "${CYAN}Deployment Type:${NC} $DEPLOYMENT_TYPE"
    echo -e "${CYAN}Domain:${NC} $DOMAIN"
    if [[ "$USE_WWW" == true ]]; then
        echo -e "${CYAN}WWW Domain:${NC} $WWW_DOMAIN"
    fi
    echo -e "${CYAN}SSL Enabled:${NC} $USE_SSL"
    if [[ "$USE_SSL" == true ]]; then
        echo -e "${CYAN}Admin Email:${NC} $ADMIN_EMAIL"
    fi
    echo -e "${CYAN}Database:${NC} $MONGO_URL"
    echo -e "${CYAN}Backend Port:${NC} $APP_PORT"
    if [[ "$DEPLOYMENT_TYPE" == "manual" ]]; then
        echo -e "${CYAN}Frontend Port:${NC} $FRONTEND_PORT"
    fi
    echo -e "${CYAN}Environment:${NC} $ENVIRONMENT"
    
    echo
    if ! confirm_action "Proceed with this configuration?" "y"; then
        print_info "Configuration cancelled. Exiting..."
        exit 0
    fi
}

# =============================================================================
# APPLICATION DEPLOYMENT
# =============================================================================

prepare_application_directory() {
    print_step "Preparing application directory..."
    
    # Create application directory
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Clone or copy application
    if [[ -n "$REPO_URL" ]]; then
        print_info "Cloning repository from $REPO_URL..."
        if [[ -d ".git" ]]; then
            git fetch origin >> "$LOG_FILE" 2>&1
            git checkout "$DEPLOY_BRANCH" >> "$LOG_FILE" 2>&1
            git pull origin "$DEPLOY_BRANCH" >> "$LOG_FILE" 2>&1
        else
            git clone "$REPO_URL" . >> "$LOG_FILE" 2>&1
            git checkout "$DEPLOY_BRANCH" >> "$LOG_FILE" 2>&1
        fi
    else
        print_info "Copying application from current directory..."
        if [[ "$SCRIPT_DIR" != "$APP_DIR" ]]; then
            cp -r "$SCRIPT_DIR"/* "$APP_DIR/" 2>/dev/null || true
            cp -r "$SCRIPT_DIR"/.[^.]* "$APP_DIR/" 2>/dev/null || true
        fi
    fi
    
    print_success "Application directory prepared"
}

create_environment_files() {
    print_step "Creating environment configuration files..."
    
    # Backend environment
    cat > "$APP_DIR/backend/.env" << EOF
# Database Configuration
MONGO_URL=$MONGO_URL

# CORS Configuration
CORS_ORIGINS=https://$DOMAIN$([ "$USE_WWW" == true ] && echo ",https://$WWW_DOMAIN")

# Application Configuration
PORT=$APP_PORT
ENVIRONMENT=$ENVIRONMENT

# Security
SECRET_KEY=$(openssl rand -hex 32)

# Generated on $(date)
EOF
    
    # Frontend environment
    local backend_url
    if [[ "$USE_SSL" == true ]]; then
        backend_url="https://$DOMAIN"
    else
        backend_url="http://$DOMAIN"
    fi
    
    cat > "$APP_DIR/frontend/.env" << EOF
# Backend Configuration
REACT_APP_BACKEND_URL=$backend_url

# Application Configuration
PORT=$FRONTEND_PORT
GENERATE_SOURCEMAP=false

# Environment
NODE_ENV=$ENVIRONMENT

# Generated on $(date)
EOF
    
    print_success "Environment files created"
}

deploy_with_docker() {
    print_step "Deploying with Docker..."
    
    # Create Docker Compose file
    cat > "$APP_DIR/docker-compose.prod.yml" << EOF
version: '3.8'

services:
  mongodb:
    image: mongo:7.0
    container_name: secret-poll-mongo
    restart: unless-stopped
    environment:
      - MONGO_INITDB_DATABASE=$DB_NAME
    volumes:
      - mongodb_data:/data/db
    networks:
      - app-network
    deploy:
      resources:
        limits:
          memory: 512m
          cpus: '0.5'

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.prod
    container_name: secret-poll-backend
    restart: unless-stopped
    environment:
      - MONGO_URL=$MONGO_URL
      - CORS_ORIGINS=https://$DOMAIN$([ "$USE_WWW" == true ] && echo ",https://$WWW_DOMAIN")
      - PORT=$APP_PORT
      - ENVIRONMENT=$ENVIRONMENT
    depends_on:
      - mongodb
    networks:
      - app-network
    deploy:
      resources:
        limits:
          memory: $MEMORY_LIMIT
          cpus: '$CPU_LIMIT'

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.prod
      args:
        - REACT_APP_BACKEND_URL=$([ "$USE_SSL" == true ] && echo "https" || echo "http")://$DOMAIN
    container_name: secret-poll-frontend
    restart: unless-stopped
    depends_on:
      - backend
    networks:
      - app-network
    deploy:
      resources:
        limits:
          memory: 256m
          cpus: '0.3'

  nginx:
    image: nginx:alpine
    container_name: secret-poll-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      $([ "$USE_SSL" == true ] && echo '      - "443:443"')
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      $([ "$USE_SSL" == true ] && echo '      - ./ssl:/etc/nginx/ssl:ro')
    depends_on:
      - frontend
      - backend
    networks:
      - app-network
    deploy:
      resources:
        limits:
          memory: 128m
          cpus: '0.2'

volumes:
  mongodb_data:

networks:
  app-network:
    driver: bridge
EOF
    
    # Create production Dockerfiles
    create_docker_files
    
    # Create Nginx configuration
    create_nginx_config
    
    # Build and start containers
    print_info "Building and starting containers..."
    docker-compose -f docker-compose.prod.yml down >> "$LOG_FILE" 2>&1 || true
    docker-compose -f docker-compose.prod.yml up -d --build >> "$LOG_FILE" 2>&1
    
    # Wait for services to start
    print_info "Waiting for services to start..."
    sleep 30
    
    # Check service status
    docker-compose -f docker-compose.prod.yml ps
    
    print_success "Docker deployment completed"
}

create_docker_files() {
    print_step "Creating Docker configuration files..."
    
    # Backend Dockerfile
    cat > "$APP_DIR/backend/Dockerfile.prod" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user
RUN useradd -m -u 1000 app && chown -R app:app /app
USER app

# Expose port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8001/api/health || exit 1

# Start application
CMD ["python", "server.py"]
EOF
    
    # Frontend Dockerfile
    cat > "$APP_DIR/frontend/Dockerfile.prod" << 'EOF'
# Build stage
FROM node:18-alpine as build

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci --only=production

# Copy source code and build
COPY . .
ARG REACT_APP_BACKEND_URL
ENV REACT_APP_BACKEND_URL=$REACT_APP_BACKEND_URL
ENV NODE_ENV=production
ENV GENERATE_SOURCEMAP=false
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built files
COPY --from=build /app/build /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
EOF
    
    # Frontend Nginx config
    cat > "$APP_DIR/frontend/nginx.conf" << 'EOF'
server {
    listen 80;
    server_name localhost;
    
    root /usr/share/nginx/html;
    index index.html;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/javascript application/javascript application/json;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Handle React Router
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # Cache static assets
    location /static/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    print_success "Docker files created"
}

deploy_manually() {
    print_step "Deploying manually..."
    
    # Install application dependencies
    print_info "Installing backend dependencies..."
    cd "$APP_DIR/backend"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt >> "$LOG_FILE" 2>&1
    
    print_info "Installing frontend dependencies..."
    cd "$APP_DIR/frontend"
    npm install >> "$LOG_FILE" 2>&1
    npm run build >> "$LOG_FILE" 2>&1
    
    # Create PM2 ecosystem file
    create_pm2_config
    
    # Configure Nginx
    create_nginx_config
    configure_nginx_manual
    
    # Start services
    print_info "Starting services with PM2..."
    cd "$APP_DIR"
    sudo -u ${SUDO_USER:-$USER} pm2 start ecosystem.config.js >> "$LOG_FILE" 2>&1
    sudo -u ${SUDO_USER:-$USER} pm2 save >> "$LOG_FILE" 2>&1
    
    # Setup PM2 startup
    env_path=$(sudo -u ${SUDO_USER:-$USER} pm2 startup | grep -o 'sudo.*')
    eval "$env_path" >> "$LOG_FILE" 2>&1
    
    print_success "Manual deployment completed"
}

create_pm2_config() {
    cat > "$APP_DIR/ecosystem.config.js" << EOF
module.exports = {
  apps: [
    {
      name: 'secret-poll-backend',
      cwd: '$APP_DIR/backend',
      script: 'server.py',
      interpreter: '$APP_DIR/backend/venv/bin/python',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        NODE_ENV: '$ENVIRONMENT',
        PORT: '$APP_PORT'
      },
      error_file: '/var/log/pm2/secret-poll-backend-error.log',
      out_file: '/var/log/pm2/secret-poll-backend-out.log',
      log_file: '/var/log/pm2/secret-poll-backend.log',
      max_memory_restart: '$MEMORY_LIMIT'
    }
  ]
};
EOF
}

create_nginx_config() {
    print_step "Creating Nginx configuration..."
    
    local server_name="$DOMAIN"
    if [[ "$USE_WWW" == true ]]; then
        server_name="$DOMAIN $WWW_DOMAIN"
    fi
    
    cat > "$APP_DIR/nginx.conf" << EOF
events {
    worker_connections 1024;
}

http {
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/javascript application/javascript application/json;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=100r/m;
    limit_req_zone \$binary_remote_addr zone=general:10m rate=200r/m;
    
    # Upstream servers
    upstream backend {
        $([ "$DEPLOYMENT_TYPE" == "docker" ] && echo "server backend:$APP_PORT;" || echo "server localhost:$APP_PORT;")
    }
    
    upstream frontend {
        $([ "$DEPLOYMENT_TYPE" == "docker" ] && echo "server frontend:80;" || echo "server localhost:$FRONTEND_PORT;")
    }
    
    # HTTP server
    server {
        listen 80;
        server_name $server_name;
        
        $(if [[ "$USE_SSL" == true ]]; then echo "
        # Redirect HTTP to HTTPS
        return 301 https://\$server_name\$request_uri;
    }
    
    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name $server_name;
        
        # SSL configuration
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        
        # Modern SSL configuration
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        
        # HSTS
        add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;"
        fi)
        
        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy strict-origin-when-cross-origin;
        
        # API routes
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://backend;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
        }
        
        # Frontend routes
        location / {
            limit_req zone=general burst=50 nodelay;
            $(if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
                echo "proxy_pass http://frontend;"
                echo "            proxy_set_header Host \$host;"
                echo "            proxy_set_header X-Real-IP \$remote_addr;"
                echo "            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
                echo "            proxy_set_header X-Forwarded-Proto \$scheme;"
            else
                echo "root $APP_DIR/frontend/build;"
                echo "            index index.html;"
                echo "            try_files \$uri \$uri/ /index.html;"
                echo "            "
                echo "            # Cache static assets"
                echo "            location /static/ {"
                echo "                expires 1y;"
                echo "                add_header Cache-Control \"public, immutable\";"
                echo "            }"
            fi)
        }
    }
}
EOF
    
    print_success "Nginx configuration created"
}

configure_nginx_manual() {
    print_step "Configuring Nginx for manual deployment..."
    
    # Copy configuration
    cp "$APP_DIR/nginx.conf" /etc/nginx/nginx.conf
    
    # Test configuration
    nginx -t >> "$LOG_FILE" 2>&1
    
    # Restart Nginx
    systemctl restart nginx >> "$LOG_FILE" 2>&1
    
    print_success "Nginx configured and restarted"
}

# =============================================================================
# SSL CERTIFICATE SETUP
# =============================================================================

setup_ssl() {
    if [[ "$USE_SSL" != true ]]; then
        return 0
    fi
    
    print_step "Setting up SSL certificate with Let's Encrypt..."
    
    # Install Certbot
    apt-get install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1
    
    # Stop services temporarily for certificate generation
    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        docker-compose -f "$APP_DIR/docker-compose.prod.yml" stop nginx >> "$LOG_FILE" 2>&1
    else
        systemctl stop nginx >> "$LOG_FILE" 2>&1
    fi
    
    # Generate certificate
    local domain_args="-d $DOMAIN"
    if [[ "$USE_WWW" == true ]]; then
        domain_args="$domain_args -d $WWW_DOMAIN"
    fi
    
    print_info "Generating SSL certificate for $DOMAIN..."
    certbot certonly --standalone --non-interactive --agree-tos --email "$ADMIN_EMAIL" $domain_args >> "$LOG_FILE" 2>&1
    
    if [[ $? -eq 0 ]]; then
        print_success "SSL certificate generated successfully"
        
        # Copy certificates to application directory
        mkdir -p "$APP_DIR/ssl"
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$APP_DIR/ssl/"
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$APP_DIR/ssl/"
        
        # Set proper permissions
        chmod 644 "$APP_DIR/ssl/fullchain.pem"
        chmod 600 "$APP_DIR/ssl/privkey.pem"
        
        # Setup auto-renewal
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
        
    else
        print_error "SSL certificate generation failed. Continuing without SSL..."
        USE_SSL=false
    fi
    
    # Restart services
    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        docker-compose -f "$APP_DIR/docker-compose.prod.yml" up -d nginx >> "$LOG_FILE" 2>&1
    else
        systemctl start nginx >> "$LOG_FILE" 2>&1
    fi
}

# =============================================================================
# HEALTH CHECKS AND VERIFICATION
# =============================================================================

verify_deployment() {
    print_step "Verifying deployment..."
    
    # Wait for services to be ready
    print_info "Waiting for services to start..."
    sleep 30
    
    # Check if services are running
    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        cd "$APP_DIR"
        docker-compose -f docker-compose.prod.yml ps
        
        # Check health
        local backend_healthy=false
        local frontend_healthy=false
        
        for i in {1..12}; do
            if docker-compose -f docker-compose.prod.yml exec -T backend curl -f http://localhost:$APP_PORT/api/health >> "$LOG_FILE" 2>&1; then
                backend_healthy=true
                break
            fi
            print_info "Waiting for backend to be healthy... ($i/12)"
            sleep 10
        done
        
        for i in {1..6}; do
            if docker-compose -f docker-compose.prod.yml exec -T nginx wget --no-verbose --tries=1 --spider http://localhost:80/ >> "$LOG_FILE" 2>&1; then
                frontend_healthy=true
                break
            fi
            print_info "Waiting for frontend to be healthy... ($i/6)"
            sleep 5
        done
        
        if [[ "$backend_healthy" == true && "$frontend_healthy" == true ]]; then
            print_success "All Docker services are healthy"
        else
            print_warning "Some services may not be healthy. Check logs for details."
        fi
        
    else
        # Check PM2 processes
        if pm2 list | grep -q "secret-poll-backend.*online"; then
            print_success "Backend service is running"
        else
            print_error "Backend service is not running properly"
        fi
        
        # Check Nginx
        if systemctl is-active --quiet nginx; then
            print_success "Nginx is running"
        else
            print_error "Nginx is not running properly"
        fi
        
        # Check MongoDB
        if systemctl is-active --quiet mongod; then
            print_success "MongoDB is running"
        else
            print_error "MongoDB is not running properly"
        fi
    fi
    
    # Test HTTP/HTTPS endpoints
    print_info "Testing application endpoints..."
    
    local protocol="http"
    if [[ "$USE_SSL" == true ]]; then
        protocol="https"
    fi
    
    local base_url="$protocol://$DOMAIN"
    
    # Test health endpoint
    if curl -f -s "$base_url/api/health" >> "$LOG_FILE" 2>&1; then
        print_success "API health check passed"
    else
        print_warning "API health check failed. The application might still be starting up."
    fi
    
    # Test frontend
    if curl -f -s "$base_url/" | grep -q "Secret Poll" >> "$LOG_FILE" 2>&1; then
        print_success "Frontend is accessible"
    else
        print_warning "Frontend might not be fully ready yet"
    fi
}

# =============================================================================
# POST-DEPLOYMENT SETUP
# =============================================================================

setup_monitoring() {
    print_step "Setting up basic monitoring..."
    
    # Create log directory
    mkdir -p /var/log/secret-poll
    
    # Setup log rotation
    cat > /etc/logrotate.d/secret-poll << EOF
/var/log/secret-poll/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}
EOF
    
    # Create monitoring script
    cat > /usr/local/bin/secret-poll-status << 'EOF'
#!/bin/bash

echo "=== Secret Poll System Status ==="
echo "Date: $(date)"
echo

if command -v docker-compose &> /dev/null && [[ -f /opt/secret-poll/docker-compose.prod.yml ]]; then
    echo "=== Docker Services ==="
    cd /opt/secret-poll
    docker-compose -f docker-compose.prod.yml ps
    echo
else
    echo "=== System Services ==="
    systemctl status nginx --no-pager -l
    systemctl status mongod --no-pager -l
    pm2 status
    echo
fi

echo "=== Disk Usage ==="
df -h
echo

echo "=== Memory Usage ==="
free -h
echo

echo "=== Network Connections ==="
netstat -tulpn | grep -E ":(80|443|8001|27017)"
EOF
    
    chmod +x /usr/local/bin/secret-poll-status
    
    print_success "Monitoring setup completed"
}

create_management_scripts() {
    print_step "Creating management scripts..."
    
    # Update script
    cat > /usr/local/bin/secret-poll-update << EOF
#!/bin/bash
set -e

echo "Updating Secret Poll application..."

cd $APP_DIR

if [[ -n "$REPO_URL" ]]; then
    git fetch origin
    git checkout $DEPLOY_BRANCH
    git pull origin $DEPLOY_BRANCH
fi

if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
    docker-compose -f docker-compose.prod.yml down
    docker-compose -f docker-compose.prod.yml up -d --build
else
    cd backend
    source venv/bin/activate
    pip install -r requirements.txt
    cd ../frontend
    npm install
    npm run build
    pm2 restart all
fi

echo "Update completed!"
EOF
    
    # Backup script
    cat > /usr/local/bin/secret-poll-backup << EOF
#!/bin/bash
set -e

BACKUP_DIR="/opt/secret-poll-backups"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/backup_\$TIMESTAMP.tar.gz"

echo "Creating backup..."

mkdir -p "\$BACKUP_DIR"

if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
    # Backup MongoDB data
    docker-compose -f $APP_DIR/docker-compose.prod.yml exec -T mongodb mongodump --archive > "\$BACKUP_DIR/mongodb_\$TIMESTAMP.archive"
else
    # Backup MongoDB data
    mongodump --db $DB_NAME --archive="\$BACKUP_DIR/mongodb_\$TIMESTAMP.archive"
fi

# Backup application configuration
tar -czf "\$BACKUP_FILE" -C $APP_DIR .env backend/.env frontend/.env docker-compose.prod.yml 2>/dev/null || true

echo "Backup created: \$BACKUP_FILE"

# Keep only last 7 backups
find "\$BACKUP_DIR" -name "backup_*.tar.gz" -type f -mtime +7 -delete
find "\$BACKUP_DIR" -name "mongodb_*.archive" -type f -mtime +7 -delete

echo "Backup completed!"
EOF
    
    # Cleanup script
    cat > /usr/local/bin/secret-poll-cleanup << EOF
#!/bin/bash

echo "Cleaning up Secret Poll application..."

if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
    cd $APP_DIR
    docker-compose -f docker-compose.prod.yml down -v
    docker system prune -f
else
    pm2 delete all || true
    systemctl stop nginx
    systemctl stop mongod
fi

# Clean logs
rm -rf /var/log/secret-poll/*
pm2 flush || true

echo "Cleanup completed!"
EOF
    
    chmod +x /usr/local/bin/secret-poll-*
    
    print_success "Management scripts created"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    print_header "SECRET POLL - INTERACTIVE DEPLOYMENT SCRIPT"
    
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    log_action "Deployment script started"
    
    # Pre-flight checks
    print_step "Running pre-flight checks..."
    check_root
    check_os
    
    # Collect configuration
    collect_configuration
    
    # System preparation
    print_header "SYSTEM PREPARATION"
    update_system
    
    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        install_docker
    else
        install_manual_dependencies
    fi
    
    setup_firewall
    
    # Application deployment
    print_header "APPLICATION DEPLOYMENT"
    prepare_application_directory
    create_environment_files
    
    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        deploy_with_docker
    else
        deploy_manually
    fi
    
    # SSL setup
    if [[ "$USE_SSL" == true ]]; then
        print_header "SSL CERTIFICATE SETUP"
        setup_ssl
    fi
    
    # Post-deployment
    print_header "POST-DEPLOYMENT SETUP"
    setup_monitoring
    create_management_scripts
    
    # Verification
    print_header "DEPLOYMENT VERIFICATION"
    verify_deployment
    
    # Final summary
    print_header "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    
    echo -e "${GREEN}🎉 Secret Poll has been deployed successfully!${NC}\n"
    
    echo -e "${CYAN}Application URLs:${NC}"
    if [[ "$USE_SSL" == true ]]; then
        echo -e "  • Primary: ${GREEN}https://$DOMAIN${NC}"
        if [[ "$USE_WWW" == true ]]; then
            echo -e "  • WWW: ${GREEN}https://$WWW_DOMAIN${NC}"
        fi
    else
        echo -e "  • Primary: ${GREEN}http://$DOMAIN${NC}"
        if [[ "$USE_WWW" == true ]]; then
            echo -e "  • WWW: ${GREEN}http://$WWW_DOMAIN${NC}"
        fi
    fi
    
    echo -e "\n${CYAN}Management Commands:${NC}"
    echo -e "  • Status: ${YELLOW}secret-poll-status${NC}"
    echo -e "  • Update: ${YELLOW}secret-poll-update${NC}"
    echo -e "  • Backup: ${YELLOW}secret-poll-backup${NC}"
    echo -e "  • Cleanup: ${YELLOW}secret-poll-cleanup${NC}"
    
    echo -e "\n${CYAN}Service Management:${NC}"
    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        echo -e "  • View logs: ${YELLOW}cd $APP_DIR && docker-compose -f docker-compose.prod.yml logs -f${NC}"
        echo -e "  • Restart: ${YELLOW}cd $APP_DIR && docker-compose -f docker-compose.prod.yml restart${NC}"
        echo -e "  • Stop: ${YELLOW}cd $APP_DIR && docker-compose -f docker-compose.prod.yml down${NC}"
    else
        echo -e "  • View logs: ${YELLOW}pm2 logs${NC}"
        echo -e "  • Restart: ${YELLOW}pm2 restart all${NC}"
        echo -e "  • Stop: ${YELLOW}pm2 stop all${NC}"
    fi
    
    echo -e "\n${CYAN}Important Files:${NC}"
    echo -e "  • Application: ${YELLOW}$APP_DIR${NC}"
    echo -e "  • Logs: ${YELLOW}$LOG_FILE${NC}"
    echo -e "  • Nginx Config: ${YELLOW}$APP_DIR/nginx.conf${NC}"
    
    if [[ "$USE_SSL" == true ]]; then
        echo -e "\n${CYAN}SSL Certificate:${NC}"
        echo -e "  • Certificate will auto-renew"
        echo -e "  • Manual renewal: ${YELLOW}certbot renew${NC}"
    fi
    
    echo -e "\n${GREEN}Your Secret Poll application is ready to use!${NC}"
    echo -e "${YELLOW}Please ensure your domain $DOMAIN points to this server's IP address.${NC}"
    
    log_action "Deployment completed successfully"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Trap signals for cleanup
trap 'print_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"

exit 0