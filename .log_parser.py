import re
import sys

def parse_logs():
    log_content = sys.stdin.read()
    
    # Matches: /path/to/file.swift:10:20: error: message
    pattern = r"^([^:]+):(\d+):(\d+):\s+error:\s+(.+)$"
    matches = re.finditer(pattern, log_content, re.MULTILINE)
    
    seen = set()
    errors_found = False
    
    for match in matches:
        file_path = match.group(1).strip()
        line = match.group(2)
        col = match.group(3)
        msg = match.group(4).strip()
        
        # Create a unique key for deduplication
        key = (file_path, line, msg)
        
        if key not in seen:
            seen.add(key)
            errors_found = True
            # Print in a clean format
            print(f"📄 {file_path}:{line}")
            print(f"❌ {msg}")
            print("-" * 40)

    if not errors_found:
        print("✅ No compilation errors found in the input.")

if __name__ == "__main__":
    parse_logs()
