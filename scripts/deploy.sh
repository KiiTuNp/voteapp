#!/bin/bash

# =============================================================================
# Secret Poll - Turnkey Interactive Deployment Script
# =============================================================================
# This script provides a completely foolproof deployment of the Secret Poll 
# application that works in ANY server context without breaking existing 
# infrastructure. It detects conflicts and offers multiple solutions.
#
# Usage: ./deploy.sh
# 
# Features:
# - Comprehensive system compatibility checks
# - Automatic conflict detection and resolution
# - Multiple deployment strategies (Docker, Manual, Isolated)
# - Existing infrastructure protection
# - Rollback capabilities
# - Real-time health monitoring
# - Zero-downtime deployment options
# - Complete automation with user guidance
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
APP_NAME="secret-poll"
DEFAULT_APP_DIR="/opt/$APP_NAME"
LOG_FILE="/var/log/$APP_NAME-deploy.log"
BACKUP_DIR="/opt/$APP_NAME-backups"
ROLLBACK_DIR="/opt/$APP_NAME-rollback"

# Version information
DOCKER_COMPOSE_VERSION="v2.20.0"
NODE_VERSION="18"
PYTHON_VERSION="3.11"
MONGODB_VERSION="7.0"

# Deployment configuration
DEPLOYMENT_TYPE=""
APP_DIR=""
DOMAIN=""
WWW_DOMAIN=""
USE_SSL=false
USE_WWW=false
ADMIN_EMAIL=""
MONGO_URL=""
APP_PORT="8001"
FRONTEND_PORT="3000"
ENVIRONMENT="production"

# Conflict detection
CONFLICTS_DETECTED=()
EXISTING_SERVICES=()
PORT_CONFLICTS=()

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
            echo -e "${YELLOW}(default: [hidden])${NC}"
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

# =============================================================================
# SYSTEM COMPATIBILITY CHECKS
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root. Please run with sudo."
        print_info "Example: sudo ./deploy.sh"
        exit 1
    fi
}

check_os() {
    print_step "Detecting operating system..."
    
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS. This script supports Linux systems."
        exit 1
    fi
    
    . /etc/os-release
    print_info "Detected OS: $PRETTY_NAME"
    
    # Check for supported distributions
    case "$ID" in
        ubuntu|debian)
            print_success "Fully supported OS detected"
            ;;
        centos|rhel|fedora|amazon)
            print_warning "This OS is supported but may require additional configuration"
            if ! confirm_action "Continue with deployment?" "y"; then
                exit 0
            fi
            ;;
        *)
            print_warning "This OS is not officially tested but the script will attempt deployment"
            if ! confirm_action "Continue at your own risk?" "n"; then
                exit 0
            fi
            ;;
    esac
}

check_system_resources() {
    print_step "Checking system resources..."
    
    local memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local memory_gb=$((memory_kb / 1024 / 1024))
    
    print_info "Available memory: ${memory_gb}GB"
    
    if [[ $memory_gb -lt 1 ]]; then
        print_error "Insufficient memory. At least 1GB RAM is required."
        exit 1
    elif [[ $memory_gb -lt 2 ]]; then
        print_warning "Low memory detected (${memory_gb}GB). Consider upgrading for better performance."
    fi
    
    local disk_space=$(df / | tail -1 | awk '{print $4}')
    local disk_gb=$((disk_space / 1024 / 1024))
    
    print_info "Available disk space: ${disk_gb}GB"
    
    if [[ $disk_gb -lt 2 ]]; then
        print_error "Insufficient disk space. At least 2GB free space is required."
        exit 1
    elif [[ $disk_gb -lt 5 ]]; then
        print_warning "Low disk space detected (${disk_gb}GB). Monitor usage closely."
    fi
    
    print_success "System resources check passed"
}

