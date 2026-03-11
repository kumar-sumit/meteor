#!/usr/bin/env python3
"""
METEOR PIPELINE CORRECTNESS TEST (Python Version)
Tests SET/GET operations in pipeline mode with cross-shard validation
More robust RESP protocol parsing than bash version
"""

import socket
import time
import hashlib
import sys
import argparse
from typing import List, Tuple, Dict

class RESPClient:
    def __init__(self, host: str, port: int, timeout: int = 5):
        self.host = host
        self.port = port 
        self.timeout = timeout
        self.sock = None
    
    def connect(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(self.timeout)
            self.sock.connect((self.host, self.port))
            return True
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False
    
    def disconnect(self):
        if self.sock:
            self.sock.close()
            self.sock = None
    
    def send_pipeline(self, commands: List[str]) -> List[str]:
        """Send multiple RESP commands in a pipeline and parse responses"""
        if not self.sock:
            if not self.connect():
                return []
        
        # Build pipeline payload
        payload = "".join(commands)
        
        try:
            # Send all commands at once
            self.sock.sendall(payload.encode())
            
            # Read all responses
            responses = []
            response_data = b""
            
            # Read with timeout (expecting multiple responses)
            start_time = time.time()
            while time.time() - start_time < self.timeout:
                try:
                    chunk = self.sock.recv(8192)
                    if not chunk:
                        break
                    response_data += chunk
                    
                    # Try to parse complete responses
                    temp_responses = self._parse_resp_responses(response_data)
                    if len(temp_responses) >= len(commands):
                        responses = temp_responses[:len(commands)]
                        break
                        
                except socket.timeout:
                    break
            
            return responses
            
        except Exception as e:
            print(f"❌ Pipeline send failed: {e}")
            return []
    
    def _parse_resp_responses(self, data: bytes) -> List[str]:
        """Parse RESP protocol responses from raw data"""
        responses = []
        lines = data.decode('utf-8', errors='ignore').split('\r\n')
        i = 0
        
        while i < len(lines):
            line = lines[i]
            
            if line.startswith('+'):
                # Simple string (e.g., +OK)
                responses.append(line[1:])
                i += 1
            elif line.startswith('-'):
                # Error (e.g., -ERR)
                responses.append(f"ERROR: {line[1:]}")
                i += 1
            elif line.startswith(':'):
                # Integer
                responses.append(line[1:])
                i += 1
            elif line.startswith('$'):
                # Bulk string
                try:
                    length = int(line[1:])
                    if length == -1:
                        responses.append(None)  # Null response
                        i += 1
                    else:
                        i += 1
                        if i < len(lines):
                            responses.append(lines[i][:length])
                            i += 1
                        else:
                            break
                except ValueError:
                    i += 1
            else:
                i += 1
        
        return responses

def generate_cross_shard_keys(num_keys: int) -> List[Tuple[str, str]]:
    """Generate keys that will distribute across different shards"""
    keys_values = []
    
    for i in range(num_keys):
        # Use different prefixes to ensure cross-shard distribution
        shard_prefix = i % 6  # 6 shards in super_optimized
        timestamp = int(time.time() * 1000000) + i
        
        key = f"shard{shard_prefix}_test_{i}_{timestamp}"
        value = f"value_{i}_{hashlib.md5(str(i).encode()).hexdigest()[:16]}"
        
        keys_values.append((key, value))
    
    return keys_values

def build_set_pipeline(keys_values: List[Tuple[str, str]]) -> List[str]:
    """Build SET commands in RESP format for pipeline"""
    commands = []
    
    for key, value in keys_values:
        # *3\r\n$3\r\nSET\r\n$keylen\r\nkey\r\n$vallen\r\nvalue\r\n
        cmd = f"*3\r\n$3\r\nSET\r\n${len(key)}\r\n{key}\r\n${len(value)}\r\n{value}\r\n"
        commands.append(cmd)
    
    return commands

def build_get_pipeline(keys: List[str]) -> List[str]:
    """Build GET commands in RESP format for pipeline"""
    commands = []
    
    for key in keys:
        # *2\r\n$3\r\nGET\r\n$keylen\r\nkey\r\n  
        cmd = f"*2\r\n$3\r\nGET\r\n${len(key)}\r\n{key}\r\n"
        commands.append(cmd)
    
    return commands

def analyze_shard_distribution(keys: List[str]) -> Dict[int, int]:
    """Analyze how keys distribute across shards (simulation)"""
    shard_counts = {i: 0 for i in range(6)}  # 6 shards in super_optimized
    
    for key in keys:
        # Simulate hash function (not exact, but gives distribution idea)
        key_hash = hash(key) % 2**32  # Simulate std::hash<string>
        shard = key_hash % 6
        shard_counts[shard] += 1
    
    return shard_counts

def main():
    parser = argparse.ArgumentParser(description='Meteor Pipeline Correctness Test')
    parser.add_argument('--host', default='127.0.0.1', help='Server host')
    parser.add_argument('--port', type=int, default=6379, help='Server port')
    parser.add_argument('--keys', type=int, default=100, help='Number of keys to test')
    parser.add_argument('--timeout', type=int, default=10, help='Timeout in seconds')
    
    args = parser.parse_args()
    
    print("🚀 METEOR PIPELINE CORRECTNESS TEST (Python)")
    print(f"   Host: {args.host}")
    print(f"   Port: {args.port}")
    print(f"   Keys: {args.keys}")
    print(f"   Timeout: {args.timeout}s")
    print("")
    
    # Generate test data
    print("📝 Generating cross-shard test data...")
    keys_values = generate_cross_shard_keys(args.keys)
    keys = [kv[0] for kv in keys_values]
    expected_values = {kv[0]: kv[1] for kv in keys_values}
    
    # Analyze shard distribution
    shard_dist = analyze_shard_distribution(keys)
    print("   Key distribution across shards (estimated):")
    for shard, count in shard_dist.items():
        print(f"     Shard {shard}: {count} keys")
    print("")
    
    # Initialize client
    client = RESPClient(args.host, args.port, args.timeout)
    
    try:
        # Test 1: Pipeline SET commands
        print("🔧 TEST 1: Pipeline SET commands")
        print(f"   Sending {args.keys} SET commands in single pipeline...")
        
        set_commands = build_set_pipeline(keys_values)
        set_responses = client.send_pipeline(set_commands)
        
        set_success = sum(1 for resp in set_responses if resp == 'OK')
        print(f"   ✅ SET responses: {set_success}/{args.keys} successful")
        
        if set_success != args.keys:
            print(f"   ❌ ERROR: Expected {args.keys} OK responses, got {set_success}")
            print("   Response sample:", set_responses[:5])
            return 1
        
        # Wait for cross-shard propagation
        print("   ⏳ Waiting for cross-shard propagation...")
        time.sleep(2)
        
        # Test 2: Pipeline GET commands
        print("")
        print("🔍 TEST 2: Pipeline GET commands")
        print(f"   Sending {args.keys} GET commands in single pipeline...")
        
        get_commands = build_get_pipeline(keys)
        get_responses = client.send_pipeline(get_commands)
        
        print(f"   📨 Received {len(get_responses)} responses")
        
        # Validate responses
        correct_responses = 0
        wrong_responses = 0
        missing_responses = 0
        
        for i, key in enumerate(keys):
            expected_value = expected_values[key]
            
            if i < len(get_responses):
                actual_value = get_responses[i]
                
                if actual_value is None:
                    print(f"   ❌ Key {key[:20]}...: Missing (null response)")
                    missing_responses += 1
                elif actual_value == expected_value:
                    correct_responses += 1
                    if i % 20 == 0:  # Show progress every 20 keys
                        print(f"   ✅ Key {key[:20]}...: Correct")
                else:
                    print(f"   ❌ Key {key[:20]}...: Wrong value")
                    print(f"      Expected: {expected_value[:30]}...")
                    print(f"      Got:      {actual_value[:30] if actual_value else 'None'}...")
                    wrong_responses += 1
            else:
                print(f"   ❌ Key {key[:20]}...: No response received")
                missing_responses += 1
        
        # Test 3: Results analysis
        print("")
        print("📊 FINAL RESULTS:")
        print(f"   ✅ Correct responses: {correct_responses}")
        print(f"   ❌ Wrong responses:   {wrong_responses}")
        print(f"   🔍 Missing responses: {missing_responses}")
        print(f"   📈 Success rate:      {correct_responses * 100 // args.keys}%")
        print("")
        
        # Determine test result
        if correct_responses == args.keys:
            print("🎉 SUCCESS: Pipeline correctness test PASSED!")
            print(f"   All {args.keys} keys correctly SET and GET in pipeline mode")
            print("   Cross-shard operations working properly")
            return 0
        elif correct_responses > (args.keys * 80 // 100):
            print("⚠️  WARNING: Pipeline correctness test MOSTLY PASSED")
            print(f"   {correct_responses}/{args.keys} responses correct (>80%)")
            print("   Some cross-shard operations may have issues")
            return 1
        else:
            print("❌ FAILURE: Pipeline correctness test FAILED")
            print(f"   Only {correct_responses}/{args.keys} responses correct (<80%)")
            print("   Pipeline cross-shard routing is broken")
            return 2
    
    finally:
        client.disconnect()

if __name__ == "__main__":
    sys.exit(main())













