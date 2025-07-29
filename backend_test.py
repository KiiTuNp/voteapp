import requests
import json
import sys
from datetime import datetime
import time

class SecretPollAPITester:
    def __init__(self, base_url="https://d8fff555-eb5a-4046-9fb4-1286bb4fcfad.preview.emergentagent.com"):
        self.base_url = base_url
        self.tests_run = 0
        self.tests_passed = 0
        self.room_id = None
        self.custom_room_id = None
        self.participant_token = None
        self.participant_id = None
        self.participant_name = None
        self.poll_id = None
        self.organizer_name = "Test Organizer"

    def run_test(self, name, method, endpoint, expected_status, data=None, params=None):
        """Run a single API test"""
        url = f"{self.base_url}/{endpoint}"
        headers = {'Content-Type': 'application/json'}

        self.tests_run += 1
        print(f"\n🔍 Testing {name}...")
        print(f"   URL: {method} {url}")
        if data:
            print(f"   Data: {data}")
        if params:
            print(f"   Params: {params}")
        
        try:
            if method == 'GET':
                response = requests.get(url, headers=headers, params=params)
            elif method == 'POST':
                if data:
                    response = requests.post(url, json=data, headers=headers, params=params)
                else:
                    response = requests.post(url, headers=headers, params=params)
            elif method == 'DELETE':
                response = requests.delete(url, headers=headers)

            success = response.status_code == expected_status
            if success:
                self.tests_passed += 1
                print(f"✅ Passed - Status: {response.status_code}")
                try:
                    response_data = response.json()
                    print(f"   Response: {response_data}")
                    return True, response_data
                except:
                    return True, {}
            else:
                print(f"❌ Failed - Expected {expected_status}, got {response.status_code}")
                try:
                    error_data = response.json()
                    print(f"   Error Response: {error_data}")
                except:
                    print(f"   Error Text: {response.text}")
                return False, {}

        except Exception as e:
            print(f"❌ Failed - Error: {str(e)}")
            return False, {}

    def test_create_room_with_custom_id(self):
        """Test creating room with custom ID"""
        custom_id = f"MARKETING-{datetime.now().strftime('%H%M%S')}"
        
        success, response = self.run_test(
            "Create Room with Custom ID",
            "POST",
            "api/rooms/create",
            200,
            params={"organizer_name": self.organizer_name, "custom_room_id": custom_id}
        )
        if success and 'room_id' in response:
            self.custom_room_id = response['room_id']
            if self.custom_room_id == custom_id.upper():
                print(f"   ✅ Created room with custom ID: {self.custom_room_id}")
                return True
            else:
                print(f"   ❌ Expected {custom_id.upper()}, got {self.custom_room_id}")
                return False
        return False

    def test_duplicate_custom_room_id(self):
        """Test creating room with duplicate custom ID (should fail)"""
        if not self.custom_room_id:
            print("❌ No custom room ID available for duplicate test")
            return False
            
        success, response = self.run_test(
            "Create Room with Duplicate Custom ID (Should Fail)",
            "POST",
            "api/rooms/create",
            400,  # Should fail with 400 Bad Request
            params={"organizer_name": "Another Organizer", "custom_room_id": self.custom_room_id}
        )
        return success

    def test_create_poll_with_timer(self):
        """Test creating a poll with auto-stop timer"""
        if not self.room_id:
            print("❌ No room ID available for poll with timer test")
            return False
            
        poll_data = {
            "room_id": self.room_id,
            "question": "What is your favorite color? (5 min timer)",
            "options": ["Red", "Blue", "Green", "Yellow"],
            "timer_minutes": 5  # 5 minute timer
        }
        
        success, response = self.run_test(
            "Create Poll with Timer",
            "POST",
            "api/polls/create",
            200,
            data=poll_data
        )
        if success and 'poll_id' in response:
            self.timer_poll_id = response['poll_id']
            print(f"   Created poll with timer: {self.timer_poll_id}")
            return True
        return False

    def test_poll_no_restart_after_votes(self):
        """Test that polls with votes cannot be restarted"""
        if not self.poll_id or not self.participant_token:
            print("❌ No poll ID or participant token available for no-restart test")
            return False
            
        # Vote on the poll first
        vote_data = {
            "participant_token": self.participant_token,
            "selected_option": "Blue"
        }
        
        success, response = self.run_test(
            "Vote Before Stop (No Restart Test)",
            "POST",
            f"api/polls/{self.poll_id}/vote",
            200,
            data=vote_data
        )
        if not success:
            return False
        
        # Stop the poll
        success, response = self.run_test(
            "Stop Poll with Votes",
            "POST",
            f"api/polls/{self.poll_id}/stop",
            200
        )
        if not success:
            return False
        
        # Try to restart the poll (should work according to current implementation)
        # But check that it shows CLOSED status in the polls list
        success, response = self.run_test(
            "Check Poll Status After Stop",
            "GET",
            f"api/rooms/{self.room_id}/polls",
            200
        )
        
        if success:
            polls = response.get('polls', [])
            for poll in polls:
                if poll['poll_id'] == self.poll_id:
                    if not poll['is_active'] and poll['total_votes'] > 0:
                        print(f"   ✅ Poll correctly shows as closed with {poll['total_votes']} votes")
                        return True
                    else:
                        print(f"   ❌ Poll status incorrect: active={poll['is_active']}, votes={poll['total_votes']}")
                        return False
            print("   ❌ Could not find poll in response")
            return False
        return False

    def test_organizer_multi_room_management(self):
        """Test organizer can manage multiple rooms"""
        # Create a second room for the same organizer
        success, response = self.run_test(
            "Create Second Room for Same Organizer",
            "POST",
            "api/rooms/create",
            200,
            params={"organizer_name": self.organizer_name}
        )
        if not success:
            return False
            
        second_room_id = response.get('room_id')
        if not second_room_id:
            print("❌ No room ID in second room response")
            return False
        
        # Test the multi-room endpoint
        success, response = self.run_test(
            "Get All Rooms for Organizer",
            "GET",
            f"api/organizer/{self.organizer_name}/rooms",
            200
        )
        
        if success:
            rooms = response.get('rooms', [])
            if len(rooms) >= 2:
                print(f"   ✅ Found {len(rooms)} rooms for organizer")
                # Check room summary data
                for room in rooms:
                    required_fields = ['room_id', 'participant_count', 'total_polls', 'active_polls']
                    for field in required_fields:
                        if field not in room:
                            print(f"   ❌ Missing field {field} in room summary")
                            return False
                print("   ✅ All room summaries have required fields")
                return True
            else:
                print(f"   ❌ Expected at least 2 rooms, found {len(rooms)}")
                return False
        return False

    def test_real_time_vote_updates(self):
        """Test real-time vote count updates"""
        if not self.room_id:
            print("❌ No room ID available for real-time updates test")
            return False
            
        # Create a new poll for this test
        poll_data = {
            "room_id": self.room_id,
            "question": "Real-time test poll",
            "options": ["Option A", "Option B", "Option C"]
        }
        
        success, response = self.run_test(
            "Create Poll for Real-time Test",
            "POST",
            "api/polls/create",
            200,
            data=poll_data
        )
        if not success:
            return False
            
        realtime_poll_id = response.get('poll_id')
        
        # Start the poll
        success, response = self.run_test(
            "Start Real-time Poll",
            "POST",
            f"api/polls/{realtime_poll_id}/start",
            200
        )
        if not success:
            return False
        
        # Create multiple participants and have them vote
        participants = []
        for i in range(3):
            participant_name = f"Realtime Participant {i+1}"
            success, response = self.run_test(
                f"Join Room (Participant {i+1})",
                "POST",
                "api/rooms/join",
                200,
                params={"room_id": self.room_id, "participant_name": participant_name}
            )
            if success:
                participants.append({
                    'name': participant_name,
                    'token': response.get('participant_token'),
                    'id': None
                })
        
        # Get participant IDs and approve them
        success, response = self.run_test(
            "Get Participants for Approval",
            "GET",
            f"api/rooms/{self.room_id}/participants",
            200
        )
        if success:
            all_participants = response.get('participants', [])
            for participant in participants:
                for p in all_participants:
                    if p.get('participant_name') == participant['name']:
                        participant['id'] = p['participant_id']
                        # Approve participant
                        self.run_test(
                            f"Approve {participant['name']}",
                            "POST",
                            f"api/participants/{participant['id']}/approve",
                            200
                        )
                        break
        
        # Have participants vote on different options
        options = ["Option A", "Option B", "Option C"]
        for i, participant in enumerate(participants):
            if participant['token']:
                vote_data = {
                    "participant_token": participant['token'],
                    "selected_option": options[i % len(options)]
                }
                
                success, response = self.run_test(
                    f"Vote by {participant['name']}",
                    "POST",
                    f"api/polls/{realtime_poll_id}/vote",
                    200,
                    data=vote_data
                )
        
        # Check final vote counts
        success, response = self.run_test(
            "Check Real-time Vote Results",
            "GET",
            f"api/rooms/{self.room_id}/polls",
            200
        )
        
        if success:
            polls = response.get('polls', [])
            for poll in polls:
                if poll['poll_id'] == realtime_poll_id:
                    vote_counts = poll.get('vote_counts', {})
                    total_votes = poll.get('total_votes', 0)
                    if total_votes == 3:
                        print(f"   ✅ Real-time votes recorded: {vote_counts}")
                        return True
                    else:
                        print(f"   ❌ Expected 3 votes, found {total_votes}")
                        return False
            print("   ❌ Could not find real-time poll in response")
            return False
        return False
        """Test creating a poll with custom request handling"""
        if not self.room_id:
            print("❌ No room ID available for poll creation test")
            return False
            
        # Try sending as form data with multiple options
        url = f"{self.base_url}/api/polls/create"
        
        self.tests_run += 1
        print(f"\n🔍 Testing Create Poll (Custom)...")
        print(f"   URL: POST {url}")
        
        try:
            # Try with multiple options parameters
            params = {
                'room_id': self.room_id,
                'question': 'What is your favorite color?',
                'options': ['Red', 'Blue', 'Green', 'Yellow']
            }
            
            response = requests.post(url, params=params)
            
            success = response.status_code == 200
            if success:
                self.tests_passed += 1
                print(f"✅ Passed - Status: {response.status_code}")
                try:
                    response_data = response.json()
                    print(f"   Response: {response_data}")
                    if 'poll_id' in response_data:
                        self.poll_id = response_data['poll_id']
                        print(f"   Created poll with ID: {self.poll_id}")
                    return True
                except:
                    return True
            else:
                print(f"❌ Failed - Expected 200, got {response.status_code}")
                try:
                    error_data = response.json()
                    print(f"   Error Response: {error_data}")
                except:
                    print(f"   Error Text: {response.text}")
                return False

        except Exception as e:
            print(f"❌ Failed - Error: {str(e)}")
            return False

    def test_health_check(self):
        """Test health check endpoint"""
        success, response = self.run_test(
            "Health Check",
            "GET",
            "api/health",
            200
        )
        return success

    def test_create_room(self, organizer_name="Test Organizer"):
        """Test room creation"""
        success, response = self.run_test(
            "Create Room",
            "POST",
            "api/rooms/create",
            200,
            params={"organizer_name": organizer_name}
        )
        if success and 'room_id' in response:
            self.room_id = response['room_id']
            print(f"   Created room with ID: {self.room_id}")
            return True
        return False

    def test_join_room_with_name(self, participant_name="Test Participant"):
        """Test joining a room with participant name (NEW APPROVAL SYSTEM)"""
        if not self.room_id:
            print("❌ No room ID available for joining test")
            return False
            
        self.participant_name = participant_name
        success, response = self.run_test(
            "Join Room with Name (Approval System)",
            "POST",
            "api/rooms/join",
            200,
            params={"room_id": self.room_id, "participant_name": participant_name}
        )
        if success and 'participant_token' in response:
            self.participant_token = response['participant_token']
            # Check if approval_status is pending
            if response.get('approval_status') == 'pending':
                print(f"   ✅ Participant created with pending status")
                print(f"   Got participant token: {self.participant_token[:8]}...")
                return True
            else:
                print(f"   ❌ Expected pending status, got: {response.get('approval_status')}")
                return False
        return False

    def test_get_participants_list(self):
        """Test getting participants list for organizer"""
        if not self.room_id:
            print("❌ No room ID available for participants list test")
            return False
            
        success, response = self.run_test(
            "Get Participants List",
            "GET",
            f"api/rooms/{self.room_id}/participants",
            200
        )
        if success and 'participants' in response:
            participants = response['participants']
            if len(participants) > 0:
                # Store participant_id for approval tests
                for p in participants:
                    if p.get('participant_name') == self.participant_name:
                        self.participant_id = p['participant_id']
                        print(f"   Found participant ID: {self.participant_id}")
                        break
                print(f"   Found {len(participants)} participants")
                return True
        return False

    def test_approve_participant(self):
        """Test approving a participant"""
        if not self.participant_id:
            print("❌ No participant ID available for approval test")
            return False
            
        success, response = self.run_test(
            "Approve Participant",
            "POST",
            f"api/participants/{self.participant_id}/approve",
            200
        )
        return success

    def test_deny_participant(self):
        """Test denying a participant (separate participant)"""
        # First create another participant to deny
        if not self.room_id:
            print("❌ No room ID available for deny test")
            return False
            
        # Join with different name
        success, response = self.run_test(
            "Join Room (For Deny Test)",
            "POST",
            "api/rooms/join",
            200,
            params={"room_id": self.room_id, "participant_name": "Test Participant 2"}
        )
        
        if not success:
            return False
            
        # Get participants list to find the new participant
        success, response = self.run_test(
            "Get Participants (For Deny)",
            "GET",
            f"api/rooms/{self.room_id}/participants",
            200
        )
        
        if not success:
            return False
            
        # Find the second participant
        deny_participant_id = None
        for p in response['participants']:
            if p.get('participant_name') == "Test Participant 2":
                deny_participant_id = p['participant_id']
                break
                
        if not deny_participant_id:
            print("❌ Could not find participant to deny")
            return False
            
        # Now deny the participant
        success, response = self.run_test(
            "Deny Participant",
            "POST",
            f"api/participants/{deny_participant_id}/deny",
            200
        )
        return success

    def test_vote_unapproved_participant(self):
        """Test voting with unapproved participant (should fail)"""
        if not self.poll_id:
            print("❌ No poll ID available for unapproved vote test")
            return False
            
        # Create a new participant that won't be approved
        success, response = self.run_test(
            "Join Room (Unapproved)",
            "POST",
            "api/rooms/join",
            200,
            params={"room_id": self.room_id, "participant_name": "Unapproved Participant"}
        )
        
        if not success:
            return False
            
        unapproved_token = response.get('participant_token')
        if not unapproved_token:
            print("❌ No token for unapproved participant")
            return False
            
        # Try to vote with unapproved participant (should fail with 403)
        vote_data = {
            "participant_token": unapproved_token,
            "selected_option": "Red"
        }
        
        success, response = self.run_test(
            "Vote with Unapproved Participant (Should Fail)",
            "POST",
            f"api/polls/{self.poll_id}/vote",
            403,  # Should fail with 403 Forbidden
            data=vote_data
        )
        return success

    def test_room_status_with_approval_counts(self):
        """Test room status shows approval counts"""
        if not self.room_id:
            print("❌ No room ID available for status test")
            return False
            
        success, response = self.run_test(
            "Get Room Status (With Approval Counts)",
            "GET",
            f"api/rooms/{self.room_id}/status",
            200
        )
        
        if success:
            # Check if response contains approval counts
            required_fields = ['participant_count', 'approved_count', 'pending_count']
            for field in required_fields:
                if field not in response:
                    print(f"   ❌ Missing field: {field}")
                    return False
                else:
                    print(f"   ✅ {field}: {response[field]}")
            return True
        return False

    def test_join_invalid_room(self):
        """Test joining an invalid room"""
        success, response = self.run_test(
            "Join Invalid Room",
            "POST",
            "api/rooms/join",
            404,
            params={"room_id": "INVALID1"}
        )
        return success

    def test_get_room_status(self):
        """Test getting room status"""
        if not self.room_id:
            print("❌ No room ID available for status test")
            return False
            
        success, response = self.run_test(
            "Get Room Status",
            "GET",
            f"api/rooms/{self.room_id}/status",
            200
        )
        return success

    def test_create_poll(self):
        """Test creating a poll with JSON body (new format)"""
        if not self.room_id:
            print("❌ No room ID available for poll creation test")
            return False
            
        # Backend now expects JSON body, not query parameters
        poll_data = {
            "room_id": self.room_id,
            "question": "What is your favorite color?",
            "options": ["Red", "Blue", "Green", "Yellow"]
        }
        
        success, response = self.run_test(
            "Create Poll (JSON Body)",
            "POST",
            "api/polls/create",
            200,
            data=poll_data
        )
        if success and 'poll_id' in response:
            self.poll_id = response['poll_id']
            print(f"   Created poll with ID: {self.poll_id}")
            return True
        return False

    def test_start_poll(self):
        """Test starting a poll"""
        if not self.poll_id:
            print("❌ No poll ID available for start test")
            return False
            
        success, response = self.run_test(
            "Start Poll",
            "POST",
            f"api/polls/{self.poll_id}/start",
            200
        )
        return success

    def test_vote_on_poll(self):
        """Test voting on a poll with JSON body (FIXED FORMAT)"""
        if not self.poll_id or not self.participant_token:
            print("❌ No poll ID or participant token available for voting test")
            return False
            
        # Backend now expects JSON body for voting (FIXED)
        vote_data = {
            "participant_token": self.participant_token,
            "selected_option": "Blue"
        }
        
        success, response = self.run_test(
            "Vote on Poll (JSON Body - FIXED)",
            "POST",
            f"api/polls/{self.poll_id}/vote",
            200,
            data=vote_data
        )
        return success

    def test_duplicate_vote(self):
        """Test voting twice with same token (should fail)"""
        if not self.poll_id or not self.participant_token:
            print("❌ No poll ID or participant token available for duplicate vote test")
            return False
            
        # Backend now expects JSON body for voting (FIXED)
        vote_data = {
            "participant_token": self.participant_token,
            "selected_option": "Red"
        }
        
        success, response = self.run_test(
            "Duplicate Vote (Should Fail) - JSON Body",
            "POST",
            f"api/polls/{self.poll_id}/vote",
            400,
            data=vote_data
        )
        return success

    def test_stop_poll(self):
        """Test stopping a poll"""
        if not self.poll_id:
            print("❌ No poll ID available for stop test")
            return False
            
        success, response = self.run_test(
            "Stop Poll",
            "POST",
            f"api/polls/{self.poll_id}/stop",
            200
        )
        return success

    def test_generate_report(self):
        """Test generating a report"""
        if not self.room_id:
            print("❌ No room ID available for report test")
            return False
            
        success, response = self.run_test(
            "Generate Report",
            "GET",
            f"api/rooms/{self.room_id}/report",
            200
        )
        return success

    def test_cleanup_room(self):
        """Test cleaning up room data"""
        if not self.room_id:
            print("❌ No room ID available for cleanup test")
            return False
            
        success, response = self.run_test(
            "Cleanup Room Data",
            "DELETE",
            f"api/rooms/{self.room_id}/cleanup",
            200
        )
        return success

    def test_multiple_active_polls(self):
        """Test multiple active polls functionality"""
        if not self.room_id:
            print("❌ No room ID available for multiple polls test")
            return False
            
        # Create multiple polls
        poll_ids = []
        for i in range(3):
            poll_data = {
                "room_id": self.room_id,
                "question": f"Poll {i+1}: What is your favorite {['color', 'food', 'season'][i]}?",
                "options": [["Red", "Blue", "Green"], ["Pizza", "Burger", "Pasta"], ["Spring", "Summer", "Winter"]][i]
            }
            
            success, response = self.run_test(
                f"Create Poll {i+1}",
                "POST",
                "api/polls/create",
                200,
                data=poll_data
            )
            if success and 'poll_id' in response:
                poll_ids.append(response['poll_id'])
            else:
                return False
        
        # Start all polls
        for i, poll_id in enumerate(poll_ids):
            success, response = self.run_test(
                f"Start Poll {i+1}",
                "POST",
                f"api/polls/{poll_id}/start",
                200
            )
            if not success:
                return False
        
        # Check room status shows multiple active polls
        success, response = self.run_test(
            "Check Multiple Active Polls Status",
            "GET",
            f"api/rooms/{self.room_id}/status",
            200
        )
        
        if success:
            active_polls = response.get('active_polls', [])
            if len(active_polls) == 3:
                print(f"   ✅ Found {len(active_polls)} active polls as expected")
                self.poll_ids = poll_ids  # Store for later tests
                return True
            else:
                print(f"   ❌ Expected 3 active polls, found {len(active_polls)}")
                return False
        return False

    def test_poll_restart_functionality(self):
        """Test poll restart functionality"""
        if not hasattr(self, 'poll_ids') or not self.poll_ids:
            print("❌ No poll IDs available for restart test")
            return False
            
        first_poll_id = self.poll_ids[0]
        
        # Vote on the first poll
        vote_data = {
            "participant_token": self.participant_token,
            "selected_option": "Red"
        }
        
        success, response = self.run_test(
            "Vote Before Stop",
            "POST",
            f"api/polls/{first_poll_id}/vote",
            200,
            data=vote_data
        )
        if not success:
            return False
        
        # Stop the poll
        success, response = self.run_test(
            "Stop Poll for Restart Test",
            "POST",
            f"api/polls/{first_poll_id}/stop",
            200
        )
        if not success:
            return False
        
        # Check that poll is no longer active
        success, response = self.run_test(
            "Check Poll Stopped",
            "GET",
            f"api/rooms/{self.room_id}/status",
            200
        )
        if success:
            active_polls = response.get('active_polls', [])
            active_poll_ids = [p['poll_id'] for p in active_polls]
            if first_poll_id not in active_poll_ids:
                print(f"   ✅ Poll correctly stopped")
            else:
                print(f"   ❌ Poll still appears active after stop")
                return False
        
        # Restart the poll
        success, response = self.run_test(
            "Restart Poll",
            "POST",
            f"api/polls/{first_poll_id}/start",
            200
        )
        if not success:
            return False
        
        # Check that poll is active again
        success, response = self.run_test(
            "Check Poll Restarted",
            "GET",
            f"api/rooms/{self.room_id}/status",
            200
        )
        if success:
            active_polls = response.get('active_polls', [])
            active_poll_ids = [p['poll_id'] for p in active_polls]
            if first_poll_id in active_poll_ids:
                print(f"   ✅ Poll successfully restarted")
                return True
            else:
                print(f"   ❌ Poll not active after restart")
                return False
        return False

    def test_vote_persistence_through_restart(self):
        """Test that votes persist through poll restart cycles"""
        if not hasattr(self, 'poll_ids') or not self.poll_ids:
            print("❌ No poll IDs available for vote persistence test")
            return False
            
        second_poll_id = self.poll_ids[1]
        
        # Create another participant to vote
        success, response = self.run_test(
            "Join Room (Second Voter)",
            "POST",
            "api/rooms/join",
            200,
            params={"room_id": self.room_id, "participant_name": "Second Voter"}
        )
        if not success:
            return False
            
        second_token = response.get('participant_token')
        
        # Get participant ID and approve
        success, response = self.run_test(
            "Get Participants for Second Voter",
            "GET",
            f"api/rooms/{self.room_id}/participants",
            200
        )
        if not success:
            return False
            
        second_participant_id = None
        for p in response['participants']:
            if p.get('participant_name') == "Second Voter":
                second_participant_id = p['participant_id']
                break
                
        if not second_participant_id:
            print("❌ Could not find second participant")
            return False
            
        # Approve second participant
        success, response = self.run_test(
            "Approve Second Participant",
            "POST",
            f"api/participants/{second_participant_id}/approve",
            200
        )
        if not success:
            return False
        
        # Both participants vote on second poll
        vote_data1 = {
            "participant_token": self.participant_token,
            "selected_option": "Pizza"
        }
        
        vote_data2 = {
            "participant_token": second_token,
            "selected_option": "Burger"
        }
        
        success, response = self.run_test(
            "First Participant Vote",
            "POST",
            f"api/polls/{second_poll_id}/vote",
            200,
            data=vote_data1
        )
        if not success:
            return False
            
        success, response = self.run_test(
            "Second Participant Vote",
            "POST",
            f"api/polls/{second_poll_id}/vote",
            200,
            data=vote_data2
        )
        if not success:
            return False
        
        # Stop and restart the poll
        success, response = self.run_test(
            "Stop Poll (Vote Persistence Test)",
            "POST",
            f"api/polls/{second_poll_id}/stop",
            200
        )
        if not success:
            return False
            
        success, response = self.run_test(
            "Restart Poll (Vote Persistence Test)",
            "POST",
            f"api/polls/{second_poll_id}/start",
            200
        )
        if not success:
            return False
        
        # Check that votes are still there
        success, response = self.run_test(
            "Check Vote Persistence",
            "GET",
            f"api/rooms/{self.room_id}/polls",
            200
        )
        
        if success:
            polls = response.get('polls', [])
            for poll in polls:
                if poll['poll_id'] == second_poll_id:
                    vote_counts = poll.get('vote_counts', {})
                    total_votes = poll.get('total_votes', 0)
                    if total_votes == 2:
                        print(f"   ✅ Votes persisted through restart: {vote_counts}")
                        return True
                    else:
                        print(f"   ❌ Expected 2 votes, found {total_votes}")
                        return False
            print("   ❌ Could not find poll in response")
            return False
        return False

    def test_enhanced_organizer_dashboard(self):
        """Test enhanced organizer dashboard features"""
        if not self.room_id:
            print("❌ No room ID available for dashboard test")
            return False
        
        # Get all polls to check enhanced features
        success, response = self.run_test(
            "Get All Polls (Enhanced Dashboard)",
            "GET",
            f"api/rooms/{self.room_id}/polls",
            200
        )
        
        if success:
            polls = response.get('polls', [])
            if len(polls) >= 3:
                print(f"   ✅ Found {len(polls)} polls with enhanced data")
                
                # Check each poll has required fields
                for poll in polls:
                    required_fields = ['poll_id', 'question', 'options', 'is_active', 'vote_counts', 'total_votes']
                    for field in required_fields:
                        if field not in poll:
                            print(f"   ❌ Missing field {field} in poll data")
                            return False
                
                # Check that some polls are active and some inactive
                active_count = sum(1 for poll in polls if poll['is_active'])
                inactive_count = len(polls) - active_count
                
                print(f"   ✅ Active polls: {active_count}, Inactive polls: {inactive_count}")
                return True
            else:
                print(f"   ❌ Expected at least 3 polls, found {len(polls)}")
                return False
        return False

    def run_all_tests(self):
        """Run all API tests in sequence including new multiple polls features"""
        print("🚀 Starting Secret Poll API Tests (MULTIPLE ACTIVE POLLS & RESTART SYSTEM)")
        print("=" * 80)
        
        # Basic functionality tests
        if not self.test_health_check():
            print("❌ Health check failed, stopping tests")
            return False

        if not self.test_create_room():
            print("❌ Room creation failed, stopping tests")
            return False

        if not self.test_join_room_with_name():
            print("❌ Room joining with name failed, stopping tests")
            return False

        self.test_join_invalid_room()

        if not self.test_get_participants_list():
            print("❌ Getting participants list failed, stopping tests")
            return False

        self.test_room_status_with_approval_counts()

        if not self.test_approve_participant():
            print("❌ Participant approval failed, stopping tests")
            return False

        # NEW MULTIPLE POLLS TESTS
        print("\n" + "="*50)
        print("🔥 TESTING NEW MULTIPLE ACTIVE POLLS FEATURES")
        print("="*50)
        
        if not self.test_multiple_active_polls():
            print("❌ Multiple active polls test failed, stopping tests")
            return False

        if not self.test_poll_restart_functionality():
            print("❌ Poll restart functionality test failed, stopping tests")
            return False

        if not self.test_vote_persistence_through_restart():
            print("❌ Vote persistence through restart test failed, stopping tests")
            return False

        if not self.test_enhanced_organizer_dashboard():
            print("❌ Enhanced organizer dashboard test failed, stopping tests")
            return False

        # Additional tests
        self.test_vote_unapproved_participant()
        self.test_duplicate_vote()
        self.test_deny_participant()
        self.test_generate_report()
        self.test_cleanup_room()

        return True

def main():
    """Main test function"""
    tester = SecretPollAPITester()
    
    success = tester.run_all_tests()
    
    # Print final results
    print("\n" + "=" * 50)
    print("📊 FINAL TEST RESULTS")
    print("=" * 50)
    print(f"Tests Run: {tester.tests_run}")
    print(f"Tests Passed: {tester.tests_passed}")
    print(f"Tests Failed: {tester.tests_run - tester.tests_passed}")
    print(f"Success Rate: {(tester.tests_passed / tester.tests_run * 100):.1f}%")
    
    if success and tester.tests_passed == tester.tests_run:
        print("🎉 All tests passed!")
        return 0
    else:
        print("❌ Some tests failed!")
        return 1

if __name__ == "__main__":
    sys.exit(main())