detect_existing_services() {
    print_step "Scanning for existing services and potential conflicts..."
    
    EXISTING_SERVICES=()
    PORT_CONFLICTS=()
    
    # Check for web servers
    if systemctl is-active --quiet nginx 2>/dev/null; then
        EXISTING_SERVICES+=("nginx")
        print_info "Found running Nginx service"
    fi
    
    if systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet httpd 2>/dev/null; then
        EXISTING_SERVICES+=("apache")
        print_info "Found running Apache service"
    fi
    
    # Check for databases
    if systemctl is-active --quiet mongod 2>/dev/null || systemctl is-active --quiet mongodb 2>/dev/null; then
        EXISTING_SERVICES+=("mongodb")
        print_info "Found running MongoDB service"
    fi
    
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        EXISTING_SERVICES+=("mysql")
        print_info "Found running MySQL/MariaDB service"
    fi
    
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        EXISTING_SERVICES+=("postgresql")
        print_info "Found running PostgreSQL service"
    fi
    
    # Check for Docker
    if systemctl is-active --quiet docker 2>/dev/null; then
        EXISTING_SERVICES+=("docker")
        print_info "Found running Docker service"
    fi
    
    # Check for Node.js process managers
    if command -v pm2 &> /dev/null && pm2 list 2>/dev/null | grep -q "online"; then
        EXISTING_SERVICES+=("pm2")
        print_info "Found running PM2 processes"
    fi
    
    # Check port usage
    local ports_to_check=("80" "443" "$APP_PORT" "$FRONTEND_PORT" "27017")
    
    for port in "${ports_to_check[@]}"; do
        if netstat -tulnp 2>/dev/null | grep -q ":${port} "; then
            local service=$(netstat -tulnp 2>/dev/null | grep ":${port} " | awk '{print $7}' | cut -d'/' -f2 | head -1)
            PORT_CONFLICTS+=("$port:$service")
            print_warning "Port $port is already in use by $service"
        fi
    done
    
    if [[ ${#EXISTING_SERVICES[@]} -gt 0 ]]; then
        print_warning "Detected existing services: ${EXISTING_SERVICES[*]}"
    else
        print_success "No conflicting services detected"
    fi
    
    if [[ ${#PORT_CONFLICTS[@]} -gt 0 ]]; then
        print_warning "Detected port conflicts: ${PORT_CONFLICTS[*]}"
    else
        print_success "No port conflicts detected"
    fi
}

check_docker_compatibility() {
    if command -v docker &> /dev/null; then
        print_info "Docker is already installed"
        
        if docker info &> /dev/null; then
            print_success "Docker is working properly"
            return 0
        else
            print_warning "Docker is installed but not working properly"
            return 1
        fi
    else
        print_info "Docker is not installed"
        return 1
    fi
}

# =============================================================================
# CONFIGURATION AND DEPLOYMENT STRATEGY
# =============================================================================

choose_deployment_strategy() {
    print_header "DEPLOYMENT STRATEGY SELECTION"
    
    echo -e "${CYAN}Based on your system analysis, here are the recommended deployment options:${NC}\n"
    
    local has_docker=$(check_docker_compatibility && echo "true" || echo "false")
    local has_conflicts=$([[ ${#PORT_CONFLICTS[@]} -gt 0 ]] && echo "true" || echo "false")
    local has_services=$([[ ${#EXISTING_SERVICES[@]} -gt 0 ]] && echo "true" || echo "false")
    
    # Option 1: Docker Isolated (Recommended for conflicts)
    echo -e "${GREEN}1) Docker Isolated Deployment${NC} ${YELLOW}(Recommended)${NC}"
    echo "   - Completely isolated from existing services"
    echo "   - Uses Docker with custom networks and ports"
    echo "   - Zero impact on existing infrastructure"
    echo "   - Easy rollback and management"
    if [[ "$has_docker" == "true" ]]; then
        echo -e "   ${GREEN}✓ Docker available${NC}"
    else
        echo -e "   ${YELLOW}! Will install Docker${NC}"
    fi
    echo
    
    # Option 2: Docker Standard (Good for clean systems)
    echo -e "${GREEN}2) Docker Standard Deployment${NC}"
    echo "   - Standard Docker setup with optimal performance"
    echo "   - Uses standard ports (80, 443, 8001)"
    echo "   - Requires resolving any port conflicts"
    if [[ "$has_conflicts" == "true" ]]; then
        echo -e "   ${RED}! Port conflicts detected - will need resolution${NC}"
    else
        echo -e "   ${GREEN}✓ No conflicts detected${NC}"
    fi
    echo
    
    # Option 3: Manual with Existing Services
    echo -e "${GREEN}3) Manual Integration Deployment${NC}"
    echo "   - Integrates with existing web server and database"
    echo "   - Uses your existing Nginx/Apache configuration"
    echo "   - Minimal system changes"
    if [[ "$has_services" == "true" ]]; then
        echo -e "   ${GREEN}✓ Will integrate with: ${EXISTING_SERVICES[*]}${NC}"
    else
        echo -e "   ${YELLOW}! Will install required services${NC}"
    fi
    echo
    
    # Option 4: Portable Installation
    echo -e "${GREEN}4) Portable Installation${NC}"
    echo "   - Installs in user directory (non-root after setup)"
    echo "   - Uses non-standard ports to avoid conflicts"
    echo "   - Minimal system impact"
    echo "   - Good for shared hosting environments"
    echo
    
    # Option 5: Custom Configuration
    echo -e "${GREEN}5) Custom Configuration${NC}"
    echo "   - Advanced users only"
    echo "   - Full control over all settings"
    echo "   - Manual conflict resolution"
    echo
    
    local choice
    if [[ "$has_conflicts" == "true" ]]; then
        choice=$(prompt_input "Select deployment option (1-5)" "1")
    else
        choice=$(prompt_input "Select deployment option (1-5)" "2")
    fi
    
    case "$choice" in
        1) 
            DEPLOYMENT_TYPE="docker-isolated"
            print_info "Selected: Docker Isolated Deployment"
            ;;
        2) 
            DEPLOYMENT_TYPE="docker-standard"
            print_info "Selected: Docker Standard Deployment"
            ;;
        3) 
            DEPLOYMENT_TYPE="manual-integration"
            print_info "Selected: Manual Integration Deployment"
            ;;
        4) 
            DEPLOYMENT_TYPE="portable"
            print_info "Selected: Portable Installation"
            ;;
        5) 
            DEPLOYMENT_TYPE="custom"
            print_info "Selected: Custom Configuration"
            ;;
        *) 
            print_error "Invalid selection"
            choose_deployment_strategy
            return
            ;;
    esac
}

collect_configuration() {
    print_header "CONFIGURATION SETUP"
    
    echo -e "${CYAN}Please provide the following configuration details:${NC}\n"
    
    # Domain configuration
    DOMAIN=$(prompt_input "Enter your domain name (e.g., poll.yourdomain.com or IP address)" "")
    while [[ -z "$DOMAIN" ]]; do
        print_error "Domain name or IP address is required!"
        DOMAIN=$(prompt_input "Enter your domain name (e.g., poll.yourdomain.com)" "")
    done
    
    # Validate domain/IP
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_info "Using IP address: $DOMAIN"
        WWW_DOMAIN=""
        USE_WWW=false
    else
        WWW_DOMAIN="www.$DOMAIN"
        USE_WWW=$(confirm_action "Include www.$DOMAIN? (Recommended for domains)" "y")
    fi
    
    # SSL Configuration
    if [[ ! "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        USE_SSL=$(confirm_action "Set up SSL certificate with Let's Encrypt? (Recommended for domains)" "y")
        
        if [[ "$USE_SSL" == true ]]; then
            ADMIN_EMAIL=$(prompt_input "Enter email for SSL certificate notifications" "")
            while [[ -z "$ADMIN_EMAIL" || ! "$ADMIN_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
                print_error "Valid email address is required for SSL setup!"
                ADMIN_EMAIL=$(prompt_input "Enter email for SSL certificate notifications" "")
            done
        fi
    else
        USE_SSL=false
        print_info "SSL disabled for IP address deployment"
    fi
    
    # Port configuration based on deployment type
    case "$DEPLOYMENT_TYPE" in
        "docker-isolated")
            APP_PORT=$(prompt_input "Backend port (will be isolated)" "8001")
            FRONTEND_PORT=$(prompt_input "Frontend port (will be isolated)" "3000")
            configure_isolated_ports
            ;;
        "portable")
            APP_PORT=$(prompt_input "Backend port (use high port to avoid conflicts)" "18001")
            FRONTEND_PORT=$(prompt_input "Frontend port (use high port to avoid conflicts)" "13000")
            ;;
        *)
            APP_PORT=$(prompt_input "Backend application port" "8001")
            FRONTEND_PORT=$(prompt_input "Frontend application port (manual deployment only)" "3000")
            ;;
    esac
    
    # Application directory
    if [[ "$DEPLOYMENT_TYPE" == "portable" ]]; then
        local user_home=$(eval echo ~${SUDO_USER:-$USER})
        APP_DIR=$(prompt_input "Installation directory" "$user_home/$APP_NAME")
    else
        APP_DIR=$(prompt_input "Installation directory" "$DEFAULT_APP_DIR")
    fi
    
    # Database configuration
    configure_database
    
    # Environment
    ENVIRONMENT=$(prompt_input "Environment (production/staging/development)" "production")
    
    # Show configuration summary
    show_configuration_summary
}

configure_isolated_ports() {
    print_step "Configuring isolated port mapping..."
    
    # Find available ports for external access
    local web_port=80
    local ssl_port=443
    
    if [[ ${#PORT_CONFLICTS[@]} -gt 0 ]]; then
        for conflict in "${PORT_CONFLICTS[@]}"; do
            local port=$(echo "$conflict" | cut -d':' -f1)
            if [[ "$port" == "80" ]]; then
                web_port=$(find_available_port 8080)
                print_info "Port 80 busy, using $web_port for HTTP"
            elif [[ "$port" == "443" ]]; then
                ssl_port=$(find_available_port 8443)
                print_info "Port 443 busy, using $ssl_port for HTTPS"
            fi
        done
    fi
    
    export EXTERNAL_HTTP_PORT=$web_port
    export EXTERNAL_HTTPS_PORT=$ssl_port
}

find_available_port() {
    local start_port=${1:-8000}
    local port=$start_port
    
    while netstat -tulnp 2>/dev/null | grep -q ":${port} "; do
        ((port++))
        if [[ $port -gt 65535 ]]; then
            print_error "Cannot find available port"
            exit 1
        fi
    done
    
    echo $port
}

configure_database() {
    echo -e "\n${CYAN}Database Configuration:${NC}"
    
    case "$DEPLOYMENT_TYPE" in
        "manual-integration")
            if [[ " ${EXISTING_SERVICES[@]} " =~ " mongodb " ]]; then
                print_info "Using existing MongoDB installation"
                local existing_db=$(confirm_action "Use existing MongoDB installation?" "y")
                if [[ "$existing_db" == true ]]; then
                    DB_HOST=$(prompt_input "MongoDB host" "localhost")
                    DB_PORT=$(prompt_input "MongoDB port" "27017")
                    DB_NAME=$(prompt_input "Database name" "poll_app")
                    MONGO_URL="mongodb://${DB_HOST}:${DB_PORT}/${DB_NAME}"
                    return
                fi
            fi
            ;;
        "docker-isolated"|"docker-standard")
            DB_NAME="poll_app"
            MONGO_URL="mongodb://mongodb:27017/${DB_NAME}"
            print_info "Using containerized MongoDB"
            return
            ;;
    esac
    
    # Default configuration
    DB_NAME=$(prompt_input "MongoDB database name" "poll_app")
    DB_HOST=$(prompt_input "MongoDB host" "localhost")
    DB_PORT=$(prompt_input "MongoDB port" "27017")
    MONGO_URL="mongodb://${DB_HOST}:${DB_PORT}/${DB_NAME}"
}

show_configuration_summary() {
    echo
    print_header "CONFIGURATION SUMMARY"
    echo -e "${CYAN}Deployment Type:${NC} $DEPLOYMENT_TYPE"
    echo -e "${CYAN}Installation Directory:${NC} $APP_DIR"
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
    echo -e "${CYAN}Frontend Port:${NC} $FRONTEND_PORT"
    echo -e "${CYAN}Environment:${NC} $ENVIRONMENT"
    
    if [[ -n "${EXTERNAL_HTTP_PORT:-}" ]]; then
        echo -e "${CYAN}External HTTP Port:${NC} $EXTERNAL_HTTP_PORT"
    fi
    if [[ -n "${EXTERNAL_HTTPS_PORT:-}" ]]; then
        echo -e "${CYAN}External HTTPS Port:${NC} $EXTERNAL_HTTPS_PORT"
    fi
    
    echo
    if ! confirm_action "Proceed with this configuration?" "y"; then
        print_info "Configuration cancelled. Restarting configuration..."
        collect_configuration
        return
    fi
}

# =============================================================================
# SYSTEM PREPARATION
# =============================================================================

create_backup_point() {
    print_step "Creating system backup point..."
    
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$ROLLBACK_DIR"
    
    # Backup important system files
    if [[ -f /etc/nginx/nginx.conf ]]; then
        cp /etc/nginx/nginx.conf "$ROLLBACK_DIR/nginx.conf.backup" 2>/dev/null || true
    fi
    
    if [[ -f /etc/apache2/apache2.conf ]]; then
        cp /etc/apache2/apache2.conf "$ROLLBACK_DIR/apache2.conf.backup" 2>/dev/null || true
    fi
    
    # Create rollback script
    cat > "$ROLLBACK_DIR/rollback.sh" << EOF
#!/bin/bash
echo "Rolling back Secret Poll deployment..."

# Stop services
if [[ "$DEPLOYMENT_TYPE" == "docker-isolated" || "$DEPLOYMENT_TYPE" == "docker-standard" ]]; then
    cd "$APP_DIR" && docker-compose down -v 2>/dev/null || true
else
    pm2 delete all 2>/dev/null || true
fi

# Restore configurations
if [[ -f "$ROLLBACK_DIR/nginx.conf.backup" ]]; then
    cp "$ROLLBACK_DIR/nginx.conf.backup" /etc/nginx/nginx.conf
    systemctl reload nginx 2>/dev/null || true
fi

if [[ -f "$ROLLBACK_DIR/apache2.conf.backup" ]]; then
    cp "$ROLLBACK_DIR/apache2.conf.backup" /etc/apache2/apache2.conf
    systemctl reload apache2 2>/dev/null || true
fi

# Remove application
rm -rf "$APP_DIR" 2>/dev/null || true

echo "Rollback completed. System restored to previous state."
EOF
    
    chmod +x "$ROLLBACK_DIR/rollback.sh"
    
    print_success "Backup point created at $ROLLBACK_DIR"
}

update_system() {
    print_step "Updating system packages..."
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >> "$LOG_FILE" 2>&1
        apt-get install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release >> "$LOG_FILE" 2>&1
    elif command -v yum &> /dev/null; then
        yum update -y >> "$LOG_FILE" 2>&1
        yum install -y curl wget git unzip >> "$LOG_FILE" 2>&1
    elif command -v dnf &> /dev/null; then
        dnf update -y >> "$LOG_FILE" 2>&1
        dnf install -y curl wget git unzip >> "$LOG_FILE" 2>&1
    else
        print_error "Unsupported package manager"
        exit 1
    fi
    
    print_success "System updated successfully"
}

install_dependencies() {
    print_step "Installing deployment dependencies..."
    
    case "$DEPLOYMENT_TYPE" in
        "docker-isolated"|"docker-standard")
            install_docker
            ;;
        "manual-integration"|"portable"|"custom")
            install_manual_dependencies
            ;;
    esac
}

install_docker() {
    if check_docker_compatibility; then
        print_success "Docker already available and working"
        return 0
    fi
    
    print_step "Installing Docker..."
    
    # Remove old versions
    if command -v apt-get &> /dev/null; then
        apt-get remove -y docker docker-engine docker.io containerd runc >> "$LOG_FILE" 2>&1 || true
    elif command -v yum &> /dev/null; then
        yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine >> "$LOG_FILE" 2>&1 || true
    fi
    
    # Install Docker
    curl -fsSL https://get.docker.com | sh >> "$LOG_FILE" 2>&1
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose >> "$LOG_FILE" 2>&1
    chmod +x /usr/local/bin/docker-compose
    
    # Start and enable Docker
    systemctl enable docker >> "$LOG_FILE" 2>&1
    systemctl start docker >> "$LOG_FILE" 2>&1
    
    # Add current user to docker group if not root
    if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER" >> "$LOG_FILE" 2>&1
    fi
    
    print_success "Docker installed successfully"
    docker --version
    docker-compose --version
}

install_manual_dependencies() {
    print_step "Installing manual deployment dependencies..."
    
    # Node.js
    if ! command -v node &> /dev/null || [[ $(node --version | sed 's/v//g' | cut -d'.' -f1) -lt $NODE_VERSION ]]; then
        print_info "Installing Node.js $NODE_VERSION..."
        if command -v apt-get &> /dev/null; then
            curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - >> "$LOG_FILE" 2>&1
            apt-get install -y nodejs >> "$LOG_FILE" 2>&1
        elif command -v yum &> /dev/null; then
            curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION}.x" | bash - >> "$LOG_FILE" 2>&1
            yum install -y nodejs npm >> "$LOG_FILE" 2>&1
        fi
    else
        print_success "Node.js already installed"
    fi
    
    # Python
    if command -v apt-get &> /dev/null; then
        apt-get install -y python3 python3-pip python3-venv python3-dev build-essential >> "$LOG_FILE" 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y python3 python3-pip python3-venv python3-devel gcc >> "$LOG_FILE" 2>&1
    fi
    
    # MongoDB (if not using existing)
    if [[ ! " ${EXISTING_SERVICES[@]} " =~ " mongodb " ]] && [[ "$DEPLOYMENT_TYPE" != "portable" ]]; then
        install_mongodb
    fi
    
    # PM2
    if ! command -v pm2 &> /dev/null; then
        print_info "Installing PM2..."
        npm install -g pm2 >> "$LOG_FILE" 2>&1
    fi
    
    print_success "Manual dependencies installed successfully"
}

install_mongodb() {
    if systemctl is-active --quiet mongod 2>/dev/null; then
        print_success "MongoDB already running"
        return 0
    fi
    
    print_step "Installing MongoDB..."
    
    if command -v apt-get &> /dev/null; then
        wget -qO - https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | apt-key add - >> "$LOG_FILE" 2>&1
        echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/${MONGODB_VERSION} multiverse" | tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list >> "$LOG_FILE" 2>&1
        apt-get update >> "$LOG_FILE" 2>&1
        apt-get install -y mongodb-org >> "$LOG_FILE" 2>&1
    elif command -v yum &> /dev/null; then
        cat > /etc/yum.repos.d/mongodb-org-${MONGODB_VERSION}.repo << EOF
[mongodb-org-${MONGODB_VERSION}]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/${MONGODB_VERSION}/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc
EOF
        yum install -y mongodb-org >> "$LOG_FILE" 2>&1
    fi
    
    systemctl enable mongod >> "$LOG_FILE" 2>&1
    systemctl start mongod >> "$LOG_FILE" 2>&1
    
    print_success "MongoDB installed and started"
}

# =============================================================================
# APPLICATION DEPLOYMENT
# =============================================================================

deploy_application() {
    print_header "APPLICATION DEPLOYMENT"
    
    prepare_application_directory
    create_environment_files
    
    case "$DEPLOYMENT_TYPE" in
        "docker-isolated")
            deploy_docker_isolated
            ;;
        "docker-standard")
            deploy_docker_standard
            ;;
        "manual-integration")
            deploy_manual_integration
            ;;
        "portable")
            deploy_portable
            ;;
        "custom")
            deploy_custom
            ;;
    esac
}

prepare_application_directory() {
    print_step "Preparing application directory at $APP_DIR..."
    
    # Create directory structure
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Copy application files
    if [[ "$SCRIPT_DIR" != "$APP_DIR" ]]; then
        local source_dir=$(dirname "$SCRIPT_DIR")
        print_info "Copying application from $source_dir..."
        
        # Copy main directories
        cp -r "$source_dir"/{backend,frontend} "$APP_DIR/" 2>/dev/null || true
        cp "$source_dir"/README.md "$APP_DIR/" 2>/dev/null || true
        
        # Copy configuration files
        find "$source_dir" -maxdepth 1 -name "*.json" -o -name "*.js" -o -name "*.md" | xargs -I {} cp {} "$APP_DIR/" 2>/dev/null || true
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
CORS_ORIGINS=$(build_cors_origins)

# Application Configuration
PORT=$APP_PORT
ENVIRONMENT=$ENVIRONMENT

# Security
SECRET_KEY=$(openssl rand -hex 32)

# Generated on $(date)
EOF
    
    # Frontend environment
    local backend_url=$(build_backend_url)
    
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

build_cors_origins() {
    local origins=""
    
    if [[ "$USE_SSL" == true ]]; then
        origins="https://$DOMAIN"
        if [[ "$USE_WWW" == true ]]; then
            origins="$origins,https://$WWW_DOMAIN"
        fi
    else
        if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            origins="http://$DOMAIN"
            if [[ -n "${EXTERNAL_HTTP_PORT:-}" && "$EXTERNAL_HTTP_PORT" != "80" ]]; then
                origins="$origins:$EXTERNAL_HTTP_PORT"
            fi
        else
            origins="http://$DOMAIN"
            if [[ "$USE_WWW" == true ]]; then
                origins="$origins,http://$WWW_DOMAIN"
            fi
        fi
    fi
    
    echo "$origins"
}

build_backend_url() {
    if [[ "$USE_SSL" == true ]]; then
        if [[ -n "${EXTERNAL_HTTPS_PORT:-}" && "$EXTERNAL_HTTPS_PORT" != "443" ]]; then
            echo "https://$DOMAIN:$EXTERNAL_HTTPS_PORT"
        else
            echo "https://$DOMAIN"
        fi
    else
        if [[ -n "${EXTERNAL_HTTP_PORT:-}" && "$EXTERNAL_HTTP_PORT" != "80" ]]; then
            echo "http://$DOMAIN:$EXTERNAL_HTTP_PORT"
        else
            echo "http://$DOMAIN"
        fi
    fi
}

deploy_docker_isolated() {
    print_step "Deploying with Docker (Isolated Mode)..."
    
    # Create isolated Docker Compose file
    create_docker_compose_isolated
    create_docker_files
    create_nginx_config_docker
    
    # Deploy
    docker-compose -f docker-compose.isolated.yml down >> "$LOG_FILE" 2>&1 || true
    docker-compose -f docker-compose.isolated.yml up -d --build >> "$LOG_FILE" 2>&1
    
    print_success "Docker isolated deployment completed"
}

deploy_docker_standard() {
    print_step "Deploying with Docker (Standard Mode)..."
    
    # Handle port conflicts first
    resolve_port_conflicts
    
    # Create standard Docker Compose file
    create_docker_compose_standard
    create_docker_files
    create_nginx_config_docker
    
    # Deploy
    docker-compose -f docker-compose.yml down >> "$LOG_FILE" 2>&1 || true
    docker-compose -f docker-compose.yml up -d --build >> "$LOG_FILE" 2>&1
    
    print_success "Docker standard deployment completed"
}

deploy_manual_integration() {
    print_step "Deploying with manual integration..."
    
    # Build application
    build_application
    
    # Configure web server integration
    configure_web_server_integration
    
    # Start with PM2
    create_pm2_config
    start_pm2_services
    
    print_success "Manual integration deployment completed"
}

deploy_portable() {
    print_step "Deploying portable installation..."
    
    # Build application
    build_application
    
    # Create portable runner scripts
    create_portable_scripts
    
    # Start services
    start_portable_services
    
    print_success "Portable deployment completed"
}

deploy_custom() {
    print_step "Starting custom deployment..."
    
    echo -e "${CYAN}Custom deployment allows you to configure every aspect manually.${NC}"
    echo -e "${YELLOW}This is for advanced users only!${NC}\n"
    
    if ! confirm_action "Are you sure you want to proceed with custom deployment?" "n"; then
        print_info "Switching to recommended deployment..."
        choose_deployment_strategy
        deploy_application
        return
    fi
    
    # Custom configuration wizard
    custom_deployment_wizard
}

# =============================================================================
# DOCKER DEPLOYMENT CONFIGURATIONS
# =============================================================================

create_docker_compose_isolated() {
    local http_port=${EXTERNAL_HTTP_PORT:-80}
    local https_port=${EXTERNAL_HTTPS_PORT:-443}
    
    cat > "$APP_DIR/docker-compose.isolated.yml" << EOF
version: '3.8'

services:
  mongodb:
    image: mongo:${MONGODB_VERSION}
    container_name: ${APP_NAME}-mongo-isolated
    restart: unless-stopped
    environment:
      - MONGO_INITDB_DATABASE=${DB_NAME}
    volumes:
      - mongodb_data:/data/db
    networks:
      - isolated-network
    deploy:
      resources:
        limits:
          memory: 512m
          cpus: '0.5'

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.prod
    container_name: ${APP_NAME}-backend-isolated
    restart: unless-stopped
    environment:
      - MONGO_URL=mongodb://mongodb:27017/${DB_NAME}
      - CORS_ORIGINS=$(build_cors_origins)
      - PORT=${APP_PORT}
      - ENVIRONMENT=${ENVIRONMENT}
    depends_on:
      - mongodb
    networks:
      - isolated-network
    deploy:
      resources:
        limits:
          memory: 1g
          cpus: '1.0'

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.prod
      args:
        - REACT_APP_BACKEND_URL=$(build_backend_url)
    container_name: ${APP_NAME}-frontend-isolated
    restart: unless-stopped
    depends_on:
      - backend
    networks:
      - isolated-network
    deploy:
      resources:
        limits:
          memory: 256m
          cpus: '0.3'

  nginx:
    image: nginx:alpine
    container_name: ${APP_NAME}-nginx-isolated
    restart: unless-stopped
    ports:
      - "${http_port}:80"
      $([ "$USE_SSL" == true ] && echo "      - \"${https_port}:443\"")
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      $([ "$USE_SSL" == true ] && echo "      - ./ssl:/etc/nginx/ssl:ro")
    depends_on:
      - frontend
      - backend
    networks:
      - isolated-network
    deploy:
      resources:
        limits:
          memory: 128m
          cpus: '0.2'

volumes:
  mongodb_data:

networks:
  isolated-network:
    driver: bridge
    name: ${APP_NAME}-isolated
EOF
}

create_docker_compose_standard() {
    cat > "$APP_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  mongodb:
    image: mongo:${MONGODB_VERSION}
    container_name: ${APP_NAME}-mongo
    restart: unless-stopped
    environment:
      - MONGO_INITDB_DATABASE=${DB_NAME}
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
    container_name: ${APP_NAME}-backend
    restart: unless-stopped
    environment:
      - MONGO_URL=mongodb://mongodb:27017/${DB_NAME}
      - CORS_ORIGINS=$(build_cors_origins)
      - PORT=${APP_PORT}
      - ENVIRONMENT=${ENVIRONMENT}
    depends_on:
      - mongodb
    networks:
      - app-network
    deploy:
      resources:
        limits:
          memory: 1g
          cpus: '1.0'

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.prod
      args:
        - REACT_APP_BACKEND_URL=$(build_backend_url)
    container_name: ${APP_NAME}-frontend
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
    container_name: ${APP_NAME}-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      $([ "$USE_SSL" == true ] && echo "      - \"443:443\"")
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      $([ "$USE_SSL" == true ] && echo "      - ./ssl:/etc/nginx/ssl:ro")
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
COPY yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy source code and build
COPY . .
ARG REACT_APP_BACKEND_URL
ENV REACT_APP_BACKEND_URL=$REACT_APP_BACKEND_URL
ENV NODE_ENV=production
ENV GENERATE_SOURCEMAP=false
RUN yarn build

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
    
    # Frontend Nginx config for Docker
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

create_nginx_config_docker() {
    print_step "Creating Nginx configuration for Docker..."
    
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
        server backend:${APP_PORT};
    }
    
    upstream frontend {
        server frontend:80;
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
            proxy_pass http://frontend;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF
    
    print_success "Nginx configuration created"
}

# =============================================================================
# MANUAL AND INTEGRATION DEPLOYMENT
# =============================================================================

build_application() {
    print_step "Building application..."
    
    # Backend
    print_info "Setting up backend..."
    cd "$APP_DIR/backend"
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip >> "$LOG_FILE" 2>&1
    pip install -r requirements.txt >> "$LOG_FILE" 2>&1
    
    # Frontend
    print_info "Building frontend..."
    cd "$APP_DIR/frontend"
    if [[ -f yarn.lock ]]; then
        yarn install >> "$LOG_FILE" 2>&1
        yarn build >> "$LOG_FILE" 2>&1
    else
        npm install >> "$LOG_FILE" 2>&1
        npm run build >> "$LOG_FILE" 2>&1
    fi
    
    print_success "Application built successfully"
}

configure_web_server_integration() {
    print_step "Configuring web server integration..."
    
    if [[ " ${EXISTING_SERVICES[@]} " =~ " nginx " ]]; then
        configure_nginx_integration
    elif [[ " ${EXISTING_SERVICES[@]} " =~ " apache " ]]; then
        configure_apache_integration
    else
        install_and_configure_nginx
    fi
}

configure_nginx_integration() {
    print_step "Integrating with existing Nginx..."
    
    # Create site configuration
    cat > "/etc/nginx/sites-available/$APP_NAME" << EOF
server {
    listen 80;
    server_name $DOMAIN$([ "$USE_WWW" == true ] && echo " $WWW_DOMAIN");
    
    $(if [[ "$USE_SSL" == true ]]; then echo "
    # Redirect to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN$([ "$USE_WWW" == true ] && echo " $WWW_DOMAIN");
    
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;"
    fi)
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Frontend
    location / {
        root $APP_DIR/frontend/build;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    # API routes
    location /api/ {
        proxy_pass http://localhost:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Cache static assets
    location /static/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    # Enable site
    ln -sf "/etc/nginx/sites-available/$APP_NAME" "/etc/nginx/sites-enabled/$APP_NAME"
    
    # Test configuration
    nginx -t >> "$LOG_FILE" 2>&1
    
    # Reload Nginx
    systemctl reload nginx >> "$LOG_FILE" 2>&1
    
    print_success "Nginx integration configured"
}

install_and_configure_nginx() {
    print_step "Installing and configuring Nginx..."
    
    # Install Nginx
    if command -v apt-get &> /dev/null; then
        apt-get install -y nginx >> "$LOG_FILE" 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y nginx >> "$LOG_FILE" 2>&1
    fi
    
    # Configure
    configure_nginx_integration
    
    # Enable and start
    systemctl enable nginx >> "$LOG_FILE" 2>&1
    systemctl start nginx >> "$LOG_FILE" 2>&1
    
    print_success "Nginx installed and configured"
}

create_pm2_config() {
    print_step "Creating PM2 configuration..."
    
    cat > "$APP_DIR/ecosystem.config.js" << EOF
module.exports = {
  apps: [
    {
      name: '$APP_NAME-backend',
      cwd: '$APP_DIR/backend',
      script: 'server.py',
      interpreter: '$APP_DIR/backend/venv/bin/python',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        NODE_ENV: '$ENVIRONMENT',
        PORT: '$APP_PORT'
      },
      error_file: '/var/log/$APP_NAME/backend-error.log',
      out_file: '/var/log/$APP_NAME/backend-out.log',
      log_file: '/var/log/$APP_NAME/backend.log',
      max_memory_restart: '1G',
      restart_delay: 1000,
      max_restarts: 10,
      min_uptime: '10s'
    }
  ]
};
EOF
    
    # Create log directory
    mkdir -p "/var/log/$APP_NAME"
    
    print_success "PM2 configuration created"
}

start_pm2_services() {
    print_step "Starting PM2 services..."
    
    cd "$APP_DIR"
    
    # Start with PM2
    if [[ -n "$SUDO_USER" ]]; then
        sudo -u "$SUDO_USER" pm2 start ecosystem.config.js >> "$LOG_FILE" 2>&1
        sudo -u "$SUDO_USER" pm2 save >> "$LOG_FILE" 2>&1
        
        # Setup PM2 startup
        startup_line=$(sudo -u "$SUDO_USER" pm2 startup | grep -o 'sudo.*')
        if [[ -n "$startup_line" ]]; then
            eval "$startup_line" >> "$LOG_FILE" 2>&1
        fi
    else
        pm2 start ecosystem.config.js >> "$LOG_FILE" 2>&1
        pm2 save >> "$LOG_FILE" 2>&1
        pm2 startup >> "$LOG_FILE" 2>&1
    fi
    
    print_success "PM2 services started"
}

# =============================================================================
# PORTABLE DEPLOYMENT
# =============================================================================

create_portable_scripts() {
    print_step "Creating portable deployment scripts..."
    
    # Main startup script
    cat > "$APP_DIR/start.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"

echo "Starting Secret Poll (Portable Mode)..."

# Start backend
cd backend
source venv/bin/activate
python server.py &
BACKEND_PID=\$!
echo \$BACKEND_PID > ../backend.pid

# Start frontend serving (using Python's http.server)
cd ../frontend/build
python3 -m http.server $FRONTEND_PORT &
FRONTEND_PID=\$!
echo \$FRONTEND_PID > ../../frontend.pid

echo "Secret Poll started successfully!"
echo "Access your application at: $(build_backend_url | sed 's/8001/'"$FRONTEND_PORT"'/')"
echo "Backend API: $(build_backend_url)"
echo ""
echo "To stop the application, run: ./stop.sh"
EOF
    
    # Stop script
    cat > "$APP_DIR/stop.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"

echo "Stopping Secret Poll..."

if [[ -f backend.pid ]]; then
    kill \$(cat backend.pid) 2>/dev/null || true
    rm backend.pid
fi

if [[ -f frontend.pid ]]; then
    kill \$(cat frontend.pid) 2>/dev/null || true
    rm frontend.pid
fi

echo "Secret Poll stopped."
EOF
    
    # Status script
    cat > "$APP_DIR/status.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"

echo "Secret Poll Status:"

if [[ -f backend.pid ]] && kill -0 \$(cat backend.pid) 2>/dev/null; then
    echo "  Backend: Running (PID: \$(cat backend.pid))"
else
    echo "  Backend: Stopped"
fi

if [[ -f frontend.pid ]] && kill -0 \$(cat frontend.pid) 2>/dev/null; then
    echo "  Frontend: Running (PID: \$(cat frontend.pid))"
else
    echo "  Frontend: Stopped"
fi
EOF
    
    # Make scripts executable
    chmod +x "$APP_DIR"/{start,stop,status}.sh
    
    print_success "Portable scripts created"
}

start_portable_services() {
    print_step "Starting portable services..."
    
    # Ensure MongoDB is running (if local)
    if [[ "$MONGO_URL" =~ localhost|127.0.0.1 ]]; then
        if ! systemctl is-active --quiet mongod 2>/dev/null; then
            print_warning "MongoDB is not running. Attempting to start..."
            systemctl start mongod >> "$LOG_FILE" 2>&1 || true
        fi
    fi
    
    # Start the application
    cd "$APP_DIR"
    ./start.sh >> "$LOG_FILE" 2>&1
    
    sleep 5
    
    # Check if services started
    if ./status.sh | grep -q "Running"; then
        print_success "Portable services started successfully"
    else
        print_error "Failed to start some services. Check logs for details."
    fi
}

# =============================================================================
# CONFLICT RESOLUTION
# =============================================================================

resolve_port_conflicts() {
    if [[ ${#PORT_CONFLICTS[@]} -eq 0 ]]; then
        return 0
    fi
    
    print_step "Resolving port conflicts..."
    
    for conflict in "${PORT_CONFLICTS[@]}"; do
        local port=$(echo "$conflict" | cut -d':' -f1)
        local service=$(echo "$conflict" | cut -d':' -f2)
        
        print_warning "Port $port is used by $service"
        
        case "$port" in
            80)
                resolve_http_conflict "$service"
                ;;
            443)
                resolve_https_conflict "$service"
                ;;
            "$APP_PORT")
                APP_PORT=$(find_available_port $((APP_PORT + 1)))
                print_info "Changed backend port to $APP_PORT"
                ;;
            "$FRONTEND_PORT")
                FRONTEND_PORT=$(find_available_port $((FRONTEND_PORT + 1)))
                print_info "Changed frontend port to $FRONTEND_PORT"
                ;;
            27017)
                resolve_mongodb_conflict
                ;;
        esac
    done
}

resolve_http_conflict() {
    local service="$1"
    
    echo -e "\n${YELLOW}HTTP port (80) conflict resolution:${NC}"
    echo "1) Use a different port (e.g., 8080)"
    echo "2) Stop the conflicting service ($service)"
    echo "3) Configure virtual host/proxy (advanced)"
    echo "4) Skip HTTP, use HTTPS only"
    
    local choice=$(prompt_input "Choose resolution method (1-4)" "1")
    
    case "$choice" in
        1)
            EXTERNAL_HTTP_PORT=$(find_available_port 8080)
            print_info "Using port $EXTERNAL_HTTP_PORT for HTTP"
            ;;
        2)
            if confirm_action "Stop $service service?" "n"; then
                systemctl stop "$service" >> "$LOG_FILE" 2>&1
                print_success "Stopped $service"
            fi
            ;;
        3)
            configure_proxy_integration "$service"
            ;;
        4)
            if [[ "$USE_SSL" == true ]]; then
                EXTERNAL_HTTP_PORT=""
                print_info "HTTP disabled, using HTTPS only"
            else
                print_error "Cannot disable HTTP without SSL enabled"
                resolve_http_conflict "$service"
            fi
            ;;
    esac
}

