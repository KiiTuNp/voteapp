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
        self.participant_token = None
        self.participant_id = None
        self.participant_name = None
        self.poll_id = None

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

    def test_create_poll_with_custom_request(self):
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

    def run_all_tests(self):
        """Run all API tests in sequence"""
        print("🚀 Starting Secret Poll API Tests")
        print("=" * 50)
        
        # Test 1: Health check
        if not self.test_health_check():
            print("❌ Health check failed, stopping tests")
            return False

        # Test 2: Create room
        if not self.test_create_room():
            print("❌ Room creation failed, stopping tests")
            return False

        # Test 3: Join room
        if not self.test_join_room():
            print("❌ Room joining failed, stopping tests")
            return False

        # Test 4: Try joining invalid room
        self.test_join_invalid_room()

        # Test 5: Get room status
        self.test_get_room_status()

        # Test 6: Create poll (using new JSON format)
        if not self.test_create_poll():
            print("❌ Poll creation failed, stopping tests")
            return False

        # Test 7: Start poll
        if not self.test_start_poll():
            print("❌ Poll start failed, stopping tests")
            return False

        # Test 8: Vote on poll
        if not self.test_vote_on_poll():
            print("❌ Voting failed, stopping tests")
            return False

        # Test 9: Try duplicate vote (should fail)
        self.test_duplicate_vote()

        # Test 10: Stop poll
        self.test_stop_poll()

        # Test 11: Generate report
        self.test_generate_report()

        # Test 12: Cleanup room data
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