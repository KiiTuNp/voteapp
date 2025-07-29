#!/bin/bash

# =============================================================================
# Secret Poll - Script de Déploiement Final (Interactif)
# =============================================================================
# Version qui fonctionne avec les inputs standards et les pipes
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration par défaut
REPO_URL="https://github.com/KiiTuNp/voteapp.git"
BRANCH="main"
DEFAULT_DOMAIN="localhost"
DEFAULT_INSTALL_DIR="/opt/secret-poll"

# Variables globales
DOMAIN=""
INSTALL_DIR=""
DEPLOYMENT_TYPE=""
USE_SSL=false
EMAIL=""

print_header() {
    echo -e "${PURPLE}"
    echo "============================================================================="
    echo "$1"
    echo "============================================================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}[ÉTAPE]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCÈS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERREUR]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1"
}

# Fonction d'input qui fonctionne avec les pipes et l'interactivité
safe_read() {
    local prompt="$1"
    local default="$2"
    local hide_input="$3"
    local value=""
    
    # Afficher le prompt
    if [[ -n "$default" ]]; then
        echo -ne "${CYAN}$prompt${NC} ${YELLOW}(défaut: $default)${NC}: " >&2
    else
        echo -ne "${CYAN}$prompt${NC}: " >&2
    fi
    
    # Lire l'input
    if [[ "$hide_input" == "true" ]]; then
        read -s value
        echo >&2  # Nouvelle ligne après input caché
    else
        read value
    fi
    
    # Utiliser la valeur par défaut si vide
    if [[ -z "$value" ]]; then
        value="$default"
    fi
    
    echo "$value"
}

# Fonction de confirmation oui/non
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -ne "${YELLOW}$prompt [O/n]:${NC} " >&2
        else
            echo -ne "${YELLOW}$prompt [o/N]:${NC} " >&2
        fi
        
        read response
        response=${response:-$default}
        
        case "$response" in
            [Yy]|[Oo]|[Yy][Ee][Ss]|[Oo][Uu][Ii])
                return 0
                ;;
            [Nn]|[Nn][Oo]|[Nn][Oo][Nn])
                return 1
                ;;
            *)
                echo -e "${RED}Réponse invalide. Tapez 'o' pour oui ou 'n' pour non.${NC}" >&2
                continue
                ;;
        esac
    done
}

# Fonction de choix multiple
choose_option() {
    local title="$1"
    shift
    local options=("$@")
    local choice
    
    echo -e "\n${CYAN}$title${NC}" >&2
    for i in "${!options[@]}"; do
        echo "$((i+1))) ${options[i]}" >&2
    done
    echo >&2
    
    while true; do
        echo -ne "${CYAN}Votre choix (1-${#options[@]})${NC} ${YELLOW}[défaut: 1]${NC}: " >&2
        read choice
        choice=${choice:-1}
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#options[@]}" ]]; then
            echo "$choice"
            return
        else
            echo -e "${RED}Choix invalide. Tapez un nombre entre 1 et ${#options[@]}.${NC}" >&2
            continue
        fi
    done
}

check_requirements() {
    print_step "Vérification des prérequis"
    
    # Vérification root
    if [[ $EUID -ne 0 ]]; then
        print_error "Ce script doit être exécuté en tant que root"
        print_info "Veuillez exécuter: sudo $0"
        exit 1
    fi
    
    # Vérification des outils nécessaires
    local missing_tools=()
    
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_warning "Outils manquants: ${missing_tools[*]}"
        if confirm "Installer les outils manquants?" "y"; then
            apt-get update -y
            apt-get install -y "${missing_tools[@]}"
        else
            print_error "Les outils requis ne sont pas disponibles"
            exit 1
        fi
    fi
    
    print_success "Prérequis vérifiés"
}

