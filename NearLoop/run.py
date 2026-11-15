#!/usr/bin/env python3
"""Launch NearLoop with Flutter, using this checkout's SDK when available."""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    desktop = {"darwin": "macos", "win32": "windows", "linux": "linux"}.get(sys.platform)
    parser.add_argument("-d", "--device", default=desktop,
                        help="Flutter device ID (default: this computer's desktop)")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--release", action="store_true", help="Run a release build")
    modes.add_argument("--profile", action="store_true", help="Run a profile build")
    parser.add_argument("--dry-run", action="store_true", help="Show the launch command without running it")
    args, extra = parser.parse_known_args()
    if extra[:1] == ["--"]:
        extra = extra[1:]

    root = Path(__file__).resolve().parent
    app = root / "apps/nearloop"
    toolchains = root.parent / ".toolchains"
    env = os.environ.copy()
    executable = "flutter.bat" if os.name == "nt" else "flutter"
    local_flutter = toolchains / "flutter/bin" / executable
    flutter = str(local_flutter) if local_flutter.is_file() else shutil.which(executable)
    if not flutter:
        parser.exit(1, "Flutter was not found. Install Flutter 3.38.0 and add its bin directory to PATH.\n")
    if not (app / "pubspec.yaml").is_file():
        parser.exit(1, f"NearLoop app sources are missing: {app}\n")

    # Reuse local caches without depending on a machine-specific flutter-env.sh.
    if local_flutter.is_file():
        env["PATH"] = str(local_flutter.parent) + os.pathsep + env.get("PATH", "")
        for variable, folder in (("PUB_CACHE", "pub-cache"), ("XDG_CONFIG_HOME", "config"),
                                 ("ANDROID_HOME", "android-sdk"), ("ANDROID_USER_HOME", "android-user"),
                                 ("GRADLE_USER_HOME", "gradle")):
            path = toolchains / folder
            if path.is_dir():
                env.setdefault(variable, str(path))
        java_homes = sorted((toolchains / "java").glob("*/Contents/Home"))
        if java_homes:
            env.setdefault("JAVA_HOME", str(java_homes[-1]))
    xcode = Path("/Applications/Xcode.app/Contents/Developer")
    if sys.platform == "darwin" and xcode.is_dir():
        env.setdefault("DEVELOPER_DIR", str(xcode))

    command = [flutter, "run"]
    if args.device:
        command += ["-d", args.device]
    if args.release:
        command.append("--release")
    elif args.profile:
        command.append("--profile")
    command += extra
    print(f"Starting NearLoop in {app}", flush=True)
    print(subprocess.list2cmdline(command) if os.name == "nt" else shlex.join(command), flush=True)
    if args.dry_run:
        return 0
    try:
        return subprocess.call(command, cwd=app, env=env)
    except KeyboardInterrupt:
        return 130
    except OSError as error:
        print(f"Could not start Flutter: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
