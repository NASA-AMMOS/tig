"""Tests for container management through a runtime's command line."""
import json
import os
import subprocess
from datetime import datetime, timezone
import pytest
from unittest.mock import Mock, patch, MagicMock
from tig_cli import spec
from tig_cli.config import Config
from tig_cli.container import (
    CALIBRATION_MOUNT,
    CONTAINER_PREFIX,
    ContainerManager,
    IMAGE_PLATFORM,
    MAX_KEPT_CONTAINERS,
    RUNNER_MARKER,
    TigError,
    ensure_x11_ready,
    get_calibration_path,
    get_container_image,
    selinux_enforcing,
    DEFAULT_IMAGE,
)
from tig_cli.engine import Engine, EngineError, EngineNotFound
from tig_cli.runtime import CommandFailed, Runtime, RuntimeCommandError

IMAGE = "test-image:latest"
IMAGE_ID = "sha256:image"
OLD_TIMESTAMP = "2020-01-01T00:00:00.123456789Z"


@pytest.fixture
def home_dir(tmp_path):
    return str(tmp_path / "home" / "user")


def described(
    started_at=OLD_TIMESTAMP,
    exec_ids=None,
    image_id=IMAGE_ID,
    status="running",
    mounts=None,
):
    """A container as a runtime describes one on 'container inspect'."""
    return {
        "Image": image_id,
        "Config": {"Image": IMAGE},
        "State": {
            "Status": status,
            "Running": status == "running",
            "StartedAt": started_at,
        },
        "ExecIDs": exec_ids,
        "Mounts": mounts or [],
    }


class FakeRuntime(Runtime):
    """A container runtime whose command line is served from memory.

    Only the commands the manager issues are answered, in the shape the real
    runtimes answer them, so what is under test is how tig drives them.
    """

    def __init__(self, containers=None, image_id=IMAGE_ID):
        super().__init__("docker", "/usr/bin/docker")
        self.containers = dict(containers or {})
        self.image_id = image_id
        self.exec_output = ""
        self.commands = []
        self.created = []
        self.removed = []
        # Command prefix -> the error running it raises.
        self.failures = {}

    def fail(self, *prefix, message="denied", exit_code=1):
        self.failures[prefix] = CommandFailed(message, exit_code)

    def run(self, *arguments, timeout=None):
        self.commands.append(list(arguments))
        for prefix, error in self.failures.items():
            if arguments[:len(prefix)] == prefix:
                raise error
        return self._answer(list(arguments))

    def _answer(self, arguments):
        verb = arguments[0]
        if verb in ("container", "image") and arguments[1] == "inspect":
            return self._inspect(verb, arguments[2])
        if verb == "run":
            return self._create(arguments)
        if verb == "start":
            self.containers[arguments[1]] = described()
            return arguments[1]
        if verb == "rm":
            return self._remove(arguments[-1])
        if verb == "ps":
            return "".join(f"{name}\n" for name in self.containers)
        if verb == "exec":
            return self.exec_output
        raise AssertionError(f"unexpected runtime command: {arguments}")

    def _inspect(self, kind, reference):
        if kind == "image":
            if self.image_id is None:
                raise CommandFailed(f"No such image: {reference}", 1)
            return json.dumps([{"Id": self.image_id}])
        if reference not in self.containers:
            raise CommandFailed(f"No such container: {reference}", 1)
        return json.dumps([self.containers[reference]])

    def _create(self, arguments):
        name = arguments[arguments.index("--name") + 1]
        if name in self.containers:
            raise CommandFailed(f"container name {name} is already in use", 125)
        self.containers[name] = described(started_at=utc_now_stamp())
        self.created.append(name)
        return "0123456789ab"

    def _remove(self, name):
        if name not in self.containers:
            raise CommandFailed(f"No such container: {name}", 1)
        del self.containers[name]
        self.removed.append(name)
        return name

    def command_starting(self, *prefix):
        """The one issued command starting with ``prefix``."""
        matching = [c for c in self.commands if tuple(c[:len(prefix)]) == prefix]
        assert len(matching) == 1, f"{prefix} was issued {len(matching)} times"
        return matching[0]


def make_manager(home, image=IMAGE, runtime=None, **kwargs):
    """Build a ContainerManager driving a runtime that answers from memory."""
    with patch.dict(os.environ, {"HOME": home}):
        return ContainerManager(
            image, runtime=runtime or FakeRuntime(), **kwargs
        )


def utc_now_stamp():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def created_args(runtime):
    """The arguments of the create the manager issued."""
    return runtime.command_starting("run")


# --- get_container_image ---

def test_get_container_image_default():
    """Returns default image when CONTAINER_IMAGE not set."""
    with patch.dict(os.environ, {}, clear=False):
        os.environ.pop("CONTAINER_IMAGE", None)
        assert get_container_image() == DEFAULT_IMAGE


def test_get_container_image_from_env():
    """Returns value of CONTAINER_IMAGE env var."""
    custom = "ghcr.io/my-org/custom-vicar:v2"
    with patch.dict(os.environ, {"CONTAINER_IMAGE": custom}):
        assert get_container_image() == custom


def test_get_container_image_from_config():
    """Falls back to the config file image when the env var is unset."""
    with patch.dict(os.environ, {}, clear=False):
        os.environ.pop("CONTAINER_IMAGE", None)
        assert get_container_image(Config(image="cfg:1")) == "cfg:1"


def test_get_container_image_env_beats_config():
    """CONTAINER_IMAGE takes precedence over the config file."""
    with patch.dict(os.environ, {"CONTAINER_IMAGE": "env:2"}):
        assert get_container_image(Config(image="cfg:1")) == "env:2"


# --- get_calibration_path ---

def test_get_calibration_path_unset(monkeypatch):
    monkeypatch.delenv("MARS_CONFIG_PATH", raising=False)
    assert get_calibration_path() is None


def test_get_calibration_path_from_config(monkeypatch):
    monkeypatch.delenv("MARS_CONFIG_PATH", raising=False)
    assert get_calibration_path(Config(calibration_path="/cfg")) == "/cfg"


def test_get_calibration_path_env_beats_config(monkeypatch):
    monkeypatch.setenv("MARS_CONFIG_PATH", "/env")
    assert get_calibration_path(Config(calibration_path="/cfg")) == "/env"


def test_get_calibration_path_env_expands_user(monkeypatch):
    monkeypatch.setenv("HOME", "/home/tester")
    monkeypatch.setenv("MARS_CONFIG_PATH", "~/calib")
    assert get_calibration_path() == "/home/tester/calib"


def test_get_calibration_path_from_env(tmp_path):
    with patch.dict(os.environ, {"MARS_CONFIG_PATH": str(tmp_path)}):
        assert get_calibration_path() == str(tmp_path)


# --- ContainerManager init ---

def test_container_manager_init(home_dir):
    manager = make_manager(home_dir)
    assert manager.image == IMAGE


