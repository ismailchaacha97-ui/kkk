import re
import sys

def check_mql4_code(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        code = f.read()

    lines = code.splitlines()
    print(f"Total lines: {len(lines)}")

    # 1. Bracket & Parentheses matching (ignoring strings and comments)
    stack = []
    in_block_comment = False
    in_string = False
    string_char = ''
    errors = []

    for line_num, line in enumerate(lines, 1):
        i = 0
        while i < len(line):
            # Check block comments
            if in_block_comment:
                if i + 1 < len(line) and line[i:i+2] == '*/':
                    in_block_comment = False
                    i += 2
                    continue
                i += 1
                continue
            
            # Check string literal
            if in_string:
                if line[i] == '\\':
                    i += 2 # skip escaped char
                    continue
                if line[i] == string_char:
                    in_string = False
                i += 1
                continue

            # Start of line comment
            if i + 1 < len(line) and line[i:i+2] == '//':
                break # rest of line is comment

            # Start of block comment
            if i + 1 < len(line) and line[i:i+2] == '/*':
                in_block_comment = True
                i += 2
                continue

            # Start of string or color literal C'...'
            if line[i] in ('"', "'"):
                in_string = True
                string_char = line[i]
                i += 1
                continue

            # Check brackets
            char = line[i]
            if char in '({[':
                stack.append((char, line_num, i))
            elif char in ')}]':
                if not stack:
                    errors.append(f"Unmatched closing bracket '{char}' at line {line_num}:{i+1}")
                else:
                    top, top_line, top_col = stack.pop()
                    expected = {'(': ')', '{': '}', '[': ']'}[top]
                    if char != expected:
                        errors.append(f"Mismatched bracket: opened '{top}' at line {top_line}:{top_col+1}, closed with '{char}' at line {line_num}:{i+1}")
            i += 1

    if in_block_comment:
        errors.append("Unclosed block comment /* ...")
    if in_string:
        errors.append("Unclosed string literal")
    while stack:
        top, top_line, top_col = stack.pop()
        errors.append(f"Unclosed opening bracket '{top}' from line {top_line}:{top_col+1}")

    if errors:
        print("SYNTAX ERRORS FOUND:")
        for err in errors:
            print("  -", err)
        return False
    else:
        print("BRACKET & DELIMITER VALIDATION PASSED: 100% BALANCED!")

    # 2. Key MT4 function and property checks
    required_elements = [
        "#property strict",
        "#property indicator_chart_window",
        "#property indicator_buffers 14",
        "#property indicator_plots   14",
        "int OnInit()",
        "void OnDeinit(",
        "int OnCalculate(",
        "SetIndexBuffer",
        "SetIndexArrow",
        "IndicatorShortName",
        "ObjectsDeleteAll",
        "EvaluateEntrySignals"
    ]

    for req in required_elements:
        if req not in code:
            errors.append(f"Missing required MQL4 construct: {req}")

    # Check for uninitialized prices or names
    if "double prices[12];" in code:
        errors.append("Uninitialized double prices[12]; detected!")
    if "iRealVolume" in code:
        errors.append("iRealVolume is not supported in MQL4!")

    if errors:
        print("SEMANTIC CHECKS FAILED:")
        for err in errors:
            print("  -", err)
        return False
    else:
        print("MQL4 CONSTRUCTS & SAFETY CHECKS VALIDATION PASSED!")
    return True

if __name__ == '__main__':
    ok = check_mql4_code("NF_VolumeProfile_MTF.mq4")
    if not ok:
        sys.exit(1)
    print("ALL VALIDATION SUCCEEDED!")
