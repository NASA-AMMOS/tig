# VICAR Native Toolkit - Demo Commands

Demonstration of the VICAR Native Toolkit using docker-compose to provide a seamless, native-like command experience. Commands execute inside a Docker container but feel like they're running natively on your system.

For direct Docker usage without the toolkit, see [../DEMO_COMMANDS.md](../DEMO_COMMANDS.md).

## What This Demo Shows

- **docker-compose** for persistent container management
- **Workspace mounting** for seamless file access
- **Command execution** that feels native to your system
- **No wrapper scripts** - just straightforward docker-compose exec commands

## Prerequisites

- Docker Engine 20.10+ or Docker Desktop
- docker-compose (usually included with Docker Desktop)
- Access to terrain-intelligence-generator image

## Image Setup

```bash
# Navigate to toolkit directory
cd /path/to/tig/vicar-native-toolkit

# Check if terrain-intelligence-generator image is available
docker images | grep terrain-intelligence-generator

# If not available, pull from GitHub Container Registry
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
```

---

## Step 1: Configure docker-compose

Verify `docker-compose.yml` uses the terrain-intelligence-generator image:

```bash
# Check current image setting
grep "image:" docker-compose.yml

# Should show:
# image: ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
```

---

## Step 2: Start the Toolkit

Start the container using docker-compose:

**Note for SELinux systems (Fedora, RHEL, CentOS):** If using volume mounts and getting "Permission denied" errors, add `:Z` flag to volumes in docker-compose.yml:
```yaml
volumes:
  - ./workspace:/workspace:Z
```

```bash
# Start container in background
docker-compose up -d

# Verify container is running
docker-compose ps

# Check logs (optional)
docker-compose logs
```

**Expected Output:**
```
Creating network "vicar-native-toolkit_default" with the default driver
Creating vicar-sidecar ... done
```

---

## Step 3: Test Basic VICAR Commands

All commands run via `docker-compose exec vicar-toolkit <command>`:

```bash
# Generate test image (64x64 pixels) in workspace
docker-compose exec vicar-toolkit bash -c 'cd /workspace && gen test.vic 64 64'

# List the file
docker-compose exec vicar-toolkit ls -lh /workspace/test.vic

# The file is also accessible on your host system!
ls -lh workspace/test.vic

# Generate larger test image (512x512 pixels)
docker-compose exec vicar-toolkit bash -c 'cd /workspace && gen large.vic 512 512'

# Check both files
docker-compose exec vicar-toolkit bash -c 'ls -lh /workspace/*.vic'
ls -lh workspace/*.vic
```

**Key Feature:** Files created in `/workspace` inside the container are immediately visible in the `workspace/` directory on your host!

---

## Step 4: Test Image Operations

```bash
# Copy image
docker-compose exec vicar-toolkit bash -c 'cd /workspace && copy test.vic test_copy.vic'

# Stretch image contrast
docker-compose exec vicar-toolkit bash -c 'cd /workspace && stretch test.vic stretched.vic'

# List all VICAR images
docker-compose exec vicar-toolkit bash -c 'ls -lh /workspace/*.vic'

# View on host
ls -lh workspace/*.vic
```

---

## Step 5: Test vicario Converter

Convert VICAR images to common formats:

```bash
# Convert to PNG
docker-compose exec vicar-toolkit vicario /workspace/test.vic /workspace/test.png

# Convert to JPEG
docker-compose exec vicar-toolkit vicario /workspace/test.vic /workspace/test.jpg

# Convert to TIFF
docker-compose exec vicar-toolkit vicario /workspace/test.vic /workspace/test.tiff

# Verify conversions in container
docker-compose exec vicar-toolkit ls -lh /workspace/test.*

# View converted images on host
ls -lh workspace/test.*

# Open the PNG in your favorite image viewer
xdg-open workspace/test.png  # Linux
# open workspace/test.png     # macOS
```