def test_container_manager_default_no_translation(home_dir):
    """Path translation enabled by default."""
    assert make_manager(home_dir).disable_path_translation is False


def test_container_manager_detects_the_runtime(home_dir, monkeypatch):
    """With no runtime given, the host's is found."""
    runtime = FakeRuntime()
    monkeypatch.setattr(
        Runtime, "detect", classmethod(lambda cls, config=None: runtime)
    )
    with patch.dict(os.environ, {"HOME": home_dir}):
        assert ContainerManager(IMAGE).runtime is runtime


def test_missing_runtime_is_user_facing(home_dir, monkeypatch):
    monkeypatch.setattr("shutil.which", lambda command: None)
    monkeypatch.delenv("TIG_CONTAINER_RUNTIME", raising=False)
    with patch.dict(os.environ, {"HOME": home_dir}):
        manager = ContainerManager(IMAGE)

    with pytest.raises(TigError, match="No container runtime"):
        manager.ensure_container([])


def test_the_config_chooses_the_runtime(home_dir, monkeypatch):
    monkeypatch.setattr(
        "shutil.which",
        lambda command: "/usr/bin/podman" if command == "podman" else None,
    )
    with patch.dict(os.environ, {"HOME": home_dir}):
        manager = ContainerManager(IMAGE, config=Config(runtime="podman"))

    assert manager.runtime.name == "podman"


# --- mounts ---

def mounts_of(manager, writable_paths=()):
    """The mounts, by host path, the manager would create a container with."""
    spec = manager._run_spec(list(writable_paths))
    return {mount.source: mount for mount in spec.mounts}


def test_mounts_the_host_read_only_and_home_writable(home_dir):
    mounts = mounts_of(make_manager(home_dir))

    assert (mounts["/"].target, mounts["/"].mode) == ("/host", "ro")
    assert (mounts[home_dir].target, mounts[home_dir].mode) == (home_dir, "rw")


def test_mounts_writable_paths(home_dir, tmp_path):
    writable_path = str(tmp_path / "data")
    os.makedirs(writable_path, exist_ok=True)

    mounts = mounts_of(make_manager(home_dir), [writable_path])

    assert mounts[writable_path].target == f"/host{writable_path}"
    assert mounts[writable_path].mode == "rw"


def test_mounts_skip_nonexistent_paths(home_dir):
    assert "/nonexistent/path" not in mounts_of(
        make_manager(home_dir), ["/nonexistent/path"]
    )


def test_mounts_make_cwd_writable(home_dir, tmp_path):
    """A cwd outside home is mounted read-write, not just read-only at /host."""
    cwd = tmp_path / "scenes"
    cwd.mkdir()

    manager = make_manager(home_dir)
    with patch('os.getcwd', return_value=str(cwd)):
        mounts = mounts_of(manager)

    assert mounts[str(cwd)].argument == f"{cwd}:/host{cwd}:rw"


def test_mounts_skip_a_cwd_inside_home(home_dir):
    """A cwd under home needs no extra mount; home is already read-write."""
    os.makedirs(f"{home_dir}/projects", exist_ok=True)

    manager = make_manager(home_dir)
    with patch('os.getcwd', return_value=f"{home_dir}/projects"):
        mounts = mounts_of(manager)

    assert f"{home_dir}/projects" not in mounts


# --- calibration files ---

def test_calibration_path_is_mounted_read_only(home_dir, tmp_path):
    calib = tmp_path / "mars_calibration_m20"
    calib.mkdir()

    manager = make_manager(home_dir, calibration_path=str(calib))

    mount = mounts_of(manager)[str(calib)]
    assert (mount.target, mount.mode) == (CALIBRATION_MOUNT, "ro")


def test_calibration_path_is_exported_to_the_container(home_dir, tmp_path):
    calib = tmp_path / "mars_calibration_m20"
    calib.mkdir()

    manager = make_manager(home_dir, calibration_path=str(calib))

    spec = manager._run_spec([])
    assert spec.environment["MARS_CONFIG_PATH"] == CALIBRATION_MOUNT


def test_missing_calibration_path_is_user_facing(home_dir):
    with pytest.raises(TigError, match="not a directory"):
        make_manager(home_dir, calibration_path="/nonexistent/calib")


# --- ensure_container ---

def test_ensure_container_linux(home_dir):
    runtime = FakeRuntime()

    manager = make_manager(home_dir, runtime=runtime)
    with patch('sys.platform', 'linux'):
        manager.ensure_container([])

    args = created_args(runtime)
    assert args[:2] == ["run", "--detach"]
    assert args[-4:] == [IMAGE, "tail", "-f", "/dev/null"]
    assert ["--name", manager.container_name] == args[2:4]
    assert ["--platform", IMAGE_PLATFORM] == args[4:6]
    assert ["--network", "host"] == pair(args, "--network")
    assert ["--user", f"{os.getuid()}:{os.getgid()}"] == pair(args, "--user")
    assert f"{home_dir}:{home_dir}:rw" in args
    assert manager.running is True


def test_a_rootless_runtime_maps_the_user_to_itself(home_dir, monkeypatch):
    """--user would write as a subordinate uid the host does not own."""
    runtime = FakeRuntime()
    runtime.name = "podman"
    monkeypatch.setattr("os.geteuid", lambda: 1000)

    manager = make_manager(home_dir, runtime=runtime)
    with patch('sys.platform', 'linux'):
        manager.ensure_container([])

    args = created_args(runtime)
    assert ["--userns", "keep-id"] == pair(args, "--userns")
    assert "--user" not in args


def test_a_rootful_runtime_runs_as_the_invoking_user(home_dir, monkeypatch):
    runtime = FakeRuntime()
    runtime.name = "podman"
    monkeypatch.setattr("os.geteuid", lambda: 0)

    manager = make_manager(home_dir, runtime=runtime)
    with patch('sys.platform', 'linux'):
        manager.ensure_container([])

    args = created_args(runtime)
    assert "--userns" not in args
    assert ["--user", f"{os.getuid()}:{os.getgid()}"] == pair(args, "--user")


def test_ensure_container_macos(home_dir):
    runtime = FakeRuntime()

    manager = make_manager(home_dir, runtime=runtime)
    with patch('sys.platform', 'darwin'):
        manager.ensure_container([])

    args = created_args(runtime)
    assert "--network" not in args
    # A runtime with a VM of its own maps ownership already.
    assert "--user" not in args
    assert ["--platform", IMAGE_PLATFORM] == pair(args, "--platform")


def pair(args, option):
    """An option and its value, as they appear in a create."""
    index = args.index(option)
    return args[index:index + 2]


def test_ensure_container_reuses_running_container(home_dir):
    """A matching container is reused rather than recreated."""
    runtime = FakeRuntime()
    manager = make_manager(home_dir, runtime=runtime)
    runtime.containers[manager._run_spec([]).container_name()] = described()

    manager.ensure_container([])

    assert runtime.created == []
    # Only looked the container and its image up; nothing was changed.
    assert sorted(c[0] for c in runtime.commands) == ["container", "image"]
    assert manager.running is True


