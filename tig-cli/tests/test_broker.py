"""The broker, its agent and a client, exercised for real.

The agent is a bash script that reaches its broker over a socket, so it can
be run next to the tests exactly as it runs in the container: what differs in
production is only which host it dials. The client is run in a subprocess,
because handing over its own standard input, output and error is the point of
the protocol and cannot be faked in-process.
"""
import os
import pathlib
import pty
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import textwrap
import threading
import time

import pytest

from tig_cli import broker, server
from tig_cli.server import Broker, Job
from tig_cli.spec import TigError

CONTAINER = "tig-vicar-test"

pytestmark = pytest.mark.skipif(
    shutil.which("bash") is None or not hasattr(socket, "AF_UNIX"),
    reason="the broker needs bash for its agent and a unix socket for clients",
)


class Session:
    """A broker with its agent, and a way to run commands through them."""

    def __init__(self, home, server):
        self.home = str(home)
        self.server = server

    def _client(self, command, workdir):
        """The argument list of a client running one command."""
        script = textwrap.dedent(
            """
            import sys
            from tig_cli import broker, server
            code = broker.run(
                sys.argv[1], sys.argv[2], sys.argv[4:], sys.argv[3],
                {"DISPLAY": ":9"},
            )
            sys.stderr.flush()
            sys.exit(0 if code is None else code + 1)
            """
        )
        return [
            sys.executable,
            "-c",
            script,
            CONTAINER,
            self.home,
            workdir if workdir is not None else self.home,
            *command,
        ]

    def run(self, command, workdir=None, stdin=None, timeout=30):
        """Run a command through the broker, as a separate process would."""
        return subprocess.run(
            self._client(command, workdir),
            input=stdin if stdin is not None else b"",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )

    def run_with_stdin(self, command, stdin, workdir=None, timeout=30):
        """Run a command with an already open input that reaches no EOF."""
        return subprocess.run(
            self._client(command, workdir),
            stdin=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )

    def start(self, command, workdir=None):
        """Start a command through the broker without waiting for it."""
        script = textwrap.dedent(
            """
            import sys
            from tig_cli import broker, server
            code = broker.run(
                sys.argv[1], sys.argv[2], sys.argv[4:], sys.argv[3], {},
            )
            sys.exit(0 if code is None else code + 1)
            """
        )
        return subprocess.Popen(
            [
                sys.executable,
                "-c",
                script,
                CONTAINER,
                self.home,
                workdir if workdir is not None else self.home,
                *command,
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )


def code_of(result):
    """The exit code the client saw, or None if nothing was run."""
    return None if result.returncode == 0 else result.returncode - 1


@pytest.fixture
def home():
    """A home short enough that the broker's socket path fits in sun_path.

    macOS puts the usual temporary directory somewhere far too long for
    that, so this one is made where the path stays short.
    """
    directory = tempfile.mkdtemp(prefix="tigb", dir="/tmp")
    yield pathlib.Path(directory)
    shutil.rmtree(directory, ignore_errors=True)


class LocalBroker(Broker):
    """A broker whose 'container' is this machine.

    Only how the agent is started differs from production; the agent itself,
    and everything it and the broker then say to each other, is the same.
    """

    def __init__(self, container, home):
        super().__init__(container, home)
        self.agent = None

    def launch_agent(self) -> bool:
        self.agent = subprocess.Popen(
            [
                "bash",
                "-c",
                broker.AGENT,
                "tig-agent",
                "127.0.0.1",
                str(self.port),
            ],
            env={**os.environ, "TIG_BROKER_TOKEN": self.token},
        )
        return True


@pytest.fixture
def session(home):
    server = LocalBroker(CONTAINER, str(home))
    serving = threading.Thread(target=server.serve, daemon=True)
    serving.start()
    deadline = time.monotonic() + 30
    while server.control is None:
        assert time.monotonic() < deadline, "the agent never called back"
        time.sleep(0.01)

    yield Session(home, server)

    server.agent.terminate()
    server.agent.wait(timeout=10)
    serving.join(timeout=30)
    assert not serving.is_alive(), "the broker did not stop with its agent"


def test_runs_a_command_and_reports_its_output(session):
    result = session.run(["sh", "-c", "echo out; echo err >&2"])

    assert code_of(result) == 0
    assert result.stdout == b"out\n"
    assert result.stderr == b"err\n"


def test_reports_the_exit_status(session):
    assert code_of(session.run(["sh", "-c", "exit 7"])) == 7


def test_runs_in_the_requested_directory(session, home):
    workdir = home / "work"
    workdir.mkdir()

    result = session.run(["pwd"], workdir=str(workdir))

    assert result.stdout.strip() == str(workdir).encode()


def test_passes_the_display_through(session):
    result = session.run(["sh", "-c", "echo $DISPLAY"])

    assert result.stdout.strip() == b":9"


def test_passes_arguments_exactly(session):
    awkward = ["a b", "*", "", "-n", "'quoted'", "$HOME", "tab\there"]
    echo_each = 'for a in "$@"; do echo "[$a]"; done'

    result = session.run(["sh", "-c", echo_each, "sh", *awkward])

    assert result.stdout.decode().splitlines() == [f"[{a}]" for a in awkward]


def test_carries_large_output(session):
    size = 4 << 20

    result = session.run(["sh", "-c", f"yes 0123456789 | head -c {size}"])

    assert code_of(result) == 0
    assert len(result.stdout) == size


def test_keeps_output_and_errors_apart(session):
    result = session.run(
        ["sh", "-c", "for i in 1 2 3; do echo o$i; echo e$i >&2; done"]
    )

    assert result.stdout == b"o1\no2\no3\n"
    assert result.stderr == b"e1\ne2\ne3\n"


def test_forwards_the_client_s_input(session):
    result = session.run(["cat"], stdin=b"hello\n")

    assert result.stdout == b"hello\n"


def test_forwards_input_larger_than_a_pipe(session):
    payload = b"x" * (4 << 20)

    result = session.run(["cat"], stdin=payload, timeout=60)

    assert code_of(result) == 0
    assert len(result.stdout) == len(payload)


def test_a_command_reading_nothing_still_ends(session):
    result = session.run(["sh", "-c", "echo done"], stdin=b"y" * (1 << 20))

    assert code_of(result) == 0
    assert result.stdout == b"done\n"


def test_a_command_whose_input_never_ends_is_answered_at_once(session):
    """A tty stdin reaches no EOF, and waiting for one would cost the grace."""
    started = time.monotonic()
    session.run(["true"])
    with_eof = time.monotonic() - started

    reader, writer = pty.openpty()
    try:
        started = time.monotonic()
        result = session.run_with_stdin(["true"], writer)
        without_eof = time.monotonic() - started
    finally:
        os.close(writer)
        os.close(reader)

    assert code_of(result) == 0
    assert without_eof < with_eof + server.OUTPUT_GRACE / 2


def test_reports_a_command_that_does_not_exist(session):
    result = session.run(["definitely-not-a-tool"])

    assert code_of(result) == 127
    assert result.stderr == b"tig: definitely-not-a-tool: not found\n"


def test_declines_a_working_directory_that_is_not_there(session, home):
    result = session.run(["pwd"], workdir=str(home / "nowhere"))

    assert code_of(result) is None


def test_declines_arguments_it_cannot_express(session):
    assert code_of(session.run(["echo", "two\nlines"])) is None


def test_declines_when_no_broker_is_listening(home):
    assert broker.run(CONTAINER, str(home), ["true"], str(home), {}) is None


def test_declines_when_disabled(session, monkeypatch):
    monkeypatch.setenv(broker.DISABLE_ENV, "1")

    assert broker.run(CONTAINER, session.home, ["true"], session.home, {}) is None


@pytest.mark.skipif(
    not sys.platform.startswith("linux"),
    reason="job control is the container's, and macOS's bash 3.2 is not it",
)
def test_forwards_an_interrupt_to_the_command(session, home):
    running = session.start(_waits_for(home, "INT", 3))
    _wait_for(home / "ready")

    running.send_signal(signal.SIGINT)

    assert running.wait(timeout=30) - 1 == 3
    assert (home / "caught").read_text() == "INT\n"


@pytest.mark.skipif(
    not sys.platform.startswith("linux"),
    reason="job control is the container's, and macOS's bash 3.2 is not it",
)
def test_the_command_s_children_are_stopped_too(session, home):
    """A tool that spawns children must not leave them in the container."""
    running = session.start(
        [
            "sh",
            "-c",
            f"sleep 300 & echo $! > {home / 'child'}; wait",
        ]
    )
    _wait_for(home / "child")
    child = int((home / "child").read_text())

    running.kill()
    running.wait(timeout=30)

    deadline = time.monotonic() + 30
    while _alive(child):
        assert time.monotonic() < deadline, "a child of the command was left"
        time.sleep(0.05)


def test_serves_several_clients_at_once(session):
    script = "sleep 0.$((RANDOM % 3)); echo job$1; exit $(($1 % 4))"
    running = [
        session.start(["sh", "-c", script, "sh", str(index)])
        for index in range(8)
    ]

    results = [(process, process.communicate(timeout=60)) for process in running]

    for index, (process, (out, _)) in enumerate(results):
        assert out == f"job{index}\n".encode()
        assert process.returncode - 1 == index % 4


def test_ends_a_command_whose_client_is_killed(session, home):
    running = session.start(_waits_for(home, "TERM", 4))
    _wait_for(home / "ready")

    running.kill()
    running.wait(timeout=30)

    # The command is told to stop rather than being left behind.
    _wait_for(home / "caught")


def test_survives_a_client_that_asks_for_nothing(session):
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.connect(broker.socket_path(session.home, CONTAINER))
    connection.close()

    assert code_of(session.run(["echo", "still here"])) == 0


def test_retire_stops_new_clients(session):
    broker.retire(session.home, CONTAINER)

    assert code_of(session.run(["true"])) is None


def test_a_command_already_running_is_never_reported_as_unrun(session, home):
    """Losing the agent must not have the caller run the command again."""
    running = session.start(_waits_for(home, "TERM", 4))
    _wait_for(home / "ready")

    session.server.agent.kill()

    assert running.wait(timeout=30) != 0


def test_a_broker_leaves_its_successor_s_socket_alone(home):
    first = LocalBroker(CONTAINER, str(home))
    broker.retire(str(home), CONTAINER)
    second = LocalBroker(CONTAINER, str(home))

    first._close()

    assert os.path.exists(second.address)
    second._close()
    assert not os.path.exists(second.address)


def test_a_job_whose_grace_has_passed_asks_for_no_wakeup():
    """A deadline in the past would have select() return at once, spinning."""
    job = Job.__new__(Job)
    job.deadline = 0.0
    job.grace_until = time.monotonic() - 1

    assert job.next_deadline() is None


def test_a_broker_that_goes_quiet_is_an_error_not_a_second_run():
    with pytest.raises(TigError):
        broker._status(b"")


def test_a_spawned_broker_is_told_which_runtime_to_use(home, monkeypatch):
    """It runs on its own later, so the choice cannot be made again then."""
    calls = []
    monkeypatch.setattr(
        subprocess, "Popen", lambda *args, **kwargs: calls.append(kwargs)
    )

    broker._spawn("tig-vicar-abc", str(home), "/opt/podman/bin/podman")

    assert calls[0]["env"]["TIG_CONTAINER_RUNTIME"] == "/opt/podman/bin/podman"


def test_the_agent_dials_a_runtime_named_by_path_by_its_gateway(monkeypatch):
    """A runtime off PATH is passed on as a path, which names no gateway."""
    monkeypatch.setattr(server.sys, "platform", "darwin")
    monkeypatch.setenv("TIG_CONTAINER_RUNTIME", "/opt/homebrew/bin/podman")

    assert server.host_address() == "host.containers.internal"


def test_the_agent_dials_the_gateway_of_the_runtime_in_use(monkeypatch):
    """Each runtime names the host differently in its virtual machine."""
    monkeypatch.setattr(server.sys, "platform", "darwin")
    monkeypatch.setenv("TIG_CONTAINER_RUNTIME", "finch")

    assert server.host_address() == "host.lima.internal"

    # nerdctl runs in a Lima machine on macOS too, whoever started it.
    monkeypatch.setenv("TIG_CONTAINER_RUNTIME", "nerdctl")

    assert server.host_address() == "host.lima.internal"


def test_the_agent_dials_the_host_directly_on_linux(monkeypatch):
    monkeypatch.setattr(server.sys, "platform", "linux")

    assert server.host_address() == "127.0.0.1"


def _waits_for(home, signal_name, code):
    """A command that waits, and says so, until it is signalled."""
    return [
        "sh",
        "-c",
        f"trap 'echo {signal_name} > {home / 'caught'}; exit {code}'"
        f" {signal_name}; echo ready > {home / 'ready'}; sleep 30 & wait",
    ]


def _alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _wait_for(path, timeout=30):
    deadline = time.monotonic() + timeout
    while not path.exists():
        assert time.monotonic() < deadline, f"{path} never appeared"
        time.sleep(0.02)


@pytest.mark.parametrize(
    "container",
    ["", ".", "..", "../escaped", "a/../../escaped", "/tmp/escaped", ".hidden",
     "-flag", "tig vicar", "tig\x00vicar"],
)
def test_a_broker_refuses_a_container_name_that_is_not_one(home, container):
    """The socket and its directory never land outside the user's cache."""
    with pytest.raises(OSError):
        Broker(container, str(home))

    assert list(home.iterdir()) == []


def test_a_broker_refuses_a_home_that_is_not_a_directory(home):
    missing = home / "missing"
    not_a_directory = home / "file"
    not_a_directory.write_text("")

    for candidate in (missing, not_a_directory):
        with pytest.raises(OSError):
            Broker(CONTAINER, str(candidate))

    assert sorted(path.name for path in home.iterdir()) == ["file"]


def test_a_broker_s_address_is_its_own_directory_under_the_cache(home):
    name = "tig-vicar-0123456789ab"
    address = server.broker_address(name, str(home / "sub" / ".."))

    assert address == broker.socket_path(str(home), name)
    assert os.path.dirname(address) == str(home / ".cache" / "tig" / name)


def test_a_relative_home_is_made_absolute(home, monkeypatch):
    monkeypatch.chdir(home)

    address = server.broker_address(CONTAINER, ".")

    assert address == broker.socket_path(os.getcwd(), CONTAINER)


def test_the_broker_command_exits_unavailable_on_a_traversing_container(home):
    assert broker.main(["../../escaped", str(home)]) == 69
    assert list(home.iterdir()) == []