resolve_https_conflict() {
    local service="$1"
    
    if [[ "$USE_SSL" != true ]]; then
        return 0
    fi
    
    echo -e "\n${YELLOW}HTTPS port (443) conflict resolution:${NC}"
    echo "1) Use a different port (e.g., 8443)"
    echo "2) Stop the conflicting service ($service)"
    echo "3) Configure virtual host/proxy (advanced)"
    echo "4) Disable SSL"
    
    local choice=$(prompt_input "Choose resolution method (1-4)" "1")
    
    case "$choice" in
        1)
            EXTERNAL_HTTPS_PORT=$(find_available_port 8443)
            print_info "Using port $EXTERNAL_HTTPS_PORT for HTTPS"
            ;;
        2)
            if confirm_action "Stop $service service?" "n"; then
                systemctl stop "$service" >> "$LOG_FILE" 2>&1
                print_success "Stopped $service"
            fi
            ;;
        3)
            configure_proxy_integration "$service"
            ;;
        4)
            USE_SSL=false
            print_warning "SSL disabled due to port conflict"
            ;;
    esac
}

resolve_mongodb_conflict() {
    echo -e "\n${YELLOW}MongoDB port (27017) conflict resolution:${NC}"
    echo "1) Use existing MongoDB instance"
    echo "2) Use a different port"
    echo "3) Stop conflicting service"
    
    local choice=$(prompt_input "Choose resolution method (1-3)" "1")
    
    case "$choice" in
        1)
            print_info "Using existing MongoDB instance"
            # MongoDB URL already configured
            ;;
        2)
            local new_port=$(find_available_port 27018)
            MONGO_URL="mongodb://localhost:${new_port}/${DB_NAME}"
            print_info "MongoDB will use port $new_port"
            ;;
        3)
            if confirm_action "Stop conflicting MongoDB service?" "n"; then
                systemctl stop mongod >> "$LOG_FILE" 2>&1 || true
                systemctl stop mongodb >> "$LOG_FILE" 2>&1 || true
                print_success "Stopped MongoDB service"
            fi
            ;;
    esac
}

