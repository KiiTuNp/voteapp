import React, { useState, useEffect } from 'react';
import './App.css';

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL || 'http://localhost:8001';

function App() {
  const [currentView, setCurrentView] = useState('home');
  const [roomData, setRoomData] = useState(null);
  const [participantToken, setParticipantToken] = useState(null);
  const [ws, setWs] = useState(null);
  const [activePoll, setActivePoll] = useState(null);
  const [voteResults, setVoteResults] = useState({});
  const [hasVoted, setHasVoted] = useState(false);
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
            setActivePoll({
              poll_id: data.poll_id,
              question: data.question,
              options: data.options
            });
            setHasVoted(false);
            setVoteResults({});
            break;
          case 'poll_stopped':
            setActivePoll(null);
            setHasVoted(false);
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
  const createRoom = async (organizerName) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/rooms/create?organizer_name=${encodeURIComponent(organizerName)}`, {
        method: 'POST'
      });
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

  // Load room status
  const loadRoomStatus = async (roomId) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/rooms/${roomId}/status`);
      const data = await response.json();
      setRoomStatus(data);
      if (data.active_poll) {
        setActivePoll(data.active_poll);
      }
    } catch (error) {
      console.error('Error loading room status:', error);
    }
  };

  // Create Poll
  const createPoll = async (question, options) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/polls/create`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          room_id: roomData.room_id,
          question,
          options
        })
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
  const vote = async (selectedOption) => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/polls/${activePoll.poll_id}/vote`, {
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
      
      setHasVoted(true);
    } catch (error) {
      alert('Error voting: ' + error.message);
    }
  };

  // Generate Report
  const generateReport = async () => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/rooms/${roomData.room_id}/report`);
      const reportData = await response.json();
      
      // Create downloadable report
      const reportText = generateReportText(reportData);
      const blob = new Blob([reportText], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `poll-report-${roomData.room_id}.txt`;
      a.click();
      
      // Clean up data after report is saved
      await fetch(`${BACKEND_URL}/api/rooms/${roomData.room_id}/cleanup`, {
        method: 'DELETE'
      });
      
      alert('Report downloaded and all data has been deleted!');
      setCurrentView('home');
      setRoomData(null);
    } catch (error) {
      alert('Error generating report: ' + error.message);
    }
  };

  const generateReportText = (reportData) => {
    let text = `POLL MEETING REPORT\n`;
    text += `========================\n`;
    text += `Room ID: ${reportData.room_id}\n`;
    text += `Organizer: ${reportData.organizer_name}\n`;
    text += `Participants: ${reportData.participant_count}\n`;
    text += `Generated: ${new Date(reportData.generated_at).toLocaleString()}\n\n`;
    
    reportData.polls.forEach((poll, index) => {
      text += `POLL ${index + 1}: ${poll.question}\n`;
      text += `Total Votes: ${poll.total_votes}\n`;
      text += `Results:\n`;
      poll.options.forEach(option => {
        const count = poll.results[option] || 0;
        const percentage = poll.total_votes > 0 ? ((count / poll.total_votes) * 100).toFixed(1) : 0;
        text += `  ${option}: ${count} votes (${percentage}%)\n`;
      });
      text += `\n`;
    });
    
    return text;
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
          activePoll={activePoll}
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
          activePoll={activePoll}
          hasVoted={hasVoted}
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

  const handleSubmit = (e) => {
    e.preventDefault();
    if (organizerName.trim()) {
      onCreateRoom(organizerName.trim());
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

  const handleSubmit = (e) => {
    e.preventDefault();
    if (roomId.trim()) {
      onJoinRoom(roomId.trim().toUpperCase());
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
        <p className="text-gray-600">Enter the room ID to participate</p>
      </div>
      
      <form onSubmit={handleSubmit} className="space-y-4">
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
  activePoll, 
  createdPolls,
  voteResults, 
  onCreatePoll, 
  onStartPoll, 
  onStopPoll, 
  onGenerateReport, 
  onBack 
}) {
  const [showPollForm, setShowPollForm] = useState(false);
  const [question, setQuestion] = useState('');
  const [options, setOptions] = useState(['', '']);

  const handleCreatePoll = (e) => {
    e.preventDefault();
    const validOptions = options.filter(opt => opt.trim());
    if (question.trim() && validOptions.length >= 2) {
      onCreatePoll(question.trim(), validOptions);
      setQuestion('');
      setOptions(['', '']);
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
        
        <div className="grid md:grid-cols-3 gap-6 mb-8">
          <div className="bg-blue-50 rounded-lg p-4">
            <h3 className="font-semibold text-blue-800 mb-2">Participants</h3>
            <p className="text-2xl font-bold text-blue-600">{roomStatus?.participant_count || 0}</p>
          </div>
          <div className="bg-green-50 rounded-lg p-4">
            <h3 className="font-semibold text-green-800 mb-2">Total Polls</h3>
            <p className="text-2xl font-bold text-green-600">{roomStatus?.total_polls || 0}</p>
          </div>
          <div className="bg-purple-50 rounded-lg p-4">
            <h3 className="font-semibold text-purple-800 mb-2">Active Poll</h3>
            <p className="text-2xl font-bold text-purple-600">{activePoll ? 'Yes' : 'No'}</p>
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
            Generate Report & End Meeting
          </button>
        </div>
      </div>

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
            
            <button
              type="submit"
              className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 transition-colors"
            >
              Create Poll
            </button>
          </form>
        </div>
      )}

      {createdPolls.length > 0 && !activePoll && (
        <div className="bg-white rounded-2xl shadow-lg p-6 mb-8">
          <h2 className="text-2xl font-bold text-gray-800 mb-6">Available Polls</h2>
          <p className="text-sm text-gray-600 mb-4">Start a poll to begin voting</p>
          <div className="space-y-3">
            {createdPolls.map((poll) => (
              <div key={poll.poll_id} className="flex justify-between items-center p-4 bg-gray-50 rounded-lg">
                <div>
                  <h4 className="font-medium text-gray-800">{poll.question}</h4>
                  <p className="text-sm text-gray-600">{poll.options.join(', ')}</p>
                </div>
                <button
                  onClick={() => onStartPoll(poll.poll_id)}
                  className="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700 transition-colors"
                >
                  Start Poll
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {activePoll && (
        <div className="bg-white rounded-2xl shadow-lg p-6">
          <div className="flex justify-between items-center mb-6">
            <h2 className="text-2xl font-bold text-gray-800">Active Poll</h2>
            <button
              onClick={() => onStopPoll(activePoll.poll_id)}
              className="bg-red-600 text-white px-4 py-2 rounded-lg hover:bg-red-700 transition-colors"
            >
              Stop Poll
            </button>
          </div>
          
          <h3 className="text-xl font-semibold text-gray-800 mb-4">{activePoll.question}</h3>
          
          <div className="space-y-3">
            {activePoll.options?.map((option, index) => {
              const count = voteResults[option] || 0;
              const total = Object.values(voteResults).reduce((sum, count) => sum + count, 0);
              const percentage = total > 0 ? ((count / total) * 100).toFixed(1) : 0;
              
              return (
                <div key={index} className="bg-gray-50 rounded-lg p-4">
                  <div className="flex justify-between items-center mb-2">
                    <span className="font-medium">{option}</span>
                    <span className="text-gray-600">{count} votes ({percentage}%)</span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div 
                      className="bg-blue-600 h-2 rounded-full transition-all duration-300"
                      style={{ width: `${percentage}%` }}
                    ></div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

// Participant View Component
function ParticipantView({ roomData, activePoll, hasVoted, voteResults, onVote, onBack }) {
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

      {!activePoll && (
        <div className="bg-white rounded-2xl shadow-lg p-8 text-center">
          <div className="w-16 h-16 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <h2 className="text-2xl font-bold text-gray-800 mb-2">Waiting for Poll</h2>
          <p className="text-gray-600">The organizer will start a poll soon...</p>
        </div>
      )}

      {activePoll && !hasVoted && (
        <div className="bg-white rounded-2xl shadow-lg p-6">
          <h2 className="text-2xl font-bold text-gray-800 mb-2">Active Poll</h2>
          <h3 className="text-xl text-gray-700 mb-6">{activePoll.question}</h3>
          
          <div className="space-y-3">
            {activePoll.options?.map((option, index) => (
              <button
                key={index}
                onClick={() => onVote(option)}
                className="w-full p-4 text-left bg-gray-50 hover:bg-blue-50 border border-gray-200 hover:border-blue-300 rounded-lg transition-colors"
              >
                {option}
              </button>
            ))}
          </div>
        </div>
      )}

      {activePoll && hasVoted && (
        <div className="bg-white rounded-2xl shadow-lg p-6">
          <h2 className="text-2xl font-bold text-gray-800 mb-2">Poll Results</h2>
          <h3 className="text-xl text-gray-700 mb-6">{activePoll.question}</h3>
          
          <div className="space-y-3">
            {activePoll.options?.map((option, index) => {
              const count = voteResults[option] || 0;
              const total = Object.values(voteResults).reduce((sum, count) => sum + count, 0);
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
          
          <div className="mt-6 p-4 bg-green-50 rounded-lg">
            <p className="text-green-800 font-medium">✓ Your vote has been recorded anonymously</p>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;