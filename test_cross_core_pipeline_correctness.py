#!/usr/bin/env python3

"""
CROSS-CORE PIPELINE CORRECTNESS TEST
====================================

Tests the temporal coherence system to ensure that:
1. Commands in a pipeline are correctly routed to different cores based on key hash
2. Temporal ordering is maintained across cores
3. Pipeline results are returned in the correct order
4. No commands are lost or duplicated

This validates the core functionality that was broken in the baseline.
"""

import socket
import time
import hashlib
import threading
import queue
import argparse
from typing import List, Tuple, Dict
import json

class RedisProtocol:
    """Simple Redis protocol encoder/decoder"""
    
    @staticmethod
    def encode_command(command: List[str]) -> bytes:
        """Encode command to RESP format"""
        resp = f"*{len(command)}\r\n"
        for arg in command:
            resp += f"${len(arg)}\r\n{arg}\r\n"
        return resp.encode('utf-8')
    
    @staticmethod
    def encode_pipeline(commands: List[List[str]]) -> bytes:
        """Encode multiple commands to RESP format"""
        pipeline = b""
        for command in commands:
            pipeline += RedisProtocol.encode_command(command)
        return pipeline
    
    @staticmethod
    def decode_response(data: bytes) -> List[str]:
        """Decode RESP response (simplified)"""
        responses = []
        lines = data.decode('utf-8').split('\r\n')
        
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if not line:
                i += 1
                continue
                
            if line.startswith('+'):
                responses.append(line[1:])
            elif line.startswith('-'):
                responses.append(f"ERROR: {line[1:]}")
            elif line.startswith(':'):
                responses.append(line[1:])
            elif line.startswith('$'):
                length = int(line[1:])
                if length >= 0 and i + 1 < len(lines):
                    responses.append(lines[i + 1])
                    i += 1
                else:
                    responses.append("NULL")
            
            i += 1
        
        return responses

