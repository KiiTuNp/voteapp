#!/bin/bash

# ============================================================================
# 🚀 SECRET POLL - ONE CLICK INSTALL
# ============================================================================
# Installation ultra-simple en un clic !
# Usage: wget -O- https://raw.githubusercontent.com/KiiTuNp/voteapp/main/install.sh | bash
# ============================================================================

set -e

# Configuration automatique
INSTALL_DIR="/opt/secret-poll"
REPO_URL="https://github.com/KiiTuNp/voteapp.git"
LOG_FILE="/var/log/secret-poll-install.log"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${PURPLE}
╔═══════════════════════════════════════════════════════════════════════════════╗
║                          🗳️  SECRET POLL INSTALLER                           ║
║                               One Click Install                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

log() {
    echo "$(date): $1" | tee -a "$LOG_FILE" >/dev/null
}

# Fonction d'installation des dépendances
install_dependencies() {
    print_step "Installation des dépendances système..."
    
    # Mise à jour des paquets
    apt-get update -y >> "$LOG_FILE" 2>&1
    
    # Installation des dépendances essentielles
    apt-get install -y \
        curl \
        wget \
        git \
        python3 \
        python3-pip \
        python3-venv \
        nodejs \
        npm \
        >> "$LOG_FILE" 2>&1
    
    # Installation de MongoDB
    if ! systemctl is-active --quiet mongod 2>/dev/null; then
        print_info "Installation de MongoDB..."
        curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg >> "$LOG_FILE" 2>&1
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list >> "$LOG_FILE" 2>&1
        apt-get update >> "$LOG_FILE" 2>&1
        apt-get install -y mongodb-org >> "$LOG_FILE" 2>&1
        systemctl enable mongod >> "$LOG_FILE" 2>&1
        systemctl start mongod >> "$LOG_FILE" 2>&1
    fi
    
    print_success "Dépendances installées"
    log "Dependencies installed successfully"
}

# Téléchargement de l'application
download_app() {
    print_step "Téléchargement de Secret Poll..."
    
    # Nettoyer l'ancien répertoire
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
    fi
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Cloner le repository
    git clone "$REPO_URL" . >> "$LOG_FILE" 2>&1
    
    print_success "Application téléchargée"
    log "Application downloaded successfully"
}

# Configuration automatique
configure_app() {
    print_step "Configuration automatique..."
    
    # Configuration Backend
    cat > "$INSTALL_DIR/backend/.env" << EOF
# Configuration Secret Poll Backend
MONGO_URL=mongodb://localhost:27017/secret_poll
PORT=8001
ENVIRONMENT=production
CORS_ORIGINS=http://localhost:3000,http://localhost:8001,http://127.0.0.1:3000,http://127.0.0.1:8001
SECRET_KEY=$(openssl rand -hex 32)

# Auto-généré le $(date)
EOF

    # Configuration Frontend
    cat > "$INSTALL_DIR/frontend/.env" << EOF
# Configuration Secret Poll Frontend
REACT_APP_BACKEND_URL=http://localhost:8001
PORT=3000
GENERATE_SOURCEMAP=false
NODE_ENV=production

# Auto-généré le $(date)
EOF

    print_success "Configuration terminée"
    log "Application configured successfully"
}

# Installation Backend
install_backend() {
    print_step "Installation du Backend..."
    
    cd "$INSTALL_DIR/backend"
    
    # Créer l'environnement virtuel Python
    python3 -m venv venv >> "$LOG_FILE" 2>&1
    source venv/bin/activate
    
    # Installer les dépendances Python
    pip install --upgrade pip >> "$LOG_FILE" 2>&1
    pip install -r requirements.txt >> "$LOG_FILE" 2>&1
    
    cd "$INSTALL_DIR"
    print_success "Backend installé"
    log "Backend installed successfully"
}

# Installation Frontend
install_frontend() {
    print_step "Installation du Frontend..."
    
    cd "$INSTALL_DIR/frontend"
    
    # Installer les dépendances Node.js
    if [[ -f yarn.lock ]]; then
        if ! command -v yarn &> /dev/null; then
            npm install -g yarn >> "$LOG_FILE" 2>&1
        fi
        yarn install >> "$LOG_FILE" 2>&1
        yarn build >> "$LOG_FILE" 2>&1
    else
        npm install >> "$LOG_FILE" 2>&1
        npm run build >> "$LOG_FILE" 2>&1
    fi
    
    cd "$INSTALL_DIR"
    print_success "Frontend installé"
    log "Frontend installed successfully"
}