collect_configuration() {
    print_header "🔧 CONFIGURATION"
    
    print_info "Configurons votre installation Secret Poll..."
    echo >&2
    
    # Domaine ou IP
    DOMAIN=$(safe_read "Entrez votre domaine ou adresse IP" "$DEFAULT_DOMAIN")
    print_info "Domaine configuré: $DOMAIN"
    
    # Répertoire d'installation  
    INSTALL_DIR=$(safe_read "Répertoire d'installation" "$DEFAULT_INSTALL_DIR")
    print_info "Installation dans: $INSTALL_DIR"
    
    # Type de déploiement
    local deployment_options=(
        "🐳 Docker (Recommandé - Isolation complète)"
        "📦 Manuel (Installation directe)"
        "💼 Portable (Répertoire utilisateur)"
        "⚙️ Automatique (Choix optimal)"
    )
    
    local choice=$(choose_option "Choisissez le type de déploiement:" "${deployment_options[@]}")
    
    case "$choice" in
        1) DEPLOYMENT_TYPE="docker" ;;
        2) DEPLOYMENT_TYPE="manual" ;;
        3) DEPLOYMENT_TYPE="portable" ;;
        4) DEPLOYMENT_TYPE="auto" ;;
    esac
    
    print_info "Type sélectionné: $DEPLOYMENT_TYPE"
    
    # Configuration SSL pour les domaines
    if [[ "$DOMAIN" != "localhost" ]] && [[ ! "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if confirm "Configurer SSL avec Let's Encrypt?" "y"; then
            USE_SSL=true
            EMAIL=$(safe_read "Email pour le certificat SSL" "admin@$DOMAIN")
            print_info "SSL activé avec email: $EMAIL"
        else
            USE_SSL=false
            print_info "SSL désactivé"
        fi
    else
        USE_SSL=false
        print_info "SSL désactivé (localhost ou IP détectée)"
    fi
}

show_configuration_summary() {
    print_header "📋 RÉSUMÉ DE LA CONFIGURATION"
    
    echo -e "${CYAN}🌐 Domaine:${NC} $DOMAIN"
    echo -e "${CYAN}📁 Installation:${NC} $INSTALL_DIR"
    echo -e "${CYAN}🚀 Type:${NC} $DEPLOYMENT_TYPE"
    echo -e "${CYAN}🔒 SSL:${NC} $([ "$USE_SSL" = true ] && echo "Activé ($EMAIL)" || echo "Désactivé")"
    echo -e "${CYAN}📦 Repository:${NC} $REPO_URL"
    echo >&2
}

execute_deployment() {
    print_header "🚀 DÉPLOIEMENT"
    
    print_step "Préparation du répertoire"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    print_success "Répertoire créé: $INSTALL_DIR"
    
    print_step "Téléchargement du code source"
    if [[ -d ".git" ]]; then
        print_info "Repository existant détecté, mise à jour..."
        git fetch origin
        git reset --hard origin/$BRANCH
    else
        print_info "Clonage depuis $REPO_URL..."
        git clone "$REPO_URL" .
        git checkout "$BRANCH"
    fi
    print_success "Code source téléchargé"
    
    print_step "Configuration des variables d'environnement"
    
    # Configuration backend
    mkdir -p backend
    cat > backend/.env << EOF
# Configuration Secret Poll Backend
MONGO_URL=mongodb://localhost:27017/poll_app
PORT=8001
ENVIRONMENT=production
CORS_ORIGINS=http://$DOMAIN,https://$DOMAIN

# Généré automatiquement le $(date)
EOF
    
    # Configuration frontend
    mkdir -p frontend
    cat > frontend/.env << EOF
# Configuration Secret Poll Frontend
REACT_APP_BACKEND_URL=http://$DOMAIN:8001
PORT=3000
NODE_ENV=production
GENERATE_SOURCEMAP=false

# Généré automatiquement le $(date)
EOF
    
    print_success "Fichiers d'environnement créés"
    
    # Installation selon le type choisi
    case "$DEPLOYMENT_TYPE" in
        "docker")
            install_docker_deployment
            ;;
        "manual")
            install_manual_deployment
            ;;
        "portable")
            install_portable_deployment
            ;;
        "auto")
            install_auto_deployment
            ;;
    esac
}

install_auto_deployment() {
    print_step "Installation automatique"
    print_info "Choix du meilleur type de déploiement automatiquement..."
    
    # Vérifier Docker
    if command -v docker &> /dev/null && systemctl is-active --quiet docker; then
        print_info "Docker détecté, utilisation du déploiement Docker"
        install_docker_deployment
    else
        print_info "Docker non disponible, utilisation du déploiement portable"
        install_portable_deployment
    fi
}