class CrossCorePipelineTest:
    """Test cross-core pipeline correctness"""
    
    def __init__(self, host='127.0.0.1', base_port=6379, num_cores=4, num_shards=16):
        self.host = host
        self.base_port = base_port
        self.num_cores = num_cores
        self.num_shards = num_shards
        self.results = {}
        self.errors = []
    
    def calculate_target_core(self, key: str) -> int:
        """Calculate which core a key should route to (matches server logic)"""
        # Hash the key and determine shard
        key_hash = hash(key) % (2**32)  # Ensure positive
        shard_id = key_hash % self.num_shards
        target_core = shard_id % self.num_cores
        return target_core
    
    def connect_to_core(self, core_id: int) -> socket.socket:
        """Connect to a specific core"""
        port = self.base_port + core_id
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5.0)
        try:
            sock.connect((self.host, port))
            return sock
        except Exception as e:
            raise ConnectionError(f"Failed to connect to core {core_id} on port {port}: {e}")
    
    def send_command(self, sock: socket.socket, command: List[str]) -> List[str]:
        """Send a single command and get response"""
        request = RedisProtocol.encode_command(command)
        sock.send(request)
        
        response = sock.recv(4096)
        return RedisProtocol.decode_response(response)
    
    def send_pipeline(self, sock: socket.socket, commands: List[List[str]]) -> List[str]:
        """Send a pipeline and get all responses"""
        request = RedisProtocol.encode_pipeline(commands)
        sock.send(request)
        
        # Receive response (may need multiple reads for large pipelines)
        response = b""
        expected_responses = len(commands)
        received_responses = 0
        
        while received_responses < expected_responses:
            data = sock.recv(4096)
            if not data:
                break
            response += data
            # Count responses (simplified)
            received_responses = response.count(b'\r\n') // 2
        
        return RedisProtocol.decode_response(response)
    
    def test_single_core_pipeline(self) -> Dict:
        """Test pipeline where all commands go to the same core"""
        print("🔍 Testing single-core pipeline (all commands to same core)...")
        
        # Generate keys that all hash to core 0
        target_core = 0
        keys = []
        
        for i in range(100):  # Try up to 100 keys to find 5 that hash to core 0
            key = f"single_core_test_{i}_{time.time_ns()}"
            if self.calculate_target_core(key) == target_core:
                keys.append(key)
                if len(keys) >= 5:
                    break
        
        if len(keys) < 5:
            return {"success": False, "error": f"Could not find 5 keys for core {target_core}"}
        
        # Create pipeline commands
        commands = []
        expected_values = {}
        
        for i, key in enumerate(keys):
            value = f"value_{i}_{time.time_ns()}"
            commands.append(["SET", key, value])
            expected_values[key] = value
        
        # Add GET commands
        for key in keys:
            commands.append(["GET", key])
        
        try:
            # Send pipeline to core 0
            sock = self.connect_to_core(target_core)
            responses = self.send_pipeline(sock, commands)
            sock.close()
            
            # Validate responses
            success_count = 0
            errors = []
            
            # First half should be SET responses (OK)
            for i in range(len(keys)):
                if i < len(responses) and responses[i] == "OK":
                    success_count += 1
                else:
                    errors.append(f"SET {keys[i]} failed: {responses[i] if i < len(responses) else 'NO_RESPONSE'}")
            
            # Second half should be GET responses (values)
            for i, key in enumerate(keys):
                response_idx = len(keys) + i
                expected_value = expected_values[key]
                
                if response_idx < len(responses) and responses[response_idx] == expected_value:
                    success_count += 1
                else:
                    actual = responses[response_idx] if response_idx < len(responses) else 'NO_RESPONSE'
                    errors.append(f"GET {key} failed: expected '{expected_value}', got '{actual}'")
            
            return {
                "success": len(errors) == 0,
                "total_commands": len(commands),
                "successful_commands": success_count,
                "errors": errors,
                "target_core": target_core
            }
            
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def test_cross_core_pipeline(self) -> Dict:
        """Test pipeline where commands go to different cores"""
        print("🌐 Testing cross-core pipeline (commands to different cores)...")
        
        # Generate keys that hash to different cores
        keys_by_core = {i: [] for i in range(self.num_cores)}
        
        for i in range(200):  # Try up to 200 keys
            key = f"cross_core_test_{i}_{time.time_ns()}"
            target_core = self.calculate_target_core(key)
            
            if len(keys_by_core[target_core]) < 3:  # 3 keys per core
                keys_by_core[target_core].append(key)
            
            # Check if we have enough keys for all cores
            if all(len(keys) >= 3 for keys in keys_by_core.values()):
                break
        
        # Ensure we have keys for all cores
        total_keys = sum(len(keys) for keys in keys_by_core.values())
        if total_keys < self.num_cores * 2:
            return {"success": False, "error": f"Could not generate keys for all cores: {keys_by_core}"}
        
        # Create cross-core pipeline
        commands = []
        expected_values = {}
        command_core_mapping = []
        
        # Add SET commands for all cores in interleaved fashion
        max_keys_per_core = max(len(keys) for keys in keys_by_core.values())
        for key_idx in range(max_keys_per_core):
            for core_id in range(self.num_cores):
                if key_idx < len(keys_by_core[core_id]):
                    key = keys_by_core[core_id][key_idx]
                    value = f"value_c{core_id}_k{key_idx}_{time.time_ns()}"
                    commands.append(["SET", key, value])
                    expected_values[key] = value
                    command_core_mapping.append(core_id)
        
        # Add GET commands
        for key_idx in range(max_keys_per_core):
            for core_id in range(self.num_cores):
                if key_idx < len(keys_by_core[core_id]):
                    key = keys_by_core[core_id][key_idx]
                    commands.append(["GET", key])
                    command_core_mapping.append(core_id)
        
        try:
            # Send cross-core pipeline to core 0 (it should route commands to correct cores)
            sock = self.connect_to_core(0)
            start_time = time.time()
            responses = self.send_pipeline(sock, commands)
            end_time = time.time()
            sock.close()
            
            # Analyze results
            set_commands = len([cmd for cmd in commands if cmd[0] == "SET"])
            get_commands = len(commands) - set_commands
            
            success_count = 0
            errors = []
            core_distribution = {i: 0 for i in range(self.num_cores)}
            
            # Count successful operations by core
            for i, cmd in enumerate(commands):
                target_core = command_core_mapping[i]
                core_distribution[target_core] += 1
                
                if cmd[0] == "SET":
                    if i < len(responses) and responses[i] == "OK":
                        success_count += 1
                    else:
                        errors.append(f"SET {cmd[1]} failed: {responses[i] if i < len(responses) else 'NO_RESPONSE'}")
                
                elif cmd[0] == "GET":
                    expected_value = expected_values[cmd[1]]
                    if i < len(responses) and responses[i] == expected_value:
                        success_count += 1
                    else:
                        actual = responses[i] if i < len(responses) else 'NO_RESPONSE'
                        errors.append(f"GET {cmd[1]} failed: expected '{expected_value}', got '{actual}'")
            
            return {
                "success": len(errors) == 0,
                "total_commands": len(commands),
                "successful_commands": success_count,
                "set_commands": set_commands,
                "get_commands": get_commands,
                "core_distribution": core_distribution,
                "latency_ms": (end_time - start_time) * 1000,
                "errors": errors[:10],  # First 10 errors only
                "total_errors": len(errors)
            }
            
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def test_temporal_ordering(self) -> Dict:
        """Test that temporal ordering is maintained in pipelines"""
        print("⏱️  Testing temporal ordering in cross-core pipelines...")
        
        # Create a sequence of operations that must maintain order
        base_key = f"temporal_test_{time.time_ns()}"
        commands = []
        
        # Operations that build upon each other
        for i in range(10):
            key = f"{base_key}_{i}"
            value = f"step_{i}"
            commands.append(["SET", key, value])
        
        # Read them back in order
        for i in range(10):
            key = f"{base_key}_{i}"
            commands.append(["GET", key])
        
        try:
            sock = self.connect_to_core(0)
            start_time = time.time()
            responses = self.send_pipeline(sock, commands)
            end_time = time.time()
            sock.close()
            
            # Check ordering
            success = True
            errors = []
            
            # First 10 should be "OK"
            for i in range(10):
                if i >= len(responses) or responses[i] != "OK":
                    success = False
                    errors.append(f"SET step {i} failed")
            
            # Next 10 should be the values in order
            for i in range(10):
                response_idx = 10 + i
                expected = f"step_{i}"
                if response_idx >= len(responses) or responses[response_idx] != expected:
                    success = False
                    actual = responses[response_idx] if response_idx < len(responses) else 'NO_RESPONSE'
                    errors.append(f"GET step {i}: expected '{expected}', got '{actual}'")
            
            return {
                "success": success,
                "total_commands": len(commands),
                "responses_received": len(responses),
                "latency_ms": (end_time - start_time) * 1000,
                "errors": errors
            }
            
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def test_high_load_pipeline(self, num_threads=10, pipelines_per_thread=100) -> Dict:
        """Test pipeline correctness under high load"""
        print(f"🚀 Testing pipeline correctness under high load ({num_threads} threads, {pipelines_per_thread} pipelines each)...")
        
        results = queue.Queue()
        
        def worker_thread(thread_id):
            local_errors = []
            local_success = 0
            
            try:
                sock = self.connect_to_core(0)
                
                for pipeline_num in range(pipelines_per_thread):
                    # Create small pipeline
                    commands = []
                    expected = {}
                    
                    for cmd_num in range(5):  # 5 commands per pipeline
                        key = f"load_test_t{thread_id}_p{pipeline_num}_c{cmd_num}_{time.time_ns()}"
                        value = f"value_{thread_id}_{pipeline_num}_{cmd_num}"
                        commands.append(["SET", key, value])
                        commands.append(["GET", key])
                        expected[key] = value
                    
                    # Send pipeline
                    responses = self.send_pipeline(sock, commands)
                    
                    # Validate (simplified)
                    if len(responses) == len(commands):
                        # Check SET/GET pairs
                        for i in range(0, len(commands), 2):
                            if (i + 1 < len(responses) and 
                                responses[i] == "OK" and 
                                responses[i + 1] in expected.values()):
                                local_success += 2
                            else:
                                local_errors.append(f"Thread {thread_id} pipeline {pipeline_num} pair {i//2} failed")
                    else:
                        local_errors.append(f"Thread {thread_id} pipeline {pipeline_num}: expected {len(commands)} responses, got {len(responses)}")
                
                sock.close()
                
            except Exception as e:
                local_errors.append(f"Thread {thread_id} error: {str(e)}")
            
            results.put({
                "thread_id": thread_id,
                "success_count": local_success,
                "errors": local_errors
            })
        
        # Start threads
        threads = []
        start_time = time.time()
        
        for i in range(num_threads):
            thread = threading.Thread(target=worker_thread, args=(i,))
            threads.append(thread)
            thread.start()
        
        # Wait for completion
        for thread in threads:
            thread.join()
        
        end_time = time.time()
        
        # Collect results
        total_success = 0
        all_errors = []
        
        while not results.empty():
            result = results.get()
            total_success += result["success_count"]
            all_errors.extend(result["errors"])
        
        total_expected = num_threads * pipelines_per_thread * 10  # 5 SET + 5 GET per pipeline
        total_operations = num_threads * pipelines_per_thread
        duration = end_time - start_time
        
        return {
            "success": len(all_errors) == 0,
            "total_operations": total_operations,
            "total_commands": total_expected,
            "successful_commands": total_success,
            "threads": num_threads,
            "pipelines_per_thread": pipelines_per_thread,
            "duration_seconds": duration,
            "operations_per_second": total_operations / duration if duration > 0 else 0,
            "errors": all_errors[:20],  # First 20 errors
            "total_errors": len(all_errors)
        }
    
    def run_all_tests(self) -> Dict:
        """Run all pipeline correctness tests"""
        print("🧪 CROSS-CORE PIPELINE CORRECTNESS TEST SUITE")
        print("=" * 50)
        print(f"Testing server at {self.host}:{self.base_port}")
        print(f"Configuration: {self.num_cores} cores, {self.num_shards} shards")
        print()
        
        results = {
            "timestamp": time.time(),
            "configuration": {
                "host": self.host,
                "base_port": self.base_port,
                "num_cores": self.num_cores,
                "num_shards": self.num_shards
            },
            "tests": {}
        }
        
        # Test 1: Single-core pipeline
        results["tests"]["single_core_pipeline"] = self.test_single_core_pipeline()
        
        # Test 2: Cross-core pipeline
        results["tests"]["cross_core_pipeline"] = self.test_cross_core_pipeline()
        
        # Test 3: Temporal ordering
        results["tests"]["temporal_ordering"] = self.test_temporal_ordering()
        
        # Test 4: High load
        results["tests"]["high_load_pipeline"] = self.test_high_load_pipeline()
        
        return results

