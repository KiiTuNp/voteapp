from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Optional
import pymongo
import os
import uuid
import json
from datetime import datetime

# Initialize FastAPI
app = FastAPI()

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# MongoDB connection
MONGO_URL = os.environ.get("MONGO_URL", "mongodb://localhost:27017")
client = pymongo.MongoClient(MONGO_URL)
db = client.poll_app

# Collections
rooms_collection = db.rooms
polls_collection = db.polls
votes_collection = db.votes
participants_collection = db.participants

# WebSocket connections manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, room_id: str):
        await websocket.accept()
        if room_id not in self.active_connections:
            self.active_connections[room_id] = []
        self.active_connections[room_id].append(websocket)

    def disconnect(self, websocket: WebSocket, room_id: str):
        if room_id in self.active_connections:
            self.active_connections[room_id].remove(websocket)

    async def broadcast_to_room(self, room_id: str, message: dict):
        if room_id in self.active_connections:
            for connection in self.active_connections[room_id]:
                try:
                    await connection.send_text(json.dumps(message))
                except:
                    pass

manager = ConnectionManager()

# Pydantic models
class Room(BaseModel):
    room_id: str
    organizer_name: str
    created_at: datetime
    is_active: bool = True

class Poll(BaseModel):
    poll_id: str
    room_id: str
    question: str
    options: List[str]
    is_active: bool = False
    created_at: datetime

class Vote(BaseModel):
    vote_id: str
    poll_id: str
    room_id: str
    participant_token: str
    selected_option: str
    voted_at: datetime

class Participant(BaseModel):
    participant_id: str
    room_id: str
    participant_name: str
    participant_token: str
    approval_status: str  # "pending", "approved", "denied"
    joined_at: datetime

# API Routes

@app.get("/api/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/api/rooms/create")
async def create_room(organizer_name: str):
    room_id = str(uuid.uuid4())[:8].upper()
    
    room = {
        "room_id": room_id,
        "organizer_name": organizer_name,
        "created_at": datetime.now(),
        "is_active": True
    }
    
    rooms_collection.insert_one(room)
    
    return {"room_id": room_id, "organizer_name": organizer_name}

@app.post("/api/rooms/join")
async def join_room(room_id: str, participant_name: str):
    # Check if room exists and is active
    room = rooms_collection.find_one({"room_id": room_id, "is_active": True})
    if not room:
        raise HTTPException(status_code=404, detail="Room not found or inactive")
    
    # Generate participant token
    participant_token = str(uuid.uuid4())
    participant_id = str(uuid.uuid4())
    
    participant = {
        "participant_id": participant_id,
        "room_id": room_id,
        "participant_name": participant_name,
        "participant_token": participant_token,
        "approval_status": "pending",
        "joined_at": datetime.now()
    }
    
    participants_collection.insert_one(participant)
    
    # Broadcast participant update to organizer
    participant_count = participants_collection.count_documents({"room_id": room_id})
    pending_count = participants_collection.count_documents({"room_id": room_id, "approval_status": "pending"})
    
    await manager.broadcast_to_room(room_id, {
        "type": "participant_update",
        "participant_count": participant_count,
        "pending_count": pending_count
    })
    
    return {
        "participant_token": participant_token,
        "participant_name": participant_name,
        "room_id": room_id,
        "approval_status": "pending",
        "organizer_name": room["organizer_name"]
    }

class PollCreateRequest(BaseModel):
    room_id: str
    question: str
    options: List[str]

@app.post("/api/polls/create")
async def create_poll(request: PollCreateRequest):
    room = rooms_collection.find_one({"room_id": request.room_id, "is_active": True})
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    poll_id = str(uuid.uuid4())
    
    poll = {
        "poll_id": poll_id,
        "room_id": request.room_id,
        "question": request.question,
        "options": request.options,
        "is_active": False,
        "created_at": datetime.now()
    }
    
    polls_collection.insert_one(poll)
    
    # Broadcast new poll to room
    await manager.broadcast_to_room(request.room_id, {
        "type": "new_poll",
        "poll": poll
    })
    
    return {"poll_id": poll_id, "question": request.question, "options": request.options}

