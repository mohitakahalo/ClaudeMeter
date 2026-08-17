#!/usr/bin/env python3
"""Strip #Preview macro blocks from Swift sources.

The #Preview freestanding macro is implemented by the PreviewsMacros compiler
plugin, which ships inside Xcode.app -- it is NOT part of the Command Line
Tools. Building with CLT-only swiftc/SwiftPM therefore fails with
"plugin for module 'PreviewsMacros' not found". Previews are dev-only UI
scaffolding with no runtime effect, so we remove them before building.
"""
import sys
import pathlib

def strip(src: str) -> tuple[str, int]:
    out = []
    i = 0
    n = len(src)
    removed = 0
    while True:
        idx = src.find('#Preview', i)
        if idx == -1:
            out.append(src[i:])
            break
        # Only treat as a macro at statement position (start of a line).
        line_start = src.rfind('\n', 0, idx) + 1
        if src[line_start:idx].strip() != '':
            out.append(src[i:idx + len('#Preview')])
            i = idx + len('#Preview')
            continue
        out.append(src[i:line_start])
        # Scan forward to the opening brace of the trailing closure.
        j = idx
        while j < n and src[j] != '{':
            j += 1
        if j >= n:
            out.append(src[idx:])
            break
        # Balanced-brace scan that ignores braces inside comments and strings.
        depth = 0
        k = j
        while k < n:
            c = src[k]
            if c == '/' and k + 1 < n and src[k + 1] == '/':
                k = src.find('\n', k)
                if k == -1:
                    k = n
                continue
            if c == '/' and k + 1 < n and src[k + 1] == '*':
                end = src.find('*/', k + 2)
                k = n if end == -1 else end + 2
                continue
            if c == '"':
                if src[k:k + 3] == '"""':
                    end = src.find('"""', k + 3)
                    k = n if end == -1 else end + 3
                    continue
                k += 1
                while k < n and src[k] != '"':
                    if src[k] == '\\':
                        k += 1
                    k += 1
                k += 1
                continue
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    k += 1
                    break
            k += 1
        removed += 1
        # Swallow the trailing newline left behind by the removed block.
        while k < n and src[k] in ' \t':
            k += 1
        if k < n and src[k] == '\n':
            k += 1
        i = k
    return ''.join(out), removed

total_files = 0
total_blocks = 0
for path in sorted(pathlib.Path(sys.argv[1]).rglob('*.swift')):
    original = path.read_text()
    if '#Preview' not in original:
        continue
    new, count = strip(original)
    if count:
        path.write_text(new)
        total_files += 1
        total_blocks += count
        print(f'stripped {count} #Preview block(s): {path}')
print(f'TOTAL: {total_blocks} blocks in {total_files} files')