def test_ensure_container_starts_stopped_container(home_dir):
    runtime = FakeRuntime()
    manager = make_manager(home_dir, runtime=runtime)
    name = manager._run_spec([]).container_name()
    runtime.containers[name] = described(status="exited")

    manager.ensure_container([])

    assert runtime.command_starting("start") == ["start", name]
    assert runtime.created == []


def test_ensure_container_replaces_container_running_a_stale_image(home_dir):
    """Re-pulling a moving tag takes effect instead of reusing the old image."""
    runtime = FakeRuntime(image_id="sha256:new")
    manager = make_manager(home_dir, runtime=runtime)
    name = manager._run_spec([]).container_name()
    runtime.containers[name] = described(image_id="sha256:old")

    manager.ensure_container([])

    assert runtime.removed == [name]
    assert runtime.created == [name]


def test_ensure_container_reuses_one_described_by_image_reference(home_dir):
    """Some runtimes record the reference a container was run from."""
    runtime = FakeRuntime()
    manager = make_manager(home_dir, runtime=runtime)
    name = manager._run_spec([]).container_name()
    runtime.containers[name] = described(image_id=IMAGE)

    manager.ensure_container([])

    assert runtime.created == []
    assert runtime.removed == []


def test_ensure_container_replaces_one_whose_image_is_not_pulled(home_dir):
    runtime = FakeRuntime(image_id=None)
    manager = make_manager(home_dir, runtime=runtime)
    name = manager._run_spec([]).container_name()
    runtime.containers[name] = described()

    manager.ensure_container([])

    assert runtime.removed == [name]


def test_container_name_identifies_the_configuration(home_dir, tmp_path):
    """Same configuration shares a container; different mounts do not."""
    extra = tmp_path / "data"
    extra.mkdir()

    def name_for(writable_paths):
        manager = make_manager(home_dir)
        manager.ensure_container(writable_paths)
        return manager.container_name

    plain = name_for([])

    assert plain.startswith(f"{CONTAINER_PREFIX}-")
    assert plain == name_for([])
    assert plain != name_for([str(extra)])


def test_container_name_tells_the_runtimes_apart(home_dir, monkeypatch):
    """Each runtime keeps its own containers, and the warm path is cached
    under the name, so two of them sharing one would cross the streams."""
    monkeypatch.setattr("sys.platform", "darwin")

    def name_for(name):
        runtime = FakeRuntime()
        runtime.name = name
        return make_manager(home_dir, runtime=runtime)._run_spec(
            []
        ).container_name()

    assert name_for("docker") != name_for("nerdctl")


def test_container_name_ignores_the_order_of_the_writable_paths(
    home_dir, tmp_path
):
    """The same mounts named in another order must not build a container."""
    first, second = tmp_path / "one", tmp_path / "two"
    first.mkdir()
    second.mkdir()

    def name_for(writable_paths):
        manager = make_manager(home_dir)
        manager.ensure_container(writable_paths)
        return manager.container_name

    assert name_for([str(first), str(second)]) == name_for(
        [str(second), str(first)]
    )


def test_ensure_container_adopts_container_created_concurrently(home_dir):
    """Two tig commands starting at once must not collide on the name."""
    runtime = FakeRuntime()
    manager = make_manager(home_dir, runtime=runtime)
    name = manager._run_spec([]).container_name()

    def create_first(*arguments):
        # The other process got there first, between look-up and create.
        runtime.containers[name] = described()
        raise CommandFailed(f"container name {name} is already in use", 125)

    with patch.object(FakeRuntime, "_create", side_effect=create_first):
        manager.ensure_container([])

    assert runtime.created == []
    assert manager.running is True


def test_ensure_container_tolerates_concurrent_removal(home_dir):
    """A container removed by another process mid-replacement is not fatal."""
    runtime = FakeRuntime(image_id="sha256:new")
    manager = make_manager(home_dir, runtime=runtime)
    name = manager._run_spec([]).container_name()
    runtime.containers[name] = described(image_id="sha256:old")

    def remove_elsewhere(*arguments):
        del runtime.containers[name]
        raise CommandFailed(f"No such container: {name}", 1)

    with patch.object(FakeRuntime, "_remove", side_effect=remove_elsewhere):
        manager.ensure_container([])

    assert runtime.created == [name]


def test_replacing_a_container_reports_a_runtime_that_cannot_be_asked(home_dir):
    """A removal that failed is only forgiven where the runtime says the
    container has gone, not where it could not answer at all."""
    runtime = FakeRuntime({f"{CONTAINER_PREFIX}-old": described()})
    runtime.fail("rm", message="permission denied")
    runtime.failures[("container", "inspect")] = RuntimeCommandError(
        "Failed to run docker: [Errno 111] Connection refused"
    )
    manager = make_manager(home_dir, runtime=runtime)

    with pytest.raises(TigError, match="Failed to replace container"):
        manager._remove(f"{CONTAINER_PREFIX}-old")


def test_ensure_container_failure_is_user_facing(home_dir):
    runtime = FakeRuntime()
    runtime.fail("run", message="no space left on device")

    manager = make_manager(home_dir, runtime=runtime)
    with pytest.raises(TigError, match="no space left on device"):
        manager.ensure_container([])


def test_ensure_container_reuse_failure_is_user_facing(home_dir):
    """A container that cannot be started is an error, not a traceback."""
    runtime = FakeRuntime()
    manager = make_manager(home_dir, runtime=runtime)
    runtime.containers[manager._run_spec([]).container_name()] = described(
        status="exited"
    )
    runtime.fail("start", message="denied")

    with pytest.raises(TigError, match="Failed to reuse container"):
        manager.ensure_container([])


def test_ensure_container_replacement_failure_is_user_facing(home_dir):
    """So is a container that cannot be replaced."""
    runtime = FakeRuntime(image_id="sha256:new")
    manager = make_manager(home_dir, runtime=runtime)
    runtime.containers[manager._run_spec([]).container_name()] = described(
        image_id="sha256:old"
    )
    runtime.fail("rm", message="in use")

    with pytest.raises(TigError, match="Failed to replace container"):
        manager.ensure_container([])


# --- shutdown / status ---

def test_shutdown_removes_every_tig_container(home_dir):
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-a": described(),
        f"{CONTAINER_PREFIX}-b": described(),
    })

    removed = make_manager(home_dir, runtime=runtime).shutdown()

    assert removed == 2
    assert sorted(runtime.removed) == [
        f"{CONTAINER_PREFIX}-a", f"{CONTAINER_PREFIX}-b"
    ]
    listing = runtime.command_starting("ps")
    assert listing[1:3] == ["--all", "--filter"]
    assert listing[3] == f"name={CONTAINER_PREFIX}"


def test_shutdown_with_no_containers(home_dir):
    assert make_manager(home_dir).shutdown() == 0


