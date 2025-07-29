#!/bin/bash

# Script de test du déploiement
set -e

# Configuration de test
TEST_DIR="/tmp/secret-poll-test"
LOG_FILE="/tmp/deploy-test.log"

echo "🧪 Test du script de déploiement"
echo "==============================="

# Nettoyer les tests précédents
if [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
fi

mkdir -p "$TEST_DIR"
echo "$(date): Test commencé" > "$LOG_FILE"

# Test avec des inputs simulés
echo -e "localhost\n$TEST_DIR\n3\nn" | timeout 120 /app/scripts/deploy-final.sh >> "$LOG_FILE" 2>&1

# Vérifier les résultats
if [[ -d "$TEST_DIR" ]]; then
    echo "✅ Répertoire de test créé"
    
    # Vérifier les fichiers clés
    local files_to_check=(
        "$TEST_DIR/.git"
        "$TEST_DIR/backend/server.py"
        "$TEST_DIR/frontend/package.json"
        "$TEST_DIR/backend/.env"
        "$TEST_DIR/frontend/.env"
        "$TEST_DIR/start.sh"
        "$TEST_DIR/stop.sh"
        "$TEST_DIR/status.sh"
    )
    
    for file in "${files_to_check[@]}"; do
        if [[ -e "$file" ]]; then
            echo "✅ $file existe"
        else
            echo "❌ $file manquant"
        fi
    done
    
    echo ""
    echo "📄 Log du test:"
    tail -20 "$LOG_FILE"
    
    echo ""
    echo "🧹 Nettoyage..."
    rm -rf "$TEST_DIR"
    
else
    echo "❌ Test échoué - répertoire non créé"
    echo "📄 Erreurs:"
    cat "$LOG_FILE"
fi

rm -f "$LOG_FILE"
echo "Test terminé."