"""Resolve Chiasmus binaries the same way the shell wrappers do.

The wrappers call `resolve_toolchain.py --require-capability ...` and use the
binaries inside the verified release. These helpers let the Python tools do
exactly that, while still accepting an explicit `--*-bin` override for local
development and tests.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
RESOLVER = SCRIPT_DIR / "resolve_toolchain.py"


class ToolchainError(RuntimeError):
    pass


def resolve_toolchain(required: list[str] | None = None) -> Path:
    command = [sys.executable, str(RESOLVER)]
    for capability in required or []:
        command += ["--require-capability", capability]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise ToolchainError(result.stderr.strip() or "toolchain resolution failed")
    return Path(result.stdout.strip())


def binary(name: str, required: list[str] | None = None, override: str | None = None) -> str:
    """Return an executable path for a Chiasmus binary, or raise ToolchainError."""
    if override:
        return override
    try:
        toolchain = resolve_toolchain(required)
    except ToolchainError as error:
        raise ToolchainError(
            f"{name} unavailable: {error}. Pass --{name.removeprefix('chiasmus-')}-bin "
            f"or set up the toolchain with install_chiasmus_toolchain.sh"
        ) from error

    candidate = toolchain / name
    if not candidate.is_file() and (toolchain / f"{name}.exe").is_file():
        candidate = toolchain / f"{name}.exe"
    if not candidate.is_file():
        raise ToolchainError(f"{name} is missing from the resolved toolchain {toolchain}")
    return str(candidate)
