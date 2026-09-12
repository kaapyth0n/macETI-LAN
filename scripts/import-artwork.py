#!/usr/bin/env python3
"""Import only catalog cover images from ETI's locally synced assets.eti archive."""
import argparse
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tempfile


def main():
    support = Path.home() / "Library/Application Support/macETI-LAN"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", nargs="?", type=Path, default=Path.home() / "Resilio Sync/macETI-LAN/eti_launcher/update/assets.eti")
    args = parser.parse_args()
    if not args.archive.is_file():
        parser.error("Sync update/assets.eti to this device in Finder first.")
    if args.archive.stat().st_size > 100_000_000:
        parser.error("Artwork archive exceeds the 100 MB limit.")
    with sqlite3.connect((support / "catalog.sqlite").as_uri() + "?mode=ro", uri=True) as db:
        ids = {r[0] for r in db.execute("SELECT game_id FROM games")}
    listing = subprocess.check_output(["/usr/bin/tar", "-tf", str(args.archive)], text=True)
    members = []
    for name in listing.splitlines():
        match = re.fullmatch(r"assets/([a-z0-9][a-z0-9_-]{0,63})\.(jpg|jpeg|png)", name)
        if match and match.group(1) in ids:
            members.append(name)
    if not members or len(members) > 5_000:
        parser.error("No supported catalog artwork found, or too many entries.")
    destination = support / "Artwork"
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix="maceti-artwork-") as directory:
        # Exact shallow image paths only: never extract scripts or archive-provided directories/links.
        subprocess.run(["/usr/bin/tar", "-xf", str(args.archive), "-C", directory,
                        "--no-same-owner", "--no-same-permissions", "--", *members], check=True)
        count = 0
        for name in set(members):
            source = Path(directory) / name
            if source.is_symlink() or not source.is_file() or source.stat().st_size > 2_000_000:
                continue
            signature = source.read_bytes()[:8]
            if not (signature.startswith(b"\xff\xd8\xff") or signature == b"\x89PNG\r\n\x1a\n"):
                continue
            target = destination / source.name
            shutil.copyfile(source, target)
            target.chmod(0o600)
            count += 1
    print(f"Imported {count} game covers into the local Artwork folder; no executables extracted.")


if __name__ == "__main__":
    main()
