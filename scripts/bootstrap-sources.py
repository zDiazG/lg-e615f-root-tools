#!/usr/bin/env python3
"""Fetch selected, hash-pinned external inputs into the ignored sources/ cache."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "sources.lock.json"
CHUNK_SIZE = 1024 * 1024
TIMEOUT_SECONDS = 30


def load_manifest(path: Path = MANIFEST) -> dict[str, dict[str, object]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("sources"), dict):
        raise ValueError("Unsupported external-source manifest")
    sources = data["sources"]
    for name, item in sources.items():
        if not isinstance(name, str) or not isinstance(item, dict):
            raise ValueError("Invalid source entry")
        url = item.get("url")
        digest = item.get("sha256")
        size = item.get("size_bytes")
        relpath = item.get("path")
        if not isinstance(url, str) or urllib.parse.urlparse(url).scheme != "https":
            raise ValueError(f"{name}: source URL must use HTTPS")
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise ValueError(f"{name}: invalid SHA-256 pin")
        if not isinstance(size, int) or size <= 0:
            raise ValueError(f"{name}: invalid byte-size pin")
        if not isinstance(relpath, str):
            raise ValueError(f"{name}: missing destination path")
        relative = PurePosixPath(relpath)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"{name}: destination must stay inside the repository")
    return sources


def destination_for(name: str, item: dict[str, object], root: Path = ROOT) -> Path:
    relative = PurePosixPath(str(item["path"]))
    target = (root / Path(*relative.parts)).resolve()
    if target != root.resolve() and root.resolve() not in target.parents:
        raise ValueError(f"{name}: destination escapes repository")
    return target


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(CHUNK_SIZE), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_existing(path: Path, item: dict[str, object]) -> bool:
    if not path.exists():
        return False
    if not path.is_file():
        raise ValueError(f"Refusing non-file destination: {path}")
    size = path.stat().st_size
    digest = file_digest(path)
    if size != item["size_bytes"] or digest != item["sha256"]:
        raise ValueError(f"Existing file does not match pinned source: {path}")
    return True


def plan_source(name: str, item: dict[str, object], root: Path = ROOT) -> str:
    target = destination_for(name, item, root)
    return f"{name}\t{item['size_bytes']} bytes\tsha256:{item['sha256']}\t{item['url']}\t{target}"


def fetch_source(name: str, item: dict[str, object], root: Path = ROOT) -> Path:
    target = destination_for(name, item, root)
    if verify_existing(target, item):
        print(f"cached={target}")
        return target

    target.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        str(item["url"]),
        headers={"User-Agent": "android-root-tools-source-bootstrap/1"},
    )
    temporary_path: Path | None = None
    digest = hashlib.sha256()
    received = 0
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            final_url = urllib.parse.urlparse(response.geturl())
            if final_url.scheme != "https":
                raise ValueError(f"{name}: refused redirect to a non-HTTPS URL")
            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) != item["size_bytes"]:
                raise ValueError(f"{name}: unexpected Content-Length {content_length}")
            with tempfile.NamedTemporaryFile(
                mode="wb", prefix=f".{target.name}.", suffix=".part",
                dir=target.parent, delete=False,
            ) as output:
                temporary_path = Path(output.name)
                while True:
                    block = response.read(CHUNK_SIZE)
                    if not block:
                        break
                    received += len(block)
                    if received > item["size_bytes"]:
                        raise ValueError(f"{name}: download exceeds pinned byte size")
                    digest.update(block)
                    output.write(block)
        if received != item["size_bytes"]:
            raise ValueError(f"{name}: expected {item['size_bytes']} bytes, received {received}")
        if digest.hexdigest() != item["sha256"]:
            raise ValueError(f"{name}: SHA-256 mismatch: {digest.hexdigest()}")
        if target.exists():
            raise ValueError(f"Refusing to replace destination created during download: {target}")
        os.replace(temporary_path, target)
        temporary_path = None
        print(f"fetched={target} sha256={item['sha256']}")
        return target
    except (OSError, urllib.error.URLError, ValueError):
        raise
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true", help="list pinned external inputs")
    mode.add_argument("--dry-run", nargs="+", metavar="NAME", help="show fetch plan without network or filesystem changes")
    mode.add_argument("--fetch", nargs="+", metavar="NAME", help="download named inputs and verify exact size and SHA-256")
    args = parser.parse_args(argv)

    try:
        sources = load_manifest()
        if args.list:
            for name in sources:
                print(name)
            return 0
        names = args.dry_run if args.dry_run is not None else args.fetch
        unknown = sorted(set(names) - set(sources))
        if unknown:
            raise ValueError("Unknown source name(s): " + ", ".join(unknown))
        for name in names:
            if args.dry_run is not None:
                print(plan_source(name, sources[name]))
            else:
                fetch_source(name, sources[name])
    except (OSError, urllib.error.URLError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
