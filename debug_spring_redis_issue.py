#!/usr/bin/env python3

import socket
import time

def send_redis_command(sock, command):
    sock.send(command.encode())
    response = sock.recv(4096)
    return response.decode()

def test_meteor_get_responses():
    print("🧪 TESTING GET COMMAND RESPONSES FROM METEOR SERVER")
    print("=" * 50)
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect(('127.0.0.1', 6379))
        
        # Test 1: GET non-existent key (should return $-1\r\n)
        print("\n📋 Test 1: GET non-existent key")
        response = send_redis_command(sock, "*2\r\n$3\r\nGET\r\n$13\r\nnonexistent-key\r\n")
        print(f"Response: {repr(response)}")
        
        # Test 2: SET then GET (should return the value)
        print("\n📋 Test 2: SET then GET")
        set_response = send_redis_command(sock, "*3\r\n$3\r\nSET\r\n$8\r\ntestkey1\r\n$9\r\ntestvalue\r\n")
        print(f"SET Response: {repr(set_response)}")
        
        get_response = send_redis_command(sock, "*2\r\n$3\r\nGET\r\n$8\r\ntestkey1\r\n")
        print(f"GET Response: {repr(get_response)}")
        
        # Test 3: SET with "OK" as value, then GET
        print("\n📋 Test 3: SET with 'OK' as value, then GET")
        set_response = send_redis_command(sock, "*3\r\n$3\r\nSET\r\n$8\r\ntestkey2\r\n$2\r\nOK\r\n")
        print(f"SET Response: {repr(set_response)}")
        
        get_response = send_redis_command(sock, "*2\r\n$3\r\nGET\r\n$8\r\ntestkey2\r\n")
        print(f"GET Response: {repr(get_response)}")
        
        # Test 4: SET JSON-like value, then GET
        print("\n📋 Test 4: SET JSON value, then GET")
        json_value = '{"test": "value"}'
        set_cmd = f"*3\r\n$3\r\nSET\r\n$8\r\ntestkey3\r\n${len(json_value)}\r\n{json_value}\r\n"
        set_response = send_redis_command(sock, set_cmd)
        print(f"SET Response: {repr(set_response)}")
        
        get_response = send_redis_command(sock, "*2\r\n$3\r\nGET\r\n$8\r\ntestkey3\r\n")
        print(f"GET Response: {repr(get_response)}")
        
        sock.close()
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test_meteor_get_responses()
