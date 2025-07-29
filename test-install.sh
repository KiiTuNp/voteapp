#!/bin/bash

# Test rapide de l'installation one-click
echo "🧪 Test de l'installation One-Click"
echo "===================================="

# Configuration de test
TEST_DIR="/tmp/secret-poll-oneclick-test"
TEST_LOG="/tmp/oneclick-test.log"

echo "🎯 Test en cours dans $TEST_DIR..."

# Nettoyer les tests précédents
sudo rm -rf "$TEST_DIR" 2>/dev/null || true

# Créer une version de test qui installe dans /tmp
cp /app/install.sh /tmp/test-install.sh
sed -i 's|INSTALL_DIR="/opt/secret-poll"|INSTALL_DIR="'$TEST_DIR'"|g' /tmp/test-install.sh

# Exécuter l'installation
echo "⚡ Lancement de l'installation automatique..."
sudo timeout 300 bash /tmp/test-install.sh > "$TEST_LOG" 2>&1

# Vérifier les résultats
echo ""
echo "🔍 Vérification des résultats:"

if [[ -d "$TEST_DIR" ]]; then
    echo "✅ Répertoire d'installation créé"
    
    # Vérifier les fichiers essentiels
    local files_check=(
        "$TEST_DIR/backend/server.py"
        "$TEST_DIR/frontend/build/index.html"
        "$TEST_DIR/start.sh"
        "$TEST_DIR/stop.sh"
        "$TEST_DIR/status.sh"
    )
    
    for file in "${files_check[@]}"; do
        if [[ -e "$file" ]]; then
            echo "✅ $(basename "$file")"
        else
            echo "❌ $(basename "$file") manquant"
        fi
    done
    
    # Tester les permissions
    if [[ -x "$TEST_DIR/start.sh" ]]; then
        echo "✅ Scripts exécutables"
    else
        echo "❌ Scripts non exécutables"
    fi
    
else
    echo "❌ Répertoire d'installation non créé"
fi

# Afficher les dernières lignes du log
echo ""
echo "📄 Dernières lignes du log:"
tail -10 "$TEST_LOG"

# Nettoyage
echo ""
echo "🧹 Nettoyage des fichiers de test..."
sudo rm -rf "$TEST_DIR" /tmp/test-install.sh "$TEST_LOG" 2>/dev/null || true

echo ""
echo "✅ Test terminé!"
echo ""
echo "🚀 Pour installer réellement:"
echo "   sudo bash /app/install.sh"