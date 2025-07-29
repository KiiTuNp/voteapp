# Secret Poll - Real-time Anonymous Polling System

A professional-grade, real-time polling application designed for secure meeting management with anonymous voting, participant approval, and comprehensive reporting.

## 🎯 Features

### Core Functionality
- **Anonymous Polling** - Secure voting with no way to trace participants to their choices
- **Real-time Updates** - Live vote counts and participant synchronization
- **Participant Approval** - Organizer controls who can participate in polls
- **Custom Room IDs** - Professional meeting identification (3-10 alphanumeric characters)
- **Poll Timers** - Automatic poll closure with visual countdown
- **Multiple Active Polls** - Run several polls simultaneously
- **Multi-format Export** - PDF, JSON, and text report generation
- **Data Security** - Complete data deletion after meeting export

### Advanced Features
- **Timer-based Polls** - Automatic stop functionality with visual countdown
- **Participant Management** - Join and participate during active poll sessions  
- **Results Privacy** - Participants cannot see results before voting (prevents bias)
- **WebSocket Communication** - Real-time synchronization across all clients
- **Network Resilience** - Automatic reconnection and retry mechanisms
- **Production-ready** - Comprehensive error handling and user feedback

## 🏗️ Architecture

**Frontend:** React with Tailwind CSS  
**Backend:** FastAPI with WebSocket support  
**Database:** MongoDB  
**Real-time:** WebSocket connections for live updates  
**Export:** PDF generation with reportlab, JSON and text fallbacks

## 📋 Prerequisites

### For Local Development
- **Node.js** 16+ and npm/yarn
- **Python** 3.8+
- **MongoDB** 4.4+
- **Git**

