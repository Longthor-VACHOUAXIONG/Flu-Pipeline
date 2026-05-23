import base64
import os
import zipfile

def obfuscate(file_path, out_path):
    with open(file_path, 'rb') as f:
        content = f.read()
    b64 = base64.b64encode(content).decode('utf-8')
    wrapper = f'#!/bin/bash\neval "$(echo \'{b64}\' | base64 --decode)"\n'
    with open(out_path, 'w', newline='') as f:
        f.write(wrapper)
    print(f"Obfuscated {file_path} -> {out_path}")

print("Obfuscating scripts...")
obfuscate('run_flu_irma_pipeline.sh', 'run_flu_irma_pipeline.sh.x')
obfuscate('.scripts/test_alignment.sh', '.scripts/test_alignment.sh.x')

# Automatically package the secure installation zip archive
zip_name = 'Influenza_Pipeline_Secure_v1.2.zip'
print(f"Packaging files into secure zip: {zip_name}...")

# Base files and folders to include
files_to_zip = [
    'install.sh',
    'README.md',
    'metadata.xlsx',
    'run_flu_irma_pipeline.sh.x',
    '.scripts/process_metadata.py',
    '.scripts/generate_master_report.py',
    '.scripts/test_alignment.sh.x'
]

with zipfile.ZipFile(zip_name, 'w', zipfile.ZIP_DEFLATED) as zipf:
    # 1. Add specific scripts and core files
    for file_path in files_to_zip:
        if os.path.exists(file_path):
            zip_path = file_path.replace(os.sep, '/')
            zipf.write(file_path, zip_path)
            print(f"  + Added file: {zip_path}")
        else:
            print(f"  [WARNING] Core file {file_path} not found!")

    # 2. Add all files in .references/ folder
    ref_dir = '.references'
    if os.path.exists(ref_dir):
        for root, dirs, files in os.walk(ref_dir):
            for file in files:
                file_path = os.path.join(root, file)
                # Ensure correct path separator (forward slash) in the ZIP file for Linux/WSL compatibility
                zip_path = file_path.replace(os.sep, '/')
                zipf.write(file_path, zip_path)
    else:
        print("  [WARNING] .references directory not found!")

print(f"SUCCESS: Secure package rebuilt: {zip_name}")
