"""Container specification: everything that decides how a container is run.

Runtime-agnostic and dependency-free, so the warm path (:mod:`tig_cli.fast`)
can work out which container to use without importing anything expensive.
:mod:`tig_cli.container` builds on the same functions, so both paths always
derive the same container name from the same inputs.
"""
from __future__ import annotations

import hashlib
import json
import os
import signal
import stat
import sys
from pathlib import Path
from .config import (
    Config,
    env_disable_path_translation,
    env_selinux_label_disable,
    env_writable_paths,
)

DEFAULT_IMAGE = "ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"

# The VICAR image is published for linux/amd64 only; force that platform so
# pulls and runs succeed on arm64 hosts (via emulation). No-op on amd64.
IMAGE_PLATFORM = "linux/amd64"

CONTAINER_PREFIX = "tig-vicar"

# Written when a locally built program is recorded, and the per-container-name
# markers saying which containers carry the current recording.
BUILDS_RECORDED_FILE = "recorded"
BUILDS_NAMES_DIR = "names"

# Marks the processes of one invocation, so a signal can reach them inside the
# shared container. Every descendant inherits it.
EXEC_ID_ENV = "TIG_EXEC_ID"


def kill_tree_command(exec_id: str, signum: int) -> str:
    """Shell command signalling one invocation's processes in a container.

    /proc is the only way in: the exec id is in the environment of the tool
    and of everything it started.
    """
    return (
        "for p in /proc/[0-9]*; do "
        f'grep -qz {EXEC_ID_ENV}={exec_id} "$p/environ" 2>/dev/null '
        f'&& kill -{signum} "${{p#/proc/}}" 2>/dev/null; done'
    )


class forwarded_signals:
    """Pass interrupts on to a command running in the container.

    Without this the caller would simply exit, leaving the tool running in a
    container that outlives it.
    """

    # SIGHUP too: closing the terminal must not leave the tool running.
    HANDLED = tuple(
        getattr(signal, name)
        for name in ("SIGINT", "SIGTERM", "SIGHUP")
        if hasattr(signal, name)
    )

    def __init__(self, forward):
        self.forward = forward
        self.previous: dict[int, object] = {}

    def __enter__(self) -> "forwarded_signals":
        for signum in self.HANDLED:
            try:
                self.previous[signum] = signal.signal(
                    signum, lambda number, frame: self.forward(number)
                )
            except (ValueError, OSError):
                pass
        return self

    def __exit__(self, *exc_info) -> bool:
        for signum, handler in self.previous.items():
            try:
                signal.signal(signum, handler)
            except (ValueError, OSError):
                pass
        return False


# Last argument of the dispatcher's and the agent's exec, marking them as
# tig's own: they run for as long as the container does, so reaping must not
# mistake them for a command someone is waiting on.
RUNNER_MARKER = "tig-runner"

# Directory of claim files (one per invocation) naming the container each live
# tig process is using, so reaping never removes a container out from under a
# concurrent invocation. Per-boot state: stale claims are ignored by PID.
CLAIM_DIR_NAME = "tig-claims"

# How long to wait for XQuartz to come up on macOS before giving up.
XQUARTZ_START_TIMEOUT = 5.0

# Names the X server that was authorized last, so a command pays for xhost
# only when the server it has to reach is not that one any more.
X11_MARKER = "x11-authorized"

# Set to leave the host display alone entirely.
DISABLE_X11_ENV = "TIG_NO_X11"

# Where calibration files (VISOR / mars_calibration_*) are mounted, matching
# the layout VICAR's MARS programs expect.
CALIBRATION_MOUNT = "/usr/local/vicar/mars_calib"

SELINUX_ENFORCE_PATH = "/sys/fs/selinux/enforce"

# Names by which a container reaches the host it runs on, when the runtime puts
# it in a virtual machine of its own (Docker Desktop, podman machine).
HOST_GATEWAY = {
    "podman": "host.containers.internal",
    # Both run their containers in a Lima virtual machine on macOS.
    "finch": "host.lima.internal",
    "nerdctl": "host.lima.internal",
}
DEFAULT_HOST_GATEWAY = "host.docker.internal"


class TigError(Exception):
    """User-facing error; reported without a traceback."""


def rootless_podman(runtime: str) -> bool:
    """Whether this is Podman running as the invoking user rather than root.

    Docker's client talks to a daemon, so what the invoking user is says
    nothing about how the container runs.
    """
    return runtime == "podman" and os.geteuid() != 0


