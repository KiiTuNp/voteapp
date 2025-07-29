#!/bin/bash

# Script de validation complète
echo "🔍 Validation complète de l'installation Secret Poll"
echo "=================================================="

# Vérifications des fichiers requis
echo ""
echo "📁 Vérification des fichiers requis:"

required_files=(
    "/app/backend/server.py"
    "/app/backend/requirements.txt"
    "/app/backend/Dockerfile"
    "/app/backend/Dockerfile.prod" 
    "/app/backend/.env"
    "/app/frontend/package.json"
    "/app/frontend/Dockerfile"
    "/app/frontend/Dockerfile.prod"
    "/app/frontend/nginx.conf"
    "/app/frontend/.env"
    "/app/scripts/deploy-final.sh"
    "/app/scripts/deploy-auto.sh"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✅ $file"
    else
        echo "❌ $file MANQUANT"
        missing_files+=("$file")
    fi
done

# Test du backend
echo ""
echo "🖥️ Test du backend:"
backend_status=$(curl -s http://localhost:8001/api/health 2>/dev/null || echo "error")
if [[ "$backend_status" == *"healthy"* ]]; then
    echo "✅ Backend opérationnel"
    echo "   Response: $backend_status"
else
    echo "❌ Backend non accessible"
    echo "   Error: $backend_status"
fi

# Test des scripts
echo ""
echo "🔧 Test des scripts de déploiement:"

# Test syntaxe bash
for script in /app/scripts/*.sh; do
    if bash -n "$script" 2>/dev/null; then
        echo "✅ $(basename "$script") - syntaxe OK"
    else
        echo "❌ $(basename "$script") - erreur syntaxe"
    fi
done

# Vérification des permissions
echo ""
echo "🔐 Vérification des permissions:"
for script in /app/scripts/*.sh; do
    if [[ -x "$script" ]]; then
        echo "✅ $(basename "$script") exécutable"
    else
        echo "❌ $(basename "$script") non exécutable"
        chmod +x "$script" 2>/dev/null && echo "   → Corrigé"
    fi
done

# Test de configuration Docker
echo ""
echo "🐳 Validation des configurations Docker:"

# Dockerfile backend
if grep -q "FROM python:3.11-slim" /app/backend/Dockerfile 2>/dev/null; then
    echo "✅ Dockerfile backend valide"
else
    echo "❌ Dockerfile backend invalide"
fi

# Dockerfile frontend
if grep -q "FROM node:18-alpine" /app/frontend/Dockerfile 2>/dev/null; then
    echo "✅ Dockerfile frontend valide"
else
    echo "❌ Dockerfile frontend invalide"
fi

# Variables d'environnement
echo ""
echo "⚙️ Vérification des variables d'environnement:"

# Backend .env
if grep -q "MONGO_URL" /app/backend/.env 2>/dev/null; then
    echo "✅ Backend .env configuré"
else
    echo "❌ Backend .env manquant ou incorrect"
fi

# Frontend .env
if grep -q "REACT_APP_BACKEND_URL" /app/frontend/.env 2>/dev/null; then
    echo "✅ Frontend .env configuré"
else
    echo "❌ Frontend .env manquant ou incorrect"
fi

# Résumé final
echo ""
echo "📋 RÉSUMÉ:"
if [[ ${#missing_files[@]} -eq 0 ]]; then
    echo "✅ Tous les fichiers requis sont présents"
else
    echo "❌ ${#missing_files[@]} fichier(s) manquant(s):"
    printf '   - %s\n' "${missing_files[@]}"
fi

if [[ "$backend_status" == *"healthy"* ]]; then
    echo "✅ Backend fonctionnel"
else
    echo "❌ Backend nécessite attention"
fi

# Test rapide de déploiement
echo ""
echo "🚀 Test rapide du script principal:"
timeout 30 bash -c 'echo -e "localhost\n/tmp/test-validation\n3\nn" | /app/scripts/deploy-final.sh > /dev/null 2>&1' && echo "✅ Script de déploiement exécutable" || echo "⚠️  Script nécessite attention"

# Nettoyage
rm -rf /tmp/test-validation 2>/dev/null || true

echo ""
echo "🎯 STATUT GÉNÉRAL:"
if [[ ${#missing_files[@]} -eq 0 && "$backend_status" == *"healthy"* ]]; then
    echo "✅ INSTALLATION COMPLÈTEMENT FONCTIONNELLE"
    echo "   → Prêt pour le déploiement!"
else
    echo "⚠️  NÉCESSITE CORRECTIONS"
    echo "   → Vérifiez les erreurs ci-dessus"
fi

echo ""
echo "📖 Pour déployer, utilisez:"
echo "   sudo /app/scripts/deploy-final.sh"