#!/usr/bin/env python3

import re
import sys

def remove_debug_logging(content):
    """Remove debug logging that causes performance regression"""
    
    # Remove std::cout lines with routing debug info
    patterns_to_remove = [
        r'\s*std::cout\s*<<.*?🔍.*?std::endl;\s*\n',
        r'\s*std::cout\s*<<.*?✅.*?CORRECT CORE.*?std::endl;\s*\n', 
        r'\s*std::cout\s*<<.*?🚀.*?ROUTING.*?std::endl;\s*\n',
        r'\s*std::cout\s*<<.*?✅.*?MIGRATED.*?std::endl;\s*\n',
        r'\s*std::cout\s*<<.*?❌.*?MIGRATION FAILED.*?std::endl;\s*\n',
        r'\s*std::cout\s*<<.*?❌.*?INVALID TARGET CORE.*?std::endl;\s*\n',
        r'\s*std::cout\s*<<.*?📨.*?received migrated.*?std::endl;\s*\n',
        r'\s*std::cout\s*<<.*?⚡.*?Processing migrated.*?std::endl;\s*\n',
    ]
    
    result = content
    for pattern in patterns_to_remove:
        result = re.sub(pattern, '', result, flags=re.MULTILINE | re.DOTALL)
    
    return result

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 remove_debug_logging.py input_file output_file")
        sys.exit(1)
        
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    with open(input_file, 'r') as f:
        content = f.read()
    
    optimized_content = remove_debug_logging(content)
    
    with open(output_file, 'w') as f:
        f.write(optimized_content)
    
    print(f"Debug logging removed. Created optimized version: {output_file}")













