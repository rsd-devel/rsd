# SPDX-License-Identifier: Apache-2.0
"""Check progress in the unmodified Zephyr Philosophers sample."""

import argparse
import re
from pathlib import Path


def check_output(output):
    if re.search(r"fatal|fault|exception|assert|error", output, re.IGNORECASE):
        raise ValueError("kernel error in UART output")
    # The instruction budget can end in the middle of the final UART line.
    lines = output.splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines.pop()
    # printk calls are synchronized, but a state line spans multiple calls.
    # A preemption can interleave lines, so use only intact state records.
    progress = [0] * 6
    seen = [set() for _ in range(6)]
    required = ("EATING", "THINKING", "EATING", "THINKING")
    pattern = re.compile(r"Philosopher ([0-5]) \[([CP]):\s*(-?\d+)\]\s+"
                         r"(STARVING|HOLDING ONE FORK|DROPPED ONE FORK|"
                         r"EATING|THINKING)(?:[^\S\n]+\[[^\S\n]*(\d+) ms \])?[^\S\n]*\n")
    for match in pattern.finditer("".join(lines)):
        ident, kind, priority, state, delay = match.groups()
        ident = int(ident)
        expected_priority = 3 - ident
        # Mutex priority inheritance can temporarily boost a philosopher.
        if (not -2 <= int(priority) <= expected_priority
                or kind != ("C" if int(priority) < 0 else "P")):
            raise ValueError(f"incorrect priority for philosopher {ident}")
        if state in ("EATING", "THINKING"):
            if delay is None or not 25 <= int(delay) <= 800 or int(delay) % 25:
                raise ValueError(f"invalid sleep duration for philosopher {ident}")
        elif delay is not None:
            raise ValueError(f"unexpected sleep duration for philosopher {ident}")
        seen[ident].add(state)
        if progress[ident] < len(required) and state == required[progress[ident]]:
            progress[ident] += 1
    missing = [ident for ident in range(6) if progress[ident] < len(required)
               or len(seen[ident]) < 5]
    if missing:
        raise ValueError("expected two eating/thinking rounds and all fork states; "
                         f"missing philosophers {missing}, progress {progress}")
    return "all six philosophers completed two eating/thinking rounds"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = check_output(args.output.read_text(encoding="ascii"))
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"NG (Zephyr/Philosophers): {error}\n")
    print(f"OK (Zephyr/Philosophers): {result}")
