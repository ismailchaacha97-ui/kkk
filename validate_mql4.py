import sys
import re

def check_mql4_file(filepath):
    print(f"Validating {filepath}...")
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    lines = content.split('\n')
    brace_count = 0
    paren_count = 0
    bracket_count = 0
    in_comment_block = False
    errors = []

    for i, line in enumerate(lines, 1):
        clean_line = ""
        j = 0
        while j < len(line):
            if in_comment_block:
                if j + 1 < len(line) and line[j:j+2] == '*/':
                    in_comment_block = False
                    j += 2
                    continue
                j += 1
                continue
            else:
                if j + 1 < len(line) and line[j:j+2] == '/*':
                    in_comment_block = True
                    j += 2
                    continue
                if j + 1 < len(line) and line[j:j+2] == '//':
                    break # Line comment, rest of line ignored
                if line[j] == '"':
                    # string literal
                    clean_line += line[j]
                    j += 1
                    while j < len(line):
                        if line[j] == '\\' and j + 1 < len(line):
                            j += 2
                            continue
                        if line[j] == '"':
                            clean_line += line[j]
                            j += 1
                            break
                        j += 1
                    continue
                if line[j] == "'":
                    # char literal
                    clean_line += line[j]
                    j += 1
                    while j < len(line):
                        if line[j] == '\\' and j + 1 < len(line):
                            j += 2
                            continue
                        if line[j] == "'":
                            clean_line += line[j]
                            j += 1
                            break
                        j += 1
                    continue
                clean_line += line[j]
                j += 1

        for char in clean_line:
            if char == '{': brace_count += 1
            elif char == '}': 
                brace_count -= 1
                if brace_count < 0:
                    errors.append(f"Line {i}: Extra closing brace '}}'")
            elif char == '(': paren_count += 1
            elif char == ')': 
                paren_count -= 1
                if paren_count < 0:
                    errors.append(f"Line {i}: Extra closing parenthesis ')'")
            elif char == '[': bracket_count += 1
            elif char == ']': 
                bracket_count -= 1
                if bracket_count < 0:
                    errors.append(f"Line {i}: Extra closing bracket ']'")

    if brace_count != 0:
        errors.append(f"Unmatched braces: balance = {brace_count}")
    if paren_count != 0:
        errors.append(f"Unmatched parentheses: balance = {paren_count}")
    if bracket_count != 0:
        errors.append(f"Unmatched brackets: balance = {bracket_count}")

    if errors:
        print(f"❌ Errors found in {filepath}:")
        for err in errors:
            print("  - " + err)
        return False
    else:
        print(f"✅ {filepath} passed bracket and structural syntax check! (Total lines: {len(lines)})")
        return True

if __name__ == '__main__':
    for path in sys.argv[1:]:
        check_mql4_file(path)
