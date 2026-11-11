"""The broker process: one per container, started on demand.

It owns the one connection the container's agent keeps to the host, and for
each ``tig`` invocation it splices that invocation's own standard input,
output and error - received as file descriptors over its unix socket - onto
the sockets the agent opens for the command. The command's bytes therefore
never pass through the client, and nothing but the first command of a session
costs a container exec.

Everything here is one non-blocking loop: a slow reader on one command's
output must not hold up another's, so every descriptor is written to only
when it says it is ready, and reading stops while what was read is waiting to
go out.

See :mod:`tig_cli.broker` for the client side and the agent's script.
"""
from __future__ import annotations

import array
import errno
import os
import re
import secrets
import select
import selectors
import socket
import sys
import time

from .broker import (
    AGENT,
    IDLE_TIMEOUT,
    READ_SIZE,
    SHELL,
    STARTUP_TIMEOUT,
    socket_path,
)
from .config import env_runtime
from .spec import RUNNER_MARKER, host_gateway


def host_address() -> str:
    """What the agent dials to reach this broker.

    On macOS the container runs in a virtual machine and reaches the host by
    the name its runtime gives the gateway; on Linux it shares the host's
    network stack.
    """
    if sys.platform != "darwin":
        return "127.0.0.1"
    # The runtime may be named by path; the gateway goes by the command.
    return host_gateway(os.path.basename(env_runtime() or "docker"))


# Sent to a client whose command was never started, telling it to run the
# command itself.
UNSTARTED = b"unstarted\n"

# What a pipe that reports itself writable is guaranteed to accept.
PIPE_BUF = select.PIPE_BUF

# How long output is still collected after the command has exited. A child
# it left behind holds the same streams, so waiting for them to close would
# be waiting for that child - but output in flight must not be lost either.
OUTPUT_GRACE = 0.2

# How much of a command's output may be held here before it stops being read
# from the container, so that a command producing faster than the caller
# reads is slowed down rather than buffered without end.
HIGH_WATER = 1 << 20

# What Docker and Podman accept as a container name. It cannot be empty, hold
# a separator or start with a dot, so it is always one path component of its
# own - never ``..``.
CONTAINER_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*")


def broker_address(container: str, home: str) -> str:
    """Where the broker for ``container`` listens, kept inside ``home``'s cache.

    Both arrive as command-line arguments, so neither may steer the socket -
    or the directory made for it, or the stale socket removed in its place -
    anywhere but its own directory under ``<home>/.cache/tig``.

    Raises:
        OSError: ``container`` is not a container name or ``home`` is not a
            directory.
    """
    if not CONTAINER_NAME.fullmatch(container):
        raise OSError(errno.EINVAL, f"not a container name: {container!r}")
    home = os.path.abspath(home)
    if not os.path.isdir(home):
        raise OSError(errno.ENOTDIR, f"not a directory: {home!r}")
    root = os.path.join(home, ".cache", "tig")
    address = os.path.abspath(socket_path(home, container))
    if (
        not address.startswith(root + os.sep)
        or os.path.dirname(os.path.dirname(address)) != root
    ):
        raise OSError(errno.EINVAL, f"broker socket outside {root!r}: {address!r}")
    return address