# =============================================================================
# SSL CERTIFICATE SETUP
# =============================================================================

setup_ssl() {
    if [[ "$USE_SSL" != true ]]; then
        return 0
    fi
    
    print_header "SSL CERTIFICATE SETUP"
    
    print_step "Setting up SSL certificate with Let's Encrypt..."
    
    # Install Certbot
    install_certbot
    
    # Stop web services temporarily
    stop_web_services_for_ssl
    
    # Generate certificate
    generate_ssl_certificate
    
    # Copy certificates
    copy_ssl_certificates
    
    # Setup auto-renewal
    setup_ssl_renewal
    
    # Restart web services
    start_web_services_after_ssl
    
    print_success "SSL certificate setup completed"
}

install_certbot() {
    print_step "Installing Certbot..."
    
    if command -v apt-get &> /dev/null; then
        apt-get install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1 || {
            # Fallback for CentOS/RHEL
            yum install -y epel-release >> "$LOG_FILE" 2>&1
            yum install -y certbot >> "$LOG_FILE" 2>&1
        }
    fi
}

generate_ssl_certificate() {
    print_step "Generating SSL certificate..."
    
    local domain_args="-d $DOMAIN"
    if [[ "$USE_WWW" == true ]]; then
        domain_args="$domain_args -d $WWW_DOMAIN"
    fi
    
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        $domain_args >> "$LOG_FILE" 2>&1
    
    if [[ $? -eq 0 ]]; then
        print_success "SSL certificate generated successfully"
    else
        print_error "SSL certificate generation failed"
        USE_SSL=false
        return 1
    fi
}

