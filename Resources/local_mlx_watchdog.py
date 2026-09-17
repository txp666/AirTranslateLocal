#!/usr/bin/env python3
"""Keep the MLX server lifetime bounded to the AirTranslate app process."""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import threading
import time


def _terminate(child: subprocess.Popen[bytes]) -> None:
    # The child starts a new session; this process group contains only the
    # server/setup process and descendants we own (for example pip workers).
    # Keep the group ID even after its leader exits: a pip/model worker can
    # outlive that leader and may ignore SIGTERM.
    group_id = child.pid

    def group_exists() -> bool:
        child.poll()  # Reap the direct child so its zombie cannot keep the group.
        try:
            os.killpg(group_id, 0)
            return True
        except ProcessLookupError:
            return False

    def signal_group(sig: int) -> None:
        try:
            os.killpg(group_id, sig)
        except ProcessLookupError:
            pass

    if not group_exists():
        return
    signal_group(signal.SIGTERM)
    deadline = time.monotonic() + 8
    while group_exists() and time.monotonic() < deadline:
        time.sleep(0.05)
    if group_exists():
        signal_group(signal.SIGKILL)
        deadline = time.monotonic() + 2
        while group_exists() and time.monotonic() < deadline:
            time.sleep(0.05)


def main() -> int:
    if len(sys.argv) < 3:
        print(
            "usage: local_mlx_watchdog.py <parent-pid> <command> [args...]",
            file=sys.stderr,
        )
        return 2

    parent_pid = int(sys.argv[1])
    stop_requested = threading.Event()

    def request_stop(_signal: int, _frame: object) -> None:
        stop_requested.set()

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    child = subprocess.Popen(sys.argv[2:], start_new_session=True)

    try:
        while child.poll() is None:
            if stop_requested.is_set() or os.getppid() != parent_pid:
                _terminate(child)
                return 0
            time.sleep(0.2)
        return child.returncode or 0
    finally:
        _terminate(child)


if __name__ == "__main__":
    raise SystemExit(main())
