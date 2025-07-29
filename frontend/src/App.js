import React, { useState, useEffect } from 'react';
import './App.css';

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL || 'http://localhost:8001';

function App() {
  const [currentView, setCurrentView] = useState('home');
  const [roomData, setRoomData] = useState(null);
  const [participantToken, setParticipantToken] = useState(null);
  const [ws, setWs] = useState(null);
  const [activePolls, setActivePolls] = useState([]); // Changed from single activePoll to multiple activePolls
  const [allPolls, setAllPolls] = useState([]); // Track all polls with their statuses
  const [hasVoted, setHasVoted] = useState({});  // Changed to object to track votes per poll
  const [voteResults, setVoteResults] = useState({});
  const [pollTimers, setPollTimers] = useState({}); // Track timers for active polls
  const [roomStatus, setRoomStatus] = useState(null);
  const [createdPolls, setCreatedPolls] = useState([]);
  const [participants, setParticipants] = useState([]);
  const [approvalStatus, setApprovalStatus] = useState(null);

  // WebSocket connection
  useEffect(() => {
    if (roomData && roomData.room_id) {
      const websocket = new WebSocket(`${BACKEND_URL.replace('http', 'ws')}/api/ws/${roomData.room_id}`);
      
      websocket.onmessage = (event) => {
        const data = JSON.parse(event.data);
        
        switch (data.type) {
          case 'participant_update':
            if (roomStatus) {
              setRoomStatus(prev => ({
                ...prev,
                participant_count: data.participant_count
              }));
            }
            break;
          case 'poll_started':
            const newPoll = {
              poll_id: data.poll_id,
              question: data.question,
              options: data.options,
              timer_minutes: data.timer_minutes
            };
            setActivePolls(prev => [...prev, newPoll]);
            setHasVoted(prev => ({...prev, [data.poll_id]: false}));
            setVoteResults(prev => ({...prev, [data.poll_id]: {}}));
            
            // Start timer if specified
            if (data.timer_minutes) {
              const endTime = Date.now() + (data.timer_minutes * 60 * 1000);
              setPollTimers(prev => ({...prev, [data.poll_id]: endTime}));
            }
            break;
          case 'poll_stopped':
            setActivePolls(prev => prev.filter(poll => poll.poll_id !== data.poll_id));
            // Keep timer for display until cleanup
            break;
          case 'poll_auto_stopped':
            setActivePolls(prev => prev.filter(poll => poll.poll_id !== data.poll_id));
            setPollTimers(prev => {
              const newTimers = {...prev};
              delete newTimers[data.poll_id];
              return newTimers;
            });
            break;
          case 'participant_approved':
            if (data.participant_token === participantToken) {
              setApprovalStatus('approved');
            }
            break;
          case 'participant_denied':
            if (data.participant_token === participantToken) {
              setApprovalStatus('denied');
            }
            break;
          case 'vote_update':
            setVoteResults(data.vote_counts);
            break;
          default:
            break;
        }
      };
      
      setWs(websocket);
      
      return () => {
        websocket.close();
      };
    }
  }, [roomData]);

  // Create Room (Organizer)
  const createRoom = async (organizerName, customRoomId = '') => {
    try {
      const params = new URLSearchParams({ organizer_name: organizerName });
      if (customRoomId) {
        params.append('custom_room_id', customRoomId);
      }
      
      const response = await fetch(`${BACKEND_URL}/api/rooms/create?${params}`, {
        method: 'POST'
      });
      
      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.detail || 'Failed to create room');
      }
      
      const data = await response.json();
      setRoomData(data);
      setCurrentView('organizer');
      loadRoomStatus(data.room_id);
    } catch (error) {
      alert('Error creating room: ' + error.message);
    }
  };

  // Join Room (Participant)
  const joinRoom = async (roomId, participantName) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/rooms/join?room_id=${roomId}&participant_name=${encodeURIComponent(participantName)}`, {
        method: 'POST'
      });
      
      if (!response.ok) {
        throw new Error('Room not found');
      }
      
      const data = await response.json();
      setRoomData(data);
      setParticipantToken(data.participant_token);
      setApprovalStatus(data.approval_status);
      setCurrentView('participant');
      
      // Load room status to check for existing active polls
      loadRoomStatus(roomId);
    } catch (error) {
      alert('Error joining room: ' + error.message);
    }
  };

  // Load participants
  const loadParticipants = async (roomId) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/rooms/${roomId}/participants`);
      const data = await response.json();
      setParticipants(data.participants);
    } catch (error) {
      console.error('Error loading participants:', error);
    }
  };

  // Approve participant
  const approveParticipant = async (participantId) => {
    try {
      await fetch(`${BACKEND_URL}/api/participants/${participantId}/approve`, {
        method: 'POST'
      });
      if (roomData && roomData.room_id) {
        loadParticipants(roomData.room_id);
        loadRoomStatus(roomData.room_id);
      }
    } catch (error) {
      alert('Error approving participant: ' + error.message);
    }
  };

  // Deny participant
  const denyParticipant = async (participantId) => {
    try {
      await fetch(`${BACKEND_URL}/api/participants/${participantId}/deny`, {
        method: 'POST'
      });
      if (roomData && roomData.room_id) {
        loadParticipants(roomData.room_id);
        loadRoomStatus(roomData.room_id);
      }
    } catch (error) {
      alert('Error denying participant: ' + error.message);
    }
  };

  // Load all polls for the room
  const loadAllPolls = async (roomId) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/rooms/${roomId}/polls`);
      const data = await response.json();
      setAllPolls(data.polls);
      setCreatedPolls(data.polls);
    } catch (error) {
      console.error('Error loading polls:', error);
    }
  };

  // Load room status
  const loadRoomStatus = async (roomId) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/rooms/${roomId}/status`);
      const data = await response.json();
      setRoomStatus(data);
      if (data.active_polls) {
        setActivePolls(data.active_polls);
      }
      // Load all polls for the organizer
      loadAllPolls(roomId);
    } catch (error) {
      console.error('Error loading room status:', error);
    }
  };

  // Create Poll
  const createPoll = async (question, options, timerMinutes = null) => {
    try {
      const pollData = {
        room_id: roomData.room_id,
        question,
        options
      };
      
      if (timerMinutes) {
        pollData.timer_minutes = timerMinutes;
      }
      
      const response = await fetch(`${BACKEND_URL}/api/polls/create`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(pollData)
      });
      
      const newPoll = await response.json();
      setCreatedPolls(prev => [...prev, newPoll]);
      loadRoomStatus(roomData.room_id);
    } catch (error) {
      alert('Error creating poll: ' + error.message);
    }
  };

  // Start Poll
  const startPoll = async (pollId) => {
    try {
      await fetch(`${BACKEND_URL}/api/polls/${pollId}/start`, {
        method: 'POST'
      });
      // Reload room status to update UI
      if (roomData && roomData.room_id) {
        loadRoomStatus(roomData.room_id);
      }
    } catch (error) {
      alert('Error starting poll: ' + error.message);
    }
  };

  // Stop Poll
  const stopPoll = async (pollId) => {
    try {
      await fetch(`${BACKEND_URL}/api/polls/${pollId}/stop`, {
        method: 'POST'
      });
    } catch (error) {
      alert('Error stopping poll: ' + error.message);
    }
  };

  // Vote
  const vote = async (pollId, selectedOption) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/polls/${pollId}/vote`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          participant_token: participantToken,
          selected_option: selectedOption
        })
      });
      
      if (!response.ok) {
        throw new Error('Failed to vote');
      }
      
      setHasVoted(prev => ({...prev, [pollId]: true}));
    } catch (error) {
      alert('Error voting: ' + error.message);
    }
  };

  // Generate Report
  const generateReport = async () => {
    try {
      // Generate and download PDF report
      const response = await fetch(`${BACKEND_URL}/api/rooms/${roomData.room_id}/report`);
      
      if (!response.ok) {
        throw new Error('Failed to generate report');
      }
      
      // Get the PDF blob
      const blob = await response.blob();
      
      // Create download link
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      
      // Extract filename from response headers if available
      const contentDisposition = response.headers.get('Content-Disposition');
      let filename = `poll_report_${roomData.room_id}.pdf`;
      if (contentDisposition) {
        const filenameMatch = contentDisposition.match(/filename="(.+)"/);
        if (filenameMatch) {
          filename = filenameMatch[1];
        }
      }
      
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      
      // Wait a moment for download to start, then cleanup data
      setTimeout(async () => {
        try {
          await fetch(`${BACKEND_URL}/api/rooms/${roomData.room_id}/cleanup`, {
            method: 'DELETE'
          });
          
          alert('📄 PDF report downloaded successfully!\n🗑️ All meeting data has been permanently deleted for security.');
          setCurrentView('home');
          setRoomData(null);
          setParticipants([]);
          setCreatedPolls([]);
          setRoomStatus(null);
        } catch (cleanupError) {
          console.error('Error during cleanup:', cleanupError);
          alert('📄 Report downloaded, but there was an issue cleaning up data. Please contact support.');
        }
      }, 1000);
      
    } catch (error) {
      alert('Error generating report: ' + error.message);
    }
  };

  // Home View
  if (currentView === 'home') {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
        <div className="container mx-auto px-4 py-16">
          <div className="text-center mb-12">
            <h1 className="text-5xl font-bold text-gray-800 mb-4">Secret Poll</h1>
            <p className="text-xl text-gray-600">Anonymous polling for meetings</p>
          </div>
          
          <div className="max-w-4xl mx-auto grid md:grid-cols-2 gap-8">
            <OrganizerCard onCreateRoom={createRoom} />
            <ParticipantCard onJoinRoom={joinRoom} />
          </div>
        </div>
      </div>
    );
  }

  // Organizer View
  if (currentView === 'organizer') {
    return (
      <div className="min-h-screen bg-gray-50">
        <OrganizerDashboard 
          roomData={roomData}
          roomStatus={roomStatus}
          activePolls={activePolls}
          allPolls={allPolls}
          createdPolls={createdPolls}
          participants={participants}
          voteResults={voteResults}
          onCreatePoll={createPoll}
          onStartPoll={startPoll}
          onStopPoll={stopPoll}
          onGenerateReport={generateReport}
          onApproveParticipant={approveParticipant}
          onDenyParticipant={denyParticipant}
          onLoadParticipants={loadParticipants}
          onBack={() => setCurrentView('home')}
        />
      </div>
    );
  }

  // Participant View
  if (currentView === 'participant') {
    return (
      <div className="min-h-screen bg-gray-50">
        <ParticipantView 
          roomData={roomData}
          activePolls={activePolls}
          hasVoted={hasVoted}
          approvalStatus={approvalStatus}
          voteResults={voteResults}
          onVote={vote}
          onBack={() => setCurrentView('home')}
        />
      </div>
    );
  }

  return null;
}

// Organizer Card Component
function OrganizerCard({ onCreateRoom }) {
  const [organizerName, setOrganizerName] = useState('');
  const [customRoomId, setCustomRoomId] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    if (organizerName.trim()) {
      // Validate custom room ID if provided
      if (customRoomId && customRoomId.length < 3) {
        alert('Custom room ID must be at least 3 characters long');
        return;
      }
      onCreateRoom(organizerName.trim(), customRoomId.trim());
    }
  };

  return (
    <div className="bg-white rounded-2xl shadow-xl p-8 border border-gray-200">
      <div className="text-center mb-6">
        <div className="w-16 h-16 bg-blue-100 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-8 h-8 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-4m-5 0H3m2 0h3M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 4h1m4 0h1" />
          </svg>
        </div>
        <h2 className="text-2xl font-bold text-gray-800 mb-2">Start a Meeting</h2>
        <p className="text-gray-600">Create polls and manage your meeting</p>
      </div>
      
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">Your Name</label>
          <input
            type="text"
            value={organizerName}
            onChange={(e) => setOrganizerName(e.target.value)}
            className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            placeholder="Enter your name"
            required
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">Custom Room ID (Optional)</label>
          <input
            type="text"
            value={customRoomId}
            onChange={(e) => {
              // Only allow alphanumeric characters and limit to 10 chars
              const value = e.target.value.replace(/[^A-Za-z0-9]/g, '').toUpperCase().slice(0, 10);
              setCustomRoomId(value);
            }}
            className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent font-mono"
            placeholder="e.g., MEETING01 (3-10 characters, letters & numbers only)"
            maxLength={10}
          />
          <p className="text-xs text-gray-500 mt-1">
            {customRoomId.length > 0 && customRoomId.length < 3 && (
              <span className="text-red-500">Minimum 3 characters required</span>
            )}
            {customRoomId.length >= 3 && (
              <span className="text-green-600">✓ Valid room ID</span>
            )}
            {customRoomId.length === 0 && (
              <span>Custom IDs help identify meetings (leave empty for random ID)</span>
            )}
          </p>
        </div>
        <button
          type="submit"
          className="w-full bg-blue-600 text-white py-3 px-6 rounded-lg hover:bg-blue-700 transition-colors font-medium"
        >
          Create Room
        </button>
      </form>
    </div>
  );
}

// Participant Card Component
function ParticipantCard({ onJoinRoom }) {
  const [roomId, setRoomId] = useState('');
  const [participantName, setParticipantName] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    if (roomId.trim() && participantName.trim()) {
      onJoinRoom(roomId.trim().toUpperCase(), participantName.trim());
    }
  };

  return (
    <div className="bg-white rounded-2xl shadow-xl p-8 border border-gray-200">
      <div className="text-center mb-6">
        <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-8 h-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
          </svg>
        </div>
        <h2 className="text-2xl font-bold text-gray-800 mb-2">Join a Meeting</h2>
        <p className="text-gray-600">Enter your details to participate</p>
      </div>
      
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">Your Name</label>
          <input
            type="text"
            value={participantName}
            onChange={(e) => setParticipantName(e.target.value)}
            className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent"
            placeholder="Enter your name"
            required
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">Room ID</label>
          <input
            type="text"
            value={roomId}
            onChange={(e) => setRoomId(e.target.value.toUpperCase())}
            className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent text-center text-lg font-mono"
            placeholder="Enter Room ID"
            maxLength={8}
            required
          />
        </div>
        <button
          type="submit"
          className="w-full bg-green-600 text-white py-3 px-6 rounded-lg hover:bg-green-700 transition-colors font-medium"
        >
          Join Room
        </button>
      </form>
    </div>
  );
}

// Organizer Dashboard Component
function OrganizerDashboard({ 
  roomData, 
  roomStatus, 
  activePolls, 
  allPolls,
  createdPolls,
  participants,
  voteResults, 
  onCreatePoll, 
  onStartPoll, 
  onStopPoll, 
  onGenerateReport,
  onApproveParticipant,
  onDenyParticipant,
  onLoadParticipants,
  onBack 
}) {
  const [showPollForm, setShowPollForm] = useState(false);
  const [question, setQuestion] = useState('');
  const [options, setOptions] = useState(['', '']);
  const [timerMinutes, setTimerMinutes] = useState('');

  // Load participants when component mounts
  useEffect(() => {
    if (roomData && roomData.room_id) {
      onLoadParticipants(roomData.room_id);
    }
  }, [roomData, onLoadParticipants]);

  const handleCreatePoll = (e) => {
    e.preventDefault();
    const validOptions = options.filter(opt => opt.trim());
    if (question.trim() && validOptions.length >= 2) {
      const pollData = {
        question: question.trim(),
        options: validOptions
      };
      
      // Add timer if specified
      if (timerMinutes && parseInt(timerMinutes) > 0) {
        pollData.timer_minutes = parseInt(timerMinutes);
      }
      
      onCreatePoll(pollData.question, pollData.options, pollData.timer_minutes);
      setQuestion('');
      setOptions(['', '']);
      setTimerMinutes('');
      setShowPollForm(false);
    }
  };

  const addOption = () => {
    setOptions([...options, '']);
  };

  const updateOption = (index, value) => {
    const newOptions = [...options];
    newOptions[index] = value;
    setOptions(newOptions);
  };

  const removeOption = (index) => {
    if (options.length > 2) {
      setOptions(options.filter((_, i) => i !== index));
    }
  };

  const pendingParticipants = participants.filter(p => p.approval_status === 'pending');
  const approvedParticipants = participants.filter(p => p.approval_status === 'approved');

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="bg-white rounded-2xl shadow-lg p-6 mb-8">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h1 className="text-3xl font-bold text-gray-800">Meeting Dashboard</h1>
            <p className="text-gray-600 mt-2">Room ID: <span className="font-mono font-bold text-lg">{roomData?.room_id}</span></p>
          </div>
          <button
            onClick={onBack}
            className="px-4 py-2 text-gray-600 hover:text-gray-800 transition-colors"
          >
            ← Back
          </button>
        </div>
        
        <div className="grid md:grid-cols-4 gap-6 mb-8">
          <div className="bg-blue-50 rounded-lg p-4">
            <h3 className="font-semibold text-blue-800 mb-2">Total Participants</h3>
            <p className="text-2xl font-bold text-blue-600">{roomStatus?.participant_count || 0}</p>
          </div>
          <div className="bg-green-50 rounded-lg p-4">
            <h3 className="font-semibold text-green-800 mb-2">Approved</h3>
            <p className="text-2xl font-bold text-green-600">{roomStatus?.approved_count || 0}</p>
          </div>
          <div className="bg-yellow-50 rounded-lg p-4">
            <h3 className="font-semibold text-yellow-800 mb-2">Pending</h3>
            <p className="text-2xl font-bold text-yellow-600">{roomStatus?.pending_count || 0}</p>
          </div>
          <div className="bg-purple-50 rounded-lg p-4">
            <h3 className="font-semibold text-purple-800 mb-2">Active Polls</h3>
            <p className="text-2xl font-bold text-purple-600">{activePolls?.length || 0}</p>
          </div>
        </div>

        <div className="flex gap-4">
          <button
            onClick={() => setShowPollForm(!showPollForm)}
            className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 transition-colors"
          >
            {showPollForm ? 'Cancel' : 'Create New Poll'}
          </button>
          <button
            onClick={onGenerateReport}
            className="bg-green-600 text-white px-6 py-3 rounded-lg hover:bg-green-700 transition-colors"
          >
            📄 Generate PDF Report & End Meeting
          </button>
        </div>
      </div>

      {/* Participant Management Section */}
      {pendingParticipants.length > 0 && (
        <div className="bg-white rounded-2xl shadow-lg p-6 mb-8">
          <h2 className="text-2xl font-bold text-gray-800 mb-6">Pending Participants</h2>
          <div className="space-y-3">
            {pendingParticipants.map((participant) => (
              <div key={participant.participant_id} className="flex justify-between items-center p-4 bg-yellow-50 rounded-lg">
                <div>
                  <h4 className="font-medium text-gray-800">{participant.participant_name}</h4>
                  <p className="text-sm text-gray-600">Joined: {new Date(participant.joined_at).toLocaleTimeString()}</p>
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={() => onApproveParticipant(participant.participant_id)}
                    className="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700 transition-colors text-sm"
                  >
                    Approve
                  </button>
                  <button
                    onClick={() => onDenyParticipant(participant.participant_id)}
                    className="bg-red-600 text-white px-4 py-2 rounded-lg hover:bg-red-700 transition-colors text-sm"
                  >
                    Deny
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Approved Participants Section */}
      {approvedParticipants.length > 0 && (
        <div className="bg-white rounded-2xl shadow-lg p-6 mb-8">
          <h2 className="text-2xl font-bold text-gray-800 mb-6">Approved Participants</h2>
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-3">
            {approvedParticipants.map((participant) => (
              <div key={participant.participant_id} className="p-3 bg-green-50 rounded-lg">
                <span className="font-medium text-green-800">{participant.participant_name}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {showPollForm && (
        <div className="bg-white rounded-2xl shadow-lg p-6 mb-8">
          <h2 className="text-2xl font-bold text-gray-800 mb-6">Create New Poll</h2>
          <form onSubmit={handleCreatePoll} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Question</label>
              <input
                type="text"
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                placeholder="Enter your question"
                required
              />
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Options</label>
              {options.map((option, index) => (
                <div key={index} className="flex gap-2 mb-2">
                  <input
                    type="text"
                    value={option}
                    onChange={(e) => updateOption(index, e.target.value)}
                    className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder={`Option ${index + 1}`}
                    required
                  />
                  {options.length > 2 && (
                    <button
                      type="button"
                      onClick={() => removeOption(index)}
                      className="px-3 py-2 text-red-600 hover:text-red-800"
                    >
                      ✕
                    </button>
                  )}
                </div>
              ))}
              <button
                type="button"
                onClick={addOption}
                className="text-blue-600 hover:text-blue-800 text-sm"
              >
                + Add Option
              </button>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Auto-Stop Timer (Optional)</label>
              <input
                type="number"
                value={timerMinutes}
                onChange={(e) => setTimerMinutes(e.target.value)}
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                placeholder="Minutes (leave empty for manual stop)"
                min="1"
                max="60"
              />
              <p className="text-xs text-gray-500 mt-1">Poll will automatically stop after specified minutes</p>
            </div>
            
            <button
              type="submit"
              className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 transition-colors"
            >
              Create Poll
            </button>
          </form>
        </div>
      )}

      {/* All Polls Management Section */}
      {allPolls.length > 0 && (
        <div className="bg-white rounded-2xl shadow-lg p-6 mb-8">
          <h2 className="text-2xl font-bold text-gray-800 mb-6">Poll Management</h2>
          <div className="space-y-4">
            {allPolls.map((poll) => (
              <div key={poll.poll_id} className={`p-4 rounded-lg border-2 ${poll.is_active ? 'border-green-500 bg-green-50' : 'border-gray-400 bg-gray-100'}`}>
                <div className="flex justify-between items-start">
                  <div className="flex-1">
                    <h4 className="font-semibold text-gray-800 mb-2">
                      {poll.question}
                      {poll.is_active && <span className="ml-2 px-2 py-1 bg-green-600 text-white text-xs rounded-full">ACTIVE</span>}
                      {!poll.is_active && poll.total_votes > 0 && <span className="ml-2 px-2 py-1 bg-gray-600 text-white text-xs rounded-full">CLOSED</span>}
                    </h4>
                    <p className="text-sm text-gray-600 mb-2">Options: {poll.options.join(', ')}</p>
                    <p className="text-sm text-gray-500">Total votes: {poll.total_votes || 0}</p>
                    
                    {/* Show live vote breakdown */}
                    {poll.total_votes > 0 && (
                      <div className="mt-2 space-y-1">
                        {poll.options.map(option => {
                          const count = poll.vote_counts[option] || 0;
                          const percentage = poll.total_votes > 0 ? ((count / poll.total_votes) * 100).toFixed(1) : 0;
                          return (
                            <div key={option} className="flex justify-between text-sm">
                              <span>{option}:</span>
                              <span>{count} votes ({percentage}%)</span>
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                  
                  <div className="flex gap-2 ml-4">
                    {poll.is_active ? (
                      <button
                        onClick={() => onStopPoll(poll.poll_id)}
                        className="bg-red-600 text-white px-3 py-1 rounded text-sm hover:bg-red-700 transition-colors"
                      >
                        Stop
                      </button>
                    ) : poll.total_votes === 0 ? (
                      <button
                        onClick={() => onStartPoll(poll.poll_id)}
                        className="bg-green-600 text-white px-3 py-1 rounded text-sm hover:bg-green-700 transition-colors"
                      >
                        Start
                      </button>
                    ) : (
                      <span className="px-3 py-1 text-xs text-gray-500 bg-gray-200 rounded">
                        Closed
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// Participant View Component
function ParticipantView({ roomData, activePolls, hasVoted, approvalStatus, voteResults, onVote, onBack }) {
  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <div className="bg-white rounded-2xl shadow-lg p-6 mb-8">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h1 className="text-3xl font-bold text-gray-800">Poll Meeting</h1>
            <p className="text-gray-600 mt-2">Organizer: {roomData?.organizer_name}</p>
            <p className="text-gray-600">Room: <span className="font-mono font-bold">{roomData?.room_id}</span></p>
          </div>
          <button
            onClick={onBack}
            className="px-4 py-2 text-gray-600 hover:text-gray-800 transition-colors"
          >
            ← Leave
          </button>
        </div>
      </div>

      {/* Approval Status Messages */}
      {approvalStatus === 'pending' && (
        <div className="bg-white rounded-2xl shadow-lg p-8 text-center">
          <div className="w-16 h-16 bg-yellow-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <h2 className="text-2xl font-bold text-gray-800 mb-2">Waiting for Approval</h2>
          <p className="text-gray-600">The organizer needs to approve you before you can participate in polls.</p>
          <p className="text-sm text-gray-500 mt-2">Name: {roomData?.participant_name}</p>
        </div>
      )}

      {approvalStatus === 'denied' && (
        <div className="bg-white rounded-2xl shadow-lg p-8 text-center">
          <div className="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </div>
          <h2 className="text-2xl font-bold text-gray-800 mb-2">Access Denied</h2>
          <p className="text-gray-600">The organizer has denied your request to participate in this meeting.</p>
        </div>
      )}

      {/* Only show polls if approved */}
      {approvalStatus === 'approved' && (!activePolls || activePolls.length === 0) && (
        <div className="bg-white rounded-2xl shadow-lg p-8 text-center">
          <div className="w-16 h-16 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <h2 className="text-2xl font-bold text-gray-800 mb-2">Waiting for Polls</h2>
          <p className="text-gray-600">The organizer will start polls soon...</p>
        </div>
      )}

      {/* Show all active polls */}
      {approvalStatus === 'approved' && activePolls && activePolls.length > 0 && (
        <div className="space-y-6">
          {activePolls.map((poll) => (
            <div key={poll.poll_id} className="bg-white rounded-2xl shadow-lg p-6">
              <h2 className="text-2xl font-bold text-gray-800 mb-2">Active Poll</h2>
              <h3 className="text-xl text-gray-700 mb-6">{poll.question}</h3>
              
              {!hasVoted[poll.poll_id] ? (
                <div className="space-y-3">
                  {poll.options?.map((option, index) => (
                    <button
                      key={index}
                      onClick={() => onVote(poll.poll_id, option)}
                      className="w-full p-4 text-left bg-gray-50 hover:bg-blue-50 border border-gray-200 hover:border-blue-300 rounded-lg transition-colors"
                    >
                      {option}
                    </button>
                  ))}
                </div>
              ) : (
                <div>
                  <div className="space-y-3 mb-6">
                    {poll.options?.map((option, index) => {
                      const count = voteResults[poll.poll_id]?.[option] || 0;
                      const total = Object.values(voteResults[poll.poll_id] || {}).reduce((sum, count) => sum + count, 0);
                      const percentage = total > 0 ? ((count / total) * 100).toFixed(1) : 0;
                      
                      return (
                        <div key={index} className="bg-gray-50 rounded-lg p-4">
                          <div className="flex justify-between items-center mb-2">
                            <span className="font-medium">{option}</span>
                            <span className="text-gray-600">{count} votes ({percentage}%)</span>
                          </div>
                          <div className="w-full bg-gray-200 rounded-full h-2">
                            <div 
                              className="bg-green-600 h-2 rounded-full transition-all duration-300"
                              style={{ width: `${percentage}%` }}
                            ></div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                  
                  <div className="p-4 bg-green-50 rounded-lg">
                    <p className="text-green-800 font-medium">✓ Your vote has been recorded anonymously</p>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default App;