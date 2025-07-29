# 🗳️ Secret Poll - Real-time Anonymous Polling System

A professional real-time anonymous polling application designed for meetings and conferences. Organizers can create polls, manage participants, and generate comprehensive reports while ensuring complete anonymity.

## 🌟 Features

- **🔒 Anonymous Voting** - No association between participants and their choices
- **⚡ Real-time Updates** - Live vote counts and participant status via WebSocket
- **👤 Participant Management** - Manual approval system for controlled access  
- **📊 Multiple Poll Types** - Support for various question formats
- **📄 PDF Reports** - Professional reports with participant lists and results
- **🔧 Room Management** - Simple room codes for easy access
- **⏱️ Poll Timers** - Optional automatic poll closure
- **🛡️ Data Privacy** - Automatic data deletion after report generation

## 🚀 Quick Installation

### Prerequisites
- Ubuntu/Debian server (18.04+)
- Root access (sudo)
- Internet connection

### One-Command Installation
```bash
sudo python3 install.py
```

The installer will:
1. ✅ Check system requirements
2. ✅ Install dependencies (Python, Node.js, MongoDB)
3. ✅ Configure web server (Nginx/Apache)
4. ✅ Setup SSL certificates (Let's Encrypt)
5. ✅ Create systemd services
6. ✅ Configure automatic startup

## 🔧 Configuration Options

During installation, you'll be prompted for:

- **Domain/IP** - Your server domain or IP address
- **SSL Certificate** - Automatic Let's Encrypt setup
- **Web Server** - Nginx (recommended), Apache, or standalone
- **Environment** - Production or staging
- **Installation Directory** - Default: `/opt/secret-poll`

## 💻 Manual Development Setup

### Backend Setup
```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python server.py
```

### Frontend Setup
```bash
cd frontend
npm install  # or yarn install
npm start    # or yarn start
```

### MongoDB
```bash
sudo systemctl start mongodb
```

## 🌐 Usage

### For Organizers
1. Create a room with a custom room ID
2. Share the room code with participants
3. Approve participants as they join
4. Create and manage polls in real-time
5. View live results and generate reports

### For Participants
1. Join using the room code
2. Provide your name and wait for approval
3. Vote on active polls
4. View results after voting

## 📊 API Endpoints

### Room Management
- `POST /api/rooms` - Create a new room
- `GET /api/rooms/{room_id}` - Get room details
- `POST /api/rooms/{room_id}/join` - Join a room

### Participant Management  
- `POST /api/rooms/{room_id}/participants/{participant_id}/approve` - Approve participant
- `POST /api/rooms/{room_id}/participants/{participant_id}/deny` - Deny participant

### Polls
- `POST /api/rooms/{room_id}/polls` - Create a poll
- `POST /api/polls/{poll_id}/start` - Start a poll
- `POST /api/polls/{poll_id}/stop` - Stop a poll
- `POST /api/polls/{poll_id}/vote` - Submit a vote

### Reports
- `GET /api/polls/{room_id}/export/pdf` - Generate PDF report
- `GET /api/polls/{room_id}/export/json` - Export as JSON

### WebSocket
- `WS /api/ws/{room_id}` - Real-time updates

## 🛠️ Management Commands

After installation, use these commands:

```bash
# Check application status
/opt/secret-poll/status.sh

# View application logs
/opt/secret-poll/logs.sh

# Restart services
/opt/secret-poll/restart.sh

# Service management
systemctl start/stop/restart secret-poll
systemctl start/stop/restart nginx
systemctl start/stop/restart mongodb
```

## 📁 Project Structure

```
secret-poll/
├── backend/                 # FastAPI backend
│   ├── server.py           # Main application
│   ├── requirements.txt    # Python dependencies
│   └── .env               # Environment variables
├── frontend/               # React frontend
│   ├── src/               # Source files
│   ├── public/            # Static assets
│   ├── package.json       # Node dependencies
│   └── .env              # Frontend configuration
├── install.py             # Production installer
└── README.md             # This file
```

## 🔒 Security Features

- **HTTPS/SSL** - Automatic Let's Encrypt certificates
- **CORS Protection** - Configured origins
- **Input Validation** - Comprehensive data validation
- **Rate Limiting** - Protection against abuse
- **Security Headers** - XSS, CSRF, and clickjacking protection

## 🐳 Docker Support (Optional)

For containerized deployment:

```bash
# Build and run with Docker Compose
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## 📄 Environment Variables

### Backend (.env)
```bash
MONGO_URL=mongodb://localhost:27017/secret_poll
PORT=8001
ENVIRONMENT=production
CORS_ORIGINS=https://yourdomain.com
SECRET_KEY=your-secret-key
```

### Frontend (.env)  
```bash
REACT_APP_BACKEND_URL=https://yourdomain.com
NODE_ENV=production
GENERATE_SOURCEMAP=false
```

## 🔍 Troubleshooting

### Common Issues

**Application not starting:**
```bash
# Check service status
systemctl status secret-poll

# View logs
journalctl -u secret-poll -f
```

**Database connection issues:**
```bash
# Check MongoDB status
systemctl status mongodb

# Restart MongoDB
systemctl restart mongodb
```

**Web server issues:**
```bash
# Test Nginx configuration
nginx -t

# Reload configuration
systemctl reload nginx
```

### Health Checks

```bash
# API health check
curl https://yourdomain.com/api/health

# Backend direct check
curl http://localhost:8001/api/health
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Commit changes: `git commit -am 'Add feature'`
4. Push to the branch: `git push origin feature-name`
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/KiiTuNp/voteapp/issues)
- **Documentation**: Check this README and inline code comments
- **Logs**: `/var/log/secret-poll-install.log` and `journalctl -u secret-poll`

## 🎉 Production Ready

This application is production-ready with:
- ✅ Professional systemd service configuration
- ✅ Automatic SSL certificate management
- ✅ Web server integration (Nginx/Apache)
- ✅ Database persistence and reliability
- ✅ Comprehensive logging and monitoring
- ✅ Security best practices implementation

---

**Made with ❤️ for anonymous polling needs**
