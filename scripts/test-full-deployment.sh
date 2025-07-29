#!/bin/bash

# Test complet de déploiement
echo "🚀 Test complet de déploiement Secret Poll"
echo "=========================================="

# Configuration de test
TEST_DIR="/tmp/secret-poll-full-test"
TEST_LOG="/tmp/deployment-test.log"

echo "📋 Configuration du test:"
echo "   Répertoire: $TEST_DIR"
echo "   Log: $TEST_LOG"
echo ""

# Nettoyage préalable
if [[ -d "$TEST_DIR" ]]; then
    echo "🧹 Nettoyage du test précédent..."
    rm -rf "$TEST_DIR"
fi

# Initialisation des logs
echo "$(date): Test de déploiement complet commencé" > "$TEST_LOG"

# Simulation d'entrées utilisateur pour déploiement portable
echo "🎯 Lancement du déploiement avec inputs simulés..."
echo "   Domain: localhost"  
echo "   Directory: $TEST_DIR"
echo "   Type: 3 (Portable)"
echo "   SSL: n"

# Lancer le déploiement avec timeout pour éviter les blocages
timeout 300 bash -c "
echo -e 'localhost\n$TEST_DIR\n3\nn' | /app/scripts/deploy-final.sh
" >> "$TEST_LOG" 2>&1

# Vérifier les résultats
echo ""
echo "🔍 Vérification des résultats..."

if [[ -d "$TEST_DIR" ]]; then
    echo "✅ Répertoire de déploiement créé"
    
    # Vérifier la structure des fichiers
    echo ""
    echo "📁 Structure des fichiers créés:"
    
    essential_files=(
        "$TEST_DIR/.git"
        "$TEST_DIR/backend/server.py"
        "$TEST_DIR/backend/requirements.txt"
        "$TEST_DIR/backend/.env"
        "$TEST_DIR/frontend/package.json"
        "$TEST_DIR/frontend/.env"
        "$TEST_DIR/start.sh"
        "$TEST_DIR/stop.sh"
        "$TEST_DIR/status.sh"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ -e "$file" ]]; then
            echo "✅ $(basename "$file")"
        else
            echo "❌ $(basename "$file") manquant"
        fi
    done
    
    # Vérifier les permissions des scripts
    echo ""
    echo "🔐 Permissions des scripts:"
    for script in "$TEST_DIR"/{start,stop,status}.sh; do
        if [[ -x "$script" ]]; then
            echo "✅ $(basename "$script") exécutable"
        else
            echo "❌ $(basename "$script") non exécutable"
        fi
    done
    
    # Vérifier le contenu des fichiers .env
    echo ""
    echo "⚙️ Configuration des environnements:"
    
    if grep -q "mongodb://localhost:27017/poll_app" "$TEST_DIR/backend/.env" 2>/dev/null; then
        echo "✅ Backend .env configuré correctement"
    else
        echo "❌ Backend .env incorrect"
    fi
    
    if grep -q "http://localhost:8001" "$TEST_DIR/frontend/.env" 2>/dev/null; then
        echo "✅ Frontend .env configuré correctement"
    else
        echo "❌ Frontend .env incorrect"
    fi
    
else
    echo "❌ Répertoire de déploiement NON créé"
fi

# Analyser les logs
echo ""
echo "📄 Analyse des logs de déploiement:"
if [[ -f "$TEST_LOG" ]]; then
    local log_size=$(wc -l < "$TEST_LOG")
    echo "   Taille: $log_size lignes"
    
    # Chercher les erreurs
    local errors=$(grep -i "error\|erreur\|failed\|échec" "$TEST_LOG" 2>/dev/null | wc -l)
    if [[ $errors -gt 0 ]]; then
        echo "⚠️  $errors erreur(s) détectée(s)"
        echo ""
        echo "Dernières erreurs:"
        grep -i "error\|erreur\|failed\|échec" "$TEST_LOG" | tail -3
    else
        echo "✅ Aucune erreur détectée"
    fi
    
    # Afficher les dernières lignes
    echo ""
    echo "Dernières lignes du log:"
    tail -5 "$TEST_LOG"
    
else
    echo "❌ Fichier de log non trouvé"
fi

# Test de syntaxe des scripts générés
if [[ -d "$TEST_DIR" ]]; then
    echo ""
    echo "🧪 Test de syntaxe des scripts générés:"
    
    for script in "$TEST_DIR"/{start,stop,status}.sh; do
        if [[ -f "$script" ]]; then
            if bash -n "$script" 2>/dev/null; then
                echo "✅ $(basename "$script") - syntaxe OK"
            else
                echo "❌ $(basename "$script") - erreur syntaxe"
            fi
        fi
    done
fi

# Résumé final
echo ""
echo "📊 RÉSUMÉ DU TEST:"
if [[ -d "$TEST_DIR" ]]; then
    local success_count=0
    local total_checks=8
    
    # Compter les succès
    [[ -e "$TEST_DIR/.git" ]] && ((success_count++))
    [[ -f "$TEST_DIR/backend/server.py" ]] && ((success_count++))
    [[ -f "$TEST_DIR/frontend/package.json" ]] && ((success_count++))
    [[ -f "$TEST_DIR/backend/.env" ]] && ((success_count++))
    [[ -f "$TEST_DIR/frontend/.env" ]] && ((success_count++))
    [[ -x "$TEST_DIR/start.sh" ]] && ((success_count++))
    [[ -x "$TEST_DIR/stop.sh" ]] && ((success_count++))
    [[ -x "$TEST_DIR/status.sh" ]] && ((success_count++))
    
    echo "✅ Déploiement réussi: $success_count/$total_checks vérifications"
    
    if [[ $success_count -eq $total_checks ]]; then
        echo "🎉 DÉPLOIEMENT PARFAITEMENT FONCTIONNEL!"
    else
        echo "⚠️  Déploiement partiel - quelques éléments à corriger"
    fi
else
    echo "❌ ÉCHEC DU DÉPLOIEMENT"
fi

# Instructions de test manuel
if [[ -d "$TEST_DIR" ]]; then
    echo ""
    echo "🧪 Pour tester manuellement:"
    echo "   cd $TEST_DIR"
    echo "   sudo ./start.sh"
    echo "   ./status.sh"
    echo "   ./stop.sh"
fi

# Nettoyage optionnel
echo ""
read -p "🧹 Nettoyer les fichiers de test? [y/N]: " cleanup
if [[ "$cleanup" =~ ^[Yy]$ ]]; then
    rm -rf "$TEST_DIR" "$TEST_LOG"
    echo "✅ Nettoyage terminé"
else
    echo "📁 Fichiers conservés pour inspection manuelle"
fi

echo ""
echo "Test terminé."