def test_listing_reads_a_name_per_container(home_dir):
    """Podman prints a container's names as a comma-separated list."""
    runtime = FakeRuntime()
    runtime._answer = lambda arguments: f"{CONTAINER_PREFIX}-a,other\n"

    assert make_manager(home_dir, runtime=runtime)._container_names() == [
        f"{CONTAINER_PREFIX}-a"
    ]


def test_status_reports_containers(home_dir):
    runtime = FakeRuntime({f"{CONTAINER_PREFIX}-abc123": described()})

    assert make_manager(home_dir, runtime=runtime).status() == [{
        "name": f"{CONTAINER_PREFIX}-abc123",
        "status": "running",
        "image": IMAGE,
        "writable": "",
    }]


def test_status_reports_writable_mounts(home_dir):
    """The writable mounts are what distinguishes one container from another."""
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-abc123": described(mounts=[
            {"Source": "/", "Destination": "/host", "RW": False},
            {"Source": "/home/user", "Destination": "/home/user", "RW": True},
            {"Source": "/scenes", "Destination": "/host/scenes", "RW": True},
            {
                "Source": "/tmp/.X11-unix",
                "Destination": "/tmp/.X11-unix",
                "RW": True,
            },
        ]),
    })

    status = make_manager(home_dir, runtime=runtime).status()

    assert status[0]["writable"] == "/home/user, /scenes"


def test_status_names_an_image_the_runtime_only_identifies(home_dir):
    runtime = FakeRuntime({f"{CONTAINER_PREFIX}-abc": described()})
    runtime.containers[f"{CONTAINER_PREFIX}-abc"].pop("Config")

    assert make_manager(home_dir, runtime=runtime).status()[0]["image"] == (
        IMAGE_ID[7:19]
    )


# --- reaping surplus containers ---

def test_creating_a_container_reaps_surplus_idle_ones(home_dir):
    """Working in several directories must not leave a pile of containers."""
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-old": described(started_at=OLD_TIMESTAMP),
        f"{CONTAINER_PREFIX}-new": described(started_at="2021-01-01T00:00:00Z"),
    })

    make_manager(home_dir, runtime=runtime).ensure_container([])

    # One kept alongside the container just created.
    assert MAX_KEPT_CONTAINERS == 2
    assert runtime.removed == [f"{CONTAINER_PREFIX}-old"]


def test_cleaning_a_build_only_removes_this_image_s_idle_containers(
    home_dir, monkeypatch
):
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-mine": described(),
        f"{CONTAINER_PREFIX}-busy": described(exec_ids=["exec1"]),
        f"{CONTAINER_PREFIX}-other": described(image_id="sha256:other"),
    })
    fake_engine(monkeypatch, {
        "Running": True,
        "ProcessConfig": {"entrypoint": "vicar", "arguments": ["in.img"]},
    })
    manager = make_manager(home_dir, runtime=runtime)

    assert manager.remove_containers_of([IMAGE_ID]) == (1, 1)

    assert runtime.removed == [f"{CONTAINER_PREFIX}-mine"]


def test_cleaning_a_build_also_removes_the_containers_of_another_image(home_dir):
    """A build forgotten for another image is still in that image's containers."""
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-mine": described(),
        f"{CONTAINER_PREFIX}-other": described(image_id="sha256:0123456789abcdef"),
        f"{CONTAINER_PREFIX}-third": described(image_id="sha256:fedcba9876543210"),
    })
    manager = make_manager(home_dir, runtime=runtime)

    # As recorded: the image's id, shortened as the state directories are.
    assert manager.remove_containers_of([IMAGE_ID, "0123456789ab"]) == (2, 0)

    assert runtime.removed == [
        f"{CONTAINER_PREFIX}-mine", f"{CONTAINER_PREFIX}-other"
    ]


def test_reaping_never_touches_the_container_in_use(home_dir):
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-{i}": described() for i in range(3)
    })
    manager = make_manager(home_dir, runtime=runtime)
    manager.ensure_container([])

    manager._reap_containers(keep=manager.container_name)

    assert manager.container_name not in runtime.removed


def test_reaping_skips_a_container_running_a_command_started_outside_tig(
    home_dir, monkeypatch
):
    """A hand-run 'exec' also keeps a container alive."""
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-newer": described("2022-01-01T00:00:00Z"),
        f"{CONTAINER_PREFIX}-busy": described(
            "2020-01-01T00:00:00Z", exec_ids=["exec1"]
        ),
    })
    fake_engine(monkeypatch, {
        "Running": True,
        "ProcessConfig": {"entrypoint": "vicar", "arguments": ["in.img"]},
    })

    make_manager(home_dir, runtime=runtime).ensure_container([])

    assert runtime.removed == []


def test_reaping_still_removes_a_container_running_only_tigs_runner(
    home_dir, monkeypatch
):
    """The dispatcher and agent live as long as the container; they are not
    a command anyone is waiting on."""
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-newer": described("2022-01-01T00:00:00Z"),
        f"{CONTAINER_PREFIX}-surplus": described(
            "2020-01-01T00:00:00Z", exec_ids=["exec1"]
        ),
    })
    fake_engine(monkeypatch, {
        "Running": True,
        "ProcessConfig": {
            "entrypoint": "/bin/sh",
            "arguments": ["/run/dispatch.sh", "/run", "/run/control", RUNNER_MARKER],
        },
    })

    make_manager(home_dir, runtime=runtime).ensure_container([])

    assert runtime.removed == [f"{CONTAINER_PREFIX}-surplus"]


def test_reaping_skips_a_container_when_the_runtime_cannot_say(
    home_dir, monkeypatch
):
    """An unanswerable liveness check is treated as in use."""
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-unknown": described(exec_ids=["exec1"]),
        f"{CONTAINER_PREFIX}-idle": described(),
    })
    fake_engine(monkeypatch, EngineError("boom"))

    make_manager(home_dir, runtime=runtime).ensure_container([])

    assert f"{CONTAINER_PREFIX}-unknown" not in runtime.removed


def test_reaping_skips_a_busy_container_on_a_runtime_without_an_api(
    home_dir, monkeypatch
):
    """nerdctl and Finch serve no API, so one exec can only mean in use."""
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-busy": described(exec_ids=["exec1"]),
        f"{CONTAINER_PREFIX}-idle": described("2022-01-01T00:00:00Z"),
    })

    def no_api(cls, runtime=None):
        raise EngineError("serves no Docker-compatible API socket")

    monkeypatch.setattr(Engine, "detect", classmethod(no_api))

    make_manager(home_dir, runtime=runtime).ensure_container([])

    assert f"{CONTAINER_PREFIX}-busy" not in runtime.removed


def test_reaping_removes_a_container_whose_exec_the_runtime_forgot(
    home_dir, monkeypatch
):
    """A vanished exec is no command; only an unanswerable check means busy."""
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-newer": described("2022-01-01T00:00:00Z"),
        f"{CONTAINER_PREFIX}-stale": described(
            "2020-01-01T00:00:00Z", exec_ids=["gone"]
        ),
    })
    fake_engine(monkeypatch, EngineNotFound("Not found: /exec/gone/json"))

    make_manager(home_dir, runtime=runtime).ensure_container([])

    assert runtime.removed == [f"{CONTAINER_PREFIX}-stale"]


