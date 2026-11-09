with open('apply_edras.py', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Cut everything from line 130 (first attempt) to just before "# Clear and rebuild with the simplified approach."
start_idx = None
for i, line in enumerate(lines):
    if 'Clear and rebuild with the simplified approach' in line:
        start_idx = i - 1
        break

end_idx = None
for i, line in enumerate(lines):
    if '# 1. Edras enabled check' in line and start_idx is not None and i > start_idx + 5:
        end_idx = i
        break

# Look for the FIRST occurrence of '# 1. Edras enabled check' after start_idx
print(f"start_idx: {start_idx}, end_idx: {end_idx}")
print(f"Removing {end_idx - start_idx} lines")

new_lines = lines[:start_idx] + lines[end_idx:]
with open('apply_edras.py', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
print("Done")
