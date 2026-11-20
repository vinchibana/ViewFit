#!/usr/bin/env python3
"""Exercise the real Native Messaging helper without touching user settings."""

import argparse
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import tempfile
import time


ORIGIN = "chrome-extension://fgmjjmcpabiopnbpgcjdbgfbcpiajmhl/"


def write_state(directory, *, external=True, generation=1, age=0):
    state = {
        "enabled": True,
        "externalConnected": external,
        "chromeEnabled": True,
        "chromeZoom": 1.25 if external else 1.0,
        "generation": generation,
        "updatedAt": time.time() - age,
    }
    temporary = directory / "chrome-state.new"
    temporary.write_text(json.dumps(state), encoding="utf-8")
    temporary.replace(directory / "chrome-state.json")


def read_exact(process, count, deadline):
    result = bytearray()
    while len(result) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError("Native host did not produce a complete frame before timeout")
        ready, _, _ = select.select([process.stdout], [], [], remaining)
        if not ready:
            raise AssertionError("Native host response timed out")
        chunk = os.read(process.stdout.fileno(), count - len(result))
        if not chunk:
            raise AssertionError(f"Native host closed stdout unexpectedly (exit={process.poll()})")
        result.extend(chunk)
    return bytes(result)


def read_until(process, predicate, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        header = read_exact(process, 4, deadline)
        length, = struct.unpack("=I", header)
        assert 0 < length <= 1024 * 1024, f"Invalid native-message length: {length}"
        message = json.loads(read_exact(process, length, deadline))
        if predicate(message):
            return message
    raise AssertionError("Expected native host state was not streamed")


def test_bridge(binary):
    with tempfile.TemporaryDirectory(prefix="viewfit-bridge-test-") as temporary:
        directory = Path(temporary)
        write_state(directory)
        environment = os.environ.copy()
        environment["SCREEN_SCALE_SUPPORT_DIRECTORY"] = temporary
        process = subprocess.Popen(
            [str(binary), ORIGIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=environment, bufsize=0,
        )
        try:
            # Deliberately split both length and body to exercise readExactly.
            body = json.dumps({"type": "getState"}).encode("utf-8")
            frame = struct.pack("=I", len(body)) + body
            for fragment in (frame[:1], frame[1:3], frame[3:8], frame[8:]):
                process.stdin.write(fragment)
                process.stdin.flush()
                time.sleep(0.025)
            initial = read_until(process, lambda state: state["generation"] == 1)
            assert initial["enabled"] is True
            assert initial["externalConnected"] is True
            assert initial["chromeZoom"] == 1.25
            print("PASS initial external state and fragmented request")

            write_state(directory, external=False, generation=2)
            unplugged = read_until(process, lambda state: state["generation"] == 2)
            assert unplugged["enabled"] is True
            assert unplugged["externalConnected"] is False
            assert unplugged["chromeZoom"] == 1.0
            print("PASS unplug state streamed without a second request")

            write_state(directory, external=False, generation=3, age=30)
            stale = read_until(process, lambda state: state["generation"] == 3)
            assert stale["enabled"] is False
            print("PASS stale application heartbeat disables automation")

            process.stdin.close()
            assert process.wait(timeout=3) == 0
            assert not process.stderr.read(), "Unexpected native host diagnostics"
            print("PASS host terminates cleanly on stdin EOF")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream and not stream.closed:
                    stream.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="Path to the built ViewFitBridge executable")
    arguments = parser.parse_args()
    binary = arguments.binary.resolve(strict=True)
    test_bridge(binary)
