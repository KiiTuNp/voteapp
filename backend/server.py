from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel
from typing import List, Dict, Optional
import pymongo
import os
import uuid
import json
import asyncio
from datetime import datetime, timedelta
from reportlab.lib.pagesizes import letter, A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib import colors
from io import BytesIO

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

# Store active poll timers
active_timers = {}

async def auto_stop_poll(poll_id: str, room_id: str, delay_minutes: int):
    """Auto-stop a poll after specified minutes"""
    await asyncio.sleep(delay_minutes * 60)  # Convert minutes to seconds
    
    # Check if poll is still active
    poll = polls_collection.find_one({"poll_id": poll_id, "is_active": True})
    if poll:
        # Stop the poll
        polls_collection.update_one(
            {"poll_id": poll_id},
            {"$set": {"is_active": False}}
        )
        
        # Broadcast poll auto-stop
        await manager.broadcast_to_room(room_id, {
            "type": "poll_auto_stopped",
            "poll_id": poll_id,
            "message": "Poll automatically stopped due to timer"
        })
        
        # Remove from active timers
        if poll_id in active_timers:
            del active_timers[poll_id]

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
async def create_room(organizer_name: str, custom_room_id: str = None):
    # Generate room ID
    if custom_room_id and custom_room_id.strip():
        # Validate custom room ID
        clean_id = custom_room_id.strip().upper()
        
        # Check length (3-10 characters)
        if len(clean_id) < 3 or len(clean_id) > 10:
            raise HTTPException(status_code=400, detail="Custom room ID must be 3-10 characters long")
        
        # Check alphanumeric only
        if not clean_id.isalnum():
            raise HTTPException(status_code=400, detail="Custom room ID must contain only letters and numbers")
        
        # Check if custom room ID already exists
        existing_room = rooms_collection.find_one({"room_id": clean_id})
        if existing_room:
            raise HTTPException(status_code=400, detail="Room ID already exists. Please choose a different ID.")
        
        room_id = clean_id
    else:
        # Generate random room ID if no custom ID provided
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
    timer_minutes: Optional[int] = None  # Optional timer in minutes

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
        "timer_minutes": request.timer_minutes,
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
    
    # Start timer if specified
    if poll.get("timer_minutes"):
        # Cancel existing timer if any
        if poll_id in active_timers:
            active_timers[poll_id].cancel()
        
        # Start new timer
        timer_task = asyncio.create_task(
            auto_stop_poll(poll_id, poll["room_id"], poll["timer_minutes"])
        )
        active_timers[poll_id] = timer_task
    
    # Broadcast poll start
    await manager.broadcast_to_room(poll["room_id"], {
        "type": "poll_started",
        "poll_id": poll_id,
        "question": poll["question"],
        "options": poll["options"],
        "timer_minutes": poll.get("timer_minutes")
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
    
    # Cancel timer if active
    if poll_id in active_timers:
        active_timers[poll_id].cancel()
        del active_timers[poll_id]
    
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
    
    # Broadcast vote count update to EVERYONE in the room (not just organizer)
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
    
    # Get all polls for this room
    all_polls = list(polls_collection.find({"room_id": room_id}))
    
    # Get all active polls (multiple can be active now)
    active_polls = list(polls_collection.find({"room_id": room_id, "is_active": True}))
    
    # Clean up active polls for JSON serialization
    clean_active_polls = []
    for poll in active_polls:
        clean_active_polls.append({
            "poll_id": poll["poll_id"],
            "question": poll["question"],
            "options": poll["options"],
            "is_active": poll["is_active"]
        })
    
    return {
        "room_id": room_id,
        "organizer_name": room["organizer_name"],
        "participant_count": participant_count,
        "approved_count": approved_count,
        "pending_count": pending_count,
        "total_polls": len(all_polls),
        "active_polls": clean_active_polls,  # Changed from single active_poll to multiple active_polls
        "active_poll_count": len(active_polls)
    }

@app.get("/api/rooms/{room_id}/polls")
async def get_all_polls(room_id: str):
    room = rooms_collection.find_one({"room_id": room_id, "is_active": True})
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    polls = list(polls_collection.find({"room_id": room_id}))
    
    # Clean up polls and add vote counts
    clean_polls = []
    for poll in polls:
        # Calculate vote results for each poll
        vote_counts = {}
        for option in poll["options"]:
            count = votes_collection.count_documents({
                "poll_id": poll["poll_id"],
                "selected_option": option
            })
            vote_counts[option] = count
        
        clean_polls.append({
            "poll_id": poll["poll_id"],
            "question": poll["question"],
            "options": poll["options"],
            "is_active": poll["is_active"],
            "created_at": poll["created_at"].isoformat(),
            "vote_counts": vote_counts,
            "total_votes": sum(vote_counts.values())
        })
    
    return {"polls": clean_polls}

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

@app.get("/api/rooms/{room_id}/report")
async def generate_pdf_report(room_id: str):
    room = rooms_collection.find_one({"room_id": room_id})
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Get all polls for this room
    polls = list(polls_collection.find({"room_id": room_id}))
    
    # Get all participants
    participants = list(participants_collection.find({"room_id": room_id}))
    
    # Create PDF in memory
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=72, leftMargin=72, topMargin=72, bottomMargin=18)
    
    # Container for the 'Flowable' objects
    story = []
    
    # Styles
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        spaceAfter=30,
        alignment=1,  # Center alignment
        textColor=colors.darkblue
    )
    
    heading_style = ParagraphStyle(
        'CustomHeading',
        parent=styles['Heading2'],
        fontSize=16,
        spaceAfter=12,
        textColor=colors.darkblue
    )
    
    # Title
    story.append(Paragraph("Secret Poll Meeting Report", title_style))
    story.append(Spacer(1, 20))
    
    # Meeting Information
    story.append(Paragraph("Meeting Information", heading_style))
    meeting_info = [
        ['Room ID:', room_id],
        ['Organizer:', room["organizer_name"]],
        ['Generated:', datetime.now().strftime("%Y-%m-%d %H:%M:%S")],
        ['Total Participants:', str(len(participants))]
    ]
    
    meeting_table = Table(meeting_info, colWidths=[2*inch, 4*inch])
    meeting_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTNAME', (1, 0), (1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 0), (-1, -1), 12),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
    ]))
    story.append(meeting_table)
    story.append(Spacer(1, 20))
    
    # Participants Section
    story.append(Paragraph("Registered Participants", heading_style))
    
    # Separate participants by approval status
    approved_participants = [p for p in participants if p["approval_status"] == "approved"]
    pending_participants = [p for p in participants if p["approval_status"] == "pending"]
    denied_participants = [p for p in participants if p["approval_status"] == "denied"]
    
    if approved_participants:
        story.append(Paragraph("<b>Approved Participants:</b>", styles['Normal']))
        participant_data = [['Name', 'Joined At', 'Status']]
        for p in approved_participants:
            participant_data.append([
                p["participant_name"],
                p["joined_at"].strftime("%H:%M:%S"),
                "✓ Approved"
            ])
        
        participant_table = Table(participant_data, colWidths=[2.5*inch, 1.5*inch, 1.5*inch])
        participant_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 10),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
            ('GRID', (0, 0), (-1, -1), 1, colors.black)
        ]))
        story.append(participant_table)
        story.append(Spacer(1, 15))
    
    if pending_participants or denied_participants:
        other_participants = []
        if pending_participants:
            other_participants.extend([(p["participant_name"], "⏳ Pending") for p in pending_participants])
        if denied_participants:
            other_participants.extend([(p["participant_name"], "❌ Denied") for p in denied_participants])
        
        if other_participants:
            story.append(Paragraph("<b>Other Participants:</b>", styles['Normal']))
            other_data = [['Name', 'Status']]
            other_data.extend(other_participants)
            
            other_table = Table(other_data, colWidths=[3*inch, 2*inch])
            other_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.lightgrey),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, 0), 10),
                ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                ('GRID', (0, 0), (-1, -1), 1, colors.black)
            ]))
            story.append(other_table)
            story.append(Spacer(1, 20))
    
    # Poll Results Section
    if polls:
        story.append(Paragraph("Poll Results", heading_style))
        
        for i, poll in enumerate(polls, 1):
            story.append(Paragraph(f"<b>Poll {i}: {poll['question']}</b>", styles['Normal']))
            
            # Calculate vote results
            vote_counts = {}
            for option in poll["options"]:
                count = votes_collection.count_documents({
                    "poll_id": poll["poll_id"],
                    "selected_option": option
                })
                vote_counts[option] = count
            
            total_votes = sum(vote_counts.values())
            
            if total_votes > 0:
                # Create results table
                results_data = [['Option', 'Votes', 'Percentage']]
                for option in poll["options"]:
                    count = vote_counts[option]
                    percentage = (count / total_votes * 100) if total_votes > 0 else 0
                    results_data.append([
                        option,
                        str(count),
                        f"{percentage:.1f}%"
                    ])
                
                results_data.append(['Total Votes', str(total_votes), '100.0%'])
                
                results_table = Table(results_data, colWidths=[2.5*inch, 1*inch, 1*inch])
                results_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.darkblue),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 10),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                    ('BACKGROUND', (0, -1), (-1, -1), colors.lightblue),
                    ('FONTNAME', (0, -1), (-1, -1), 'Helvetica-Bold'),
                    ('GRID', (0, 0), (-1, -1), 1, colors.black)
                ]))
                story.append(results_table)
            else:
                story.append(Paragraph("No votes recorded for this poll.", styles['Normal']))
            
            story.append(Spacer(1, 15))
    else:
        story.append(Paragraph("No polls were created in this meeting.", styles['Normal']))
    
    # Footer
    story.append(Spacer(1, 30))
    footer_style = ParagraphStyle(
        'Footer',
        parent=styles['Normal'],
        fontSize=10,
        textColor=colors.grey,
        alignment=1
    )
    story.append(Paragraph("This report was generated automatically by the Secret Poll system.", footer_style))
    story.append(Paragraph("All participant data has been permanently deleted after report generation.", footer_style))
    
    # Build PDF
    doc.build(story)
    
    # Get PDF data
    pdf_data = buffer.getvalue()
    buffer.close()
    
    # Create filename with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"poll_report_{room_id}_{timestamp}.pdf"
    
    return Response(
        content=pdf_data,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Type": "application/pdf"
        }
    )

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