import os
import sys
import uuid
import re
import subprocess
import shutil

# Configuration
REPLACEMENTS = {
    "Mod Name": "Dynamic Camera Rotation Sensitivity",
    "ModName": "DynamicCameraRotationSensitivity",
    "mod-name": "dynamic-camera-rotation-sensitivity",
    "MN": "DCRS"
}

def run_command(cmd, cwd=None):
    """Run a shell command and return the result."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            shell=True,
            capture_output=True,
            text=True,
            check=True
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.CalledProcessError as e:
        return False, e.stdout, e.stderr

def add_volition_cabinet(base_dir, mod_name):
    """Add VolitionCabinet as a subtree dependency."""
    print("\n--- Adding VolitionCabinet Dependency ---")

    # Check if git is available
    success, _, _ = run_command("git --version")
    if not success:
        print("Warning: Git not found. Skipping VolitionCabinet setup.")
        print("You can manually add it later or install Git and re-run this script.")
        return

    # Check if we're in a git repository
    success, _, _ = run_command("git rev-parse --git-dir", cwd=base_dir)
    if not success:
        print("Warning: Not in a git repository. Skipping VolitionCabinet setup.")
        print("Initialize a git repository first with: git init")
        return

    temp_dir = os.path.join(base_dir, "temp", "volition-cabinet")
    target_dir = os.path.join(base_dir, mod_name, "Mods", mod_name.replace(" ", "").replace("-", ""),
                              "ScriptExtender", "Lua", "_Libs", "VolitionCabinet")

    try:
        # Clone the repository to a temporary location
        print("Cloning VolitionCabinet repository...")
        success, stdout, stderr = run_command(
            "git clone --depth 1 https://github.com/AtilioA/BG3-volition-cabinet.git temp/volition-cabinet",
            cwd=base_dir
        )

        if not success:
            print(f"Error cloning repository: {stderr}")
            return

        # Create target directory
        os.makedirs(target_dir, exist_ok=True)

        # Copy files from the nested structure
        source_path = os.path.join(temp_dir, "VolitionCabinet", "Mods", "VolitionCabinet",
                                   "ScriptExtender", "Lua")

        if os.path.exists(source_path):
            print(f"Copying VolitionCabinet files to {target_dir}...")

            # Copy all files and directories from source to target
            for item in os.listdir(source_path):
                s = os.path.join(source_path, item)
                d = os.path.join(target_dir, item)
                if os.path.isdir(s):
                    shutil.copytree(s, d, dirs_exist_ok=True)
                else:
                    shutil.copy2(s, d)

            print("VolitionCabinet files copied successfully!")
        else:
            print(f"Warning: Source path not found: {source_path}")

        # Clean up temporary directory
        print("Cleaning up temporary files...")
        shutil.rmtree(os.path.join(base_dir, "temp"), ignore_errors=True)

        # Stage the new files
        print("Staging VolitionCabinet files...")
        run_command(f'git add "{os.path.relpath(target_dir, base_dir)}"', cwd=base_dir)

        print("VolitionCabinet added successfully!")
        print(f"Location: {os.path.relpath(target_dir, base_dir)}")

    except Exception as e:
        print(f"Error adding VolitionCabinet: {e}")
        # Clean up on error
        if os.path.exists(os.path.join(base_dir, "temp")):
            shutil.rmtree(os.path.join(base_dir, "temp"), ignore_errors=True)

def main():
    # Get the current directory or a specific target directory
    base_dir = os.getcwd()
    current_dir_name = os.path.basename(base_dir)
    print(f"Running in: {base_dir}")
    print(f"Current directory name: {current_dir_name}")

    # 1. Rename Directories (Bottom-up to avoid path changes affecting future steps)
    print("\n--- Renaming Directories ---")
    for root, dirs, files in os.walk(base_dir, topdown=False):
        for name in dirs:
            if name in [".git", ".vscode", ".agent", "ignore", "__pycache__", "temp"]: continue

            new_name = name
            for old_str, new_str in REPLACEMENTS.items():
                if old_str in new_name:
                    new_name = new_name.replace(old_str, new_str)

            if new_name != name:
                old_path = os.path.join(root, name)
                new_path = os.path.join(root, new_name)
                # Check if target exists (merge or skip?)
                if os.path.exists(new_path):
                    print(f"Skipping rename {old_path} -> {new_path} : Target exists")
                else:
                    try:
                        os.rename(old_path, new_path)
                        print(f"Renamed Directory: {old_path} -> {new_path}")
                    except OSError as e:
                        print(f"Error renaming directory {old_path}: {e}")

    # 2. Rename Files
    print("\n--- Renaming Files ---")
    for root, dirs, files in os.walk(base_dir):
        if ".git" in root: continue

        for name in files:
            # Avoid renaming the script itself if it matches pattern (unlikely but safe)
            if name == os.path.basename(__file__): continue

            new_name = name
            for old_str, new_str in REPLACEMENTS.items():
                if old_str in new_name:
                    new_name = new_name.replace(old_str, new_str)

            if new_name != name:
                old_path = os.path.join(root, name)
                new_path = os.path.join(root, new_name)
                if os.path.exists(new_path):
                     print(f"Skipping rename {old_path} -> {new_path} : Target exists")
                else:
                    try:
                        os.rename(old_path, new_path)
                        print(f"Renamed File: {old_path} -> {new_path}")
                    except OSError as e:
                        print(f"Error renaming file {old_path}: {e}")

    # 3. Replace Content in Files
    print("\n--- Replacing Content ---")
    # Extensions to scan
    EXTENSIONS = {'.xml', '.lsx', '.json', '.lua', '.md', '.txt', '.code-workspace', '.bat'}
    IGNORED_FILES = {"MCM_blueprint.json"}

    for root, dirs, files in os.walk(base_dir):
        if ".git" in root or "temp" in root: continue

        for name in files:
            if name == os.path.basename(__file__): continue
            if name in IGNORED_FILES: continue

            if not any(name.endswith(ext) for ext in EXTENSIONS) and name != "symlink.bat":
                continue

            file_path = os.path.join(root, name)
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()

                new_content = content
                changes_made = False
                for old_str, new_str in REPLACEMENTS.items():
                    if old_str in new_content:
                        new_content = new_content.replace(old_str, new_str)
                        changes_made = True

                if changes_made:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f"Updated Content: {file_path}")
            except Exception as e:
                print(f"Error processing file {file_path}: {e}")

    # 4. Special handling for meta.lsx - Generate new UUID
    print("\n--- Generating New UUID for meta.lsx ---")
    meta_lsx_path = os.path.join(base_dir, REPLACEMENTS["Mod Name"], "Mods", REPLACEMENTS["ModName"], "meta.lsx")
    if os.path.exists(meta_lsx_path):
        try:
            with open(meta_lsx_path, 'r', encoding='utf-8') as f:
                meta_content = f.read()

            # Generate a new UUID
            new_uuid = str(uuid.uuid4())

            # Replace the UUID in meta.lsx using regex to find the UUID attribute
            uuid_pattern = r'(<attribute id="UUID" type="FixedString" value=")([a-f0-9\-]+)(" />)'
            match = re.search(uuid_pattern, meta_content)

            if match:
                old_uuid = match.group(2)
                meta_content = re.sub(uuid_pattern, r'\g<1>' + new_uuid + r'\g<3>', meta_content)

                with open(meta_lsx_path, 'w', encoding='utf-8') as f:
                    f.write(meta_content)

                print(f"Updated UUID in meta.lsx:")
                print(f"  Old UUID: {old_uuid}")
                print(f"  New UUID: {new_uuid}")
            else:
                print("Warning: Could not find UUID attribute in meta.lsx")
        except Exception as e:
            print(f"Error updating UUID in meta.lsx: {e}")
    else:
        print(f"Warning: meta.lsx not found at {meta_lsx_path}")

    # 5. Special handling for symlink.bat - Replace 'BG3-mod' with current directory name
    print("\n--- Updating symlink.bat ---")
    symlink_path = os.path.join(base_dir, "symlink.bat")
    if os.path.exists(symlink_path):
        try:
            with open(symlink_path, 'r', encoding='utf-8') as f:
                symlink_content = f.read()

            # Replace 'BG3-mod' with the current directory name
            if 'BG3-mod' in symlink_content:
                symlink_content = symlink_content.replace('BG3-mod', current_dir_name)

                with open(symlink_path, 'w', encoding='utf-8') as f:
                    f.write(symlink_content)

                print(f"Updated symlink.bat: Replaced 'BG3-mod' with '{current_dir_name}'")
            else:
                print("Info: 'BG3-mod' not found in symlink.bat (may have been already replaced)")
        except Exception as e:
            print(f"Error updating symlink.bat: {e}")
    else:
        print(f"Warning: symlink.bat not found at {symlink_path}")

    # 6. Add VolitionCabinet dependency
    add_volition_cabinet(base_dir, REPLACEMENTS["Mod Name"])

    print("\nDone!")

if __name__ == "__main__":
    main()
