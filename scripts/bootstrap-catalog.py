#!/usr/bin/env python3
"""Obtain only ETI's bootstrap metadata. Never extract or run its installer scripts."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import tarfile
import urllib.request

SOURCE = "https://www.eti-lan.xyz/sync_server.tar"
LIMIT = 4 * 1024 * 1024


def private_write(destination, data):
    temporary = destination.with_name(destination.name + ".tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use a previously downloaded official archive")
    args = parser.parse_args()
    if args.archive:
        with args.archive.open("rb") as source:
            content = source.read(LIMIT + 1)
    else:
        with urllib.request.urlopen(SOURCE, timeout=30) as response:
            content = response.read(LIMIT + 1)
    if len(content) > LIMIT:
        raise ValueError("Bootstrap archive exceeds the 4 MB limit")
    with tarfile.open(fileobj=io.BytesIO(content), mode="r:*") as archive:
        def member(name):
            entry = archive.getmember(name)
            if not entry.isfile() or entry.size > LIMIT:
                raise ValueError("Unexpected bootstrap member")
            return archive.extractfile(entry).read()
        config = member("/root/eti-config.conf").decode("utf-8")
        match = re.search(r"^eti_call='[^'\n]*[?&]secret=(B[A-Z2-7]{32})'", config, re.MULTILINE)
        if not match:
            raise ValueError("No standard read-only launcher key found; bootstrap format may have changed")
        seed = member("/root/game.db")
        if not seed.startswith(b"SQLite format 3\0"):
            raise ValueError("Seed is not a SQLite database")
        seed_mtime = archive.getmember("/root/game.db").mtime
    support = Path.home() / "Library/Application Support/macETI-LAN"
    support.mkdir(mode=0o700, parents=True, exist_ok=True)
    private_write(support / "launcher.key", match.group(1).encode("ascii"))
    private_write(support / "bootstrap-game.db", seed)
    receipt = {"source": SOURCE, "archiveSHA256": hashlib.sha256(content).hexdigest(),
               "seedModifiedUnix": seed_mtime, "note": "Historical seed, not a live catalog"}
    private_write(support / "bootstrap-receipt.json", json.dumps(receipt, indent=2).encode())
    print("Read-only launcher key and historical seed saved in private application support.")
    print("Next: maceti copy-key launcher; connect it in Resilio to the eti_launcher folder.")
    print("Use the newly synced eti_launcher/update/game.db for the live catalog.")


if __name__ == "__main__":
    main()