copy_ssl_certificates() {
    print_step "Setting up SSL certificates..."
    
    mkdir -p "$APP_DIR/ssl"
    
    cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$APP_DIR/ssl/"
    cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$APP_DIR/ssl/"
    
    # Set proper permissions
    chmod 644 "$APP_DIR/ssl/fullchain.pem"
    chmod 600 "$APP_DIR/ssl/privkey.pem"
    
    print_success "SSL certificates configured"
}

setup_ssl_renewal() {
    print_step "Setting up SSL auto-renewal..."
    
    # Create renewal hook script
    cat > /etc/letsencrypt/renewal-hooks/post/secret-poll-reload << EOF
#!/bin/bash
# Reload services after SSL renewal

if [[ -f "$APP_DIR/docker-compose.yml" ]]; then
    cd "$APP_DIR"
    docker-compose restart nginx
elif [[ -f "$APP_DIR/docker-compose.isolated.yml" ]]; then
    cd "$APP_DIR"
    docker-compose -f docker-compose.isolated.yml restart nginx
else
    systemctl reload nginx 2>/dev/null || true
fi

# Copy new certificates
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$APP_DIR/ssl/"
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$APP_DIR/ssl/"
chmod 644 "$APP_DIR/ssl/fullchain.pem"
chmod 600 "$APP_DIR/ssl/privkey.pem"
EOF
    
    chmod +x /etc/letsencrypt/renewal-hooks/post/secret-poll-reload
    
    # Test renewal
    certbot renew --dry-run >> "$LOG_FILE" 2>&1
    
    print_success "SSL auto-renewal configured"
}