def host_gateway(runtime: str = "docker") -> str:
    """The name a container of this runtime reaches the host by."""
    return HOST_GATEWAY.get(runtime, DEFAULT_HOST_GATEWAY)


def get_container_image(config: Config | None = None) -> str:
    """Return the container image to use for VICAR execution.

    Precedence: CONTAINER_IMAGE environment variable, then the ``image`` key
    from the configuration files, then the opensource image.
    """
    from_env = os.environ.get("CONTAINER_IMAGE")
    if from_env:
        return from_env
    if config is not None and config.image:
        return config.image
    return DEFAULT_IMAGE


def get_calibration_path(config: Config | None = None) -> str | None:
    """Return the host path holding MARS/VISOR calibration files, if any.

    Precedence: MARS_CONFIG_PATH (the same variable the toolkit used), then the
    ``calibration_path`` key from the configuration files.
    """
    from_env = os.environ.get("MARS_CONFIG_PATH")
    if from_env:
        return os.path.expanduser(from_env)
    if config is not None and config.calibration_path:
        return config.calibration_path
    return None


def resolve_writable_paths(
    config: Config, option: list[str] | None = None
) -> list[str]:
    """Extra read-write mounts, from the command line, environment or config."""
    if option:
        return list(option)
    from_env = env_writable_paths()
    if from_env is not None:
        return from_env
    return list(config.writable_paths)


def resolve_disable_path_translation(config: Config, flag: bool = False) -> bool:
    """Whether host paths are passed through untranslated."""
    if flag:
        return True
    override = env_disable_path_translation()
    if override is None:
        override = config.disable_path_translation
    return bool(override)


def resolve_selinux_label_disable(
    config: Config, flag: bool | None = None
) -> bool | None:
    """Whether to run with ``label=disable``; ``None`` means decide by host."""
    if flag is not None:
        return flag
    from_env = env_selinux_label_disable()
    if from_env is not None:
        return from_env
    return config.selinux_label_disable


def _run_quietly(command: list[str], timeout: float = 10.0) -> bool:
    """Run a host helper command, discarding output; True if it succeeded."""
    import subprocess

    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return completed.returncode == 0


def _output_of(command: list[str], timeout: float = 10.0) -> str | None:
    """Run a host helper command; its output, or None if it failed."""
    import subprocess

    try:
        completed = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout


def selinux_enforcing() -> bool:
    """Whether this host is Linux with SELinux in Enforcing mode.

    The kernel state is read first: it answers for every host that has
    SELinux compiled in, and costs a file read rather than a process spawn.
    """
    if not sys.platform.startswith("linux"):
        return False

    try:
        return Path(SELINUX_ENFORCE_PATH).read_text().strip() == "1"
    except OSError:
        pass

    import shutil
    import subprocess

    getenforce = shutil.which("getenforce")
    if getenforce is None:
        return False
    try:
        completed = subprocess.run(
            [getenforce], capture_output=True, text=True, timeout=10.0
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return completed.returncode == 0 and completed.stdout.strip() == "Enforcing"


def _tcp_refused() -> bool:
    """Whether XQuartz is set to refuse the TCP connections tig needs."""
    value = _output_of(["defaults", "read", "org.xquartz.X11", "nolisten_tcp"])
    return value is None or value.strip().lower() not in ("0", "false", "no")


def _allow_tcp_connections() -> None:
    """Have XQuartz listen on TCP, which the container's DISPLAY needs.

    The preference is only read at startup, so a running XQuartz that still
    refuses TCP - how it comes out of an update that reset the preference -
    is reported rather than quit out from under the user's other clients.
    """
    if not _tcp_refused():
        return
    _run_quietly(
        ["defaults", "write", "org.xquartz.X11", "nolisten_tcp", "-bool", "false"]
    )
    if _run_quietly(["pgrep", "-x", "Xquartz"]):
        print(
            "tig: XQuartz is running with TCP connections turned off, which "
            "GUI tools in the container need. Quit XQuartz and run the "
            "command again.",
            file=sys.stderr,
        )


def _ensure_xquartz() -> None:
    """Make XQuartz running and listening on TCP, as the container needs."""
    import time

    _allow_tcp_connections()
    if _run_quietly(["pgrep", "-x", "Xquartz"]):
        return
    if not _run_quietly(["open", "-a", "XQuartz"]):
        return
    deadline = time.monotonic() + XQUARTZ_START_TIMEOUT
    while time.monotonic() < deadline:
        if _run_quietly(["pgrep", "-x", "Xquartz"]):
            return
        time.sleep(0.5)


def _x_socket(display: str) -> str | None:
    """The socket file a local ``display`` names, if it is a local one."""
    host, separator, number = display.rpartition(":")
    if not separator or host not in ("", "unix") or not number:
        return None
    return f"/tmp/.X11-unix/X{number.split('.')[0]}"


def x_server_identity() -> str | None:
    """Something that differs whenever the X server is a different one.

    Recognizing the server is what lets the expensive XQuartz checks be
    skipped while it stays the same. ``None`` means no server was
    recognized, and the caller should do the work rather than assume.
    """
    display = os.environ.get("DISPLAY", "")
    if sys.platform == "darwin":
        # The process, since the socket DISPLAY names belongs to launchd and
        # outlives any one XQuartz.
        running = _output_of(["pgrep", "-x", "Xquartz"]) or ""
        pids = running.split()
        return f"{display} xquartz={pids[0]}" if pids else None

    socket = _x_socket(display)
    if socket is None:
        # A display reached over the network: nothing local says whether it
        # is still the server that was authorized.
        return None
    try:
        info = os.stat(socket)
    except OSError:
        return None
    return f"{display} socket={info.st_ino}:{int(info.st_mtime)}"


def _x11_marker() -> Path:
    return Path(home_directory()) / ".cache" / "tig" / X11_MARKER


def _authorized_server() -> str | None:
    """The server the last authorization was for, if it is still recorded."""
    try:
        return _x11_marker().read_text()
    except OSError:
        return None


def _record_authorized_server(identity: str) -> None:
    marker = _x11_marker()
    try:
        marker.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        marker.write_text(identity)
    except OSError:
        pass


def ensure_x11_ready() -> None:
    """Authorize the host X server so GUI tools (xvd, marsmap) can connect.

    Done before every command rather than only when a container is created:
    the authorization is the X server's own state, which the container
    outlives, so anything that drops it - a restart after an XQuartz update,
    a logout, an ``xhost -`` - leaves the container unable to connect. That
    is what has users running ``xhost`` by hand. ``xhost`` is idempotent and
    costs milliseconds, so it is simply repeated; only the pricier XQuartz
    checks are skipped while the server is the one already seen.

    Silently does nothing when there is no display or no ``xhost``; those
    hosts simply have no GUI to authorize.
    """
    import shutil

    if os.environ.get(DISABLE_X11_ENV):
        return
    if not os.environ.get("DISPLAY") or shutil.which("xhost") is None:
        return

    identity = x_server_identity()
    if sys.platform == "darwin":
        if identity is None or identity != _authorized_server():
            # The container reaches XQuartz over TCP via the host gateway
            # name, so XQuartz has to be up and listening on it.
            _ensure_xquartz()
            # Asked again, since XQuartz may have only just been started.
            identity = x_server_identity()
        # The address explicitly as well as the name: the connection arrives
        # from the runtime's gateway on IPv4 loopback however localhost
        # happens to resolve.
        authorized = _run_quietly(["xhost", "+localhost", "+inet:127.0.0.1"])
    else:
        # The broad form is deliberate: with 'label=disable' the container
        # connects as the LOCAL: family, which '+local:docker' misses.
        authorized = _run_quietly(["xhost", "+local:"])

    if authorized and identity is not None:
        _record_authorized_server(identity)


def container_display(runtime: str = "docker") -> str:
    """The DISPLAY value a command should see inside the container."""
    if sys.platform == "darwin":
        return f"{host_gateway(runtime)}:0"
    return os.environ.get("DISPLAY", ":0")


def home_directory() -> str:
    """The invoking user's home directory, as mounted in the container."""
    return os.environ.get("HOME") or str(Path.home())


def resolve_calibration_path(path: str | None) -> str | None:
    """Validate and normalize a calibration directory path."""
    if path is None:
        return None
    if not os.path.isdir(path):
        raise TigError(f"Calibration path is not a directory: {path}")
    return str(Path(path).resolve())


class Mount:
    """One host path made visible in the container."""

    def __init__(self, source: str, target: str, read_only: bool = False):
        self.source = source
        self.target = target
        self.read_only = read_only

    @property
    def mode(self) -> str:
        return "ro" if self.read_only else "rw"

    @property
    def argument(self) -> str:
        """The mount as every runtime's ``--volume`` spells it."""
        return f"{self.source}:{self.target}:{self.mode}"

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Mount):
            return NotImplemented
        return self.argument == other.argument

    def __repr__(self) -> str:
        return f"Mount({self.argument!r})"