def main():
    parser = argparse.ArgumentParser(description='Cross-Core Pipeline Correctness Test')
    parser.add_argument('--host', default='127.0.0.1', help='Server host')
    parser.add_argument('--port', type=int, default=6379, help='Base port')
    parser.add_argument('--cores', type=int, default=4, help='Number of cores')
    parser.add_argument('--shards', type=int, default=16, help='Number of shards')
    parser.add_argument('--output', help='Output results to JSON file')
    
    args = parser.parse_args()
    
    # Run tests
    tester = CrossCorePipelineTest(args.host, args.port, args.cores, args.shards)
    results = tester.run_all_tests()
    
    # Print summary
    print("\n🏆 TEST RESULTS SUMMARY")
    print("=" * 30)
    
    total_tests = len(results["tests"])
    passed_tests = sum(1 for test in results["tests"].values() if test.get("success", False))
    
    for test_name, test_result in results["tests"].items():
        status = "✅ PASS" if test_result.get("success", False) else "❌ FAIL"
        print(f"{test_name}: {status}")
        
        if not test_result.get("success", False) and "error" in test_result:
            print(f"  Error: {test_result['error']}")
        elif "errors" in test_result and test_result["errors"]:
            print(f"  Errors: {len(test_result['errors'])} issues found")
    
    print(f"\nOverall: {passed_tests}/{total_tests} tests passed")
    
    # Detailed results
    if results["tests"]["cross_core_pipeline"].get("success"):
        ccpr = results["tests"]["cross_core_pipeline"]
        print(f"\n📊 Cross-Core Pipeline Performance:")
        print(f"  - Total commands: {ccpr['total_commands']}")
        print(f"  - Successful: {ccpr['successful_commands']}")
        print(f"  - Latency: {ccpr['latency_ms']:.2f}ms")
        if 'core_distribution' in ccpr:
            print(f"  - Core distribution: {ccpr['core_distribution']}")
    
    if results["tests"]["high_load_pipeline"].get("success"):
        hlpr = results["tests"]["high_load_pipeline"]
        print(f"\n🚀 High Load Performance:")
        print(f"  - Operations per second: {hlpr['operations_per_second']:.0f}")
        print(f"  - Duration: {hlpr['duration_seconds']:.2f}s")
        print(f"  - Success rate: {hlpr['successful_commands']}/{hlpr['total_commands']}")
    
    # Save results if requested
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        print(f"\n📄 Detailed results saved to: {args.output}")
    
    # Exit code
    return 0 if passed_tests == total_tests else 1

if __name__ == "__main__":
    exit(main())