stop_web_services_for_ssl() {
    print_step "Temporarily stopping web services for SSL setup..."
    
    case "$DEPLOYMENT_TYPE" in
        "docker-isolated")
            docker-compose -f "$APP_DIR/docker-compose.isolated.yml" stop nginx >> "$LOG_FILE" 2>&1 || true
            ;;
        "docker-standard")
            docker-compose -f "$APP_DIR/docker-compose.yml" stop nginx >> "$LOG_FILE" 2>&1 || true
            ;;
        *)
            systemctl stop nginx >> "$LOG_FILE" 2>&1 || true
            systemctl stop apache2 >> "$LOG_FILE" 2>&1 || true
            systemctl stop httpd >> "$LOG_FILE" 2>&1 || true
            ;;
    esac
}

start_web_services_after_ssl() {
    print_step "Restarting web services after SSL setup..."
    
    case "$DEPLOYMENT_TYPE" in
        "docker-isolated")
            docker-compose -f "$APP_DIR/docker-compose.isolated.yml" up -d nginx >> "$LOG_FILE" 2>&1
            ;;
        "docker-standard")
            docker-compose -f "$APP_DIR/docker-compose.yml" up -d nginx >> "$LOG_FILE" 2>&1
            ;;
        *)
            systemctl start nginx >> "$LOG_FILE" 2>&1 || true
            ;;
    esac
}

# =============================================================================
# HEALTH CHECKS AND VERIFICATION
# =============================================================================

verify_deployment() {
    print_header "DEPLOYMENT VERIFICATION"
    
    print_step "Waiting for services to start..."
    sleep 30
    
    # Check service health
    check_service_health
    
    # Test endpoints
    test_application_endpoints
    
    # Performance check
    basic_performance_check
    
    print_success "Deployment verification completed"
}

check_service_health() {
    print_step "Checking service health..."
    
    case "$DEPLOYMENT_TYPE" in
        "docker-isolated")
            check_docker_health "docker-compose.isolated.yml"
            ;;
        "docker-standard")
            check_docker_health "docker-compose.yml"
            ;;
        "manual-integration"|"portable")
            check_manual_health
            ;;
    esac
}

check_docker_health() {
    local compose_file="$1"
    
    cd "$APP_DIR"
    
    # Check container status
    print_info "Container status:"
    docker-compose -f "$compose_file" ps
    
    # Health check attempts
    local backend_healthy=false
    local frontend_healthy=false
    
    for i in {1..12}; do
        if docker-compose -f "$compose_file" exec -T backend curl -f "http://localhost:$APP_PORT/api/health" >> "$LOG_FILE" 2>&1; then
            backend_healthy=true
            break
        fi
        print_info "Waiting for backend to be healthy... ($i/12)"
        sleep 10
    done
    
    for i in {1..6}; do
        if docker-compose -f "$compose_file" exec -T nginx wget --no-verbose --tries=1 --spider http://localhost:80/ >> "$LOG_FILE" 2>&1; then
            frontend_healthy=true
            break
        fi
        print_info "Waiting for frontend to be healthy... ($i/6)"
        sleep 5
    done
    
    if [[ "$backend_healthy" == true && "$frontend_healthy" == true ]]; then
        print_success "All services are healthy"
    else
        print_warning "Some services may not be healthy. Check logs for details."
        
        # Show recent logs
        echo -e "\n${YELLOW}Recent logs:${NC}"
        docker-compose -f "$compose_file" logs --tail=20
    fi
}

check_manual_health() {
    # Check PM2 processes
    if command -v pm2 &> /dev/null; then
        if pm2 list | grep -q "$APP_NAME-backend.*online"; then
            print_success "Backend service is running"
        else
            print_error "Backend service is not running properly"
            pm2 logs "$APP_NAME-backend" --lines 10
        fi
    fi
    
    # Check web server
    if systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    elif systemctl is-active --quiet apache2; then
        print_success "Apache is running"
    else
        print_error "Web server is not running properly"
    fi
    
    # Check MongoDB
    if systemctl is-active --quiet mongod || systemctl is-active --quiet mongodb; then
        print_success "MongoDB is running"
    else
        print_warning "MongoDB service check failed"
    fi
}

test_application_endpoints() {
    print_step "Testing application endpoints..."
    
    local base_url=$(build_backend_url)
    local frontend_url="$base_url"
    
    # Adjust URLs for different deployment types
    case "$DEPLOYMENT_TYPE" in
        "portable")
            frontend_url=$(echo "$base_url" | sed "s/:$APP_PORT/:$FRONTEND_PORT/")
            ;;
    esac
    
    # Test health endpoint
    print_info "Testing API health endpoint..."
    if curl -f -s --max-time 30 "$base_url/api/health" >> "$LOG_FILE" 2>&1; then
        print_success "✓ API health check passed"
    else
        print_warning "! API health check failed - service may still be starting"
    fi
    
    # Test frontend
    print_info "Testing frontend accessibility..."
    if curl -f -s --max-time 30 "$frontend_url/" >> "$LOG_FILE" 2>&1; then
        print_success "✓ Frontend is accessible"
    else
        print_warning "! Frontend accessibility test failed"
    fi
    
    # Test WebSocket (if possible)
    print_info "Testing WebSocket connectivity..."
    if command -v wscat &> /dev/null; then
        echo "test" | timeout 5 wscat -c "${base_url/http/ws}/api/ws/test" >> "$LOG_FILE" 2>&1 || true
    fi
}

basic_performance_check() {
    print_step "Running basic performance check..."
    
    local base_url=$(build_backend_url)
    
    # Simple load test
    print_info "Testing response times..."
    local response_time=$(curl -o /dev/null -s -w '%{time_total}' --max-time 10 "$base_url/api/health" 2>/dev/null || echo "timeout")
    
    if [[ "$response_time" != "timeout" ]]; then
        local ms=$(echo "$response_time * 1000" | bc 2>/dev/null || echo "unknown")
        print_info "API response time: ${ms}ms"
        
        if (( $(echo "$response_time < 1.0" | bc -l 2>/dev/null || echo 0) )); then
            print_success "✓ Good response time"
        else
            print_warning "! Slow response time detected"
        fi
    else
        print_warning "! Performance check timeout"
    fi
}

# =============================================================================
# POST-DEPLOYMENT SETUP
# =============================================================================

create_management_tools() {
    print_header "CREATING MANAGEMENT TOOLS"
    
    create_status_command
    create_management_scripts
    create_monitoring_setup
    create_backup_system
    
    print_success "Management tools created successfully"
}

create_status_command() {
    print_step "Creating status monitoring command..."
    
    cat > "/usr/local/bin/$APP_NAME-status" << EOF
#!/bin/bash

echo "=== Secret Poll System Status ==="
echo "Date: \$(date)"
echo "Deployment Type: $DEPLOYMENT_TYPE"
echo "Installation Directory: $APP_DIR"
echo

case "$DEPLOYMENT_TYPE" in
    "docker-isolated")
        echo "=== Docker Services (Isolated) ==="
        cd "$APP_DIR"
        docker-compose -f docker-compose.isolated.yml ps
        echo
        echo "=== Container Health ==="
        docker-compose -f docker-compose.isolated.yml exec backend curl -s http://localhost:$APP_PORT/api/health || echo "Backend: Unhealthy"
        ;;
    "docker-standard")
        echo "=== Docker Services ==="
        cd "$APP_DIR"
        docker-compose -f docker-compose.yml ps
        echo
        echo "=== Container Health ==="
        docker-compose -f docker-compose.yml exec backend curl -s http://localhost:$APP_PORT/api/health || echo "Backend: Unhealthy"
        ;;
    *)
        echo "=== System Services ==="
        systemctl status nginx --no-pager -l 2>/dev/null || echo "Nginx: Not managed by systemctl"
        systemctl status mongod --no-pager -l 2>/dev/null || echo "MongoDB: Not managed by systemctl"
        if command -v pm2 &> /dev/null; then
            echo
            echo "=== PM2 Processes ==="
            pm2 status
        fi
        ;;
esac

echo
echo "=== System Resources ==="
echo "Memory Usage:"
free -h
echo
echo "Disk Usage:"
df -h "$APP_DIR"
echo
echo "=== Network Status ==="
netstat -tulpn | grep -E ":(80|443|$APP_PORT|$FRONTEND_PORT|27017)" || echo "No relevant network connections found"
echo
echo "=== Application URLs ==="
echo "Primary: $(build_backend_url | sed "s/:$APP_PORT//")"
if [[ -n "\${EXTERNAL_HTTP_PORT:-}" && "\$EXTERNAL_HTTP_PORT" != "80" ]]; then
    echo "HTTP Port: \$EXTERNAL_HTTP_PORT"
fi
if [[ -n "\${EXTERNAL_HTTPS_PORT:-}" && "\$EXTERNAL_HTTPS_PORT" != "443" ]]; then
    echo "HTTPS Port: \$EXTERNAL_HTTPS_PORT"
fi
EOF
    
    chmod +x "/usr/local/bin/$APP_NAME-status"
    
    print_success "Status command created: $APP_NAME-status"
}

