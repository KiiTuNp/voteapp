#!/bin/bash

# =============================================================================
# Secret Poll - Auto Deployment Script (Non-Interactive)
# =============================================================================
# This version runs automatically with sensible defaults for testing/CI
# For interactive deployment, use deploy.sh
#
# Usage: ./deploy-auto.sh [DOMAIN] [DEPLOYMENT_TYPE]
# 
# Examples:
#   ./deploy-auto.sh example.com docker-isolated
#   ./deploy-auto.sh 192.168.1.100 portable
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

# Default configuration
DOMAIN="${1:-localhost}"
DEPLOYMENT_TYPE="${2:-portable}"
APP_NAME="secret-poll"
DEFAULT_APP_DIR="/opt/$APP_NAME"
LOG_FILE="/var/log/$APP_NAME-deploy.log"
BACKUP_DIR="/opt/$APP_NAME-backups"
ROLLBACK_DIR="/opt/$APP_NAME-rollback"

# Auto-configuration based on domain
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$DOMAIN" == "localhost" ]]; then
    USE_SSL=false
    USE_WWW=false
    ADMIN_EMAIL=""
else
    USE_SSL=true
    USE_WWW=true
    ADMIN_EMAIL="admin@${DOMAIN}"
fi

# Port configuration
APP_PORT="18001"  # High port to avoid conflicts
FRONTEND_PORT="13000"  # High port to avoid conflicts
DB_NAME="poll_app_auto"
MONGO_URL="mongodb://localhost:27017/${DB_NAME}"

# Repository configuration
REPO_URL="https://github.com/KiiTuNp/voteapp.git"
DEPLOY_BRANCH="main"
ENVIRONMENT="production"

# Set app directory based on deployment type
if [[ "$DEPLOYMENT_TYPE" == "portable" ]]; then
    APP_DIR="$HOME/$APP_NAME"
else
    APP_DIR="$DEFAULT_APP_DIR"
fi

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
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$(date): $1" >> "$LOG_FILE"
}

# =============================================================================
# SYSTEM CHECKS
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]] && [[ "$DEPLOYMENT_TYPE" != "portable" ]]; then
        print_error "This script must be run as root for $DEPLOYMENT_TYPE deployment."
        print_info "Either run with sudo or use 'portable' deployment type."
        exit 1
    fi
}

update_system() {
    print_step "Updating system packages..."
    
    if [[ $EUID -eq 0 ]]; then
        # Only update if running as root
        if command -v apt-get &> /dev/null; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y >> "$LOG_FILE" 2>&1
            apt-get install -y curl wget git unzip python3 python3-pip python3-venv nodejs npm >> "$LOG_FILE" 2>&1
        elif command -v yum &> /dev/null; then
            yum update -y >> "$LOG_FILE" 2>&1
            yum install -y curl wget git unzip python3 python3-pip nodejs npm >> "$LOG_FILE" 2>&1
        fi
    else
        print_info "Skipping system update (not running as root)"
    fi
    
    print_success "System preparation completed"
}

# =============================================================================
# APPLICATION DEPLOYMENT
# =============================================================================

prepare_application_directory() {
    print_step "Preparing application directory at $APP_DIR..."
    
    # Create directory structure
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Clone repository
    if [[ -d ".git" ]]; then
        print_info "Repository already exists, updating..."
        git fetch origin >> "$LOG_FILE" 2>&1
        git checkout "$DEPLOY_BRANCH" >> "$LOG_FILE" 2>&1
        git pull origin "$DEPLOY_BRANCH" >> "$LOG_FILE" 2>&1
    else
        print_info "Cloning repository from $REPO_URL..."
        git clone "$REPO_URL" . >> "$LOG_FILE" 2>&1
        git checkout "$DEPLOY_BRANCH" >> "$LOG_FILE" 2>&1
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
CORS_ORIGINS=http://$DOMAIN:$APP_PORT,http://$DOMAIN:$FRONTEND_PORT

# Application Configuration
PORT=$APP_PORT
ENVIRONMENT=$ENVIRONMENT

# Generated automatically on $(date)
EOF
    
    # Frontend environment
    cat > "$APP_DIR/frontend/.env" << EOF
# Backend Configuration
REACT_APP_BACKEND_URL=http://$DOMAIN:$APP_PORT

# Application Configuration
PORT=$FRONTEND_PORT
GENERATE_SOURCEMAP=false

# Environment
NODE_ENV=$ENVIRONMENT

# Generated automatically on $(date)
EOF
    
    print_success "Environment files created"
}

