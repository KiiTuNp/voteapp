#!/usr/bin/env python3
"""
Test script for the Secret Poll installation script
"""

import os
import sys
import subprocess
import tempfile
import shutil
from pathlib import Path

def test_installation_script():
    """Test the installation script for syntax and basic functionality"""
    print("🧪 Testing Secret Poll Installation Script")
    print("=" * 50)
    
    script_path = Path(__file__).parent / "install.py"
    
    # Test 1: Check if install.py exists
    if script_path.exists():
        print("✅ install.py exists")
    else:
        print("❌ install.py not found")
        return False
    
    # Test 2: Check if script is executable
    if os.access(script_path, os.X_OK):
        print("✅ install.py is executable")
    else:
        print("❌ install.py is not executable")
        return False
    
    # Test 3: Check Python syntax
    try:
        result = subprocess.run([
            sys.executable, "-m", "py_compile", str(script_path)
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ Python syntax is valid")
        else:
            print("❌ Python syntax errors:")
            print(result.stderr)
            return False
    except Exception as e:
        print(f"❌ Error checking syntax: {e}")
        return False
    
    # Test 4: Test import (without running)
    try:
        # Create a temporary test file to check imports
        test_import = """
import sys
sys.path.insert(0, '{}')
from install import SecretPollInstaller, Colors
print("Imports successful")
        """.format(script_path.parent)
        
        result = subprocess.run([
            sys.executable, "-c", test_import
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ All imports successful")
        else:
            print("❌ Import errors:")
            print(result.stderr)
            return False
    except Exception as e:
        print(f"❌ Error testing imports: {e}")
        return False
    
    # Test 5: Check required methods exist
    try:
        from install import SecretPollInstaller
        installer = SecretPollInstaller()
        
        required_methods = [
            'check_root', 'check_system_requirements', 'collect_configuration',
            'install_system_dependencies', 'setup_application', 'configure_web_server',
            'setup_ssl', 'create_systemd_service', 'verify_installation'
        ]
        
        for method in required_methods:
            if hasattr(installer, method):
                print(f"✅ Method {method} exists")
            else:
                print(f"❌ Method {method} missing")
                return False
                
    except Exception as e:
        print(f"❌ Error checking methods: {e}")
        return False
    
    # Test 6: Check README.md is properly updated
    readme_path = Path(__file__).parent / "README.md"
    if readme_path.exists():
        with open(readme_path, 'r') as f:
            content = f.read()
            if "sudo python3 install.py" in content:
                print("✅ README.md updated with installation command")
            else:
                print("❌ README.md not updated properly")
                return False
    else:
        print("❌ README.md not found")
        return False
    
    print("\n🎉 All tests passed! Installation script is ready.")
    return True

def check_required_files():
    """Check if all required files are present"""
    print("\n📁 Checking required files:")
    
    required_files = [
        "install.py",
        "README.md", 
        "backend/server.py",
        "backend/requirements.txt",
        "frontend/package.json",
        "frontend/src/App.js"
    ]
    
    missing_files = []
    base_path = Path(__file__).parent
    
    for file_path in required_files:
        full_path = base_path / file_path
        if full_path.exists():
            print(f"✅ {file_path}")
        else:
            print(f"❌ {file_path} MISSING")
            missing_files.append(file_path)
    
    if missing_files:
        print(f"\n❌ {len(missing_files)} file(s) missing:")
        for file in missing_files:
            print(f"   - {file}")
        return False
    else:
        print("\n✅ All required files present")
        return True

def show_installation_instructions():
    """Show installation instructions for users"""
    print("\n" + "=" * 50)
    print("🚀 INSTALLATION INSTRUCTIONS")
    print("=" * 50)
    print("""
To install Secret Poll on your server:

1. Clone the repository:
   git clone https://github.com/KiiTuNp/voteapp.git
   cd voteapp

2. Run the installation script:
   sudo python3 install.py

3. Follow the interactive prompts to configure:
   - Domain/IP address
   - SSL certificate setup
   - Web server choice (Nginx/Apache)
   - Installation directory

The script will automatically:
✅ Install all dependencies
✅ Configure web server
✅ Setup SSL certificates
✅ Create systemd services
✅ Configure automatic startup

After installation, access your app at:
https://yourdomain.com (or http://your-ip/)
""")

def main():
    """Main test function"""
    print("🔍 Secret Poll Installation Script Validation")
    print("=" * 60)
    
    # Run tests
    files_ok = check_required_files()
    script_ok = test_installation_script()
    
    print("\n" + "=" * 60)
    print("📊 VALIDATION RESULTS")
    print("=" * 60)
    
    if files_ok and script_ok:
        print("✅ ALL TESTS PASSED")
        print("🎉 Installation script is ready for production use!")
        
        show_installation_instructions()
        
        print("\n🎯 Status: READY FOR DEPLOYMENT")
        return True
    else:
        print("❌ SOME TESTS FAILED")
        print("⚠️  Please fix the issues above before deployment")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)