class Broker:
    """Serves one container's commands until it is idle or its agent goes."""

    def __init__(self, container: str, home: str):
        self.container = container
        self.address = broker_address(container, home)
        self.token = secrets.token_hex(16)
        self.selector = selectors.SelectSelector()
        self.jobs: dict[str, Job] = {}
        self.greeting: dict[socket.socket, bytes] = {}
        self.control: socket.socket | None = None
        self.jobs_started = 0
        self.idle_until = time.monotonic() + IDLE_TIMEOUT

        os.makedirs(os.path.dirname(self.address), mode=0o700, exist_ok=True)
        self.clients = _listen_unix(self.address)
        bound = os.stat(self.address)
        self.bound = (bound.st_dev, bound.st_ino)
        self.agents = _listen_tcp()
        self.port = self.agents.getsockname()[1]
        self.selector.register(self.clients, selectors.EVENT_READ, ("clients", None))
        self.selector.register(self.agents, selectors.EVENT_READ, ("agents", None))

    def serve(self) -> int:
        """Run until the agent goes or nothing has been asked for a while."""
        try:
            if not self._start_agent():
                return 69
            self._loop()
        finally:
            self._close()
        return 0

    def _start_agent(self) -> bool:
        return self.launch_agent() and self._await_agent()

    def launch_agent(self) -> bool:
        """Start the agent in the container; it dials back from there."""
        from .engine import Engine, EngineError

        try:
            Engine.detect().exec_detached(
                self.container,
                [
                    SHELL,
                    "-c",
                    AGENT,
                    "tig-agent",
                    host_address(),
                    str(self.port),
                    RUNNER_MARKER,
                ],
                {"TIG_BROKER_TOKEN": self.token},
            )
        except (EngineError, OSError):
            return False
        return True

    def _await_agent(self) -> bool:
        deadline = time.monotonic() + STARTUP_TIMEOUT
        while self.control is None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            for key, event in self.selector.select(timeout=remaining):
                self._ready(key, event)
        return True

    def _loop(self) -> None:
        while self.control is not None:
            now = time.monotonic()
            if self.jobs:
                # A command still running is not idleness: an idle deadline
                # left behind would have every select() return at once.
                self.idle_until = now + IDLE_TIMEOUT
            deadlines = [self.idle_until] + [
                deadline
                for deadline in (job.next_deadline() for job in self.jobs.values())
                if deadline is not None
            ]
            events = self.selector.select(timeout=max(0.0, min(deadlines) - now))
            for key, event in events:
                self._ready(key, event)
            self._expire()
            if not events and not self.jobs:
                if time.monotonic() >= self.idle_until:
                    return

    def _ready(self, key: selectors.SelectorKey, event: int) -> None:
        # An earlier event in the same round may have finished a job and
        # closed what this one is about.
        if self.selector.get_map().get(key.fd) is not key:
            return
        kind, job = key.data
        if kind == "clients":
            self._accept_client()
        elif kind == "agents":
            self._accept_agent()
        elif kind == "greeting":
            self._read_greeting(key.fileobj)
        elif kind == "control":
            self._read_control()
        elif job is not None:
            job.ready(kind, event)
            if job.finished():
                self._finish(job, job.answer())

    # Clients ------------------------------------------------------------

    def _accept_client(self) -> None:
        try:
            connection, _ = self.clients.accept()
        except OSError:
            return
        self.idle_until = time.monotonic() + IDLE_TIMEOUT
        try:
            request, fds = _receive_request(connection)
        except OSError:
            request, fds = None, []
        if request is None or len(fds) != 3 or self.control is None:
            for fd in fds:
                _close_fd(fd)
            _answer(connection, UNSTARTED)
            connection.close()
            return
        self._start_job(connection, request, fds)

    def _start_job(
        self, connection: socket.socket, request: list[str], fds: list[int]
    ) -> None:
        assert self.control is not None
        self.jobs_started += 1
        job = Job(str(self.jobs_started), self, connection, fds)
        self.jobs[job.id] = job

        workdir, display, *command = request
        message = (
            f"job {job.id} {len(command)}\n"
            + "\n".join([workdir, display, *command])
            + "\n"
        )
        try:
            self.control.sendall(message.encode())
        except OSError:
            self._finish(job, UNSTARTED)

    # The agent ----------------------------------------------------------

    def _accept_agent(self) -> None:
        try:
            connection, _ = self.agents.accept()
        except OSError:
            return
        connection.setblocking(False)
        self.greeting[connection] = b""
        self.selector.register(
            connection, selectors.EVENT_READ, ("greeting", None)
        )

    def _read_greeting(self, connection: socket.socket) -> None:
        """Work out what an incoming connection is: the agent, or a stream."""
        data = _recv(connection)
        if not data:
            self.greeting.pop(connection, None)
            _drop(self.selector, connection)
            return
        buffered = self.greeting.get(connection, b"") + data
        if b"\n" not in buffered:
            self.greeting[connection] = buffered
            return

        line, rest = buffered.split(b"\n", 1)
        self.greeting.pop(connection, None)
        # Whoever takes the connection on registers it for themselves.
        self.selector.unregister(connection)

        parts = line.decode("utf-8", "replace").split()
        if parts[:2] == ["hello", self.token] and self.control is None:
            self.control = connection
            self.selector.register(
                connection, selectors.EVENT_READ, ("control", None)
            )
            return

        job = self.jobs.get(parts[2]) if len(parts) == 4 else None
        if (
            job is None
            or parts[0] != "stream"
            or parts[1] != self.token
            or not job.attach(parts[3], connection, rest)
        ):
            _close(connection)

    def _read_control(self) -> None:
        """The agent's own connection carries nothing back; it only ends."""
        assert self.control is not None
        if _recv(self.control):
            return
        _drop(self.selector, self.control)
        self.control = None
        for job in list(self.jobs.values()):
            self._finish(job, job.answer())

    def tell_agent(self, message: str) -> None:
        if self.control is None:
            return
        try:
            self.control.sendall(message.encode())
        except OSError:
            pass

    # Housekeeping -------------------------------------------------------

    def _expire(self) -> None:
        """End jobs whose streams never opened, or have said all they will."""
        now = time.monotonic()
        for job in list(self.jobs.values()):
            if job.stalled(now):
                self._finish(job, UNSTARTED)
            elif job.finished(now):
                self._finish(job, job.answer())

    def _finish(self, job: Job, answer: bytes) -> None:
        self.jobs.pop(job.id, None)
        job.close(answer)
        self.idle_until = time.monotonic() + IDLE_TIMEOUT

    def _close(self) -> None:
        for job in list(self.jobs.values()):
            self._finish(job, job.answer())
        for source in (self.clients, self.agents, self.control):
            if source is not None:
                _drop(self.selector, source)
        self._unlink_own_socket()

    def _unlink_own_socket(self) -> None:
        """Remove the socket file, unless it is a successor's by now."""
        try:
            current = os.stat(self.address)
        except OSError:
            return
        if (current.st_dev, current.st_ino) != self.bound:
            return
        try:
            os.unlink(self.address)
        except OSError:
            pass