### For VPS Deployment
- **Ubuntu/Debian** VPS with root access
- **Docker** and **Docker Compose** (recommended)
- **Domain name** (optional but recommended)
- **SSL Certificate** (Let's Encrypt recommended)

## 🚀 Quick Start (Local Development)

### 1. Clone Repository
```bash
git clone <your-repository-url>
cd secret-poll
```

### 2. Backend Setup
```bash
# Navigate to backend directory
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
cp .env.example .env
# Edit .env with your settings
```

### 3. Frontend Setup
```bash
# Navigate to frontend directory
cd ../frontend

# Install dependencies
npm install
# or
yarn install

# Set environment variables
cp .env.example .env
# Edit .env with your settings
```

### 4. Database Setup
```bash
# Start MongoDB (Ubuntu/Debian)
sudo systemctl start mongod
sudo systemctl enable mongod

# Or using Docker
docker run -d -p 27017:27017 --name mongodb mongo:latest
```

### 5. Run Application
```bash
# Terminal 1: Backend
cd backend
source venv/bin/activate
python server.py

# Terminal 2: Frontend  
cd frontend
npm start
# or
yarn start
```

Application will be available at:
- **Frontend:** http://localhost:3000
- **Backend API:** http://localhost:8001

## 🌐 VPS Deployment

### Option 1: Docker Deployment (Recommended)

#### Step 1: Prepare VPS
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo systemctl enable docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Logout and login to apply Docker group
exit
# SSH back in
```

#### Step 2: Create Deployment Structure
```bash
mkdir -p /opt/secret-poll
cd /opt/secret-poll

# Clone your repository
git clone <your-repository-url> .
```

#### Step 3: Create Docker Compose Configuration
Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  mongodb:
    image: mongo:7.0
    container_name: secret-poll-mongo
    restart: unless-stopped
    environment:
      - MONGO_INITDB_DATABASE=poll_app
    volumes:
      - mongodb_data:/data/db
      - ./mongo-init.js:/docker-entrypoint-initdb.d/mongo-init.js:ro
    networks:
      - app-network

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.prod
    container_name: secret-poll-backend
    restart: unless-stopped
    environment:
      - MONGO_URL=mongodb://mongodb:27017/poll_app
      - CORS_ORIGINS=https://yourdomain.com,https://www.yourdomain.com
    depends_on:
      - mongodb
    networks:
      - app-network

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.prod
      args:
        - REACT_APP_BACKEND_URL=https://yourdomain.com
    container_name: secret-poll-frontend
    restart: unless-stopped
    depends_on:
      - backend
    networks:
      - app-network

  nginx:
    image: nginx:alpine
    container_name: secret-poll-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - frontend
      - backend
    networks:
      - app-network

volumes:
  mongodb_data:

networks:
  app-network:
    driver: bridge
```

#### Step 4: Create Production Dockerfiles

**Backend Dockerfile (`backend/Dockerfile.prod`):**
```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user
RUN useradd -m -u 1000 app && chown -R app:app /app
USER app

# Expose port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8001/api/health || exit 1

# Start application
CMD ["python", "server.py"]
```

**Frontend Dockerfile (`frontend/Dockerfile.prod`):**
```dockerfile
# Build stage
FROM node:18-alpine as build

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci --only=production

# Copy source code and build
COPY . .
ARG REACT_APP_BACKEND_URL
ENV REACT_APP_BACKEND_URL=$REACT_APP_BACKEND_URL
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built files
COPY --from=build /app/build /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

#### Step 5: Create Nginx Configuration
Create `nginx.conf`:

```nginx
events {
    worker_connections 1024;
}

http {
    upstream backend {
        server backend:8001;
    }

    upstream frontend {
        server frontend:80;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
    limit_req_zone $binary_remote_addr zone=general:10m rate=200r/m;

    server {
        listen 80;
        server_name yourdomain.com www.yourdomain.com;
        
        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy strict-origin-when-cross-origin;
        
        # API routes
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400;
        }
        
        # Frontend routes
        location / {
            limit_req zone=general burst=50 nodelay;
            proxy_pass http://frontend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    # HTTPS configuration (add after obtaining SSL certificate)
    # server {
    #     listen 443 ssl http2;
    #     server_name yourdomain.com www.yourdomain.com;
    #     
    #     ssl_certificate /etc/nginx/ssl/fullchain.pem;
    #     ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    #     
    #     # Modern SSL configuration
    #     ssl_protocols TLSv1.2 TLSv1.3;
    #     ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    #     ssl_prefer_server_ciphers off;
    #     ssl_session_cache shared:SSL:10m;
    #     
    #     # Same location blocks as HTTP
    # }
}
```

#### Step 6: Deploy Application
```bash
# Build and start services
docker-compose -f docker-compose.prod.yml up -d --build

# Check status
docker-compose -f docker-compose.prod.yml ps

# View logs
docker-compose -f docker-compose.prod.yml logs -f
```

#### Step 7: SSL Certificate (Optional but Recommended)
```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Stop nginx temporarily
docker-compose -f docker-compose.prod.yml stop nginx

# Obtain certificate
sudo certbot certonly --standalone -d yourdomain.com -d www.yourdomain.com

# Copy certificates to project directory
sudo mkdir -p ssl
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ssl/
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem ssl/
sudo chown $USER:$USER ssl/*.pem

# Update nginx.conf to enable HTTPS block
# Then restart
docker-compose -f docker-compose.prod.yml up -d nginx
```

### Option 2: Manual VPS Deployment

#### Step 1: Prepare VPS Environment
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Python and pip
sudo apt install python3 python3-pip python3-venv -y

# Install MongoDB
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod

# Install Nginx
sudo apt install nginx -y
sudo systemctl enable nginx

# Install PM2 for process management
sudo npm install -g pm2
```

#### Step 2: Deploy Application
```bash
# Create application directory
sudo mkdir -p /opt/secret-poll
sudo chown $USER:$USER /opt/secret-poll
cd /opt/secret-poll

# Clone repository
git clone <your-repository-url> .

# Setup backend
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Create production environment file
cat > .env << EOF
MONGO_URL=mongodb://localhost:27017/poll_app
CORS_ORIGINS=https://yourdomain.com,https://www.yourdomain.com
EOF

# Setup frontend
cd ../frontend
npm install
cat > .env << EOF
REACT_APP_BACKEND_URL=https://yourdomain.com
EOF

# Build frontend
npm run build
```

#### Step 3: Configure Process Management
Create PM2 ecosystem file (`ecosystem.config.js`):

```javascript
module.exports = {
  apps: [
    {
      name: 'secret-poll-backend',
      cwd: '/opt/secret-poll/backend',
      script: 'server.py',
      interpreter: '/opt/secret-poll/backend/venv/bin/python',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        NODE_ENV: 'production'
      },
      error_file: '/var/log/pm2/secret-poll-backend-error.log',
      out_file: '/var/log/pm2/secret-poll-backend-out.log',
      log_file: '/var/log/pm2/secret-poll-backend.log',
      max_memory_restart: '500M'
    }
  ]
};
```

#### Step 4: Configure Nginx
```bash
# Create Nginx configuration
sudo tee /etc/nginx/sites-available/secret-poll << EOF
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;
    
    # Serve frontend
    location / {
        root /opt/secret-poll/frontend/build;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    # API proxy
    location /api/ {
        proxy_pass http://localhost:8001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Enable site
sudo ln -s /etc/nginx/sites-available/secret-poll /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

#### Step 5: Start Services
```bash
# Start backend with PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup

# Enable firewall (optional)
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable
```

## 🔧 Configuration

### Environment Variables

#### Backend (`.env`)
```env
# Database
MONGO_URL=mongodb://localhost:27017/poll_app

# CORS (for production)
CORS_ORIGINS=https://yourdomain.com,https://www.yourdomain.com

# Optional: Custom port
PORT=8001
```

#### Frontend (`.env`)
```env
# Backend URL
REACT_APP_BACKEND_URL=https://yourdomain.com

# Optional: Custom port for development
PORT=3000
```

## 📱 Usage Guide

### For Organizers
1. **Create Meeting**
   - Enter your name and optional custom room ID
   - Share room ID with participants

2. **Manage Participants**
   - View participants as they join
   - Approve or deny access individually
   - Monitor approval status in real-time

3. **Create Polls**
   - Add questions with multiple options
   - Set optional auto-stop timers
   - Start/stop polls as needed

4. **Monitor Results**
   - View live vote counts
   - See real-time participation
   - Track multiple active polls

5. **Export Data**
   - Generate comprehensive reports
   - Multiple format download (PDF, JSON, Text)
   - Automatic data cleanup after export

### For Participants
1. **Join Meeting**
   - Enter your name and room ID
   - Wait for organizer approval

2. **Vote on Polls**
   - See active polls after approval
   - Vote without seeing biased results
   - View results after voting

3. **Real-time Updates**
   - Automatic poll notifications
   - Live result updates
   - Timer countdowns

## 🛠️ API Documentation

### Authentication
No authentication required - uses anonymous session tokens

### Core Endpoints

#### Rooms
- `POST /api/rooms/create` - Create new room
- `POST /api/rooms/join` - Join existing room
- `GET /api/rooms/{room_id}/status` - Get room status
- `GET /api/rooms/{room_id}/participants` - List participants
- `GET /api/rooms/{room_id}/polls` - List all polls
- `GET /api/rooms/{room_id}/report` - Generate PDF report
- `DELETE /api/rooms/{room_id}/cleanup` - Delete room data

#### Polls
- `POST /api/polls/create` - Create new poll
- `POST /api/polls/{poll_id}/start` - Start poll
- `POST /api/polls/{poll_id}/stop` - Stop poll
- `POST /api/polls/{poll_id}/vote` - Submit vote

#### Participants
- `POST /api/participants/{participant_id}/approve` - Approve participant
- `POST /api/participants/{participant_id}/deny` - Deny participant

#### WebSocket
- `WS /api/ws/{room_id}` - Real-time updates

## 🔍 Troubleshooting

### Common Issues

#### MongoDB Connection Failed
```bash
# Check MongoDB status
sudo systemctl status mongod

# Restart MongoDB
sudo systemctl restart mongod

# Check logs
sudo journalctl -u mongod
```

#### Frontend Build Fails
```bash
# Clear cache and reinstall
rm -rf node_modules package-lock.json
npm install

# Check Node.js version
node --version  # Should be 16+
```

#### WebSocket Connection Issues
- Ensure firewall allows WebSocket connections
- Check proxy configuration for Upgrade headers
- Verify CORS settings in backend

#### PDF Generation Fails
```bash
# Install missing system dependencies
sudo apt-get install -y libcairo2-dev libpango1.0-dev
pip install --upgrade reportlab
```

### Performance Tuning

#### For High Traffic
```javascript
// PM2 cluster mode
pm2 start ecosystem.config.js --instances max

// Nginx optimization
worker_processes auto;
worker_connections 1024;
```

#### Database Optimization
```javascript
// MongoDB indexes
db.rooms.createIndex({ "room_id": 1 })
db.participants.createIndex({ "room_id": 1 })
db.polls.createIndex({ "room_id": 1 })
db.votes.createIndex({ "poll_id": 1 })
```

## 🔒 Security Considerations

### Production Security
- Use HTTPS with valid SSL certificates
- Implement rate limiting (included in Nginx config)
- Regular security updates
- Monitor for unusual activity
- Use environment variables for sensitive data

### Data Privacy
- Anonymous voting system
- Automatic data cleanup
- No personal data persistence
- Secure session management

## 📦 Maintenance

### Regular Tasks
```bash
# Update dependencies
cd backend && pip install -r requirements.txt --upgrade
cd frontend && npm update

# Database maintenance
mongodump --db poll_app --out backup/
mongo poll_app --eval "db.dropDatabase()"  # Only for cleanup

# Log rotation
pm2 flush  # Clear PM2 logs
sudo logrotate -f /etc/logrotate.conf
```

### Monitoring
```bash
# Check application health
curl https://yourdomain.com/api/health

# Monitor resources
htop
df -h
free -h

# PM2 monitoring
pm2 status
pm2 logs
pm2 monit
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

## 📞 Support

For support and questions:
- Check troubleshooting section above
- Review API documentation
- Check application logs
- Create GitHub issue for bugs

---

**Secret Poll** - Professional anonymous polling for secure meetings 🗳️