class RunSpec:
    """How the container is created, in runtime-neutral terms.

    Also what identifies it: the same specification always names the same
    container, so one is only ever reused when recreating it would produce
    the same thing.
    """

    def __init__(
        self,
        image: str,
        mounts: list[Mount],
        environment: dict[str, str],
        command: list[str],
        runtime: str = "docker",
        platform: str = IMAGE_PLATFORM,
        network: str | None = None,
        user: str | None = None,
        userns: str | None = None,
        group_add: list[str] | None = None,
        security_opt: list[str] | None = None,
    ):
        self.image = image
        self.mounts = mounts
        self.environment = environment
        self.command = command
        self.runtime = runtime
        self.platform = platform
        self.network = network
        self.user = user
        self.userns = userns
        self.group_add = group_add or []
        self.security_opt = security_opt or []

    def fields(self) -> dict[str, object]:
        """The specification as plain data, for the fingerprint and tests."""
        return {
            "image": self.image,
            # Sorted: the same mounts named in another order are the same
            # container, and the name must not depend on the order.
            "mounts": sorted(mount.argument for mount in self.mounts),
            "environment": dict(self.environment),
            "command": list(self.command),
            # Each runtime keeps its own containers: two of them must not
            # share a name, or a command would be run in the wrong one.
            "runtime": self.runtime,
            "platform": self.platform,
            "network": self.network,
            "user": self.user,
            "userns": self.userns,
            "group_add": list(self.group_add),
            "security_opt": list(self.security_opt),
        }

    def container_name(self) -> str:
        """A container name that identifies this configuration."""
        fingerprint = json.dumps(self.fields(), sort_keys=True)
        digest = hashlib.sha256(fingerprint.encode()).hexdigest()[:12]
        return f"{CONTAINER_PREFIX}-{digest}"

    def create_args(self, name: str) -> list[str]:
        """The runtime arguments that create and start this container."""
        args = [
            "run",
            "--detach",
            "--name", name,
            "--platform", self.platform,
        ]
        for mount in self.mounts:
            args += ["--volume", mount.argument]
        for key, value in sorted(self.environment.items()):
            args += ["--env", f"{key}={value}"]
        if self.network:
            args += ["--network", self.network]
        if self.user:
            args += ["--user", self.user]
        if self.userns:
            args += ["--userns", self.userns]
        for group in self.group_add:
            args += ["--group-add", group]
        for option in self.security_opt:
            args += ["--security-opt", option]
        return [*args, self.image, *self.command]

    def __repr__(self) -> str:
        return f"RunSpec({self.fields()!r})"


def build_mounts(
    home: str,
    writable_paths: list[str],
    calibration_path: str | None = None,
) -> list[Mount]:
    """Build the container's mounts.

    The host filesystem is mounted read-only at /host so tools can read
    inputs from anywhere. Locations the user is expected to write to - the
    home directory, the current directory and any --writable-path - are
    additionally mounted read-write.

    Args:
        home: The invoking user's home directory
        writable_paths: Additional paths to mount as read-write
        calibration_path: Host path with MARS/VISOR calibration files
    """
    mounts = {
        "/": Mount("/", "/host", read_only=True),
        home: Mount(home, home),
    }

    for path in [os.getcwd()] + list(writable_paths):
        if not os.path.isdir(path):
            continue
        resolved = str(Path(path).resolve())
        if Path(resolved).is_relative_to(home):
            continue
        mounts[resolved] = Mount(resolved, f"/host{resolved}")

    if calibration_path:
        mounts[calibration_path] = Mount(
            calibration_path, CALIBRATION_MOUNT, read_only=True
        )

    return list(mounts.values())


