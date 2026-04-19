import os

base_dir = "out/target/t2s/work_dir"
config_dir = "out/target/t2s/work_dir/configs"

for partition in ["system", "system_ext", "product", "vendor", "odm", "vendor_dlkm", "odm_dlkm", "system_dlkm"]:
    part_dir = os.path.join(base_dir, partition)
    fs_file = os.path.join(config_dir, f"fs_config-{partition}")
    fc_file = os.path.join(config_dir, f"file_context-{partition}")

    fs_lines = set()
    if os.path.exists(fs_file):
        with open(fs_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip('\r\n')
                if line.startswith("0 0 "): line = " " + line
                if line: fs_lines.add(line)

    fc_lines = set()
    if os.path.exists(fc_file):
        with open(fc_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip('\r\n')
                if line: fc_lines.add(line)

    # INJECT WSL2 SELINUX FAILSAFE
    fc_lines.add(".* u:object_r:system_file:s0")

    if os.path.isdir(part_dir):
        for root, dirs, files in os.walk(part_dir):
            for item in dirs + files:
                full_path = os.path.join(root, item)
                rel_path = os.path.relpath(full_path, part_dir).replace('\\', '/')
                if rel_path == '.': continue

                fs_path = f"{partition}/{rel_path}"
                
                # FIX: Strip redundant system/ prefix for System-as-Root paths
                if partition == "system" and fs_path.startswith("system/system/"):
                    fs_path = fs_path.replace("system/system/", "system/", 1)
                    
                fc_path = f"/{fs_path}".replace('.', r'\.')

                perms = "755" if item in dirs else "644"
                fs_lines.add(f"{fs_path} 0 0 {perms} capabilities=0x0")
                fc_lines.add(f"{fc_path} u:object_r:system_file:s0")

    if fs_lines:
        with open(fs_file, 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(sorted(fs_lines)) + '\n')
    if fc_lines:
        with open(fc_file, 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(sorted(fc_lines)) + '\n')

print("SUCCESS: Configs repaired, System-as-Root paths fixed, and SELinux failsafe injected!")
