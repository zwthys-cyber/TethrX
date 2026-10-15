#!/usr/bin/env python3
"""Prepare a checkout for a single-app, unsigned ESign build (no certificates)."""

import argparse
from pathlib import Path
import plistlib
import re


def prepare(ios_dir: Path, bundle_id: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id):
        raise ValueError("Bundle ID must be a reverse-DNS identifier matching your profile")

    project = ios_dir / "GrokRemote.xcodeproj/project.pbxproj"
    info_path = ios_dir / "GrokRemote/Info.plist"
    text = project.read_text()
    # Fail on project changes instead of silently shipping embedded targets that
    # cannot be signed by a profile covering just the main application.
    references = (
        "ABCDEF0123456789ABCF0030 /* Embed Watch Content */",
        "ABCDEF0123456789ABCF0041 /* PBXTargetDependency */",
        "E69633B7E40A946D3938A446 /* Embed Foundation Extensions */",
        "01312C879EC3DA4E268FE0E8 /* PBXTargetDependency */",
        "ABCDEF0123456789ABCE0052 /* PBXTargetDependency */",
    )
    for reference in references:
        line = f"\t\t\t\t{reference},\n"
        if text.count(line) != 1:
            raise ValueError(f"Expected exactly one embed/dependency reference: {reference}")
        text = text.replace(line, "")

    for old, new in (
        ("CODE_SIGN_ENTITLEMENTS = GrokRemote/GrokRemote.entitlements;", 'CODE_SIGN_ENTITLEMENTS = "";'),
        ("PRODUCT_BUNDLE_IDENTIFIER = com.tethrx.app;", f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};"),
    ):
        if text.count(old) != 2:
            raise ValueError(f"Expected Debug and Release settings: {old}")
        text = text.replace(old, new)

    with info_path.open("rb") as source:
        info = plistlib.load(source)
    info["TethrXStandalone"] = True
    info["NSSupportsLiveActivities"] = False
    info.pop("TethrXSharedKeychainGroup", None)
    for url_type in info.get("CFBundleURLTypes", []):
        url_type["CFBundleURLName"] = bundle_id

    # Validate everything before modifying either input file.
    info_bytes = plistlib.dumps(info, sort_keys=False)
    project.write_text(text)
    info_path.write_bytes(info_bytes)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-dir", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--bundle-id", required=True)
    args = parser.parse_args()
    prepare(args.ios_dir, args.bundle_id)
    print(f"Prepared standalone ESign build: {args.bundle_id}")