@app.post("/api/polls/{poll_id}/start")
async def start_poll(poll_id: str):
    poll = polls_collection.find_one({"poll_id": poll_id})
    if not poll:
        raise HTTPException(status_code=404, detail="Poll not found")
    
    polls_collection.update_one(
        {"poll_id": poll_id},
        {"$set": {"is_active": True}}
    )
    
    # Broadcast poll start
    await manager.broadcast_to_room(poll["room_id"], {
        "type": "poll_started",
        "poll_id": poll_id,
        "question": poll["question"],
        "options": poll["options"]
    })
    
    return {"message": "Poll started"}

@app.post("/api/polls/{poll_id}/stop")
async def stop_poll(poll_id: str):
    poll = polls_collection.find_one({"poll_id": poll_id})
    if not poll:
        raise HTTPException(status_code=404, detail="Poll not found")
    
    polls_collection.update_one(
        {"poll_id": poll_id},
        {"$set": {"is_active": False}}
    )
    
    # Broadcast poll stop
    await manager.broadcast_to_room(poll["room_id"], {
        "type": "poll_stopped",
        "poll_id": poll_id
    })
    
    return {"message": "Poll stopped"}

class VoteRequest(BaseModel):
    participant_token: str
    selected_option: str

@app.post("/api/polls/{poll_id}/vote")
async def vote(poll_id: str, request: VoteRequest):
    poll = polls_collection.find_one({"poll_id": poll_id, "is_active": True})
    if not poll:
        raise HTTPException(status_code=404, detail="Poll not found or inactive")
    
    # Check if participant is approved to vote
    participant = participants_collection.find_one({"participant_token": request.participant_token})
    if not participant:
        raise HTTPException(status_code=404, detail="Participant not found")
    
    if participant["approval_status"] != "approved":
        raise HTTPException(status_code=403, detail="Participant not approved to vote")
    
    # Check if participant already voted for this poll
    existing_vote = votes_collection.find_one({
        "poll_id": poll_id,
        "participant_token": request.participant_token
    })
    
    if existing_vote:
        raise HTTPException(status_code=400, detail="Already voted")
    
    # Validate option
    if request.selected_option not in poll["options"]:
        raise HTTPException(status_code=400, detail="Invalid option")
    
    vote_id = str(uuid.uuid4())
    
    vote = {
        "vote_id": vote_id,
        "poll_id": poll_id,
        "room_id": poll["room_id"],
        "participant_token": request.participant_token,
        "selected_option": request.selected_option,
        "voted_at": datetime.now()
    }
    
    votes_collection.insert_one(vote)
    
    # Broadcast vote count update
    vote_counts = {}
    for option in poll["options"]:
        count = votes_collection.count_documents({
            "poll_id": poll_id,
            "selected_option": option
        })
        vote_counts[option] = count
    
    await manager.broadcast_to_room(poll["room_id"], {
        "type": "vote_update",
        "poll_id": poll_id,
        "vote_counts": vote_counts,
        "total_votes": sum(vote_counts.values())
    })
    
    return {"message": "Vote recorded"}

@app.get("/api/rooms/{room_id}/status")
async def get_room_status(room_id: str):
    room = rooms_collection.find_one({"room_id": room_id, "is_active": True})
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    participant_count = participants_collection.count_documents({"room_id": room_id})
    approved_count = participants_collection.count_documents({"room_id": room_id, "approval_status": "approved"})
    pending_count = participants_collection.count_documents({"room_id": room_id, "approval_status": "pending"})
    polls = list(polls_collection.find({"room_id": room_id}))
    
    # Get current active poll
    active_poll = polls_collection.find_one({"room_id": room_id, "is_active": True})
    
    # Clean up active_poll for JSON serialization
    if active_poll:
        active_poll = {
            "poll_id": active_poll["poll_id"],
            "question": active_poll["question"],
            "options": active_poll["options"],
            "is_active": active_poll["is_active"]
        }
    
    return {
        "room_id": room_id,
        "organizer_name": room["organizer_name"],
        "participant_count": participant_count,
        "approved_count": approved_count,
        "pending_count": pending_count,
        "total_polls": len(polls),
        "active_poll": active_poll
    }