def test_creating_a_container_survives_an_unlistable_runtime(home_dir):
    """Reaping is housekeeping; it must not fail a command that has a
    container."""
    runtime = FakeRuntime()
    runtime.fail("ps", message="cannot connect")

    manager = make_manager(home_dir, runtime=runtime)
    manager.ensure_container([])

    assert manager.running is True


def test_status_reports_a_runtime_that_cannot_be_asked(home_dir):
    """Silently reporting nothing would look like nothing is running."""
    runtime = FakeRuntime({f"{CONTAINER_PREFIX}-one": described()})
    runtime.fail("ps", message="cannot connect to the runtime")

    manager = make_manager(home_dir, runtime=runtime)

    with pytest.raises(TigError, match="cannot connect"):
        manager.status()
    with pytest.raises(TigError, match="cannot connect"):
        manager.shutdown()


def fake_engine(monkeypatch, inspected):
    """Serve exec details, or raise, from the optional API accelerator."""
    engine = MagicMock()
    if isinstance(inspected, Exception):
        engine.inspect_exec.side_effect = inspected
    else:
        engine.inspect_exec.return_value = inspected
    monkeypatch.setattr(
        Engine, "detect", classmethod(lambda cls, runtime=None: engine)
    )
    return engine


def test_reaping_skips_a_container_claimed_by_a_live_process(home_dir):
    """A container another live invocation claimed is not reaped, even idle.

    The claim is what covers the window between another process creating its
    container and its first exec appearing.
    """
    claimed_name = f"{CONTAINER_PREFIX}-claimed"
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-newest": described("2022-01-01T00:00:00Z"),
        claimed_name: described("2021-01-01T00:00:00Z"),
        f"{CONTAINER_PREFIX}-oldest": described("2020-01-01T00:00:00Z"),
    })

    manager = make_manager(home_dir, runtime=runtime)
    claim_dir = manager._claim_dir()
    claim_dir.mkdir(parents=True, exist_ok=True)
    (claim_dir / f"{claimed_name}.{os.getpid()}").touch()

    manager.ensure_container([])

    assert runtime.removed == [f"{CONTAINER_PREFIX}-oldest"]


def test_reaping_ignores_and_prunes_a_claim_from_a_dead_process(home_dir):
    stale_name = f"{CONTAINER_PREFIX}-stale"
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-newest": described("2022-01-01T00:00:00Z"),
        stale_name: described("2021-01-01T00:00:00Z"),
    })

    manager = make_manager(home_dir, runtime=runtime)
    claim_dir = manager._claim_dir()
    claim_dir.mkdir(parents=True, exist_ok=True)
    claim = claim_dir / f"{stale_name}.999999"
    claim.touch()

    with patch('tig_cli.spec.os.kill', side_effect=ProcessLookupError):
        manager.ensure_container([])

    assert not claim.exists()
    assert runtime.removed == [stale_name]


def test_a_container_is_claimed_before_it_is_created(home_dir):
    """Claiming first is what closes the create-then-exec race."""
    runtime = FakeRuntime()
    manager = make_manager(home_dir, runtime=runtime)

    def creating(*arguments):
        assert manager.claim.exists()
        return "0123456789ab"

    with patch.object(FakeRuntime, "_create", side_effect=creating):
        manager.ensure_container([])

    assert manager.claim.name.endswith(f".{os.getpid()}")
    assert manager.claim.name.startswith(manager.container_name)


def test_releasing_the_claim_makes_the_container_reapable(home_dir):
    manager = make_manager(home_dir)
    manager.ensure_container([])
    claim = manager.claim

    manager.release_claim()

    assert not claim.exists()
    assert manager.claim is None
    manager.release_claim()  # idempotent


def test_the_claim_directory_is_private_to_the_user(home_dir):
    claim = spec.Claim()
    claim.acquire("tig-vicar-private")

    info = os.lstat(spec.Claim.directory())
    assert info.st_mode & 0o777 == 0o700
    assert info.st_uid == os.getuid()
    assert claim.path.exists()


def test_an_open_claim_directory_of_the_users_own_is_closed(home_dir):
    directory = spec.Claim.directory()
    directory.mkdir(parents=True)
    directory.chmod(0o777)

    claim = spec.Claim()
    claim.acquire("tig-vicar-open")

    assert os.lstat(directory).st_mode & 0o777 == 0o700
    assert claim.path is not None


def test_a_symlink_in_place_of_the_claim_directory_is_not_trusted(
    home_dir, tmp_path
):
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    (elsewhere / f"tig-vicar-planted.{os.getpid()}").touch()
    spec.Claim.directory().symlink_to(elsewhere)

    claim = spec.Claim()
    claim.acquire("tig-vicar-linked")

    assert claim.path is None
    assert list(elsewhere.iterdir()) == [
        elsewhere / f"tig-vicar-planted.{os.getpid()}"
    ]
    assert spec.Claim.claimed_containers() == set()


def test_a_claim_directory_owned_by_another_user_is_not_trusted(
    home_dir, monkeypatch
):
    other = os.getuid() + 1
    monkeypatch.setattr(spec.os, "getuid", lambda: other)
    directory = spec.Claim.directory()
    directory.mkdir(mode=0o700)
    (directory / f"tig-vicar-planted.{os.getpid()}").touch()

    claim = spec.Claim()
    claim.acquire("tig-vicar-foreign")

    assert claim.path is None
    assert spec.Claim.claimed_containers() == set()


def test_claims_not_owned_by_the_user_are_ignored(home_dir, monkeypatch):
    directory = spec.Claim.directory()
    directory.mkdir(mode=0o700)
    (directory / f"tig-vicar-planted.{os.getpid()}").touch()
    (directory / f"tig-vicar-linked.{os.getpid()}").symlink_to(directory)
    real_lstat = os.lstat

    def lstat(path):
        info = real_lstat(path)
        if "planted" in os.fspath(path):
            return os.stat_result(
                info[:4] + (os.getuid() + 1,) + info[5:]
            )
        return info

    monkeypatch.setattr(spec.os, "lstat", lstat)

    assert spec.Claim.claimed_containers() == set()


def test_claims_fall_back_to_the_temporary_directory(
    home_dir, tmp_path, monkeypatch
):
    import tempfile

    monkeypatch.delenv("XDG_RUNTIME_DIR", raising=False)
    monkeypatch.setenv("TMPDIR", str(tmp_path))
    monkeypatch.setattr(tempfile, "tempdir", None)

    assert spec.Claim.directory() == (
        tmp_path / f"{spec.CLAIM_DIR_NAME}-{os.getuid()}"
    )