build_application() {
    print_step "Building application..."
    
    # Backend setup
    print_info "Setting up backend..."
    cd "$APP_DIR/backend"
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip >> "$LOG_FILE" 2>&1
    pip install -r requirements.txt >> "$LOG_FILE" 2>&1
    
    # Frontend setup
    print_info "Building frontend..."
    cd "$APP_DIR/frontend"
    
    # Use yarn if available, otherwise npm
    if command -v yarn &> /dev/null && [[ -f yarn.lock ]]; then
        yarn install >> "$LOG_FILE" 2>&1
        yarn build >> "$LOG_FILE" 2>&1
    else
        npm install >> "$LOG_FILE" 2>&1
        npm run build >> "$LOG_FILE" 2>&1
    fi
    
    print_success "Application built successfully"
}

create_startup_scripts() {
    print_step "Creating startup scripts..."
    
    # Backend startup script
    cat > "$APP_DIR/start-backend.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")/backend"
source venv/bin/activate
export MONGO_URL="$MONGO_URL"
export PORT="$APP_PORT"
python server.py
EOF
    
    # Frontend startup script (simple HTTP server)
    cat > "$APP_DIR/start-frontend.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")/frontend/build"
python3 -m http.server $FRONTEND_PORT
EOF
    
    # Main startup script
    cat > "$APP_DIR/start.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"

echo "Starting Secret Poll..."

# Start backend
./start-backend.sh &
BACKEND_PID=\$!
echo \$BACKEND_PID > backend.pid

# Start frontend
./start-frontend.sh &
FRONTEND_PID=\$!
echo \$FRONTEND_PID > frontend.pid

echo "Secret Poll started successfully!"
echo "Backend: http://$DOMAIN:$APP_PORT"
echo "Frontend: http://$DOMAIN:$FRONTEND_PORT"
echo ""
echo "To stop: ./stop.sh"
EOF
    
    # Stop script
    cat > "$APP_DIR/stop.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"

echo "Stopping Secret Poll..."

if [[ -f backend.pid ]] && kill -0 \$(cat backend.pid) 2>/dev/null; then
    kill \$(cat backend.pid)
    rm backend.pid
    echo "Backend stopped"
fi

if [[ -f frontend.pid ]] && kill -0 \$(cat frontend.pid) 2>/dev/null; then
    kill \$(cat frontend.pid)
    rm frontend.pid
    echo "Frontend stopped"
fi

echo "Secret Poll stopped."
EOF
    
    # Status script
    cat > "$APP_DIR/status.sh" << EOF
#!/bin/bash
cd "\$(dirname "\$0")"

echo "Secret Poll Status:"

if [[ -f backend.pid ]] && kill -0 \$(cat backend.pid) 2>/dev/null; then
    echo "  Backend: Running (PID: \$(cat backend.pid)) - http://$DOMAIN:$APP_PORT"
else
    echo "  Backend: Stopped"
fi

if [[ -f frontend.pid ]] && kill -0 \$(cat frontend.pid) 2>/dev/null; then
    echo "  Frontend: Running (PID: \$(cat frontend.pid)) - http://$DOMAIN:$FRONTEND_PORT"
else
    echo "  Frontend: Stopped"
fi
EOF
    
    # Make scripts executable
    chmod +x "$APP_DIR"/{start,stop,status,start-backend,start-frontend}.sh
    
    print_success "Startup scripts created"
}

# =============================================================================
# VERIFICATION
# =============================================================================

