#!/bin/bash

# Test simple des fonctions d'input

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}Test d'entrée simple:${NC}"
echo -ne "Tapez votre nom: " >&2
read name
echo -e "${GREEN}Bonjour $name!${NC}"

echo -e "\n${CYAN}Test avec choix:${NC}"
echo "1) Option A" >&2
echo "2) Option B" >&2
echo -ne "Votre choix (1-2): " >&2
read choice

case "$choice" in
    1) echo -e "${GREEN}Vous avez choisi Option A${NC}" ;;
    2) echo -e "${GREEN}Vous avez choisi Option B${NC}" ;;
    *) echo -e "${RED}Choix invalide${NC}" ;;
esac

echo -e "\n${GREEN}Test terminé!${NC}"