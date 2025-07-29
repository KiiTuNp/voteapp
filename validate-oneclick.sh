#!/bin/bash

# Validation du one-click install
echo "🔍 Validation de l'installation One-Click"
echo "=========================================="

# Vérifier les fichiers essentiels
echo ""
echo "📁 Vérification des fichiers requis:"

essential_files=(
    "/app/install.sh"
    "/app/backend/server.py"
    "/app/backend/requirements.txt"
    "/app/backend/.env"
    "/app/frontend/package.json" 
    "/app/frontend/.env"
    "/app/ONE_CLICK_INSTALL.md"
)

missing_files=()
for file in "${essential_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✅ $(basename "$file")"
    else
        echo "❌ $(basename "$file") MANQUANT"
        missing_files+=("$file")
    fi
done

# Vérifier les permissions
echo ""
echo "🔐 Vérification des permissions:"
if [[ -x "/app/install.sh" ]]; then
    echo "✅ install.sh exécutable"
else
    echo "❌ install.sh non exécutable"
    chmod +x /app/install.sh
    echo "   → Corrigé"
fi

# Vérifier la syntaxe du script
echo ""
echo "🧪 Test de syntaxe:"
if bash -n /app/install.sh 2>/dev/null; then
    echo "✅ install.sh - syntaxe correcte"
else
    echo "❌ install.sh - erreur de syntaxe"
fi

# Vérifier que le backend fonctionne toujours
echo ""
echo "🖥️ Test du backend actuel:"
backend_status=$(curl -s http://localhost:8001/api/health 2>/dev/null || echo "error")
if [[ "$backend_status" == *"healthy"* ]]; then
    echo "✅ Backend fonctionnel"
else
    echo "⚠️  Backend non accessible (normal si pas démarré)"
fi

# Test rapide du script (sans exécution complète)
echo ""
echo "⚡ Test rapide du script:"
if timeout 30 bash -c 'head -50 /app/install.sh | tail -1' >/dev/null 2>&1; then
    echo "✅ Script lisible"
else
    echo "❌ Problème avec le script"
fi

# Vérifier les URLs GitHub
echo ""
echo "🌐 Vérification des URLs:"
if curl -s -I https://raw.githubusercontent.com/KiiTuNp/voteapp/main/install.sh | grep -q "200"; then
    echo "✅ URL GitHub accessible"
else
    echo "⚠️  URL GitHub non accessible (à vérifier)"
fi

# Résumé final
echo ""
echo "📊 RÉSUMÉ DE VALIDATION:"

if [[ ${#missing_files[@]} -eq 0 ]]; then
    echo "✅ Tous les fichiers requis sont présents"
    ready_status="PRÊT"
else
    echo "❌ ${#missing_files[@]} fichier(s) manquant(s)"
    ready_status="NÉCESSITE CORRECTIONS"
fi

echo ""
echo "🎯 STATUT ONE-CLICK INSTALL: $ready_status"

if [[ "$ready_status" == "PRÊT" ]]; then
    echo ""
    echo "🚀 L'installation One-Click est prête !"
    echo ""
    echo "Instructions pour l'utilisateur:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "sudo bash install.sh"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Ou depuis GitHub:"
    echo "curl -sSL https://raw.githubusercontent.com/KiiTuNp/voteapp/main/install.sh | sudo bash"
else
    echo ""
    echo "⚠️ Corrections nécessaires avant utilisation"
fi

echo ""
echo "📖 Documentation: /app/ONE_CLICK_INSTALL.md"