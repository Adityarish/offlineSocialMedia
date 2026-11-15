#!/usr/bin/env python3
"""Cache the pinned Gradle ZIP using curl before Java starts the wrapper."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parent.parent
    properties = root / "apps/nearloop/android/gradle/wrapper/gradle-wrapper.properties"
    config = dict(
        line.strip().split("=", 1)
        for line in properties.read_text().splitlines()
        if "=" in line and not line.lstrip().startswith("#")
    )
    url = config["distributionUrl"].replace("\\:", ":")
    checksum = config["distributionSha256Sum"]
    if not re.fullmatch(r"https://services\.gradle\.org/distributions/gradle-[\d.]+-bin\.zip", url):
        raise ValueError("Expected a pinned official Gradle binary distribution URL")
    if not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise ValueError("Expected a pinned Gradle SHA-256 checksum")
    if any(config[key] != "GRADLE_USER_HOME" for key in ("distributionBase", "zipStoreBase")):
        raise ValueError("Expected GRADLE_USER_HOME wrapper cache bases")
    if config["distributionPath"] != config["zipStorePath"]:
        raise ValueError("Expected matching wrapper distribution and ZIP cache paths")

    # This is the standard Gradle wrapper URL-to-cache-directory mapping.
    number = int.from_bytes(hashlib.md5(url.encode()).digest(), "big")
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    cache_key = ""
    while number:
        number, remainder = divmod(number, 36)
        cache_key = digits[remainder] + cache_key
    home = Path(os.environ.get("GRADLE_USER_HOME", str(Path.home() / ".gradle")))
    filename = url.rsplit("/", 1)[1]
    cache = home / config["zipStorePath"] / filename[:-4] / cache_key
    archive = cache / filename
    installed = filename.removesuffix("-bin.zip")
    if archive.with_suffix(".zip.ok").is_file() and (cache / installed / "bin/gradle").is_file():
        print(f"Gradle is ready: {cache / installed}", flush=True)
        return

    def verified(path):
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest() == checksum

    cache.mkdir(parents=True, exist_ok=True)
    if archive.is_file() and verified(archive):
        print(f"Gradle download already verified: {archive}", flush=True)
        return
    print(f"Downloading {filename} with curl (retries enabled)...", flush=True)
    descriptor, temporary = tempfile.mkstemp(prefix=filename + ".", suffix=".part", dir=cache)
    os.close(descriptor)
    temporary = Path(temporary)
    try:
        subprocess.run([
            "curl", "--fail", "--location", "--show-error", "--progress-bar",
            "--retry", "3", "--retry-delay", "2", "--retry-connrefused",
            "--connect-timeout", "30", "--max-time", "900",
            "--output", str(temporary), url,
        ], check=True)
        if not verified(temporary):
            raise ValueError("Gradle download checksum mismatch; refusing to install")
        temporary.replace(archive)
        print(f"Gradle download verified: {archive}", flush=True)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Gradle preparation failed: {error}\n"
              "Check access to services.gradle.org, github.com and "
              "release-assets.githubusercontent.com, then rerun the build.", file=sys.stderr)
        sys.exit(1)