@app.get("/api/rooms/{room_id}/participants")
async def get_participants(room_id: str):
    room = rooms_collection.find_one({"room_id": room_id, "is_active": True})
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    participants = list(participants_collection.find({"room_id": room_id}))
    
    # Clean up participants for JSON serialization
    clean_participants = []
    for p in participants:
        clean_participants.append({
            "participant_id": p["participant_id"],
            "participant_name": p["participant_name"],
            "approval_status": p["approval_status"],
            "joined_at": p["joined_at"].isoformat()
        })
    
    return {"participants": clean_participants}

@app.post("/api/participants/{participant_id}/approve")
async def approve_participant(participant_id: str):
    participant = participants_collection.find_one({"participant_id": participant_id})
    if not participant:
        raise HTTPException(status_code=404, detail="Participant not found")
    
    participants_collection.update_one(
        {"participant_id": participant_id},
        {"$set": {"approval_status": "approved"}}
    )
    
    # Broadcast approval to participant
    await manager.broadcast_to_room(participant["room_id"], {
        "type": "participant_approved",
        "participant_token": participant["participant_token"],
        "participant_name": participant["participant_name"]
    })
    
    return {"message": "Participant approved"}

@app.post("/api/participants/{participant_id}/deny")
async def deny_participant(participant_id: str):
    participant = participants_collection.find_one({"participant_id": participant_id})
    if not participant:
        raise HTTPException(status_code=404, detail="Participant not found")
    
    participants_collection.update_one(
        {"participant_id": participant_id},
        {"$set": {"approval_status": "denied"}}
    )
    
    # Broadcast denial to participant
    await manager.broadcast_to_room(participant["room_id"], {
        "type": "participant_denied",
        "participant_token": participant["participant_token"],
        "participant_name": participant["participant_name"]
    })
    
    return {"message": "Participant denied"}
async def generate_report(room_id: str):
    room = rooms_collection.find_one({"room_id": room_id})
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Get all polls for this room
    polls = list(polls_collection.find({"room_id": room_id}))
    
    report_data = {
        "room_id": room_id,
        "organizer_name": room["organizer_name"],
        "generated_at": datetime.now().isoformat(),
        "participant_count": participants_collection.count_documents({"room_id": room_id}),
        "polls": []
    }
    
    for poll in polls:
        vote_counts = {}
        for option in poll["options"]:
            count = votes_collection.count_documents({
                "poll_id": poll["poll_id"],
                "selected_option": option
            })
            vote_counts[option] = count
        
        poll_data = {
            "question": poll["question"],
            "options": poll["options"],
            "results": vote_counts,
            "total_votes": sum(vote_counts.values())
        }
        report_data["polls"].append(poll_data)
    
    return report_data

@app.delete("/api/rooms/{room_id}/cleanup")
async def cleanup_room_data(room_id: str):
    # Delete all data for this room
    rooms_collection.delete_many({"room_id": room_id})
    polls_collection.delete_many({"room_id": room_id})
    votes_collection.delete_many({"room_id": room_id})
    participants_collection.delete_many({"room_id": room_id})
    
    return {"message": "Room data deleted successfully"}

# WebSocket endpoint
@app.websocket("/api/ws/{room_id}")
async def websocket_endpoint(websocket: WebSocket, room_id: str):
    await manager.connect(websocket, room_id)
    try:
        while True:
            data = await websocket.receive_text()
            # Keep connection alive
    except WebSocketDisconnect:
        manager.disconnect(websocket, room_id)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)