def build_run_spec(
    image: str,
    mounts: list[Mount],
    home: str,
    calibration_path: str | None = None,
    selinux_label_disable: bool = False,
    runtime: str = "docker",
) -> RunSpec:
    """Build the specification of the container to run."""
    environment = {"HOME": home}
    if calibration_path:
        environment["MARS_CONFIG_PATH"] = CALIBRATION_MOUNT

    spec = RunSpec(
        image=image,
        mounts=list(mounts),
        environment=environment,
        command=["tail", "-f", "/dev/null"],
        runtime=runtime,
    )

    if sys.platform != "darwin":
        spec.mounts.append(Mount("/tmp/.X11-unix", "/tmp/.X11-unix"))
        spec.network = "host"
        if rootless_podman(runtime):
            # Rootless Podman runs as the invoking user but maps it to a
            # subordinate uid inside; keep-id maps it to itself, so files it
            # writes to the mounts are owned by the user.
            spec.userns = "keep-id"
        else:
            # Run as the invoking user so output files are owned by them
            # rather than by root. Runtimes with a VM of their own map
            # ownership already.
            spec.user = f"{os.getuid()}:{os.getgid()}"
            spec.group_add = [str(os.getgid())]
        if selinux_label_disable:
            # SELinux Enforcing otherwise denies the container the bind
            # mounts and the X11 socket, and blocks the 32-bit legacy
            # libraries some VICAR tools load. Deliberately not ':z'/':Z'
            # relabeling, which must never touch the host-root mount.
            spec.security_opt = ["label=disable"]

    return spec


def build_state_root() -> Path:
    """Where programs built with ``--build`` are recorded, following XDG."""
    xdg = os.environ.get("XDG_DATA_HOME")
    base = (
        Path(xdg) if xdg else Path(os.environ.get("HOME") or Path.home()) / ".local/share"
    )
    return base / "tig" / "builds"


def container_carries_builds(container_name: str) -> bool:
    """Whether a container is known to hold the recorded built programs.

    Two stats, so the warm path can hand a container that still needs
    patching to the full path: the markers are dropped whenever a build is
    recorded or forgotten.
    """
    root = build_state_root()
    if not (root / BUILDS_RECORDED_FILE).is_file():
        return True
    return (root / BUILDS_NAMES_DIR / container_name).is_file()


class Claim:
    """This process's claim on a container, protecting it from reaping.

    Claimed before the container is created or adopted, so a container
    another invocation is still setting up is never seen as unused.
    """

    def __init__(self) -> None:
        self.path: Path | None = None

    @staticmethod
    def directory() -> Path:
        base = os.environ.get("XDG_RUNTIME_DIR")
        if not base:
            # Imported only here: the warm path almost always has a runtime
            # directory, and tempfile is comparatively slow to import.
            import tempfile

            base = tempfile.gettempdir()
        return Path(base) / f"{CLAIM_DIR_NAME}-{os.getuid()}"

    @classmethod
    def _private_directory(cls, create: bool) -> Path | None:
        """The claim directory, if it is safe to trust.

        The fallback base is shared and world-writable, so another user could
        have made the directory first, or a symlink in its place, to plant or
        delete claims. Only a real directory owned by this user and closed to
        everyone else is used.
        """
        directory = cls.directory()
        if create:
            try:
                directory.mkdir(mode=0o700, parents=True)
            except FileExistsError:
                pass
            except OSError:
                return None
        try:
            info = os.lstat(directory)
        except OSError:
            return None
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            return None
        if stat.S_IMODE(info.st_mode) & 0o077:
            try:
                os.chmod(directory, 0o700)
            except OSError:
                return None
        return directory

    def acquire(self, container_name: str) -> None:
        """Record that this process is about to use ``container_name``."""
        self.release()
        directory = self._private_directory(create=True)
        if directory is None:
            return
        claim = directory / f"{container_name}.{os.getpid()}"
        try:
            claim.touch()
        except OSError:
            # Unclaimable state directory: reaping then just keeps containers.
            return
        self.path = claim

    def release(self) -> None:
        """Drop this process's claim, making its container reapable again."""
        if self.path is None:
            return
        try:
            self.path.unlink()
        except OSError:
            pass
        self.path = None

    @classmethod
    def claimed_containers(cls) -> set:
        """Container names claimed by a still-running tig process.

        Claims left behind by a process that died are pruned as they are
        found.
        """
        claimed = set()
        directory = cls._private_directory(create=False)
        if directory is None:
            return claimed
        try:
            claims = list(directory.iterdir())
        except OSError:
            return claimed

        for claim in claims:
            name, _, pid = claim.name.rpartition(".")
            if not pid.isdigit():
                continue
            try:
                os.kill(int(pid), 0)
            except ProcessLookupError:
                try:
                    claim.unlink()
                except OSError:
                    pass
                continue
            except OSError:
                pass
            claimed.add(name)
        return claimed