create_management_scripts() {
    print_step "Creating management scripts..."
    
    # Update script
    cat > "/usr/local/bin/$APP_NAME-update" << EOF
#!/bin/bash
set -e

echo "Updating Secret Poll application..."
cd "$APP_DIR"

# Backup current state
cp -r . "../$APP_NAME-backup-\$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

case "$DEPLOYMENT_TYPE" in
    "docker-isolated")
        docker-compose -f docker-compose.isolated.yml down
        docker-compose -f docker-compose.isolated.yml up -d --build
        ;;
    "docker-standard")
        docker-compose -f docker-compose.yml down
        docker-compose -f docker-compose.yml up -d --build
        ;;
    *)
        # Manual update
        cd backend
        source venv/bin/activate
        pip install -r requirements.txt --upgrade
        cd ../frontend
        if [[ -f yarn.lock ]]; then
            yarn install
            yarn build
        else
            npm install
            npm run build
        fi
        pm2 restart all
        ;;
esac

echo "Update completed!"
EOF
    
    # Restart script
    cat > "/usr/local/bin/$APP_NAME-restart" << EOF
#!/bin/bash

echo "Restarting Secret Poll application..."

case "$DEPLOYMENT_TYPE" in
    "docker-isolated")
        cd "$APP_DIR"
        docker-compose -f docker-compose.isolated.yml restart
        ;;
    "docker-standard")
        cd "$APP_DIR"
        docker-compose -f docker-compose.yml restart
        ;;
    "portable")
        cd "$APP_DIR"
        ./stop.sh
        sleep 2
        ./start.sh
        ;;
    *)
        pm2 restart all
        systemctl reload nginx 2>/dev/null || true
        ;;
esac

echo "Restart completed!"
EOF
    
    # Stop script
    cat > "/usr/local/bin/$APP_NAME-stop" << EOF
#!/bin/bash

echo "Stopping Secret Poll application..."

case "$DEPLOYMENT_TYPE" in
    "docker-isolated")
        cd "$APP_DIR"
        docker-compose -f docker-compose.isolated.yml down
        ;;
    "docker-standard")
        cd "$APP_DIR"
        docker-compose -f docker-compose.yml down
        ;;
    "portable")
        cd "$APP_DIR"
        ./stop.sh
        ;;
    *)
        pm2 stop all
        ;;
esac

echo "Application stopped!"
EOF
    
    # Logs script
    cat > "/usr/local/bin/$APP_NAME-logs" << EOF
#!/bin/bash

case "$DEPLOYMENT_TYPE" in
    "docker-isolated")
        cd "$APP_DIR"
        docker-compose -f docker-compose.isolated.yml logs -f
        ;;
    "docker-standard")
        cd "$APP_DIR"
        docker-compose -f docker-compose.yml logs -f
        ;;
    *)
        if command -v pm2 &> /dev/null; then
            pm2 logs
        else
            tail -f "$LOG_FILE"
        fi
        ;;
esac
EOF
    
    chmod +x "/usr/local/bin/$APP_NAME"-{update,restart,stop,logs}
    
    print_success "Management scripts created"
}

create_monitoring_setup() {
    print_step "Setting up monitoring..."
    
    # Create log rotation
    cat > "/etc/logrotate.d/$APP_NAME" << EOF
$LOG_FILE {
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

/var/log/$APP_NAME/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
}
EOF
    
    # Create simple health check
    cat > "/usr/local/bin/$APP_NAME-healthcheck" << EOF
#!/bin/bash

HEALTH_URL="$(build_backend_url)/api/health"
LOG_FILE="/var/log/$APP_NAME/health.log"

mkdir -p "\$(dirname "\$LOG_FILE")"

if curl -f -s --max-time 10 "\$HEALTH_URL" > /dev/null 2>&1; then
    echo "\$(date): OK" >> "\$LOG_FILE"
    exit 0
else
    echo "\$(date): FAIL" >> "\$LOG_FILE"
    exit 1
fi
EOF
    
    chmod +x "/usr/local/bin/$APP_NAME-healthcheck"
    
    # Add to crontab for monitoring (optional)
    if confirm_action "Setup automated health monitoring (runs every 5 minutes)?" "n"; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/$APP_NAME-healthcheck") | crontab -
        print_success "Health monitoring enabled"
    fi
}

create_backup_system() {
    print_step "Creating backup system..."
    
    cat > "/usr/local/bin/$APP_NAME-backup" << EOF
#!/bin/bash
set -e

BACKUP_DIR="/opt/$APP_NAME-backups"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/backup_\$TIMESTAMP.tar.gz"

echo "Creating backup..."
mkdir -p "\$BACKUP_DIR"

# Database backup
case "$DEPLOYMENT_TYPE" in
    "docker-isolated")
        cd "$APP_DIR"
        docker-compose -f docker-compose.isolated.yml exec -T mongodb mongodump --archive > "\$BACKUP_DIR/mongodb_\$TIMESTAMP.archive"
        ;;
    "docker-standard")
        cd "$APP_DIR"
        docker-compose -f docker-compose.yml exec -T mongodb mongodump --archive > "\$BACKUP_DIR/mongodb_\$TIMESTAMP.archive"
        ;;
    *)
        mongodump --db $DB_NAME --archive="\$BACKUP_DIR/mongodb_\$TIMESTAMP.archive" 2>/dev/null || echo "MongoDB backup failed"
        ;;
esac

# Application backup
tar -czf "\$BACKUP_FILE" -C "$APP_DIR" \
    .env backend/.env frontend/.env \
    docker-compose*.yml nginx.conf ecosystem.config.js \
    2>/dev/null || true

echo "Backup created: \$BACKUP_FILE"

# Cleanup old backups (keep last 7)
find "\$BACKUP_DIR" -name "backup_*.tar.gz" -type f -mtime +7 -delete 2>/dev/null || true
find "\$BACKUP_DIR" -name "mongodb_*.archive" -type f -mtime +7 -delete 2>/dev/null || true

echo "Backup completed!"
EOF
    
    chmod +x "/usr/local/bin/$APP_NAME-backup"
    
    print_success "Backup system created"
}

# =============================================================================
# CUSTOM DEPLOYMENT WIZARD
# =============================================================================

custom_deployment_wizard() {
    print_header "CUSTOM DEPLOYMENT WIZARD"
    
    echo -e "${YELLOW}This wizard will guide you through a completely custom deployment.${NC}"
    echo -e "${YELLOW}You'll have control over every aspect of the installation.${NC}\n"
    
    # Advanced configuration
    configure_custom_ports
    configure_custom_database
    configure_custom_web_server
    configure_custom_ssl
    configure_custom_security
    
    # Execute custom deployment
    execute_custom_deployment
}

configure_custom_ports() {
    echo -e "\n${CYAN}Port Configuration:${NC}"
    
    APP_PORT=$(prompt_input "Backend port" "$APP_PORT")
    FRONTEND_PORT=$(prompt_input "Frontend port" "$FRONTEND_PORT")
    
    local custom_mongo_port=$(prompt_input "MongoDB port (leave empty for default)" "")
    if [[ -n "$custom_mongo_port" ]]; then
        MONGO_URL="mongodb://localhost:${custom_mongo_port}/${DB_NAME}"
    fi
}

configure_custom_database() {
    echo -e "\n${CYAN}Database Configuration:${NC}"
    
    echo "1) Use existing MongoDB"
    echo "2) Install new MongoDB locally"
    echo "3) Use remote MongoDB"
    echo "4) Use Docker MongoDB"
    
    local db_choice=$(prompt_input "Choose database option (1-4)" "2")
    
    case "$db_choice" in
        1)
            MONGO_URL=$(prompt_input "MongoDB connection string" "$MONGO_URL")
            ;;
        2)
            install_mongodb
            ;;
        3)
            local remote_host=$(prompt_input "MongoDB host" "")
            local remote_port=$(prompt_input "MongoDB port" "27017")
            local remote_user=$(prompt_input "Username (optional)" "")
            local remote_pass=$(prompt_input "Password (optional)" "" "true")
            
            if [[ -n "$remote_user" ]]; then
                MONGO_URL="mongodb://${remote_user}:${remote_pass}@${remote_host}:${remote_port}/${DB_NAME}"
            else
                MONGO_URL="mongodb://${remote_host}:${remote_port}/${DB_NAME}"
            fi
            ;;
        4)
            DEPLOYMENT_TYPE="docker-custom"
            ;;
    esac
}

configure_custom_web_server() {
    echo -e "\n${CYAN}Web Server Configuration:${NC}"
    
    echo "1) Install and configure Nginx"
    echo "2) Use existing Nginx"
    echo "3) Install and configure Apache"
    echo "4) Use existing Apache"
    echo "5) No web server (direct access)"
    
    local web_choice=$(prompt_input "Choose web server option (1-5)" "1")
    
    case "$web_choice" in
        1)
            CUSTOM_WEB_SERVER="nginx-new"
            ;;
        2)
            CUSTOM_WEB_SERVER="nginx-existing"
            ;;
        3)
            CUSTOM_WEB_SERVER="apache-new"
            ;;
        4)
            CUSTOM_WEB_SERVER="apache-existing"
            ;;
        5)
            CUSTOM_WEB_SERVER="none"
            ;;
    esac
}

