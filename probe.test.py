#!/usr/bin/env python3
"""Probe fixtures use fake commands and sleeping processes, never screen capture."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent


def portal(name):
    return [
        {"id": 1, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": "xdph-test"}}},
        {"id": 2, "type": "PipeWire:Interface:Node", "info": {"props": {"application.name": name}}},
        {"type": "PipeWire:Interface:Link", "info": {"output-node-id": 1, "input-node-id": 2}},
    ]


with tempfile.TemporaryDirectory(prefix="screencast-check-") as directory:
    tmp = Path(directory)
    calls = tmp / "calls"
    shims = {
        "pw-dump": 'case "$TEST_MODE" in failure) exit 7;; malformed) printf "[";; timeout) exec sleep 2;; stubborn) trap "" TERM; exec sleep 2;; *) printf "%s\\n" "$TEST_GRAPH";; esac',
        "pgrep": 'if [[ " $* " == *" -a "* ]]; then printf "%s\\n" "$TEST_COMMANDS"; else printf "%s\\n" "$TEST_PIDS"; fi',
        "ss": 'printf "%s\\n" "$TEST_SOCKETS"',
        "ps": 'printf "%s\\n" "$TEST_CLIENTS"',
    }
    for name, body in shims.items():
        path = tmp / name
        path.write_text('#!/bin/bash\nprintf "%s\\n" "${0##*/}" >> "$TEST_CALLS"\n' + body + "\n")
        path.chmod(0o755)

    def run(graph=(), processes=(), sockets="", clients="", display="test-wayland", mode="", expected=0):
        calls.write_text("")
        env = dict(os.environ, PATH=str(tmp) + os.pathsep + os.environ["PATH"],
                   XDG_RUNTIME_DIR=str(tmp), WAYLAND_DISPLAY=display,
                   TEST_CALLS=str(calls), TEST_GRAPH=json.dumps(list(graph)), TEST_MODE=mode,
                   TEST_PIDS="\n".join(str(p.pid) for p in processes),
                   TEST_COMMANDS="\n".join(str(p.pid) + " " + " ".join(p.args) for p in processes),
                   TEST_SOCKETS=sockets, TEST_CLIENTS=clients)
        result = subprocess.run(["bash", str(ROOT / "probe.sh")], env=env,
                                capture_output=True, text=True, timeout=4)
        assert result.returncode == expected, (result.returncode, result.stderr)
        assert not result.stderr, result.stderr
        return result.stdout.splitlines(), calls.read_text().splitlines()

    assert run()[0] == []
    for mode in ("failure", "malformed", "timeout"):
        assert run(mode=mode, expected=1)[0] == []
    start = time.monotonic()
    assert run(mode="stubborn", expected=1)[0] == []
    assert time.monotonic() - start < 1.8, "probe waited for a process that ignored SIGTERM"
    names, invoked = run(portal("Example browser"))
    assert names == ["A Example browser"]
    assert "ss" not in invoked and "ps" not in invoked
    assert run(portal("Example\nA injected\tapp"))[0] == ["A Example A injected app"]
    markup = '<img src="https://example.invalid/">'
    assert run(portal(markup))[0] == ["A " + markup]
    assert run([{"type": "PipeWire:Interface:Node", "id": 1, "info": {"props": {"node.name": "ordinary-node"}}}])[0] == []

    socket = str(tmp / "test-wayland")
    sockets = f'u_str ESTAB 0 0 {socket} 111 * 222\nu_str ESTAB 0 0 * 222 * 111 users:(("example",pid=1,fd=5))'
    assert run(sockets=sockets, clients="2 1 Example client")[0] == ["N Example client"]
    assert run(sockets=sockets, clients="2 1 wl-paste")[0] == []
    assert run(sockets=sockets, clients="6 1 Old client")[0] == []
    assert run(sockets=sockets, clients="2 1 Example client", display=socket)[0] == ["N Example client"]

    sleepers = []
    try:
        for name, prefix in (("wf-recorder", "A"), ("obs", "N")):
            executable = tmp / name
            executable.symlink_to(shutil.which("sleep"))
            process = subprocess.Popen([str(executable), "30"])
            sleepers.append(process)
            names, invoked = run(processes=[process])
            assert len(names) == 1 and names[0].startswith(prefix + " " + name)
            assert ("ss" not in invoked) == (prefix == "A")
            if prefix == "A":
                assert run(processes=[process], mode="failure")[0][0].startswith("A " + name)

        harmless = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)", "gpu-screen-recorder"])
        sleepers.append(harmless)
        assert run(processes=[harmless])[0] == []

        script = tmp / "tools with spaces" / "grim"
        script.parent.mkdir()
        script.write_text("#!/bin/bash\nsleep 30\n")
        wrapped = subprocess.Popen(["bash", "-e", str(script)], start_new_session=True)
        sleepers.append(wrapped)
        assert run(processes=[wrapped])[0][0].startswith("N grim")

        agent = tmp / "codex"
        agent.symlink_to(shutil.which("bash"))
        parent = subprocess.Popen([str(agent), "-c", '"$1" 30 & printf "%s\\n" "$!"; wait',
                                   "test", str(tmp / "wf-recorder")], stdout=subprocess.PIPE,
                                  text=True, start_new_session=True)
        sleepers.append(parent)
        child_pid = int(parent.stdout.readline())
        child = type("Child", (), {"pid": child_pid, "args": [str(tmp / "wf-recorder"), "30"]})()
        assert run(processes=[child])[0] == ["A wf-recorder via codex"]
    finally:
        for process in sleepers:
            if process.pid == os.getpgid(process.pid):
                os.killpg(process.pid, signal.SIGTERM)
            else:
                process.terminate()
            process.wait()

print("Probe tests PASS (no screen capture)")
