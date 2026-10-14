#!/usr/bin/env python3
"""Exercise the actual service offscreen with fake capture metadata."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent

with tempfile.TemporaryDirectory(prefix="screencast-qml-check-") as directory:
    tmp = Path(directory)
    for name in ("Service.qml", "Model.js", "probe.sh", "consumers.jq", "qml.test.qml"):
        shutil.copy2(ROOT / name, tmp / name)
    graph = [
        {"id": 1, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": "xdph-test"}}},
        {"id": 2, "type": "PipeWire:Interface:Node", "info": {"props": {"application.name": "Example browser"}}},
        {"type": "PipeWire:Interface:Link", "info": {"output-node-id": 1, "input-node-id": 2}},
    ]
    for name, body in {"pw-dump": 'count=0; [[ ! -f "$TEST_COUNTER" ]] || read -r count < "$TEST_COUNTER"\ncount=$((count + 1)); printf "%s\\n" "$count" > "$TEST_COUNTER"\n((count <= 3)) || exit 7\nprintf "%s\\n" "$TEST_GRAPH"', "pgrep": "exit 1",
                       "inotifywait": "exec sleep 30"}.items():
        path = tmp / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)
    env = dict(os.environ, PATH=str(tmp) + os.pathsep + os.environ["PATH"],
               QT_QPA_PLATFORM="offscreen", HYPRLAND_INSTANCE_SIGNATURE="",
               TEST_GRAPH=json.dumps(graph), TEST_COUNTER=str(tmp / "counter"))
    process = subprocess.Popen(["quickshell", "--no-color", "--path", str(tmp / "qml.test.qml")],
                               env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        output = process.communicate(timeout=5)[0]
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        output = process.communicate()[0]
        raise AssertionError("QML check timed out: " + output)
    assert "QML tests PASS" in output and "QML tests FAIL" not in output, output

print("QML tests PASS (no screen capture)")