**Benefit:** Converted images are immediately accessible on your host for viewing in any application!

---

## Step 6: Verify MARS Commands

```bash
# List all MARS commands (74 total)
docker-compose exec vicar-toolkit bash -c 'ls /usr/local/bin | grep "^mars" | head -20'

# Count MARS commands
docker-compose exec vicar-toolkit bash -c 'ls /usr/local/bin | grep "^mars" | wc -l'

# Check specific commands
docker-compose exec vicar-toolkit which marsmap
docker-compose exec vicar-toolkit which marscorr
docker-compose exec vicar-toolkit which marsxyz
```

---

## Step 7: Check Available Commands

```bash
# Count total commands (545)
docker-compose exec vicar-toolkit bash -c 'ls /usr/local/bin | wc -l'

# List first 20 commands
docker-compose exec vicar-toolkit bash -c 'ls /usr/local/bin | head -20'

# Sample VICAR commands
docker-compose exec vicar-toolkit bash -c 'ls /usr/local/bin | grep -E "^(gen|copy|stretch|label|list|hist)$"'
```

---

## Step 8: Check Environment

```bash
# View VICAR environment variables
docker-compose exec vicar-toolkit bash -c 'echo "V2TOP=$V2TOP"'
docker-compose exec vicar-toolkit bash -c 'echo "WORKSPACE=$WORKSPACE"'
docker-compose exec vicar-toolkit bash -c 'echo "VICSYS=$VICSYS"'

# Check VISOR data availability
docker-compose exec vicar-toolkit bash -c 'find $VISOR_CALIB -type f | wc -l'
docker-compose exec vicar-toolkit bash -c 'find $VISOR_SAMPLES -type f | wc -l'
```

**Expected Output:**
- V2TOP=/usr/local/vicar/dev
- 1,461 calibration files
- 249 sample files

---

## Step 9: Interactive Shell

Enter the container for interactive work:

```bash
# Start interactive shell
docker-compose exec vicar-toolkit bash

# Now you're inside the container - run commands directly:
cd /workspace
gen interactive.vic 256 256
label interactive.vic
vicario interactive.vic interactive.png
ls -lh

# Exit when done
exit

# Files persist on host
ls -lh workspace/interactive.*
```

---

## Step 10: Advanced - Shell Aliases (Optional)

Create shell aliases for a more native feel:

```bash
# Add to your ~/.bashrc or ~/.zshrc
alias vicar='docker-compose -f /path/to/vicar-native-toolkit/docker-compose.yml exec vicar-toolkit'

# Now you can run:
vicar gen myimage.vic 512 512
vicar label myimage.vic
vicar vicario myimage.vic myimage.png
```

Or create a helper script:

```bash
# Create ~/bin/vicar-run.sh
cat > ~/bin/vicar-run.sh << 'EOF'
#!/bin/bash
cd /path/to/vicar-native-toolkit
docker-compose exec vicar-toolkit "$@"
EOF

chmod +x ~/bin/vicar-run.sh

# Use it:
~/bin/vicar-run.sh gen test.vic 512 512
~/bin/vicar-run.sh label test.vic
```

---

## Cleanup

### Stop but Keep Container

Keep the container around for fast restart:

```bash
# Stop container (preserves state)
docker-compose stop

# Restart later (very fast)
docker-compose start

# Check status
docker-compose ps
```

### Complete Removal

Remove container completely:

```bash
# Stop and remove container
docker-compose down

# Verify removal
docker-compose ps

# Files in workspace/ persist even after container removal!
ls -lh workspace/
```

---

## Comparison: docker-compose vs Direct Docker

### docker-compose Advantages

✅ **Simpler commands**: `docker-compose exec vicar-toolkit gen ...` vs `docker exec vicar-demo gen ...`  
✅ **Configuration file**: All settings in docker-compose.yml  
✅ **Service management**: Easy start/stop/restart  
✅ **Network management**: Automatic network creation  
✅ **Multi-container support**: Can add more services later  
✅ **Environment variables**: Centralized in docker-compose.yml  