# Création des scripts de gestion
create_management_scripts() {
    print_step "Création des scripts de gestion..."
    
    # Script de démarrage
    cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash
echo "🚀 Démarrage de Secret Poll..."

# Vérifier MongoDB
if ! systemctl is-active --quiet mongod 2>/dev/null; then
    echo "Démarrage de MongoDB..."
    sudo systemctl start mongod
    sleep 3
fi

# Démarrer le backend
echo "Démarrage du backend..."
cd "$(dirname "$0")/backend"
source venv/bin/activate
nohup python server.py > ../backend.log 2>&1 &
echo $! > ../backend.pid

# Démarrer le frontend (serveur simple)
echo "Démarrage du frontend..."
cd ../frontend/build
nohup python3 -m http.server 3000 > ../../frontend.log 2>&1 &
echo $! > ../../frontend.pid

cd ../..

echo "✅ Secret Poll démarré avec succès!"
echo ""
echo "🌐 Accès à l'application:"
echo "   Frontend: http://localhost:3000"
echo "   Backend:  http://localhost:8001"
echo "   Health:   http://localhost:8001/api/health"
echo ""
echo "📄 Logs:"
echo "   Backend:  tail -f backend.log"
echo "   Frontend: tail -f frontend.log"
echo ""
echo "🛑 Pour arrêter: ./stop.sh"
EOF

    # Script d'arrêt
    cat > "$INSTALL_DIR/stop.sh" << 'EOF'
#!/bin/bash
echo "🛑 Arrêt de Secret Poll..."

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

echo "✅ Secret Poll arrêté."
EOF

    # Script de statut
    cat > "$INSTALL_DIR/status.sh" << 'EOF'
#!/bin/bash
echo "📊 État de Secret Poll:"
echo "======================="

# MongoDB
if systemctl is-active --quiet mongod 2>/dev/null; then
    echo "MongoDB:  ✅ Actif"
else
    echo "MongoDB:  ❌ Inactif"
fi

# Backend
if [[ -f backend.pid ]] && kill -0 $(cat backend.pid) 2>/dev/null; then
    echo "Backend:  ✅ Actif (PID: $(cat backend.pid))"
    echo "  URL: http://localhost:8001"
    echo "  Health: $(curl -s http://localhost:8001/api/health 2>/dev/null || echo "Non accessible")"
else
    echo "Backend:  ❌ Inactif"
fi

# Frontend
if [[ -f frontend.pid ]] && kill -0 $(cat frontend.pid) 2>/dev/null; then
    echo "Frontend: ✅ Actif (PID: $(cat frontend.pid))"
    echo "  URL: http://localhost:3000"
else
    echo "Frontend: ❌ Inactif"
fi

echo ""
echo "📄 Logs disponibles:"
[[ -f backend.log ]] && echo "  backend.log  ($(wc -l < backend.log) lignes)"
[[ -f frontend.log ]] && echo "  frontend.log ($(wc -l < frontend.log) lignes)"
EOF

    # Script de redémarrage
    cat > "$INSTALL_DIR/restart.sh" << 'EOF'
#!/bin/bash
echo "🔄 Redémarrage de Secret Poll..."
./stop.sh
sleep 2
./start.sh
EOF

    # Rendre les scripts exécutables
    chmod +x "$INSTALL_DIR"/{start,stop,status,restart}.sh
    
    print_success "Scripts de gestion créés"
    log "Management scripts created successfully"
}

# Test de l'installation
test_installation() {
    print_step "Test de l'installation..."
    
    # Vérifier que tous les fichiers sont présents
    local required_files=(
        "$INSTALL_DIR/backend/server.py"
        "$INSTALL_DIR/frontend/build/index.html"
        "$INSTALL_DIR/backend/.env"
        "$INSTALL_DIR/frontend/.env"
        "$INSTALL_DIR/start.sh"
        "$INSTALL_DIR/stop.sh"
        "$INSTALL_DIR/status.sh"
    )
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [[ ! -e "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "Fichiers manquants: ${missing_files[*]}"
        return 1
    fi
    
    print_success "Test d'installation réussi"
    log "Installation test passed"
    return 0
}

# Affichage des instructions finales
show_final_instructions() {
    echo ""
    echo -e "${GREEN}
╔═══════════════════════════════════════════════════════════════════════════════╗
║                        🎉 INSTALLATION TERMINÉE !                           ║
╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "${CYAN}
📍 Installation: $INSTALL_DIR

🚀 Pour démarrer Secret Poll:
   cd $INSTALL_DIR
   ./start.sh

🌐 URLs d'accès:
   • Application: http://localhost:3000
   • API Backend: http://localhost:8001
   • Health Check: http://localhost:8001/api/health

🛠️ Commandes disponibles:
   • ./start.sh    - Démarrer l'application
   • ./stop.sh     - Arrêter l'application
   • ./status.sh   - Voir l'état des services
   • ./restart.sh  - Redémarrer l'application

📄 Logs:
   • Backend:  tail -f backend.log
   • Frontend: tail -f frontend.log

📋 Installation: $LOG_FILE
${NC}"
}

# Fonction principale
main() {
    # Vérifier les permissions root
    if [[ $EUID -ne 0 ]]; then
        print_error "Ce script doit être exécuté en tant que root"
        echo "Utilisez: sudo bash install.sh"
        exit 1
    fi
    
    # Initialisation des logs
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$(date): Secret Poll One-Click Install started" > "$LOG_FILE"
    
    print_header
    
    echo -e "${CYAN}Installation automatique de Secret Poll en cours...${NC}"
    echo -e "${YELLOW}Cette installation va configurer tout automatiquement !${NC}"
    echo ""
    
    # Étapes d'installation
    install_dependencies
    download_app
    configure_app
    install_backend
    install_frontend
    create_management_scripts
    
    # Test de l'installation
    if test_installation; then
        show_final_instructions
        
        echo -e "${GREEN}
🎊 SECRET POLL EST PRÊT À ÊTRE UTILISÉ !

Pour démarrer maintenant:
cd $INSTALL_DIR && ./start.sh
${NC}"
        
        log "Installation completed successfully"
    else
        print_error "L'installation a échoué. Vérifiez les logs: $LOG_FILE"
        log "Installation failed"
        exit 1
    fi
}

# Gestion des interruptions
trap 'echo -e "\n${RED}Installation interrompue!${NC}"; exit 1' INT TERM

# Exécution
main "$@"

exit 0