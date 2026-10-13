with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

# We know the block starts around line 3187 and ends at 3224.
start_index = -1
end_index = -1

for i, line in enumerate(lines):
    if "// ---- Info Card ----" in line:
        start_index = i
    if "// ---- IP Input ----" in line:
        end_index = i
        break

if start_index != -1 and end_index != -1:
    del lines[start_index:end_index]
    with open("lib/main.dart", "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("Deleted info card")
else:
    print("Could not find info card block")
