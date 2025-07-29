# 🚀 Secret Poll - Installation One-Click

## ⚡ **Installation Ultra-Simple**

### Option 1: Depuis GitHub (Recommandé)
```bash
curl -sSL https://raw.githubusercontent.com/KiiTuNp/voteapp/main/install.sh | sudo bash
```

### Option 2: Installation Locale
```bash
git clone https://github.com/KiiTuNp/voteapp.git
cd voteapp
sudo bash install.sh
```

## 🎉 **C'est Tout !**

Le script fait **TOUT automatiquement** :
- ✅ Installe toutes les dépendances (Python, Node.js, MongoDB)
- ✅ Télécharge l'application
- ✅ Configure automatiquement
- ✅ Construit le frontend et backend
- ✅ Crée les scripts de gestion
- ✅ Prêt à utiliser immédiatement !

## 🚀 **Après l'installation:**

```bash
cd /opt/secret-poll
./start.sh
```

**Accès à l'application :**
- 🌐 **Frontend**: http://localhost:3000
- ⚙️ **Backend**: http://localhost:8001
- 🏥 **Health Check**: http://localhost:8001/api/health

## 🛠️ **Commandes simples:**

```bash
./start.sh    # Démarrer
./stop.sh     # Arrêter
./status.sh   # Voir l'état
./restart.sh  # Redémarrer
```

## 📄 **Voir les logs:**

```bash
tail -f backend.log   # Logs backend
tail -f frontend.log  # Logs frontend
```

## 🎯 **Zéro Configuration Requise !**

- ✅ **Aucune question posée**
- ✅ **Détection automatique de l'environnement**
- ✅ **Configuration optimale automatique**
- ✅ **Gestion des conflits automatique**
- ✅ **Installation en moins de 5 minutes**

## 🔧 **Que fait le script automatiquement ?**

1. **Installe les dépendances** (Python 3, Node.js, MongoDB)
2. **Clone l'application** depuis GitHub
3. **Configure les variables d'environnement**
4. **Installe les packages Python** (backend)
5. **Installe les packages Node.js** et build (frontend)
6. **Démarre MongoDB**
7. **Crée les scripts de gestion**
8. **Teste l'installation**
9. **Affiche les instructions finales**

## 🆘 **En cas de problème:**

```bash
# Voir les logs d'installation
tail -f /var/log/secret-poll-install.log

# Redémarrer MongoDB
sudo systemctl restart mongod

# Tester l'API
curl http://localhost:8001/api/health
```

## 🎊 **Prêt en Une Commande !**

```bash
curl -sSL https://raw.githubusercontent.com/KiiTuNp/voteapp/main/install.sh | sudo bash
```

**Plus simple, ça n'existe pas !** ⚡

---

## 📋 **Prérequis Système**

- Ubuntu 18.04+ (ou dérivés Debian)
- Accès root (sudo)
- Connexion Internet
- 2GB RAM minimum
- 5GB espace disque libre

**Le script gère tout le reste automatiquement !** 🎉