class Job:
    """One command: the client's descriptors and the agent's three sockets.

    ``in`` carries the command's input to the container and, the other way,
    the agent's word on how the command is getting on; ``out`` and ``err``
    carry what it writes.
    """

    def __init__(
        self,
        identifier: str,
        broker: Broker,
        client: socket.socket,
        fds: list[int],
    ):
        self.id = identifier
        self.broker = broker
        self.selector = broker.selector
        self.client = client
        self.fds = {"in": fds[0], "out": fds[1], "err": fds[2]}
        self.streams: dict[str, socket.socket] = {}
        self.buffers = {"in": b"", "out": b"", "err": b""}
        self.ended = {"in": False, "out": False, "err": False}
        self.reported = b""
        self.status: int | None = None
        self.unstarted = False
        self.pid: int | None = None
        self.deadline = time.monotonic() + STARTUP_TIMEOUT
        self.grace_until = 0.0
        self.watching: dict[object, int] = {}

        self.client.setblocking(False)
        self._watch(self.client, selectors.EVENT_READ, "client")

    # Setting up ---------------------------------------------------------

    def attach(self, name: str, connection: socket.socket, rest: bytes) -> bool:
        """Take on one of the three connections the agent opened for us."""
        if name not in self.fds or name in self.streams:
            return False
        self.streams[name] = connection
        self.deadline = 0.0
        self._watch(connection, selectors.EVENT_READ, name)
        if name == "in":
            self._watch(self.fds["in"], selectors.EVENT_READ, "stdin")
        if rest:
            self.ready(name, selectors.EVENT_READ, buffered=rest)
        return True

    def stalled(self, now: float) -> bool:
        return bool(self.deadline) and now >= self.deadline

    def next_deadline(self) -> float | None:
        """When this job next needs looking at, whatever it is waiting on."""
        if self.deadline:
            return self.deadline
        # Once the grace period is past there is nothing to wake for: output
        # left over finishes the job when its reader next takes it.
        if self.grace_until and self.grace_until > time.monotonic():
            return self.grace_until
        return None

    # Moving bytes -------------------------------------------------------

    def ready(self, kind: str, event: int, buffered: bytes = b"") -> None:
        if kind == "client":
            self._client_spoke()
        elif kind == "stdin":
            self._take_input()
        elif kind == "in":
            if event & selectors.EVENT_WRITE:
                self._send_input()
            if event & selectors.EVENT_READ:
                self._agent_spoke(buffered)
        elif kind in ("out", "err"):
            if event & selectors.EVENT_READ or buffered:
                self._take_output(kind, buffered)
        elif kind in ("stdout", "stderr"):
            self._give_output("out" if kind == "stdout" else "err")

    def _client_spoke(self) -> None:
        """The client only asks for a signal to be passed on, or goes away."""
        data = _recv(self.client)
        if not data:
            self._signal(15)
            self.ended = dict.fromkeys(self.ended, True)
            self.buffers = dict.fromkeys(self.buffers, b"")
            if self.status is None:
                self.status = 128 + 15
            return
        for line in data.split(b"\n"):
            parts = line.split()
            if parts[:1] == [b"signal"]:
                number = _number(parts[1:])
                if number is not None:
                    self._signal(number)

    def _signal(self, signum: int) -> None:
        if self.pid is not None:
            self.broker.tell_agent(f"kill {self.pid} {signum}\n")

    def _take_input(self) -> None:
        """Read what the caller typed or piped in, EOF closing the write."""
        fd = self.fds["in"]
        try:
            data = os.read(fd, READ_SIZE)
        except (BlockingIOError, InterruptedError):
            return
        except OSError:
            data = b""
        if not data:
            self.ended["in"] = True
            self._unwatch(fd)
            if not self.buffers["in"]:
                self._end_input()
            return
        self.buffers["in"] += data
        self._send_input()

    def _send_input(self) -> None:
        connection = self.streams.get("in")
        if connection is None:
            return
        while self.buffers["in"]:
            try:
                sent = connection.send(self.buffers["in"][:READ_SIZE])
            except (BlockingIOError, InterruptedError):
                break
            except OSError:
                # The command is not reading its input any more.
                self.buffers["in"] = b""
                self.ended["in"] = True
                self._unwatch(self.fds["in"])
                return
            self.buffers["in"] = self.buffers["in"][sent:]

        waiting = bool(self.buffers["in"])
        self._watch(
            connection,
            selectors.EVENT_READ | (selectors.EVENT_WRITE if waiting else 0),
            "in",
        )
        # Read ahead only while what was read has gone out.
        if not self.ended["in"]:
            self._watch(
                self.fds["in"],
                0 if waiting else selectors.EVENT_READ,
                "stdin",
            )
        elif not waiting:
            self._end_input()

    def _end_input(self) -> None:
        connection = self.streams.get("in")
        if connection is None:
            return
        try:
            connection.shutdown(socket.SHUT_WR)
        except OSError:
            pass

    def _agent_spoke(self, buffered: bytes = b"") -> None:
        connection = self.streams["in"]
        data = buffered + _recv(connection)
        if not data:
            if self.status is None:
                # The agent's job shell went without a word: nothing can be
                # said about the command, so it counts as never started only
                # if it had not got as far as running.
                self.unstarted = self.pid is None
                self.status = None if self.unstarted else 125
            self.ended["in"] = True
            return
        self.reported += data
        while b"\n" in self.reported:
            line, self.reported = self.reported.split(b"\n", 1)
            parts = line.split()
            if parts[:1] == [b"pid"]:
                self.pid = _number(parts[1:])
            elif parts[:1] == [b"status"]:
                self.status = _number(parts[1:])
                self.grace_until = time.monotonic() + OUTPUT_GRACE
            elif parts[:1] == [b"unstarted"]:
                self.unstarted = True

    def _take_output(self, name: str, buffered: bytes = b"") -> None:
        connection = self.streams[name]
        data = buffered + _recv(connection)
        if not data:
            self.ended[name] = True
            self._unwatch(connection)
        else:
            self.buffers[name] += data
        self._give_output(name)

    def _give_output(self, name: str) -> None:
        """Write to the descriptor the client gave us, if it will take it."""
        fd = self.fds[name]
        if fd < 0:
            self.buffers[name] = b""
            return
        while self.buffers[name] and _writable(fd):
            try:
                # A pipe that selects writable takes this much without
                # blocking, and the descriptor is the client's to leave alone.
                written = os.write(fd, self.buffers[name][:PIPE_BUF])
            except (BlockingIOError, InterruptedError):
                break
            except OSError:
                # Nobody is reading (``tig list big.img | head``); the
                # command still has to be seen through to its exit status.
                self.buffers[name] = b""
                self.fds[name] = -1
                self._unwatch(fd)
                break
            self.buffers[name] = self.buffers[name][written:]

        waiting = bool(self.buffers[name])
        if fd >= 0:
            self._watch(
                fd, selectors.EVENT_WRITE if waiting else 0, _stream_name(name)
            )
        connection = self.streams.get(name)
        if connection is not None and not self.ended[name]:
            self._watch(
                connection,
                0 if len(self.buffers[name]) >= HIGH_WATER else selectors.EVENT_READ,
                name,
            )

    # Finishing ----------------------------------------------------------

    def finished(self, now: float | None = None) -> bool:
        if self.unstarted:
            return True
        if self.status is None or any(self.buffers[n] for n in ("out", "err")):
            return False
        if all(self.ended[name] for name in ("out", "err")):
            return True
        return (now or time.monotonic()) >= self.grace_until

    def answer(self) -> bytes:
        if self.status is not None:
            return f"{self.status}\n".encode()
        if self.pid is None:
            return UNSTARTED
        # It had started when we lost sight of it; saying nothing ran would
        # have the client run it a second time.
        return b"125\n"

    def close(self, answer: bytes) -> None:
        for name in ("out", "err"):
            self._blocking_flush(name)
        for source in list(self.watching):
            self._unwatch(source)
        for connection in self.streams.values():
            _close(connection)
        _answer(self.client, answer)
        _close(self.client)
        for fd in self.fds.values():
            _close_fd(fd)

    def _blocking_flush(self, name: str) -> None:
        """Get the last of the output out, now that there is time to wait."""
        fd = self.fds[name]
        if fd < 0 or not self.buffers[name]:
            return
        try:
            os.set_blocking(fd, True)
            os.write(fd, self.buffers[name])
        except OSError:
            pass
        self.buffers[name] = b""

    # The selector -------------------------------------------------------

    def _watch(self, source, events: int, kind: str) -> None:
        """Register, change or drop interest in one descriptor or socket."""
        if isinstance(source, int) and source < 0:
            return
        current = self.watching.get(source)
        if current == events:
            return
        try:
            if events == 0:
                self.selector.unregister(source)
                del self.watching[source]
                return
            if current is None:
                self.selector.register(source, events, (kind, self))
            else:
                self.selector.modify(source, events, (kind, self))
        except (KeyError, ValueError, OSError):
            self.watching.pop(source, None)
            return
        self.watching[source] = events

    def _unwatch(self, source) -> None:
        self._watch(source, 0, "")


