import os
import re

def escape_non_ascii(text):
    result = []
    for char in text:
        if ord(char) > 127:
            # Check if it fits in 4 hex digits (\uXXXX) or needs 6 (\u{XXXXXX})
            code = ord(char)
            if code <= 0xFFFF:
                result.append(f'\\u{code:04X}')
            else:
                result.append(f'\\u{{{code:X}}}')
        else:
            result.append(char)
    return "".join(result)

def process_directory(directory):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                try:
                    # Try reading as UTF-8
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read()
                except UnicodeDecodeError:
                    # If it fails, fallback to cp1252 (Windows)
                    with open(filepath, 'r', encoding='cp1252') as f:
                        content = f.read()
                
                new_content = escape_non_ascii(content)
                
                if new_content != content:
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f"Fixed encoding in: {filepath}")

if __name__ == "__main__":
    process_directory("f:/society app/society_hub/lib")