def test_reaping_tolerates_a_container_removed_concurrently(home_dir):
    runtime = FakeRuntime({
        f"{CONTAINER_PREFIX}-a": described(),
        f"{CONTAINER_PREFIX}-b": described("2022-01-01T00:00:00Z"),
    })
    runtime.fail("rm", message="No such container")

    make_manager(home_dir, runtime=runtime).ensure_container([])  # no raise


def test_reusing_a_container_does_not_reap(home_dir):
    """The warm path stays a single lookup, so latency is unchanged."""
    runtime = FakeRuntime()
    manager = make_manager(home_dir, runtime=runtime)
    runtime.containers[manager._run_spec([]).container_name()] = described()

    manager.ensure_container([])

    assert not any(command[0] == "ps" for command in runtime.commands)


# --- SELinux ---

def test_selinux_enforcing_reads_the_kernel_state(tmp_path, monkeypatch):
    enforce = tmp_path / "enforce"
    enforce.write_text("1\n")
    monkeypatch.setattr('tig_cli.spec.SELINUX_ENFORCE_PATH', str(enforce))

    with patch('sys.platform', 'linux'), \
         patch('subprocess.run') as run:
        assert selinux_enforcing() is True

    # The kernel state answers on its own; no process is spawned for it.
    run.assert_not_called()


def test_selinux_permissive_is_not_enforcing(tmp_path, monkeypatch):
    enforce = tmp_path / "enforce"
    enforce.write_text("0\n")
    monkeypatch.setattr('tig_cli.spec.SELINUX_ENFORCE_PATH', str(enforce))

    with patch('sys.platform', 'linux'):
        assert selinux_enforcing() is False


def test_selinux_falls_back_to_getenforce(tmp_path, monkeypatch):
    monkeypatch.setattr(
        'tig_cli.spec.SELINUX_ENFORCE_PATH', str(tmp_path / "missing")
    )

    with patch('sys.platform', 'linux'), \
         patch('shutil.which', return_value="/usr/sbin/getenforce"), \
         patch('subprocess.run',
               return_value=subprocess.CompletedProcess([], 0, "Enforcing\n", "")):
        assert selinux_enforcing() is True


def test_selinux_permissive_from_getenforce(tmp_path, monkeypatch):
    monkeypatch.setattr(
        'tig_cli.spec.SELINUX_ENFORCE_PATH', str(tmp_path / "missing")
    )

    with patch('sys.platform', 'linux'), \
         patch('shutil.which', return_value="/usr/sbin/getenforce"), \
         patch('subprocess.run',
               return_value=subprocess.CompletedProcess([], 0, "Permissive\n", "")):
        assert selinux_enforcing() is False


def test_selinux_absent_when_there_is_no_selinux(tmp_path, monkeypatch):
    monkeypatch.setattr(
        'tig_cli.spec.SELINUX_ENFORCE_PATH', str(tmp_path / "missing")
    )

    with patch('sys.platform', 'linux'), \
         patch('shutil.which', return_value=None):
        assert selinux_enforcing() is False


def test_selinux_not_checked_off_linux():
    with patch('sys.platform', 'darwin'), \
         patch('shutil.which') as which:
        assert selinux_enforcing() is False
        which.assert_not_called()


def test_enforcing_host_gets_label_disable(home_dir):
    runtime = FakeRuntime()

    with patch('tig_cli.container.selinux_enforcing', return_value=True):
        manager = make_manager(home_dir, runtime=runtime)
    with patch('sys.platform', 'linux'):
        manager.ensure_container([])

    assert pair(created_args(runtime), "--security-opt") == [
        "--security-opt", "label=disable"
    ]


def test_non_enforcing_host_keeps_standard_labeling(home_dir):
    runtime = FakeRuntime()

    with patch('tig_cli.container.selinux_enforcing', return_value=False):
        manager = make_manager(home_dir, runtime=runtime)
    with patch('sys.platform', 'linux'):
        manager.ensure_container([])

    assert "--security-opt" not in created_args(runtime)


def test_label_disable_can_be_forced_on(home_dir):
    runtime = FakeRuntime()

    with patch('tig_cli.container.selinux_enforcing', return_value=False):
        manager = make_manager(
            home_dir, runtime=runtime, selinux_label_disable=True
        )
    with patch('sys.platform', 'linux'):
        manager.ensure_container([])

    assert "label=disable" in created_args(runtime)


def test_label_disable_can_be_forced_off_on_an_enforcing_host(home_dir, capsys):
    runtime = FakeRuntime()

    with patch('tig_cli.container.selinux_enforcing', return_value=True):
        manager = make_manager(
            home_dir, runtime=runtime, selinux_label_disable=False
        )
    with patch('sys.platform', 'linux'):
        manager.ensure_container([])

    assert "--security-opt" not in created_args(runtime)
    assert "SELinux is Enforcing" in capsys.readouterr().err


def test_label_disable_is_not_used_on_macos(home_dir):
    runtime = FakeRuntime()

    with patch('tig_cli.container.selinux_enforcing', return_value=True):
        manager = make_manager(
            home_dir, runtime=runtime, selinux_label_disable=True
        )
    with patch('sys.platform', 'darwin'):
        manager.ensure_container([])

    assert "--security-opt" not in created_args(runtime)


def test_host_root_mount_is_never_relabeled(home_dir, tmp_path):
    """Relabeling (:z/:Z) the host root filesystem would be unrecoverable."""
    calib = tmp_path / "mars_calibration_m20"
    calib.mkdir()

    with patch('tig_cli.container.selinux_enforcing', return_value=True):
        manager = make_manager(home_dir, calibration_path=str(calib))

    assert all(
        mount.mode in ("ro", "rw") for mount in manager._run_spec([]).mounts
    )


# --- X11 host setup ---

@pytest.fixture
def host_display(monkeypatch, tmp_path):
    """A host with a display and no record of an authorized X server."""
    home = tmp_path / "x11-home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("DISPLAY", ":0")
    monkeypatch.delenv("TIG_NO_X11", raising=False)
    return home


def test_x11_setup_authorizes_local_connections_on_linux(host_display):
    with patch('sys.platform', 'linux'), \
         patch('shutil.which', return_value="/usr/bin/xhost"), \
         patch('subprocess.run') as run:
        ensure_x11_ready()

    # The broad form: label=disable makes the container connect as LOCAL:.
    assert run.call_args[0][0] == ["xhost", "+local:"]


def test_x11_setup_authorizes_again_for_every_command(host_display):
    """Whatever dropped the authorization - a restart, a bare 'xhost -' -
    the next command puts it back rather than trusting what it saw before."""
    with patch('sys.platform', 'linux'), \
         patch('shutil.which', return_value="/usr/bin/xhost"), \
         patch('tig_cli.spec.x_server_identity', return_value="server-1"), \
         patch('subprocess.run') as run:
        run.return_value = subprocess.CompletedProcess([], 0)
        ensure_x11_ready()
        ensure_x11_ready()

    assert [call[0][0] for call in run.call_args_list] == [
        ["xhost", "+local:"], ["xhost", "+local:"]
    ]