### Direct Docker Advantages

✅ **No extra config**: Works with any image immediately  
✅ **Simpler for one-off tasks**: `docker run --rm` for quick tests  
✅ **Lower overhead**: No docker-compose installation needed  

---

## Creating Shell Wrapper Functions (Advanced)

For the most native-like experience, add wrapper functions to your shell:

```bash
# Add to ~/.bashrc or ~/.zshrc
export VICAR_TOOLKIT_DIR="/path/to/tig/vicar-native-toolkit"

vicar() {
    docker-compose -f "$VICAR_TOOLKIT_DIR/docker-compose.yml" exec vicar-toolkit "$@"
}

vicar-shell() {
    docker-compose -f "$VICAR_TOOLKIT_DIR/docker-compose.yml" exec vicar-toolkit bash
}

vicar-up() {
    docker-compose -f "$VICAR_TOOLKIT_DIR/docker-compose.yml" up -d
}

vicar-down() {
    docker-compose -f "$VICAR_TOOLKIT_DIR/docker-compose.yml" down
}

# Reload shell
source ~/.bashrc  # or source ~/.zshrc

# Now use like native commands:
vicar-up
vicar gen test.vic 512 512
vicar label test.vic
vicar-shell
```

---

## Workspace Organization Tips

```bash
# Organize workspace by project
workspace/
├── project1/
│   ├── inputs/
│   └── outputs/
├── project2/
└── scratch/

# Use project directories in commands
docker-compose exec vicar-toolkit bash -c 'cd /workspace/project1 && gen input.vic 512 512'
```

---

## Summary

### What You Learned

✅ Start/stop the toolkit with docker-compose  
✅ Run VICAR commands via `docker-compose exec`  
✅ Access files seamlessly between container and host  
✅ Use interactive shell for exploratory work  
✅ Create shell aliases for native-like experience  

### Key Benefits Over Direct Docker

1. **Persistent container**: Fast command execution (no startup overhead)
2. **Configuration management**: Settings in docker-compose.yml
3. **Easy service management**: `docker-compose up/down/restart`
4. **Workspace mounting**: Automatic file synchronization
5. **Extensible**: Easy to add more services (databases, web servers, etc.)

---

## Troubleshooting

### Container not starting

```bash
# Check logs
docker-compose logs

# Remove and recreate
docker-compose down
docker-compose up -d
```

### Permission errors on workspace files

```bash
# Check workspace permissions
ls -la workspace/

# Fix permissions (Linux)
sudo chown -R $USER:$USER workspace/

# SELinux systems - add :Z flag in docker-compose.yml
# volumes:
#   - ./workspace:/workspace:Z
```

### Commands not found

```bash
# Verify container is running
docker-compose ps

# Check image
docker-compose config | grep image

# Verify PATH in container
docker-compose exec vicar-toolkit bash -c 'echo $PATH'
```

### Files not appearing on host

```bash
# Check volume mount
docker-compose exec vicar-toolkit ls -la /workspace

# Verify docker-compose.yml has workspace mount
grep -A5 "volumes:" docker-compose.yml

# Restart with recreate
docker-compose down
docker-compose up -d
```

---

## Time Estimate

- Initial setup: 2-3 minutes
- Demo execution: 5-10 minutes
- **Total: 7-13 minutes**

---

## Next Steps

- **Explore direnv integration**: See [README.md](./README.md) for automatic environment activation
- **Learn more commands**: See [QUICKREF.md](./QUICKREF.md) for VICAR command reference
- **Advanced workflows**: See [VICAR_NATIVE_TOOLKIT_WALKTHROUGH.md](./VICAR_NATIVE_TOOLKIT_WALKTHROUGH.md)
- **Direct Docker approach**: See [../DEMO_COMMANDS.md](../DEMO_COMMANDS.md)
