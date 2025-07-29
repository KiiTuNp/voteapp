#!/bin/bash

# =============================================================================
# Secret Poll - Script de Déploiement Simplifié et Interactif
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

# Configuration
REPO_URL="https://github.com/KiiTuNp/voteapp.git"
BRANCH="main"

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

ask_input() {
    local prompt="$1"
    local default="$2"
    local value
    
    if [[ -n "$default" ]]; then
        echo -ne "${CYAN}$prompt${NC} ${YELLOW}(défaut: $default)${NC}: "
    else
        echo -ne "${CYAN}$prompt${NC}: "
    fi
    
    read -r value < /dev/tty
    echo "${value:-$default}"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -ne "${YELLOW}$prompt [O/n]:${NC} "
        else
            echo -ne "${YELLOW}$prompt [o/N]:${NC} "
        fi
        
        read -r response < /dev/tty
        response=${response:-$default}
        
        case "$response" in
            [Yy]|[Oo]|[Yy][Ee][Ss]|[Oo][Uu][Ii])
                return 0
                ;;
            [Nn]|[Nn][Oo]|[Nn][Oo][Nn])
                return 1
                ;;
            *)
                echo -e "${RED}Réponse invalide. Tapez 'o' pour oui ou 'n' pour non.${NC}"
                continue
                ;;
        esac
    done
}

choose_deployment() {
    echo -e "\n${CYAN}Types de déploiement disponibles :${NC}"
    echo "1) 🐳 Docker (Recommandé - Isolation complète)"
    echo "2) 📦 Manuel (Installation directe sur le système)"
    echo "3) 💼 Portable (Dans le répertoire utilisateur)"
    echo
    
    while true; do
        echo -ne "${CYAN}Choisissez le type de déploiement (1-3)${NC} ${YELLOW}[défaut: 1]${NC}: "
        read -r choice < /dev/tty
        choice=${choice:-1}
        
        case "$choice" in
            1)
                echo -e "${GREEN}Déploiement Docker sélectionné${NC}"
                return 1
                ;;
            2)
                echo -e "${GREEN}Déploiement Manuel sélectionné${NC}"
                return 2
                ;;
            3)
                echo -e "${GREEN}Déploiement Portable sélectionné${NC}"
                return 3
                ;;
            *)
                echo -e "${RED}Choix invalide. Tapez 1, 2 ou 3.${NC}"
                continue
                ;;
        esac
    done
}

main() {
    print_header "🚀 SECRET POLL - DÉPLOIEMENT INTERACTIF"
    
    echo -e "${CYAN}Bienvenue dans le script de déploiement de Secret Poll!${NC}"
    echo -e "${CYAN}Ce script va vous guider étape par étape.${NC}\n"
    
    # Vérification des permissions
    if [[ $EUID -ne 0 ]]; then
        print_error "Ce script doit être exécuté en tant que root"
        print_info "Veuillez exécuter: sudo $0"
        exit 1
    fi
    
    # Configuration de base
    print_step "Configuration de base"
    
    # Nom du domaine ou IP
    DOMAIN=$(ask_input "Entrez votre domaine ou IP" "localhost")
    print_info "Domaine configuré: $DOMAIN"
    
    # Répertoire d'installation
    INSTALL_DIR=$(ask_input "Répertoire d'installation" "/opt/secret-poll")
    print_info "Installation dans: $INSTALL_DIR"
    
    # Type de déploiement
    choose_deployment
    DEPLOYMENT_TYPE=$?
    
    case $DEPLOYMENT_TYPE in
        1) TYPE_NAME="Docker" ;;
        2) TYPE_NAME="Manuel" ;;
        3) TYPE_NAME="Portable" ;;
    esac
    
    # Configuration SSL
    if [[ "$DOMAIN" != "localhost" ]] && [[ ! "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if ask_yes_no "Configurer SSL avec Let's Encrypt?" "y"; then
            USE_SSL=true
            EMAIL=$(ask_input "Email pour le certificat SSL" "admin@$DOMAIN")
        else
            USE_SSL=false
        fi
    else
        USE_SSL=false
    fi
    
    # Résumé de la configuration
    echo
    print_header "📋 RÉSUMÉ DE LA CONFIGURATION"
    echo -e "${CYAN}Domaine:${NC} $DOMAIN"
    echo -e "${CYAN}Installation:${NC} $INSTALL_DIR"
    echo -e "${CYAN}Type de déploiement:${NC} $TYPE_NAME"
    echo -e "${CYAN}SSL:${NC} $([ "$USE_SSL" = true ] && echo "Activé ($EMAIL)" || echo "Désactivé")"
    echo -e "${CYAN}Repository:${NC} $REPO_URL"
    echo
    
    if ask_yes_no "Confirmer et démarrer le déploiement?" "y"; then
        print_success "Configuration confirmée!"
        
        # Démarrage du déploiement
        print_step "Démarrage du déploiement..."
        
        # Création du répertoire
        print_info "Création du répertoire d'installation..."
        mkdir -p "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        
        # Clonage du repository
        print_info "Téléchargement du code source..."
        if [[ -d ".git" ]]; then
            git pull origin $BRANCH
        else
            git clone "$REPO_URL" .
        fi
        
        # Configuration des fichiers d'environnement
        print_info "Configuration des variables d'environnement..."
        
        # Backend .env
        cat > backend/.env << EOF
MONGO_URL=mongodb://localhost:27017/poll_app
PORT=8001
ENVIRONMENT=production
EOF
        
        # Frontend .env  
        cat > frontend/.env << EOF
REACT_APP_BACKEND_URL=http://$DOMAIN:8001
PORT=3000
NODE_ENV=production
EOF
        
        print_success "Déploiement de base terminé!"
        
        # Instructions finales
        print_header "✅ DÉPLOIEMENT TERMINÉ"
        echo -e "${GREEN}Secret Poll a été installé avec succès!${NC}\n"
        
        echo -e "${CYAN}📍 Emplacement:${NC} $INSTALL_DIR"
        echo -e "${CYAN}🌐 Accès:${NC} http://$DOMAIN"
        echo
        echo -e "${YELLOW}Prochaines étapes:${NC}"
        echo "1. Configurer et démarrer les services"
        echo "2. Tester l'application"
        echo "3. Configurer un proxy web si nécessaire"
        echo
        print_success "Installation terminée avec succès!"
        
    else
        print_info "Déploiement annulé par l'utilisateur."
        exit 0
    fi
}

# Gestion des signaux
trap 'echo -e "\n${RED}Déploiement interrompu!${NC}"; exit 1' INT TERM

# Exécution du script principal
main "$@"

exit 0