verify_installation() {
    print_step "Verifying installation..."
    
    # Check if files exist
    local required_files=(
        "$APP_DIR/backend/server.py"
        "$APP_DIR/frontend/build/index.html"
        "$APP_DIR/backend/.env"
        "$APP_DIR/frontend/.env"
        "$APP_DIR/start.sh"
        "$APP_DIR/stop.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_success "✓ $file exists"
        else
            print_error "✗ $file missing"
            return 1
        fi
    done
    
    print_success "Installation verification completed"
    return 0
}

show_summary() {
    print_header "🎉 AUTO DEPLOYMENT COMPLETED! 🎉"
    
    echo -e "${GREEN}Secret Poll has been automatically deployed!${NC}\n"
    
    echo -e "${CYAN}📱 Application Configuration:${NC}"
    echo -e "  • Deployment Type: ${YELLOW}$DEPLOYMENT_TYPE${NC}"
    echo -e "  • Installation Directory: ${YELLOW}$APP_DIR${NC}"
    echo -e "  • Domain/IP: ${YELLOW}$DOMAIN${NC}"
    echo -e "  • Backend Port: ${YELLOW}$APP_PORT${NC}"
    echo -e "  • Frontend Port: ${YELLOW}$FRONTEND_PORT${NC}"
    
    echo -e "\n${CYAN}🚀 How to Start:${NC}"
    echo -e "  ${YELLOW}cd $APP_DIR${NC}"
    echo -e "  ${YELLOW}./start.sh${NC}"
    
    echo -e "\n${CYAN}🛠️ Management Commands:${NC}"
    echo -e "  • Start: ${YELLOW}$APP_DIR/start.sh${NC}"
    echo -e "  • Stop: ${YELLOW}$APP_DIR/stop.sh${NC}"
    echo -e "  • Status: ${YELLOW}$APP_DIR/status.sh${NC}"
    
    echo -e "\n${CYAN}🌐 Access URLs (after starting):${NC}"
    echo -e "  • Backend API: ${GREEN}http://$DOMAIN:$APP_PORT${NC}"
    echo -e "  • Frontend App: ${GREEN}http://$DOMAIN:$FRONTEND_PORT${NC}"
    echo -e "  • Health Check: ${GREEN}http://$DOMAIN:$APP_PORT/api/health${NC}"
    
    if [[ "$DOMAIN" == "localhost" ]]; then
        echo -e "\n${YELLOW}💡 Note: Using localhost. For external access, replace with your server's IP address.${NC}"
    fi
    
    echo -e "\n${GREEN}🎊 Ready to use! Start the application with the commands above. 🎊${NC}"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    print_header "SECRET POLL - AUTO DEPLOYMENT"
    
    print_info "Auto deployment configuration:"
    print_info "  Domain: $DOMAIN"
    print_info "  Type: $DEPLOYMENT_TYPE" 
    print_info "  Backend Port: $APP_PORT"
    print_info "  Frontend Port: $FRONTEND_PORT"
    
    log_action "Auto deployment started - $DEPLOYMENT_TYPE for $DOMAIN"
    
    # System preparation
    check_root
    update_system
    
    # Application deployment
    prepare_application_directory
    create_environment_files
    build_application
    create_startup_scripts
    
    # Verification
    if verify_installation; then
        show_summary
        log_action "Auto deployment completed successfully"
    else
        print_error "Installation verification failed"
        exit 1
    fi
}

# Handle script arguments
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [DOMAIN] [DEPLOYMENT_TYPE]"
    echo ""
    echo "Arguments:"
    echo "  DOMAIN          Domain name or IP address (default: localhost)"
    echo "  DEPLOYMENT_TYPE Deployment type: portable, docker-isolated, manual (default: portable)"
    echo ""
    echo "Examples:"
    echo "  $0                              # Deploy on localhost with portable mode"
    echo "  $0 192.168.1.100               # Deploy on IP with portable mode"
    echo "  $0 example.com docker-isolated  # Deploy on domain with Docker"
    exit 0
fi

# Execute main function
main "$@"

exit 0