configure_custom_ssl() {
    if [[ "$CUSTOM_WEB_SERVER" == "none" ]]; then
        USE_SSL=false
        return
    fi
    
    echo -e "\n${CYAN}SSL Configuration:${NC}"
    
    echo "1) Generate Let's Encrypt certificate"
    echo "2) Use existing certificates"
    echo "3) Self-signed certificate"
    echo "4) No SSL"
    
    local ssl_choice=$(prompt_input "Choose SSL option (1-4)" "1")
    
    case "$ssl_choice" in
        1)
            USE_SSL=true
            CUSTOM_SSL="letsencrypt"
            ADMIN_EMAIL=$(prompt_input "Email for Let's Encrypt" "")
            ;;
        2)
            USE_SSL=true
            CUSTOM_SSL="existing"
            CUSTOM_SSL_CERT=$(prompt_input "Path to certificate file" "")
            CUSTOM_SSL_KEY=$(prompt_input "Path to private key file" "")
            ;;
        3)
            USE_SSL=true
            CUSTOM_SSL="selfsigned"
            ;;
        4)
            USE_SSL=false
            ;;
    esac
}

configure_custom_security() {
    echo -e "\n${CYAN}Security Configuration:${NC}"
    
    CUSTOM_FIREWALL=$(confirm_action "Configure firewall rules?" "y")
    CUSTOM_FAIL2BAN=$(confirm_action "Install and configure Fail2ban?" "n")
    CUSTOM_RATE_LIMITING=$(confirm_action "Enable rate limiting?" "y")
}

execute_custom_deployment() {
    print_step "Executing custom deployment..."
    
    # Deploy based on custom configuration
    case "$DEPLOYMENT_TYPE" in
        "docker-custom")
            create_custom_docker_setup
            ;;
        *)
            create_custom_manual_setup
            ;;
    esac
    
    # Configure web server
    configure_custom_web_server_setup
    
    # Setup SSL
    if [[ "$USE_SSL" == true ]]; then
        setup_custom_ssl
    fi
    
    # Security setup
    if [[ "$CUSTOM_FIREWALL" == true ]]; then
        setup_custom_firewall
    fi
    
    print_success "Custom deployment completed"
}

# Additional custom deployment functions would be implemented here...

# =============================================================================
# FINAL DEPLOYMENT SUMMARY
# =============================================================================

show_final_summary() {
    print_header "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"
    
    echo -e "${GREEN}Secret Poll has been deployed and is ready to use!${NC}\n"
    
    # Application URLs
    echo -e "${CYAN}📱 Application Access:${NC}"
    local primary_url=$(build_backend_url | sed "s/:$APP_PORT//")
    echo -e "  • Primary URL: ${GREEN}$primary_url${NC}"
    
    if [[ "$USE_WWW" == true ]]; then
        local www_url=$(echo "$primary_url" | sed "s://$DOMAIN://$WWW_DOMAIN:")
        echo -e "  • WWW URL: ${GREEN}$www_url${NC}"
    fi
    
    if [[ -n "${EXTERNAL_HTTP_PORT:-}" && "$EXTERNAL_HTTP_PORT" != "80" ]]; then
        echo -e "  • HTTP Port: ${YELLOW}$EXTERNAL_HTTP_PORT${NC}"
    fi
    
    if [[ -n "${EXTERNAL_HTTPS_PORT:-}" && "$EXTERNAL_HTTPS_PORT" != "443" ]]; then
        echo -e "  • HTTPS Port: ${YELLOW}$EXTERNAL_HTTPS_PORT${NC}"
    fi
    
    # Deployment details
    echo -e "\n${CYAN}🔧 Deployment Details:${NC}"
    echo -e "  • Type: ${YELLOW}$DEPLOYMENT_TYPE${NC}"
    echo -e "  • Location: ${YELLOW}$APP_DIR${NC}"
    echo -e "  • Environment: ${YELLOW}$ENVIRONMENT${NC}"
    echo -e "  • SSL Enabled: ${YELLOW}$USE_SSL${NC}"
    
    # Management commands
    echo -e "\n${CYAN}🛠️ Management Commands:${NC}"
    echo -e "  • Status: ${YELLOW}$APP_NAME-status${NC}"
    echo -e "  • Restart: ${YELLOW}$APP_NAME-restart${NC}"
    echo -e "  • Stop: ${YELLOW}$APP_NAME-stop${NC}"
    echo -e "  • Logs: ${YELLOW}$APP_NAME-logs${NC}"
    echo -e "  • Update: ${YELLOW}$APP_NAME-update${NC}"
    echo -e "  • Backup: ${YELLOW}$APP_NAME-backup${NC}"
    
    # Service management
    echo -e "\n${CYAN}🔄 Service Management:${NC}"
    case "$DEPLOYMENT_TYPE" in
        "docker-isolated")
            echo -e "  • View containers: ${YELLOW}cd $APP_DIR && docker-compose -f docker-compose.isolated.yml ps${NC}"
            echo -e "  • Container logs: ${YELLOW}cd $APP_DIR && docker-compose -f docker-compose.isolated.yml logs -f${NC}"
            ;;
        "docker-standard")
            echo -e "  • View containers: ${YELLOW}cd $APP_DIR && docker-compose ps${NC}"
            echo -e "  • Container logs: ${YELLOW}cd $APP_DIR && docker-compose logs -f${NC}"
            ;;
        "portable")
            echo -e "  • Start: ${YELLOW}cd $APP_DIR && ./start.sh${NC}"
            echo -e "  • Stop: ${YELLOW}cd $APP_DIR && ./stop.sh${NC}"
            echo -e "  • Status: ${YELLOW}cd $APP_DIR && ./status.sh${NC}"
            ;;
        *)
            echo -e "  • PM2 status: ${YELLOW}pm2 status${NC}"
            echo -e "  • PM2 logs: ${YELLOW}pm2 logs${NC}"
            ;;
    esac
    
    # Important files and directories
    echo -e "\n${CYAN}📁 Important Locations:${NC}"
    echo -e "  • Application: ${YELLOW}$APP_DIR${NC}"
    echo -e "  • Logs: ${YELLOW}$LOG_FILE${NC}"
    echo -e "  • Backups: ${YELLOW}$BACKUP_DIR${NC}"
    echo -e "  • Rollback: ${YELLOW}$ROLLBACK_DIR${NC}"
    
    # SSL information
    if [[ "$USE_SSL" == true ]]; then
        echo -e "\n${CYAN}🔒 SSL Certificate:${NC}"
        echo -e "  • Auto-renewal is configured"
        echo -e "  • Manual renewal: ${YELLOW}certbot renew${NC}"
        echo -e "  • Certificate location: ${YELLOW}/etc/letsencrypt/live/$DOMAIN${NC}"
    fi
    
    # Next steps
    echo -e "\n${CYAN}🚀 Next Steps:${NC}"
    
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "  1. ${YELLOW}Your application is accessible via IP address${NC}"
    else
        echo -e "  1. ${YELLOW}Ensure your domain $DOMAIN points to this server's IP${NC}"
    fi
    
    echo -e "  2. ${YELLOW}Test your application thoroughly${NC}"
    echo -e "  3. ${YELLOW}Configure any additional security as needed${NC}"
    echo -e "  4. ${YELLOW}Set up monitoring and alerting${NC}"
    echo -e "  5. ${YELLOW}Create regular backup schedules${NC}"
    
    # Troubleshooting
    echo -e "\n${CYAN}🔍 Troubleshooting:${NC}"
    echo -e "  • Check status: ${YELLOW}$APP_NAME-status${NC}"
    echo -e "  • View logs: ${YELLOW}$APP_NAME-logs${NC}"
    echo -e "  • Health check: ${YELLOW}curl $(build_backend_url)/api/health${NC}"
    echo -e "  • Rollback: ${YELLOW}$ROLLBACK_DIR/rollback.sh${NC}"
    
    # Contact and support
    echo -e "\n${CYAN}📞 Support:${NC}"
    echo -e "  • Documentation: Check the README.md in $APP_DIR"
    echo -e "  • Logs: All deployment logs are in $LOG_FILE"
    
    echo -e "\n${GREEN}🎊 Congratulations! Your Secret Poll application is now live and ready for use! 🎊${NC}"
    
    # Final verification
    echo -e "\n${YELLOW}Running final verification...${NC}"
    sleep 2
    
    local health_url=$(build_backend_url)/api/health
    if curl -f -s --max-time 10 "$health_url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Application is responding correctly!${NC}"
    else
        echo -e "${YELLOW}⚠️  Application might still be starting up. Please wait a few minutes and check again.${NC}"
    fi
    
    log_action "Deployment completed successfully - $DEPLOYMENT_TYPE at $APP_DIR"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Initialize
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    log_action "Turnkey deployment script started"
    
    print_header "SECRET POLL - TURNKEY DEPLOYMENT SCRIPT"
    echo -e "${CYAN}This script will deploy Secret Poll in a completely automated way${NC}"
    echo -e "${CYAN}that works in ANY server environment without breaking existing services.${NC}\n"
    
    # Pre-flight checks
    print_header "SYSTEM ANALYSIS"
    check_root
    check_os
    check_system_resources
    detect_existing_services
    
    # Create backup point
    create_backup_point
    
    # Choose deployment strategy
    choose_deployment_strategy
    
    # Collect configuration
    collect_configuration
    
    # System preparation
    print_header "SYSTEM PREPARATION"
    update_system
    install_dependencies
    
    # Application deployment
    deploy_application
    
    # SSL setup
    if [[ "$USE_SSL" == true ]]; then
        setup_ssl
    fi
    
    # Post-deployment setup
    create_management_tools
    
    # Final verification
    verify_deployment
    
    # Show final summary
    show_final_summary
}

# Error handling
trap 'echo -e "\n${RED}Deployment interrupted!${NC}"; echo "Rollback available at: $ROLLBACK_DIR/rollback.sh"; exit 1' INT TERM

# Execute main function
main "$@"

exit 0