def _stream_name(name: str) -> str:
    return "stdout" if name == "out" else "stderr"


def _number(parts: list[bytes]) -> int | None:
    try:
        return int(parts[0])
    except (IndexError, ValueError):
        return None


def _writable(fd: int) -> bool:
    """Whether this descriptor will take output now.

    The client's descriptors are its own, so they cannot be made
    non-blocking here; they are only written to when they say they are ready.
    """
    try:
        return bool(select.select([], [fd], [], 0)[1])
    except (OSError, ValueError):
        return False


def _recv(connection: socket.socket) -> bytes:
    try:
        return connection.recv(READ_SIZE)
    except (BlockingIOError, InterruptedError):
        return b""
    except OSError:
        return b""


def _close(connection: socket.socket) -> None:
    try:
        connection.close()
    except OSError:
        pass


def _close_fd(fd: int) -> None:
    if fd < 0:
        return
    try:
        os.close(fd)
    except OSError:
        pass


def _drop(selector: selectors.BaseSelector, source) -> None:
    try:
        selector.unregister(source)
    except (KeyError, ValueError):
        pass
    _close(source)


def _answer(connection: socket.socket, answer: bytes) -> None:
    try:
        connection.setblocking(True)
        connection.sendall(answer)
    except OSError:
        pass


