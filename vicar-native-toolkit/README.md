# VICAR Native Toolkit

Make 540+ VICAR CLI programs living inside a Docker container feel like native commands on your host machine. When you activate the environment, the container starts, directories mount, X11 routing is established, and every command "just works" as if installed locally.

**Works on both Linux (bash) and macOS (zsh), including Apple Silicon (M1/M2).**

## Distribution Options

This toolkit provides multiple ways to run VICAR:

- **Open Source Build** (Recommended for public use) - Builds VICAR from the public GitHub repository. See [OPENSOURCE-BUILD.md](docs/OPENSOURCE-BUILD.md) for details.
- **Local Binaries** - Uses locally compiled VICAR binaries

For most users, the **open-source build** is recommended. It requires no special access and builds directly from the [NASA-AMMOS/VICAR](https://github.com/NASA-AMMOS/VICAR) repository.

## Architecture

This project implements the docker-native-wrapper pattern using:

- **direnv** - Automatic environment activation when entering/leaving directories
- **Long-running container** - Fast `docker exec` calls (not slow `docker run` per command)
- **Universal wrapper** - Single `vicar-exec` script handles all VICAR commands via symlinks
- **Cross-platform X11** - Unix sockets on Linux, XQuartz TCP on macOS
- **Smart bind-mounts** - Single workspace mount with intelligent CWD resolution

### Wrapper Architecture

Instead of generating 540+ individual wrapper scripts, the toolkit uses a symlink-based approach:

1. **Single wrapper script** (`vicar-exec`) - Handles all VICAR commands
2. **Command detection** - Auto-discovers available commands from container
3. **Symlink generation** - Creates symlinks pointing to `vicar-exec` for each command
4. **Dynamic routing** - `vicar-exec` determines which command to run based on symlink name

**Benefits:**
- Faster activation (~1 second vs 3-5 seconds)
- Reduced disk usage (~2MB vs 3.5MB)
- Single point of maintenance
- Identical functionality

### Performance

- **Command latency**: ~50-100ms on Linux, ~80-150ms on macOS
- **vs. docker run**: 10-30x faster than per-command containers
- **vs. native**: Slight overhead, but allows consistent environment across platforms

**macOS Apple Silicon:**
The published image is `linux/amd64` only, so on M1/M2/M3 Macs the container runs under Docker's emulation. The toolkit forces `--platform linux/amd64` automatically, so no manual configuration is needed.

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

### Automated Bootstrap (Recommended)

The easiest way to get started:

```bash
cd vicar-native-toolkit
make bootstrap
```

This single target:
- ✓ Checks prerequisites (Docker, direnv)
- ✓ Pulls the open-source VICAR container image
- ✓ Creates configuration files
- ✓ Activates the toolkit environment

**With MARS calibration:**
```bash
make bootstrap MARS_CALIB=/path/to/mars_calibration
```

**With custom image:**
```bash
make bootstrap IMAGE=myregistry/vicar:custom
```

See `make help` for all targets and variables.

### Manual Setup (Advanced)

If you prefer manual setup or need to build a custom image:

#### 1. One-Time System Setup

##### macOS
```bash
cd vicar-native-toolkit
chmod +x scripts/setup-macos.sh
./scripts/setup-macos.sh
```

**Important for macOS:**
- If XQuartz was just installed, **you must reboot** before proceeding
- After reboot, start XQuartz and keep it running
- The first time you use X11 apps, macOS may prompt for accessibility permissions

##### Linux
```bash
cd vicar-native-toolkit
chmod +x scripts/setup-linux.sh
./scripts/setup-linux.sh
```

**Note:** If Docker was just installed, log out and log back in for group permissions to take effect.

#### 2. Build the Docker Image (Optional)

If using a custom build instead of the open-source image:

```bash
chmod +x scripts/build-opensource-image.sh
./scripts/build-opensource-image.sh
```

This creates the `vicar-native-toolkit:opensource` image with all dependencies installed.

#### 3. Activate the Toolkit

```bash
cd vicar-native-toolkit
direnv allow
```

The first time you `cd` into the directory:
- direnv loads the `.envrc` configuration
- The Docker container starts automatically
- Wrapper scripts are generated dynamically and added to your PATH
- X11 forwarding is configured for your platform

### 4. Use VICAR Tools

```bash
# All VICAR commands now work as if native
vicar input.img output.img
vicario image.vic image.png   # Java-based image converter
label myfile.vic
gen out.img 512 512

# Mars processing tools
marsmap input.img output.map
marsmos *.img output.mosaic

# Utility commands
toolkit-shell     # Open interactive shell in container
toolkit-status    # Show container status and wrapper count
toolkit-stop      # Stop and remove container
toolkit-restart   # Restart container (useful after config changes)
toolkit-update    # Pull the latest CONTAINER_IMAGE and recreate the container
toolkit-verify-calib  # Verify MARS calibration mounting (if configured)
```

**Note:** All VICAR commands execute via a single universal wrapper (`vicar-exec`) with symlinks, reducing overhead and simplifying maintenance.

### 5. Deactivate

```bash
cd ..    # Leave the directory - wrappers automatically disappear from PATH
```

The container keeps running in the background. Re-entering the directory makes the tools available again instantly.

## Project Structure

```
vicar-native-toolkit/
├── .envrc                      # direnv config (auto-activates environment)
├── .envrc.local                # User configuration (gitignored, created by `make config`)
├── Makefile                    # Setup automation (make bootstrap / config / pull / ...)
├── docker-compose.yml          # Alternative container management
├── scripts/
│   ├── setup-macos.sh          # macOS dependency installer
│   ├── setup-linux.sh          # Linux dependency installer
│   └── build-opensource-image.sh # Docker image builder
├── workspace/                  # Your working directory (mounted to /workspace)
└── .direnv/                    # Auto-generated (gitignored)
    ├── vicar-exec              # Universal command wrapper (generated)
    ├── toolkit-utils           # Utility commands handler (generated)
    └── wrappers/               # Symlinks to vicar-exec
```

## How It Works

### Environment Activation Flow

1. You `cd` into `vicar-native-toolkit/`
2. direnv detects `.envrc` and asks for permission (first time only)
3. `.envrc` runs:
   - Loads configuration from `.envrc.local` (if exists)
   - Detects your platform (Linux/macOS)
   - Checks if Docker image exists
   - Starts the container (or uses existing one)
   - Configures X11 forwarding for your platform
   - Generates `vicar-exec` and `toolkit-utils` scripts
   - Auto-discovers available VICAR commands
   - Creates symlinks for each command in `.direnv/wrappers/`
   - Adds `.direnv/wrappers/` to your PATH
4. All VICAR commands are now available

### Command Execution Flow

1. You run `vicar input.img output.img`
2. The symlink at `.direnv/wrappers/vicar` points to `vicar-exec`
3. `vicar-exec` detects the command name from `$0` (basename)
4. It resolves your current directory relative to the workspace
5. It runs `docker exec -w /workspace/<rel-path> vicar-sidecar vicar input.img output.img`
6. The command runs inside the container with correct working directory
7. Output appears in your terminal as if it were a native command

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

Configuration is managed through `.envrc.local` (created by `make config` or manually).

### Using the Makefile

The easiest way to configure:

```bash
# Default configuration (no image pull)
make config

# Custom image
make config IMAGE=myregistry/vicar:v2.0

# With MARS calibration
make config MARS_CALIB=/data/mars_calibration

# Custom container name
make config CONTAINER=my-vicar-container

# Disable SELinux labeling (Linux; needed by some images)
make config IMAGE=myregistry/vicar:v2.0 \
            MARS_CALIB=/data/mars_calibration DISABLE_SELINUX=1
```

### Manual Configuration

Create `.envrc.local` with your settings:

```bash
# Container settings
CONTAINER_NAME="vicar-sidecar"
CONTAINER_IMAGE="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"

# MARS calibration (optional)
MARS_CONFIG_PATH="/path/to/mars_calibration"
```

After creating/editing `.envrc.local`:

```bash
direnv allow          # Reload configuration
toolkit-restart       # Restart container with new settings
```

### Available Configuration Options

See [CONFIGURATION.md](docs/CONFIGURATION.md) for detailed options including:
- Custom container images
- Workspace location
- Additional volume mounts
- Manual tool lists (disable auto-discovery)
- Advanced Docker options

### Mounting Calibration Data

For MARS processing tools (marsmap, marsmos, etc.), mount calibration files:

```bash
# Set environment variable
export MARS_CONFIG_PATH="/path/to/mars_calibration"

# Restart container
cd vicar-native-toolkit
toolkit-restart

# Verify calibration mounted
toolkit-verify-calib
```

See [MOUNTING-DATA.md](docs/MOUNTING-DATA.md) for detailed configuration options.

## Troubleshooting

### "Docker image not found"

```bash
./scripts/build-opensource-image.sh
```

### "Container vicar-sidecar is not running"

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

To customize the VICAR build, edit the image Dockerfile at `../terrain-intelligence-generator/docker/Dockerfile` and rebuild:

```bash
./scripts/build-opensource-image.sh
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

Apache License 2.0. See the [LICENSE](../LICENSE) file at the repository root.

## Credits

Architecture based on the docker-native-wrapper pattern (long-running sidecar container + symlinked universal `vicar-exec` wrapper).

## Support

For issues:
1. Check the Troubleshooting section above
2. Verify Docker and direnv are properly installed
3. Check container logs: `docker logs vicar-sidecar`
4. Open an issue with platform details (OS, Docker version, error messages)

---

**Happy VICAR processing!**