install_portable_deployment() {
    print_step "Installation portable"
    
    # Installation des dépendances de base
    print_info "Installation des dépendances..."
    
    # Update package list
    apt-get update -y >> /var/log/secret-poll-deploy.log 2>&1
    
    # Install basic dependencies
    apt-get install -y curl wget git python3 python3-pip python3-venv >> /var/log/secret-poll-deploy.log 2>&1
    
    # Install Node.js 18
    if ! node --version 2>/dev/null | grep -q "v18"; then
        print_info "Installation de Node.js 18..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >> /var/log/secret-poll-deploy.log 2>&1
        apt-get install -y nodejs >> /var/log/secret-poll-deploy.log 2>&1
    fi
    
    # Install MongoDB
    if ! systemctl is-active --quiet mongod 2>/dev/null; then
        print_info "Installation de MongoDB..."
        curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg >> /var/log/secret-poll-deploy.log 2>&1
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list >> /var/log/secret-poll-deploy.log 2>&1
        apt-get update >> /var/log/secret-poll-deploy.log 2>&1
        apt-get install -y mongodb-org >> /var/log/secret-poll-deploy.log 2>&1
        systemctl enable mongod >> /var/log/secret-poll-deploy.log 2>&1
        systemctl start mongod >> /var/log/secret-poll-deploy.log 2>&1
    fi
    
    # Configuration backend
    print_info "Configuration du backend..."
    cd "$INSTALL_DIR/backend"
    python3 -m venv venv >> /var/log/secret-poll-deploy.log 2>&1
    source venv/bin/activate
    pip install --upgrade pip >> /var/log/secret-poll-deploy.log 2>&1
    pip install -r requirements.txt >> /var/log/secret-poll-deploy.log 2>&1
    cd ..
    
    # Configuration frontend
    print_info "Configuration du frontend..."
    cd "$INSTALL_DIR/frontend"
    if [[ -f yarn.lock ]]; then
        if ! command -v yarn &> /dev/null; then
            npm install -g yarn >> /var/log/secret-poll-deploy.log 2>&1
        fi
        yarn install >> /var/log/secret-poll-deploy.log 2>&1
        yarn build >> /var/log/secret-poll-deploy.log 2>&1
    else
        npm install >> /var/log/secret-poll-deploy.log 2>&1
        npm run build >> /var/log/secret-poll-deploy.log 2>&1
    fi
    cd ..
    
    # Scripts de gestion
    create_management_scripts
    
    print_success "Installation portable terminée"
}

install_docker_deployment() {
    print_step "Installation Docker"
    
    # Installation de Docker si nécessaire
    if ! command -v docker &> /dev/null; then
        print_info "Installation de Docker..."
        curl -fsSL https://get.docker.com | sh >> /var/log/secret-poll-deploy.log 2>&1
        systemctl enable docker >> /var/log/secret-poll-deploy.log 2>&1
        systemctl start docker >> /var/log/secret-poll-deploy.log 2>&1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_info "Installation de Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose >> /var/log/secret-poll-deploy.log 2>&1
        chmod +x /usr/local/bin/docker-compose
    fi
    
    # Création du fichier docker-compose
    create_docker_compose
    
    # Construction et démarrage
    print_info "Construction des images Docker..."
    docker-compose build >> /var/log/secret-poll-deploy.log 2>&1
    
    print_info "Démarrage des conteneurs..."
    docker-compose up -d >> /var/log/secret-poll-deploy.log 2>&1
    
    # Attendre que les services démarrent
    print_info "Attente du démarrage des services..."
    sleep 30
    
    print_success "Déploiement Docker terminé"
}

install_manual_deployment() {
    print_step "Installation manuelle"
    print_info "Installation manuelle simplifiée..."
    
    # Installation des services système
    apt-get update -y
    apt-get install -y nginx mongodb python3 python3-pip python3-venv nodejs npm
    
    # Configuration des services
    systemctl enable mongodb
    systemctl start mongodb
    systemctl enable nginx
    systemctl start nginx
    
    install_portable_deployment
    
    print_success "Installation manuelle terminée"
}

