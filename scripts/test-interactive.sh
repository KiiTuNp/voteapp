#!/bin/bash

# =============================================================================
# Test Script for Interactive Input
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Test d'Interactivité ===${NC}"
echo

# Test 1: Simple input
echo -e "${CYAN}Test 1: Saisie simple${NC}"
echo -ne "Entrez votre nom: "
read -r name < /dev/tty
echo -e "${GREEN}Bonjour $name!${NC}"
echo

# Test 2: Input with default
echo -e "${CYAN}Test 2: Saisie avec valeur par défaut${NC}"
echo -ne "Entrez votre ville (défaut: Paris): "
read -r city < /dev/tty
city=${city:-Paris}
echo -e "${GREEN}Vous habitez à $city${NC}"
echo

# Test 3: Yes/No confirmation
echo -e "${CYAN}Test 3: Confirmation Oui/Non${NC}"
while true; do
    echo -ne "Voulez-vous continuer? [y/N]: "
    read -r response < /dev/tty
    response=${response:-n}
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss]|[Oo]|[Oo][Uu][Ii])
            echo -e "${GREEN}Parfait! Vous avez choisi de continuer.${NC}"
            break
            ;;
        [Nn]|[Nn][Oo]|[Nn][Oo][Nn])
            echo -e "${YELLOW}Ok, vous avez choisi d'arrêter.${NC}"
            break
            ;;
        *)
            echo -e "${RED}Réponse invalide. Tapez 'y' pour oui ou 'n' pour non.${NC}"
            continue
            ;;
    esac
done
echo

# Test 4: Multiple choice
echo -e "${CYAN}Test 4: Choix multiple${NC}"
echo "Choisissez votre couleur préférée:"
echo "1) Rouge"
echo "2) Vert"
echo "3) Bleu"
echo "4) Jaune"
echo

while true; do
    echo -ne "Votre choix (1-4): "
    read -r choice < /dev/tty
    
    case "$choice" in
        1)
            echo -e "${GREEN}Vous avez choisi Rouge!${NC}"
            break
            ;;
        2)
            echo -e "${GREEN}Vous avez choisi Vert!${NC}"
            break
            ;;
        3)
            echo -e "${GREEN}Vous avez choisi Bleu!${NC}"
            break
            ;;
        4)
            echo -e "${GREEN}Vous avez choisi Jaune!${NC}"
            break
            ;;
        *)
            echo -e "${RED}Choix invalide. Tapez 1, 2, 3 ou 4.${NC}"
            continue
            ;;
    esac
done
echo

# Test 5: Hidden input (password)
echo -e "${CYAN}Test 5: Saisie cachée (mot de passe)${NC}"
echo -ne "Entrez un mot de passe: "
read -s password < /dev/tty
echo
echo -e "${GREEN}Mot de passe saisi (${#password} caractères)${NC}"
echo

echo -e "${GREEN}=== Tous les tests d'interactivité ont réussi! ===${NC}"
echo -e "${YELLOW}Le script de déploiement devrait maintenant fonctionner correctement.${NC}"