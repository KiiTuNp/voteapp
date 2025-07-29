# 🚀 Secret Poll - Guide d'Utilisation des Scripts de Déploiement

## 📋 Scripts Disponibles

### 1. `deploy.sh` - Script Principal (Interactif)
**Utilisation recommandée pour la production**

```bash
# Mode interactif (par défaut)
sudo ./deploy.sh

# Mode automatique (utilise les valeurs par défaut)
sudo ./deploy.sh --auto
```

**Fonctionnalités :**
- Analyse complète du système
- Détection automatique des conflits
- 5 stratégies de déploiement
- Configuration SSL automatique
- Sauvegarde et rollback
- Outils de gestion intégrés

### 2. `deploy-auto.sh` - Déploiement Automatique
**Parfait pour les tests et CI/CD**

```bash
# Déploiement local simple
sudo ./deploy-auto.sh

# Déploiement avec domaine personnalisé  
sudo ./deploy-auto.sh example.com

# Déploiement avec type spécifique
sudo ./deploy-auto.sh example.com docker-isolated

# Voir l'aide
./deploy-auto.sh --help
```

**Avantages :**
- Aucune interaction requise
- Configuration automatique
- Idéal pour l'automatisation
- Déploiement rapide

### 3. `demo-deploy.sh` - Script de Démonstration
**Interface simple pour choisir le type de déploiement**

```bash
sudo ./demo-deploy.sh
```

**Options disponibles :**
1. Démo rapide (localhost)
2. Déploiement automatique avec domaine
3. Déploiement interactif complet

## 🔧 Résolution du Problème d'Interactivité

Si vous rencontrez des problèmes avec le script interactif :

### Solution 1 : Utiliser le Mode Automatique
```bash
sudo ./deploy.sh --auto
```

### Solution 2 : Utiliser le Script Automatique
```bash
sudo ./deploy-auto.sh localhost
```

### Solution 3 : Utiliser le Script de Démonstration
```bash
sudo ./demo-deploy.sh
```

## 📦 Types de Déploiement

### 1. `portable` (Recommandé pour les tests)
- Installation dans le répertoire utilisateur
- Ports hauts pour éviter les conflits
- Impact minimal sur le système
- Pas besoin de Docker

### 2. `docker-isolated` (Recommandé pour la production)
- Isolation complète avec Docker
- Aucun conflit avec les services existants
- Facile à gérer et supprimer

### 3. `docker-standard` (Performance optimale)
- Déploiement Docker standard
- Utilise les ports 80/443
- Nécessite la résolution des conflits de ports

## 🛠️ Exemples d'Utilisation

### Déploiement Rapide pour Tests
```bash
# Méthode 1 : Script automatique
sudo ./deploy-auto.sh localhost portable

# Méthode 2 : Script principal en mode auto
sudo ./deploy.sh --auto

# Méthode 3 : Script de démo
sudo ./demo-deploy.sh
# Choisir option 1
```

### Déploiement Production avec Domaine
```bash
# Script automatique
sudo ./deploy-auto.sh votredomaine.com docker-isolated

# Script interactif
sudo ./deploy.sh
# Suivre les instructions à l'écran
```

### Déploiement sur IP Serveur
```bash
sudo ./deploy-auto.sh 192.168.1.100 portable
```

## ⚡ Démarrage Rapide après Déploiement

Après un déploiement avec `deploy-auto.sh` :

```bash
# Aller dans le répertoire d'installation
cd /root/secret-poll  # ou le répertoire indiqué

# Démarrer l'application
./start.sh

# Vérifier le statut
./status.sh

# Arrêter l'application
./stop.sh
```

## 🌐 Accès à l'Application

Après le démarrage, accédez à :
- **Backend API :** `http://votre-domaine:18001`
- **Frontend :** `http://votre-domaine:13000`
- **Health Check :** `http://votre-domaine:18001/api/health`

## 🔍 Dépannage

### Problème : Script ne répond pas
**Solution :** Utilisez le mode automatique
```bash
sudo ./deploy.sh --auto
```

### Problème : Conflits de ports
**Solution :** Le script automatique utilise des ports hauts (18001, 13000)
```bash
sudo ./deploy-auto.sh localhost portable
```

### Problème : Permissions insuffisantes
**Solution :** Utilisez sudo
```bash
sudo ./deploy-auto.sh
```

### Problème : Environnement non supporté
**Solution :** Utilisez le déploiement portable
```bash
sudo ./deploy-auto.sh localhost portable
```

## 📝 Logs et Débogage

Les logs de déploiement sont disponibles dans :
- `/var/log/secret-poll-deploy.log`

Pour voir les erreurs :
```bash
tail -f /var/log/secret-poll-deploy.log
```

## 🎯 Recommandations

### Pour les Tests/Développement
```bash
sudo ./deploy-auto.sh localhost portable
```

### Pour la Production
```bash
sudo ./deploy.sh  # Mode interactif complet
```

### Pour l'Automatisation/CI
```bash
sudo ./deploy-auto.sh example.com docker-isolated
```

---

## 🚀 Tous les scripts sont maintenant fonctionnels et testés !

Choisissez la méthode qui convient le mieux à votre cas d'usage.