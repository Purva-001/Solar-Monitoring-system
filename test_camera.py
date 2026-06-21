#!/usr/bin/env python3
"""
Test script to verify ESP32 camera connectivity
"""
import requests
import sys
from pathlib import Path

def test_camera_connection():
    """Test if the ESP32 camera is reachable"""
    
    camera_url = "http://10.70.187.244/capture"
    print("=" * 60)
    print(f"\nTesting camera at: {camera_url}")
    print("-" * 60)
    
    # Test 1: Basic connectivity
    print("\n[Test 1] Basic connectivity...")
    try:
        response = requests.get(camera_url, timeout=5)
        print(f"✓ Connected! Status: {response.status_code}")
    except requests.exceptions.ConnectTimeout:
        print("✗ Connection timeout - Camera not responding")
        print("  - Check if camera is powered on")
        print("  - Check if camera is connected to network")
        print("  - Check IP address is correct (10.70.187.244)")
        return False
    except requests.exceptions.ConnectionError as e:
        print(f"✗ Connection error: {e}")
        print("  - Camera may be offline or IP is incorrect")
        return False
    except Exception as e:
        print(f"✗ Unexpected error: {e}")
        return False
    
    # Test 2: Image data
    print("\n[Test 2] Image data...")
    try:
        response = requests.get(camera_url, timeout=5)
        if response.status_code == 200:
            content_length = len(response.content)
            content_type = response.headers.get('Content-Type', 'Unknown')
            print(f"✓ Received image data")
            print(f"  - Content-Type: {content_type}")
            print(f"  - Size: {content_length} bytes")
            
            # Check if it looks like JPEG
            if response.content[:2] == b'\xff\xd8':
                print(f"  - Format: Valid JPEG ✓")
            else:
                print(f"  - Format: Possibly invalid (not JPEG)")
                return False
        else:
            print(f"✗ Invalid status code: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Failed to get image: {e}")
        return False
    
    # Test 3: Save image
    print("\n[Test 3] Saving test image...")
    try:
        response = requests.get(camera_url, timeout=5)
        test_image_path = Path(__file__).parent / "test_camera_image.jpg"
        test_image_path.write_bytes(response.content)
        print(f"✓ Test image saved to: {test_image_path}")
    except Exception as e:
        print(f"✗ Failed to save image: {e}")
        return False
    
    print("\n" + "=" * 60)
    print("✓ ALL TESTS PASSED - Camera is working correctly!")
    print("=" * 60)
    return True

if __name__ == "__main__":
    try:
        success = test_camera_connection()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        sys.exit(1)
