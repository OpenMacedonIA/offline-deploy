
import os
import sys
import gzip
import urllib.request
import urllib.parse
import re
import configparser
from collections import deque

# Configuration
DEBIAN_MIRROR = "http://ftp.debian.org/debian"
ARCH = "amd64"
COMPONENTS = ["main", "contrib", "non-free", "non-free-firmware"]

def download_file(url, target_path):
    print(f"Downloading {url}...")
    try:
        urllib.request.urlretrieve(url, target_path)
        return True
    except Exception as e:
        print(f"Error downloading {url}: {e}")
        return False

def parse_packages_file(file_path):
    packages = {}
    current_pkg = {}
    last_key = None
    
    with gzip.open(file_path, 'rt', encoding='utf-8', errors='ignore') as f:
        for line in f:
            if line.startswith('\n') or line.strip() == '':
                if 'Package' in current_pkg:
                    packages[current_pkg['Package']] = current_pkg
                current_pkg = {}
                last_key = None
                continue
            
            if line[0].isspace():
                if last_key:
                    current_pkg[last_key] += line.strip()
                continue
            
            match = re.match(r'([^:]+): (.*)', line)
            if match:
                key, value = match.groups()
                current_pkg[key] = value.strip()
                last_key = key
    
    if 'Package' in current_pkg:
        packages[current_pkg['Package']] = current_pkg
        
    return packages

def parse_dependencies(dep_str):
    if not dep_str:
        return []
    # Remove version constraints mostly for simple resolution (e.g., "libc6 (>= 2.14)")
    # This is a basic parser and might not handle complex OR dependencies perfectly (A | B)
    # For A | B, we take A.
    deps = []
    parts = dep_str.split(',')
    for part in parts:
        part = part.strip()
        if '|' in part:
            part = part.split('|')[0].strip()
        
        # Remove version info (foo (>= 1.0)) -> foo
        match = re.match(r'^([a-zA-Z0-9+\-\.]+)', part)
        if match:
            deps.append(match.group(1))
    return deps

def resolve_dependencies(packages_db, target_packages):
    queue = deque(target_packages)
    resolved = set()
    to_download = {} # pkg_name: package_info
    
    missing = set()

    while queue:
        pkg = queue.popleft()
        if pkg in resolved:
            continue
        
        if pkg not in packages_db:
            # Try finding a provider (virtual package) - Simplified: Just check direct names first
            # Real resolution is complex. We stick to simple name match or skip.
            missing.add(pkg)
            continue
        
        info = packages_db[pkg]
        resolved.add(pkg)
        to_download[pkg] = info
        
        depends = parse_dependencies(info.get('Depends', ''))
        pre_depends = parse_dependencies(info.get('Pre-Depends', ''))
        
        for dep in depends + pre_depends:
            if dep not in resolved:
                queue.append(dep)
                
    if missing:
        print(f"Warning: Could not resolve dependencies for: {', '.join(missing)}")
        
    return to_download

def main():
    if len(sys.argv) < 4:
        print("Usage: python3 download_deb_deps.py <debian_version_codename> <output_dir> <pkg1> [pkg2 ...]")
        print("Example: python3 download_deb_deps.py bookworm ./debs git python3")
        sys.exit(1)
        
    codename = sys.argv[1] # e.g., bookworm, trixie
    output_dir = sys.argv[2]
    target_pkgs = sys.argv[3:]
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        
    # 1. Download Packages.gz for each component
    print(f"Fetching package lists for {codename}...")
    packages_db = {}
    
    for comp in COMPONENTS:
        url = f"{DEBIAN_MIRROR}/dists/{codename}/{comp}/binary-{ARCH}/Packages.gz"
        local_filename = os.path.join(output_dir, f"Packages_{comp}.gz")
        if download_file(url, local_filename):
            print(f"Parsing {comp}...")
            comp_pkgs = parse_packages_file(local_filename)
            packages_db.update(comp_pkgs)
            # Clean up index file to save space? Keep checks simple for now
            os.remove(local_filename)
    
    print(f"Loaded {len(packages_db)} packages definitions.")
    
    # 2. Resolve Dependencies
    print("Resolving dependencies...")
    to_download = resolve_dependencies(packages_db, target_pkgs)
    
    print(f"Found {len(to_download)} packages to download.")
    
    # 3. Download .deb files
    count = 0
    for pkg, info in to_download.items():
        count += 1
        filename = info['Filename']
        url = f"{DEBIAN_MIRROR}/{filename}"
        local_name = os.path.basename(filename)
        save_path = os.path.join(output_dir, local_name)
        
        if os.path.exists(save_path):
            print(f"[{count}/{len(to_download)}] Skipping {pkg} (already exists)")
            continue
            
        print(f"[{count}/{len(to_download)}] Downloading {pkg}...")
        download_file(url, save_path)
        
    print("Done.")

if __name__ == "__main__":
    main()