def _listen_unix(address: str) -> socket.socket:
    """Listen for clients, refusing to displace a broker already serving."""
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    # The socket is owner-only from the moment it exists; tightening it after
    # binding would leave a moment in which anyone could connect.
    previous = os.umask(0o177)
    try:
        try:
            server.bind(address)
        except OSError as e:
            if e.errno != errno.EADDRINUSE:
                raise
            if _answering(address):
                raise
            os.unlink(address)
            server.bind(address)
    finally:
        os.umask(previous)
    os.chmod(address, 0o600)
    server.listen(64)
    server.setblocking(False)
    return server


def _answering(address: str) -> bool:
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        probe.connect(address)
    except OSError:
        return False
    finally:
        probe.close()
    return True


def _listen_tcp() -> socket.socket:
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(("127.0.0.1", 0))
    server.listen(64)
    server.setblocking(False)
    return server


def _receive_request(
    connection: socket.socket,
) -> tuple[list[str] | None, list[int]]:
    """Read a client's request and the three descriptors that came with it."""
    connection.setblocking(True)
    connection.settimeout(STARTUP_TIMEOUT)
    fds = array.array("i")
    message, ancillary, _, _ = connection.recvmsg(4, socket.CMSG_SPACE(3 * 4))
    for level, kind, data in ancillary:
        if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
            fds.frombytes(data[: len(data) - (len(data) % fds.itemsize)])
    if len(message) != 4 or len(fds) != 3:
        return None, list(fds)

    size = int.from_bytes(message, "big")
    payload = b""
    while len(payload) < size:
        chunk = connection.recv(min(READ_SIZE, size - len(payload)))
        if not chunk:
            return None, list(fds)
        payload += chunk
    connection.settimeout(None)

    request = payload.decode("utf-8", "replace").split("\n")
    if request and request[-1] == "":
        request.pop()
    if len(request) < 3:
        return None, list(fds)
    return request, list(fds)