create_docker_compose() {
    print_info "Création du fichier docker-compose.yml..."
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  mongodb:
    image: mongo:7.0
    container_name: secret-poll-mongo
    restart: unless-stopped
    environment:
      - MONGO_INITDB_DATABASE=poll_app
    volumes:
      - mongodb_data:/data/db
    networks:
      - poll-network
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 30s
      timeout: 10s
      retries: 3

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: secret-poll-backend
    restart: unless-stopped
    environment:
      - MONGO_URL=mongodb://mongodb:27017/poll_app
      - PORT=8001
      - ENVIRONMENT=production
      - CORS_ORIGINS=http://$DOMAIN,http://$DOMAIN:3000
    depends_on:
      mongodb:
        condition: service_healthy
    networks:
      - poll-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8001/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      args:
        - REACT_APP_BACKEND_URL=http://$DOMAIN:8001
    container_name: secret-poll-frontend
    restart: unless-stopped
    ports:
      - "3000:80"
      - "8001:8001"
    depends_on:
      backend:
        condition: service_healthy
    networks:
      - poll-network

  nginx:
    image: nginx:alpine
    container_name: secret-poll-nginx
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./nginx-proxy.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - frontend
      - backend
    networks:
      - poll-network

volumes:
  mongodb_data:
    driver: local

networks:
  poll-network:
    driver: bridge
EOF

    # Créer la configuration Nginx pour le proxy
    cat > nginx-proxy.conf << EOF
upstream backend {
    server backend:8001;
}

upstream frontend {
    server frontend:80;
}

server {
    listen 80;
    server_name $DOMAIN localhost;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # API routes vers le backend
    location /api/ {
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
    }
    
    # Frontend routes
    location / {
        proxy_pass http://frontend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
}

create_management_scripts() {
    print_info "Création des scripts de gestion..."
    
    # Script de démarrage
    cat > start.sh << EOF
#!/bin/bash
echo "Démarrage de Secret Poll..."

# Vérifier MongoDB
if ! systemctl is-active --quiet mongod 2>/dev/null; then
    echo "Démarrage de MongoDB..."
    sudo systemctl start mongod
fi

# Backend
cd "\$(dirname "\$0")/backend"
source venv/bin/activate
export MONGO_URL="mongodb://localhost:27017/poll_app"
export PORT="8001"
nohup python server.py > ../backend.log 2>&1 &
echo \$! > ../backend.pid
cd ..

# Frontend (serveur simple)
cd frontend/build
nohup python3 -m http.server 3000 > ../../frontend.log 2>&1 &
echo \$! > ../../frontend.pid
cd ../..

echo "Secret Poll démarré!"
echo "Backend: http://$DOMAIN:8001"
echo "Frontend: http://$DOMAIN:3000"
echo "Logs: backend.log, frontend.log"
EOF

    # Script d'arrêt
    cat > stop.sh << 'EOF'
#!/bin/bash
echo "Arrêt de Secret Poll..."

if [[ -f backend.pid ]]; then
    kill $(cat backend.pid) 2>/dev/null || true
    rm -f backend.pid
    echo "Backend arrêté"
fi

if [[ -f frontend.pid ]]; then
    kill $(cat frontend.pid) 2>/dev/null || true
    rm -f frontend.pid
    echo "Frontend arrêté"
fi

echo "Secret Poll arrêté."
EOF

    # Script de status
    cat > status.sh << 'EOF'
#!/bin/bash
echo "État de Secret Poll:"
echo "==================="

# MongoDB
if systemctl is-active --quiet mongod 2>/dev/null; then
    echo "  MongoDB: ✅ Actif"
else
    echo "  MongoDB: ❌ Inactif"
fi

# Backend
if [[ -f backend.pid ]] && kill -0 $(cat backend.pid) 2>/dev/null; then
    echo "  Backend: ✅ Actif (PID: $(cat backend.pid))"
    echo "    URL: http://localhost:8001"
    echo "    Health: $(curl -s http://localhost:8001/api/health 2>/dev/null || echo "Non accessible")"
else
    echo "  Backend: ❌ Inactif"
fi

# Frontend
if [[ -f frontend.pid ]] && kill -0 $(cat frontend.pid) 2>/dev/null; then
    echo "  Frontend: ✅ Actif (PID: $(cat frontend.pid))"
    echo "    URL: http://localhost:3000"
else
    echo "  Frontend: ❌ Inactif"
fi

echo ""
echo "Logs disponibles:"
[[ -f backend.log ]] && echo "  - backend.log ($(wc -l < backend.log) lignes)"
[[ -f frontend.log ]] && echo "  - frontend.log ($(wc -l < frontend.log) lignes)"
EOF

    # Script de logs
    cat > logs.sh << 'EOF'
#!/bin/bash
echo "=== Logs Secret Poll ==="

if [[ "$1" == "backend" ]]; then
    echo "=== Backend Logs ==="
    tail -f backend.log 2>/dev/null || echo "Pas de logs backend"
elif [[ "$1" == "frontend" ]]; then
    echo "=== Frontend Logs ==="
    tail -f frontend.log 2>/dev/null || echo "Pas de logs frontend"
else
    echo "Usage: ./logs.sh [backend|frontend]"
    echo ""
    echo "Dernières lignes backend:"
    tail -5 backend.log 2>/dev/null || echo "Pas de logs backend"
    echo ""
    echo "Dernières lignes frontend:"
    tail -5 frontend.log 2>/dev/null || echo "Pas de logs frontend"
fi
EOF

    chmod +x {start,stop,status,logs}.sh
    print_success "Scripts de gestion créés"
}

show_final_instructions() {
    print_header "✅ INSTALLATION TERMINÉE!"
    
    echo -e "${GREEN}🎉 Secret Poll a été installé avec succès!${NC}"
    echo >&2
    
    echo -e "${CYAN}📍 Emplacement:${NC} $INSTALL_DIR"
    echo -e "${CYAN}🌐 Domaine:${NC} $DOMAIN"
    echo -e "${CYAN}🚀 Type:${NC} $DEPLOYMENT_TYPE"
    echo >&2
    
    case "$DEPLOYMENT_TYPE" in
        "docker")
            echo -e "${YELLOW}Commandes Docker:${NC}"
            echo "  • Voir les conteneurs: docker-compose ps"
            echo "  • Voir les logs: docker-compose logs -f"
            echo "  • Redémarrer: docker-compose restart"
            echo "  • Arrêter: docker-compose down"
            ;;
        *)
            echo -e "${YELLOW}Commandes de gestion:${NC}"
            echo "  • Démarrer: $INSTALL_DIR/start.sh"
            echo "  • Arrêter: $INSTALL_DIR/stop.sh"
            echo "  • Statut: $INSTALL_DIR/status.sh"
            ;;
    esac
    
    echo >&2
    echo -e "${YELLOW}URLs d'accès:${NC}"
    echo "  • Application: http://$DOMAIN"
    echo "  • API: http://$DOMAIN:8001"
    echo "  • Health Check: http://$DOMAIN:8001/api/health"
    echo >&2
    
    print_success "Installation complète! Votre application Secret Poll est prête."
}

main() {
    print_header "🗳️ SECRET POLL - DÉPLOIEMENT INTERACTIF"
    
    echo -e "${CYAN}Bienvenue dans l'assistant de déploiement Secret Poll!${NC}" >&2
    echo -e "${CYAN}Nous allons configurer votre application étape par étape.${NC}" >&2
    echo >&2
    
    # Exécution des étapes
    check_requirements
    collect_configuration
    show_configuration_summary
    
    if confirm "Confirmer et démarrer le déploiement?" "y"; then
        execute_deployment
        show_final_instructions
    else
        print_info "Déploiement annulé par l'utilisateur."
        exit 0
    fi
    
    print_success "Déploiement terminé avec succès!"
}

# Gestion des interruptions
trap 'echo -e "\n${RED}Déploiement interrompu!${NC}" >&2; exit 1' INT TERM

# Lancement du script principal
main "$@"

exit 0