def test_xquartz_is_only_checked_for_a_server_not_seen_before(host_display):
    """Starting XQuartz and reading its preferences is the slow part."""
    with patch('sys.platform', 'darwin'), \
         patch('shutil.which', return_value="/opt/X11/bin/xhost"), \
         patch('tig_cli.spec.x_server_identity', return_value="server-1"), \
         patch('tig_cli.spec._run_quietly', return_value=True), \
         patch('tig_cli.spec._ensure_xquartz') as xquartz:
        ensure_x11_ready()
        ensure_x11_ready()

        assert xquartz.call_count == 1

    with patch('sys.platform', 'darwin'), \
         patch('shutil.which', return_value="/opt/X11/bin/xhost"), \
         patch('tig_cli.spec.x_server_identity', return_value="server-2"), \
         patch('tig_cli.spec._run_quietly', return_value=True), \
         patch('tig_cli.spec._ensure_xquartz') as restarted:
        ensure_x11_ready()

        restarted.assert_called_once()


def test_x11_setup_can_be_turned_off(host_display, monkeypatch):
    monkeypatch.setenv("TIG_NO_X11", "1")

    with patch('shutil.which', return_value="/usr/bin/xhost"), \
         patch('subprocess.run') as run:
        ensure_x11_ready()

    run.assert_not_called()


def test_x_server_identity_follows_the_linux_socket(monkeypatch, tmp_path):
    """A restarted server leaves a different socket behind."""
    monkeypatch.setenv("DISPLAY", ":0")
    socket = tmp_path / "X0"
    socket.write_text("")

    with patch('sys.platform', 'linux'), \
         patch('tig_cli.spec._x_socket', return_value=str(socket)):
        before = spec.x_server_identity()
        socket.unlink()
        socket.write_text("")
        # A recreated socket can land on the same inode within the same
        # second, which a restarted server minutes later would not.
        replaced = os.stat(socket).st_mtime + 60
        os.utime(socket, (replaced, replaced))
        after = spec.x_server_identity()

    assert before is not None and before != after


def test_a_network_display_is_never_taken_as_authorized(monkeypatch):
    """Nothing local says whether a remote server is the one authorized."""
    monkeypatch.setenv("DISPLAY", "192.168.1.5:0")

    with patch('sys.platform', 'linux'):
        assert spec.x_server_identity() is None


def test_failed_authorization_is_not_remembered(host_display):
    """A skipped xhost is only safe after one that worked."""
    with patch('sys.platform', 'linux'), \
         patch('shutil.which', return_value="/usr/bin/xhost"), \
         patch('tig_cli.spec.x_server_identity', return_value="server-1"), \
         patch('tig_cli.spec._run_quietly', return_value=False):
        ensure_x11_ready()

        assert spec._authorized_server() is None


def test_x_server_identity_follows_the_xquartz_process(monkeypatch):
    monkeypatch.setenv("DISPLAY", "/private/tmp/com.apple.launchd.x/org.xquartz:0")

    with patch('sys.platform', 'darwin'), \
         patch('tig_cli.spec._output_of', side_effect=["501\n", "777\n", None]):
        first = spec.x_server_identity()
        second = spec.x_server_identity()
        stopped = spec.x_server_identity()

    assert first != second
    # No server running is no server to recognize, so nothing is skipped.
    assert stopped is None


def test_x11_setup_skipped_without_a_display(host_display, monkeypatch):
    monkeypatch.delenv("DISPLAY", raising=False)

    with patch('subprocess.run') as run:
        ensure_x11_ready()

    run.assert_not_called()


def test_x11_setup_skipped_without_xhost(host_display):
    with patch('shutil.which', return_value=None), \
         patch('subprocess.run') as run:
        ensure_x11_ready()

    run.assert_not_called()


def test_x11_setup_failure_is_not_fatal(host_display):
    with patch('sys.platform', 'linux'), \
         patch('shutil.which', return_value="/usr/bin/xhost"), \
         patch('subprocess.run', side_effect=OSError):
        ensure_x11_ready()  # should not raise


def test_x11_setup_prepares_xquartz_on_macos(host_display, monkeypatch):
    monkeypatch.setenv("DISPLAY", "/private/tmp/com.apple.launchd.x/org.xquartz:0")

    with patch('sys.platform', 'darwin'), \
         patch('shutil.which', return_value="/opt/X11/bin/xhost"), \
         patch('subprocess.run') as run:
        run.return_value = subprocess.CompletedProcess(
            [], 0, stdout="", stderr=""
        )
        ensure_x11_ready()

    commands = [call[0][0] for call in run.call_args_list]
    assert ["defaults", "write", "org.xquartz.X11",
            "nolisten_tcp", "-bool", "false"] in commands
    # Both families: the container's connection arrives on the loopback
    # address, whichever way the name resolves.
    assert ["xhost", "+localhost", "+inet:127.0.0.1"] in commands


def test_xquartz_left_refusing_tcp_says_so(host_display, capsys):
    """An update resets the preference, and it is only read at startup."""
    with patch('sys.platform', 'darwin'), \
         patch('tig_cli.spec._tcp_refused', return_value=True), \
         patch('tig_cli.spec._run_quietly', return_value=True) as run:
        spec._allow_tcp_connections()

    assert ["defaults", "write", "org.xquartz.X11",
            "nolisten_tcp", "-bool", "false"] in [
        call[0][0] for call in run.call_args_list
    ]
    assert "Quit XQuartz" in capsys.readouterr().err


def test_x11_setup_runs_when_a_container_is_created(home_dir):
    manager = make_manager(home_dir)
    with patch('tig_cli.container.ensure_x11_ready') as ready:
        manager.ensure_container([])

    ready.assert_called_once()


@patch('tig_cli.container.subprocess.Popen')
def test_x11_setup_runs_for_every_command(mock_popen, home_dir):
    """The container outlives the X server, so reusing one authorizes nobody."""
    mock_popen.return_value = Mock(wait=Mock(return_value=0))
    manager = make_manager(home_dir)

    with patch('tig_cli.container.ensure_x11_ready') as ready:
        manager.execute_vicar_command("xvd", [])

    ready.assert_called_once()


# --- execute_vicar_command ---

@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command(mock_popen, home_dir):
    mock_popen.return_value = Mock(wait=Mock(return_value=0))

    manager = make_manager(home_dir)
    with patch('os.getcwd', return_value=f"{home_dir}/projects"):
        exit_code = manager.execute_vicar_command(
            "marsmap", ["input.vic", "output.vic"]
        )

    assert exit_code == 0
    call_args = mock_popen.call_args[0][0]
    assert call_args[:3] == [manager.runtime.executable, "exec", "-i"]
    assert call_args[-3:] == ["marsmap", "input.vic", "output.vic"]
    assert manager.container_name in call_args


