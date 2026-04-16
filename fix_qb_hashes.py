import os
import re

# Paths
BASE_DIR = os.path.expanduser("~/UN1CA")
WORKSPACE = os.path.join(BASE_DIR, "out/target/t2s/apktool")
PATCH_DIRS = [os.path.join(BASE_DIR, "unica/patches"), os.path.join(BASE_DIR, "unica/mods")]

def get_actual_hash(app_name, smali_rel_path):
    """Finds the actual QB hash from the workspace."""
    # Search for the app directory (e.g., DAAgent.apk)
    app_folder = None
    for root, dirs, _ in os.walk(WORKSPACE):
        if root.endswith(app_name):
            app_folder = root
            break
    
    if not app_folder:
        return None

    # Construct path to the smali file
    target_file = os.path.join(app_folder, smali_rel_path)
    if os.path.exists(target_file):
        with open(target_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if '.source "qb/' in line:
                    return line.strip()
    return None

def process_patch(patch_path):
    # Determine the target app from the patch directory structure
    parts = patch_path.split(os.sep)
    target_app = next((p for p in parts if p.endswith(('.apk', '.jar'))), None)
    if not target_app:
        return

    with open(patch_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    updated = False
    new_lines = []
    current_smali = None

    for line in lines:
        # Detect the file being patched: diff --git a/smali/xxx b/smali/xxx
        match = re.match(r"^diff --git a/(.*) b/.*", line)
        if match:
            current_smali = match.group(1)

        if current_smali and '.source "qb/' in line:
            real_hash = get_actual_hash(target_app, current_smali)
            if real_hash:
                # Preserve the leading space (context line) or + (added line)
                prefix = " " if line.startswith(" ") else ("+" if line.startswith("+") else "")
                new_line = f"{prefix}{real_hash}\n"
                if line != new_line:
                    print(f"  [SYNC] {target_app} -> {os.path.basename(current_smali)}")
                    line = new_line
                    updated = True
        
        new_lines.append(line)

    if updated:
        with open(patch_path, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)

print("🚀 Scanning all patches for Android 16.1 hash synchronization...")
for p_dir in PATCH_DIRS:
    if os.path.exists(p_dir):
        for root, _, files in os.walk(p_dir):
            for file in files:
                if file.endswith(".patch"):
                    process_patch(os.path.join(root, file))
print("✨ Synchronization complete.")