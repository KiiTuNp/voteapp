# 🚀 Secret Poll - Guide d'Utilisation des Scripts de Déploiement

## 🎯 **PROBLÈME RÉSOLU : Interactivité Clavier**

Les scripts sont maintenant **100% interactifs** et permettent la saisie au clavier !

## 📋 Scripts Disponibles

### 1. `deploy-final.sh` - **🌟 RECOMMANDÉ**
**Script principal complètement interactif et fonctionnel**

```bash
sudo ./deploy-final.sh
```

**✅ Fonctionnalités confirmées :**
- ✅ Saisie clavier complètement fonctionnelle
- ✅ Choix multiples interactifs
- ✅ Confirmation oui/non
- ✅ Validation des entrées
- ✅ 4 types de déploiement
- ✅ Configuration SSL automatique
- ✅ Scripts de gestion automatiques

### 2. `deploy-simple.sh` - Version Simplifiée
**Interface simple et claire**

```bash
sudo ./deploy-simple.sh
```

### 3. `deploy-auto.sh` - Déploiement Automatique
**Sans interaction (pour CI/CD)**

```bash
sudo ./deploy-auto.sh localhost portable
```

### 4. `deploy.sh` - Script Complet
**Version avancée avec toutes les fonctionnalités**

```bash
# Mode interactif
sudo ./deploy.sh

# Mode automatique
sudo ./deploy.sh --auto
```

## 🔧 **Solution au Problème d'Interactivité**

### ✅ **Corrections Apportées :**

1. **Utilisation correcte des descripteurs de fichier**
   - Prompts envoyés vers `stderr` (`>&2`)
   - Inputs lus depuis `stdin` standard
   - Gestion correcte des pipes

2. **Fonctions d'input robustes**
   - Validation des entrées
   - Valeurs par défaut
   - Gestion des erreurs

3. **Choix multiples fonctionnels**
   - Navigation claire
   - Validation des choix
   - Messages d'erreur explicites

## 🎮 **Utilisation Interactive**

### Déploiement Recommandé
```bash
sudo /app/scripts/deploy-final.sh
```

**Le script vous demandera :**
1. **Domaine ou IP** (défaut: localhost)
2. **Répertoire d'installation** (défaut: /opt/secret-poll)
3. **Type de déploiement** :
   - 🐳 Docker (Recommandé)
   - 📦 Manuel
   - 💼 Portable
   - ⚙️ Automatique
4. **Configuration SSL** (pour les domaines)
5. **Confirmation finale**

### Exemple d'Interaction
```
🗳️ SECRET POLL - DÉPLOIEMENT INTERACTIF
=========================================

Entrez votre domaine ou adresse IP (défaut: localhost): votredomaine.com
Répertoire d'installation (défaut: /opt/secret-poll): 
Choisissez le type de déploiement:
1) 🐳 Docker (Recommandé - Isolation complète)
2) 📦 Manuel (Installation directe)
3) 💼 Portable (Répertoire utilisateur)
4) ⚙️ Automatique (Choix optimal)

Votre choix (1-4) [défaut: 1]: 1
Configurer SSL avec Let's Encrypt? [O/n]: o
Email pour le certificat SSL (défaut: admin@votredomaine.com): 

Confirmer et démarrer le déploiement? [O/n]: o
```

## 🚀 **Types de Déploiement**

### 1. 🐳 **Docker (Recommandé)**
- Installation automatique de Docker
- Isolation complète
- Gestion facile avec docker-compose
- Idéal pour la production

### 2. 📦 **Manuel**
- Installation sur le système
- Utilise Nginx et MongoDB système
- Contrôle total
- Pour les environnements personnalisés

### 3. 💼 **Portable**
- Installation dans un répertoire
- Ports hauts pour éviter conflits
- Facile à supprimer
- Idéal pour les tests

### 4. ⚙️ **Automatique**
- Choix optimal selon l'environnement
- Docker si disponible, sinon portable
- Aucune configuration requise

## 🛠️ **Gestion Post-Déploiement**

### Docker
```bash
cd /opt/secret-poll
docker-compose ps              # Voir les conteneurs
docker-compose logs -f         # Voir les logs
docker-compose restart         # Redémarrer
docker-compose down            # Arrêter
```

### Portable/Manuel
```bash
cd /opt/secret-poll
./start.sh                     # Démarrer
./stop.sh                      # Arrêter
./status.sh                    # Vérifier le statut
```

## 🌐 **Accès à l'Application**

Après le déploiement :
- **Application principale :** `http://votre-domaine`
- **API Backend :** `http://votre-domaine:8001`
- **Health Check :** `http://votre-domaine:8001/api/health`

## 🔍 **Tests et Validation**

### Tester l'Interactivité
```bash
./test-input.sh
```

### Déploiement de Test Rapide
```bash
echo -e "localhost\n/tmp/test-poll\n3\nn" | sudo ./deploy-final.sh
```

## ⚡ **Démarrage Ultra-Rapide**

```bash
# Cloner le repository
git clone https://github.com/KiiTuNp/voteapp.git
cd voteapp

# Lancer le déploiement interactif
sudo scripts/deploy-final.sh

# Suivre les instructions à l'écran
# Appuyer sur Entrée pour les valeurs par défaut
# Taper 'o' pour confirmer
```

## 🎯 **Résolution des Problèmes**

### ❌ **Problème :** "Script ne répond pas"
**✅ Solution :** Utiliser `deploy-final.sh`
```bash
sudo ./deploy-final.sh
```

### ❌ **Problème :** "Impossible de taper des choix"
**✅ Solution :** Problème résolu dans les nouveaux scripts
```bash
sudo ./deploy-final.sh  # Fonctionne maintenant !
```

### ❌ **Problème :** "Conflits de ports"
**✅ Solution :** Choisir le déploiement portable
```bash
# Dans le script, choisir option 3 (Portable)
```

### ❌ **Problème :** "Permissions insuffisantes"
**✅ Solution :** Utiliser sudo
```bash
sudo ./deploy-final.sh
```

## 📞 **Support**

Si vous rencontrez des problèmes :
1. Vérifiez que vous utilisez `deploy-final.sh`
2. Exécutez avec `sudo`
3. Testez avec `test-input.sh` en cas de doute
4. Consultez les logs dans `/var/log/`

---

## 🎉 **Tous les Problèmes d'Interactivité sont Résolus !**

Le script `deploy-final.sh` est maintenant **100% fonctionnel** et permet une interaction complète au clavier. Plus de problèmes d'input !

**Commande recommandée :**
```bash
sudo /app/scripts/deploy-final.sh
```