@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command_runs_the_chosen_runtime(mock_popen, home_dir):
    """Nothing hardcodes docker: the command is the runtime that was found."""
    mock_popen.return_value = Mock(wait=Mock(return_value=0))
    runtime = FakeRuntime()
    runtime.name, runtime.executable = "podman", "/usr/bin/podman"

    make_manager(home_dir, runtime=runtime).execute_vicar_command("label", [])

    assert mock_popen.call_args[0][0][0] == "/usr/bin/podman"


@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command_passes_display(mock_popen, home_dir):
    """DISPLAY is passed per exec, so it is not part of container identity."""
    mock_popen.return_value = Mock(wait=Mock(return_value=0))

    with patch.dict(os.environ, {"HOME": home_dir, "DISPLAY": ":7"}), \
         patch('tig_cli.container.ensure_x11_ready'):
        manager = make_manager(home_dir)
        with patch('sys.platform', 'linux'):
            manager.execute_vicar_command("xvd", [])

    assert "DISPLAY=:7" in mock_popen.call_args[0][0]


@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command_leaves_x_resource_paths_to_the_image(
    mock_popen, home_dir
):
    """The image's own xvd wrapper exports these; ours pointed at nothing."""
    mock_popen.return_value = Mock(wait=Mock(return_value=0))

    make_manager(home_dir).execute_vicar_command("xvd", [])

    call_args = mock_popen.call_args[0][0]
    assert not any("XFILESEARCHPATH" in arg for arg in call_args)
    assert not any("XBMLANGPATH" in arg for arg in call_args)


@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command_allocates_tty_when_interactive(mock_popen, home_dir):
    mock_popen.return_value = Mock(wait=Mock(return_value=0))

    manager = make_manager(home_dir)
    with patch('sys.stdin.isatty', return_value=True), \
         patch('sys.stdout.isatty', return_value=True):
        manager.execute_vicar_command("tae", [])

    assert "-t" in mock_popen.call_args[0][0]


@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command_no_tty_when_piped(mock_popen, home_dir):
    """A TTY would merge stderr into stdout and mangle redirected output."""
    mock_popen.return_value = Mock(wait=Mock(return_value=0))

    manager = make_manager(home_dir)
    with patch('sys.stdin.isatty', return_value=False), \
         patch('sys.stdout.isatty', return_value=True):
        manager.execute_vicar_command("list", [])

    assert "-t" not in mock_popen.call_args[0][0]


@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command_with_path_translation(mock_popen, home_dir):
    mock_popen.return_value = Mock(wait=Mock(return_value=0))

    manager = make_manager(home_dir)
    with patch('os.getcwd', return_value=f"{home_dir}/projects"):
        manager.execute_vicar_command(
            "marsmap",
            ["/data/input.vic", f"{home_dir}/output.vic"]
        )

    call_args = mock_popen.call_args[0][0]
    assert "/host/data/input.vic" in call_args
    assert f"{home_dir}/output.vic" in call_args


@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command_translates_keyword_args(mock_popen, home_dir):
    mock_popen.return_value = Mock(wait=Mock(return_value=0))

    manager = make_manager(home_dir)
    with patch('os.getcwd', return_value=f"{home_dir}/projects"):
        manager.execute_vicar_command(
            "marsmap", ["INP=/data/input.vic", "SIZE=(1,1,500,500)"]
        )

    call_args = mock_popen.call_args[0][0]
    assert "INP=/host/data/input.vic" in call_args
    assert "SIZE=(1,1,500,500)" in call_args


@patch('tig_cli.container.subprocess.Popen')
def test_execute_vicar_command_without_translation(mock_popen, home_dir):
    mock_popen.return_value = Mock(wait=Mock(return_value=0))

    manager = make_manager(home_dir, disable_path_translation=True)
    with patch('os.getcwd', return_value=f"{home_dir}/projects"):
        manager.execute_vicar_command("marsmap", ["/data/input.vic"])

    call_args = mock_popen.call_args[0][0]
    assert "/data/input.vic" in call_args
    assert "/host/data/input.vic" not in call_args


# --- signal_command ---

def test_signal_command_forwards_to_the_running_client(home_dir):
    manager = make_manager(home_dir)
    command = MagicMock()
    manager.command = command

    with patch("tig_cli.container.subprocess.run"):
        manager.signal_command(15)

    command.send_signal.assert_called_once_with(15)
    # Waiting here would deadlock against the wait() the main flow is in.
    command.wait.assert_not_called()


def test_signal_command_kills_the_processes_in_the_container(home_dir):
    """Runtimes do not proxy signals to an exec, so tig has to do it."""
    manager = make_manager(home_dir)
    manager.command = MagicMock()
    manager.container_name = "tig-vicar-abc"
    manager.exec_id = "deadbeef"

    with patch("tig_cli.container.subprocess.run") as run:
        manager.signal_command(15)

    command = run.call_args[0][0]
    assert command[:3] == [manager.runtime.executable, "exec", "tig-vicar-abc"]
    assert "TIG_EXEC_ID=deadbeef" in command[-1]
    assert "kill -15" in command[-1]


def test_signal_command_tolerates_a_failing_kill(home_dir):
    manager = make_manager(home_dir)
    manager.command = MagicMock()
    manager.exec_id = "deadbeef"

    with patch("tig_cli.container.subprocess.run", side_effect=OSError):
        manager.signal_command(15)  # should not raise

    manager.command.send_signal.assert_called_once_with(15)


def test_signal_command_tolerates_an_exited_client(home_dir):
    manager = make_manager(home_dir)
    manager.command = MagicMock(
        send_signal=MagicMock(side_effect=ProcessLookupError)
    )

    with patch("tig_cli.container.subprocess.run"):
        manager.signal_command(15)  # should not raise


def test_signal_command_without_running_command(home_dir):
    make_manager(home_dir).signal_command(15)  # should not raise


# --- list_tools ---

def test_list_tools_returns_sorted_unique_names(home_dir):
    runtime = FakeRuntime()
    runtime.exec_output = "marsmesh\nmarsmap\nmarsmap\n"
    manager = make_manager(home_dir, runtime=runtime)
    manager.running = True

    assert manager.list_tools() == ["marsmap", "marsmesh"]


def test_list_tools_asks_only_for_executables(home_dir):
    """The tool directories also hold payloads such as vicario.jar."""
    runtime = FakeRuntime()
    runtime.exec_output = "marsmap\n"
    manager = make_manager(home_dir, runtime=runtime)
    manager.running = True

    assert manager.list_tools() == ["marsmap"]
    command = runtime.command_starting("exec")
    assert "find" in command
    assert "-executable" in command


def test_list_tools_without_a_container(home_dir):
    with pytest.raises(TigError):
        make_manager(home_dir).list_tools()


def test_list_tools_reports_a_failed_listing(home_dir):
    """A failing listing must not turn its stderr into a tool name."""
    runtime = FakeRuntime()
    runtime.fail("exec", message="find: '/usr/local/bin': No such file")
    manager = make_manager(home_dir, runtime=runtime)
    manager.running = True

    with pytest.raises(TigError, match="No such file"):
        manager.list_tools()
