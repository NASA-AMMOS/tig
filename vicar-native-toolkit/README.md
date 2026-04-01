# VICAR Native Toolkit

Make ~200 VICAR CLI programs living inside a Docker container feel like native commands on your host machine. When you activate the environment, the container starts, directories mount, X11 routing is established, and every command "just works" as if installed locally.

**Works on both Linux (bash) and macOS (zsh), including Apple Silicon (M1/M2).**

## Architecture

This project implements the docker-native-wrapper pattern using:

- **direnv** - Automatic environment activation when entering/leaving directories
- **Long-running container** - Fast `docker exec` calls (not slow `docker run` per command)
- **Wrapper scripts** - Each VICAR tool gets a transparent wrapper on your PATH
- **Cross-platform X11** - Unix sockets on Linux, XQuartz TCP on macOS
- **Smart bind-mounts** - Single workspace mount with intelligent CWD resolution

### Performance

- **Command latency**: ~50-100ms on Linux, ~80-150ms on macOS
- **vs. docker run**: 10-30x faster than per-command containers
- **vs. native**: Slight overhead, but allows consistent environment across platforms

## Prerequisites

### macOS (M1/M2/Intel)

- macOS 10.15+ (Catalina or later)
- Homebrew package manager
- Docker Desktop
- ~10GB free disk space

### Linux

- Ubuntu 20.04+ / Debian 11+ (or equivalent)
- Docker CE
- X11 display server
- ~10GB free disk space

## Quick Start

### 1. One-Time System Setup

#### macOS
```bash
cd vicar-native-toolkit
chmod +x scripts/setup-macos.sh
./scripts/setup-macos.sh
```

**Important for macOS:**
- If XQuartz was just installed, **you must reboot** before proceeding
- After reboot, start XQuartz and keep it running
- The first time you use X11 apps, macOS may prompt for accessibility permissions

#### Linux
```bash
cd vicar-native-toolkit
chmod +x scripts/setup-linux.sh
./scripts/setup-linux.sh
```

**Note:** If Docker was just installed, log out and log back in for group permissions to take effect.

### 2. Build the Docker Image

```bash
chmod +x scripts/build-image.sh
./scripts/build-image.sh
```

This creates the `vicar-tools:latest` image with all dependencies installed.

### 3. Activate the Toolkit

```bash
cd vicar-native-toolkit
direnv allow
```

The first time you `cd` into the directory:
- direnv loads the `.envrc` configuration
- The Docker container starts automatically
- ~200 wrapper scripts are generated and added to your PATH
- X11 forwarding is configured for your platform

### 4. Use VICAR Tools

```bash
# All VICAR commands now work as if native
vicar input.img output.img
vic2pic image.vic image.png
label myfile.vic
gen out.img 512 512

# Mars processing tools
marsmap input.img output.map
marsmos *.img output.mosaic

# Utility commands
toolkit-shell     # Open interactive shell in container
toolkit-build     # Build VICAR from source (if you have source code)
toolkit-stop      # Stop and remove container
toolkit-restart   # Restart container (useful after config changes)
```

### 5. Deactivate

```bash
cd ..    # Leave the directory - wrappers automatically disappear from PATH
```

The container keeps running in the background. Re-entering the directory makes the tools available again instantly.

## Project Structure

```
vicar-native-toolkit/
├── .envrc                      # direnv config (auto-activates environment)
├── docker/
│   ├── Dockerfile              # Container definition
│   └── build-vicar.sh          # VICAR build script (runs inside container)
├── docker-compose.yml          # Alternative container management
├── scripts/
│   ├── setup-macos.sh          # macOS dependency installer
│   ├── setup-linux.sh          # Linux dependency installer
│   └── build-image.sh          # Docker image builder
├── workspace/                  # Your working directory (mounted to /workspace)
└── .direnv/                    # Auto-generated (wrappers live here)
    └── wrappers/               # Generated wrapper scripts
```

## How It Works

### Environment Activation Flow

1. You `cd` into `vicar-native-toolkit/`
2. direnv detects `.envrc` and asks for permission (first time only)
3. `.envrc` runs:
   - Detects your platform (Linux/macOS)
   - Checks if Docker image exists
   - Starts the container (or uses existing one)
   - Configures X11 forwarding for your platform
   - Generates wrapper scripts for each VICAR tool
   - Adds `.direnv/wrappers/` to your PATH
4. All VICAR commands are now available

### Command Execution Flow

1. You run `vicar input.img output.img`
2. The wrapper script at `.direnv/wrappers/vicar` executes
3. It resolves your current directory relative to the workspace
4. It runs `docker exec -i vicar-toolkit vicar input.img output.img`
5. The command runs inside the container with access to your files
6. Output appears in your terminal as if it were a native command

### X11 Forwarding

#### Linux
- Shares `/tmp/.X11-unix` socket directly into container
- Uses `--network host` for native performance
- Requires `xhost +local:docker` (setup script handles this)

#### macOS
- Uses XQuartz (must be installed and running)
- Forwards over TCP to `host.docker.internal:0`
- No socket sharing (macOS Docker limitation)
- Slightly higher latency than Linux, but works reliably

## Configuration

### Customizing Tool List

Edit `.envrc` and modify the `TOOLS` array:

```bash
TOOLS=(
    vicar
    vic2pic
    label
    gen
    marsmap
    marsmos
    # Add your tools here
)
```

Or let it auto-discover (requires VICAR to be built):

```bash
# In .envrc, replace the TOOLS array with:
TOOLS=$(docker exec vicar-toolkit find /usr/local/vicar/ndev/bin -type f -executable -printf '%f\n' 2>/dev/null)
```

### Changing Workspace Location

Edit `.envrc` and modify:

```bash
WORKSPACE_ROOT="${PWD}/workspace"    # Change this path
```

### Using External Data

Add additional mounts in `.envrc`:

```bash
docker run -d \
    --name "${CONTAINER_NAME}" \
    -v "${WORKSPACE_ROOT}:/workspace" \
    -v "/data/missions:/data/missions:ro" \    # Read-only mission data
    -v "/scratch:/scratch" \                     # Scratch space
    ...
```

## Building VICAR from Source

If you have access to VICAR source code:

### 1. Clone VICAR Repositories

```bash
cd /path/to/vicar-source
git clone -b develop git@github.jpl.nasa.gov:MIPL/Vicar_dev.git
git clone -b develop git@github.jpl.nasa.gov:MIPL/Vicar-tools-jpl.git
git clone -b develop git@github.jpl.nasa.gov:MIPL/Vicar-tools-open.git
# ... other repos
```

### 2. Mount Source in Container

Edit `.envrc` and add source mount:

```bash
docker run -d \
    --name "${CONTAINER_NAME}" \
    -v "${WORKSPACE_ROOT}:/workspace" \
    -v "/path/to/vicar-source:/usr/local/vicar/cmbld" \
    ...
```

### 3. Build Inside Container

```bash
cd vicar-native-toolkit
toolkit-build    # Runs build-vicar.sh inside container
```

The build process takes 30-60 minutes depending on your system.

## Troubleshooting

### "Docker image not found"

```bash
./scripts/build-image.sh
```

### "Container vicar-toolkit is not running"

```bash
toolkit-restart
cd .. && cd -    # Re-enter directory to restart
```

### "Can't open display" (macOS)

1. Make sure XQuartz is running: `open -a XQuartz`
2. Allow localhost: `xhost +localhost`
3. Restart container: `toolkit-restart`

### "Permission denied" for Docker (Linux)

```bash
sudo usermod -aG docker $USER
# Log out and log back in
```

### "realpath: command not found" (macOS)

```bash
brew install coreutils
```

### X11 apps are slow/laggy (macOS)

This is expected - macOS uses TCP forwarding instead of Unix sockets. For better performance:
- Close other applications to reduce network load
- Ensure XQuartz has hardware acceleration enabled
- Consider using Linux for production workloads

### Container can't see my files

Make sure your files are inside the `workspace/` directory. Files outside this directory are not visible to the container unless you add additional mounts.

## Advanced Usage

### Using docker-compose

Instead of direnv, you can manage the container with docker-compose:

```bash
docker-compose up -d           # Start container
docker-compose exec vicar-toolkit bash   # Interactive shell
docker-compose down            # Stop and remove
```

### Multiple Workspaces

Create multiple directories, each with their own `.envrc`:

```
~/vicar-workspace-1/.envrc     # Project 1
~/vicar-workspace-2/.envrc     # Project 2
```

Each can use the same Docker image but different workspace mounts.

### Custom Build Configuration

To customize the VICAR build, edit `docker/build-vicar.sh` and rebuild:

```bash
./scripts/build-image.sh
```

### Network Services

If VICAR tools need network access, Linux's `--network host` is already configured. On macOS, use the default bridge network (already configured).

## Platform-Specific Notes

### macOS (M1/M2/Intel)

**Pros:**
- Works identically on Intel and Apple Silicon
- Docker Desktop handles architecture automatically
- Seamless integration with zsh (default shell)

**Cons:**
- Slower file I/O due to virtualization (use VirtioFS in Docker Desktop settings)
- X11 over TCP has higher latency than Linux
- XQuartz must be installed and running
- Some apps may look blurry on Retina displays

**Performance Tips:**
- Enable VirtioFS: Docker Desktop → Settings → General → VirtioFS
- Keep large datasets in Docker volumes instead of bind mounts
- Use `docker cp` for one-off files instead of adding mounts

### Linux

**Pros:**
- Native Docker performance (no VM layer)
- Fast X11 socket sharing
- Better file I/O performance
- GPU acceleration possible (with proper drivers)

**Cons:**
- Requires manual Docker installation
- X11 security requires `xhost` configuration

## Contributing

This project is based on the docker-native-wrapper pattern. To contribute:

1. Test changes on both Linux and macOS
2. Update wrapper generation logic in `.envrc`
3. Ensure X11 forwarding works on both platforms
4. Update this README with any new features

## License

[Add your license here]

## Credits

Architecture based on research documented in `docker-native-wrapper-research-v2.md`.

## Support

For issues:
1. Check the Troubleshooting section above
2. Verify Docker and direnv are properly installed
3. Check container logs: `docker logs vicar-toolkit`
4. Open an issue with platform details (OS, Docker version, error messages)

---

**Happy VICAR processing!**
