#!/usr/bin/env python3
"""Build an explicit Debug payments sandbox without editing production settings."""

import argparse
import base64
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET


PRODUCTION_REFERENCE = "yysxjtexwlnvoptxcxlp"
REPOSITORY = Path(__file__).resolve().parents[1]


def validate_public_config(config):
    if not isinstance(config, dict) or set(config) - {
        "supabase_url", "supabase_anon_key", "project_ref", "apple_environment", "commerce_enabled", "pro_enabled"
    }:
        raise ValueError("The sandbox file must contain only public project configuration.")
    if config.get("apple_environment", "Sandbox") != "Sandbox" or config.get("pro_enabled", False) is not False:
        raise ValueError("The sandbox build requires Apple's Sandbox environment with Pro disabled.")
    raw_url = config.get("supabase_url", "")
    key = config.get("supabase_anon_key", "")
    if not isinstance(raw_url, str) or not isinstance(key, str):
        raise ValueError("The sandbox URL and public key must be strings.")
    parsed = urlsplit(raw_url)
    match = re.fullmatch(r"([a-z0-9]{20})\.supabase\.co", parsed.hostname or "")
    if (parsed.scheme != "https" or not match or parsed.username or parsed.password
            or parsed.port is not None or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise ValueError("Use the isolated project's HTTPS Supabase URL without credentials, paths, or query parameters.")
    project = match.group(1)
    if project == PRODUCTION_REFERENCE:
        raise ValueError("A payments sandbox build must not use the production project.")
    if config.get("project_ref", project) != project:
        raise ValueError("project_ref must match the sandbox URL.")
    public_key = re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{16,}", key) is not None
    if not public_key:
        try:
            parts = key.split(".")
            if len(parts) != 3:
                raise ValueError()
            claims = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
            public_key = claims.get("role") == "anon" and claims.get("ref") == project
        except (ValueError, TypeError, AttributeError):
            public_key = False
    if not public_key:
        raise ValueError("Only the matching public anon or publishable key may be embedded; server-only keys are rejected.")
    return f"https://{project}.supabase.co", key, project


def generate_configuration(config, output_directory, repository=REPOSITORY):
    url, public_key, project = validate_public_config(config)
    scheme = repository / "bilu.xcodeproj/xcshareddata/xcschemes/bilu.xcscheme"
    if ET.parse(scheme).find(".//StoreKitConfigurationFileReference") is not None:
        raise ValueError("Remove the local StoreKit configuration from the bilu scheme before testing real App Store products.")
    with (repository / "bilu/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    info.update({
        "BILUPaymentSandbox": True,
        "BILUSupabaseURL": url,
        "BILUSupabaseAnonKey": public_key,
        "BILUCommerceEnabled": True,
        "BILUProEnabled": False,
        "CFBundleDisplayName": "bilu Sandbox",
    })
    output_directory.mkdir(parents=True, exist_ok=True)
    plist_path = output_directory / "bilu-Sandbox-Info.plist"
    with plist_path.open("wb") as target:
        plistlib.dump(info, target)
    # Per-target selection keeps the share extension's own Info.plist intact.
    # No production plist or project build setting is edited.
    xcconfig = output_directory / "PaymentSandbox.xcconfig"
    plist_value = str(plist_path.resolve())
    if any(character in plist_value for character in ('"', "\n", "\r", "$")):
        raise ValueError("Choose a build directory without quotes, newlines, or dollar signs.")
    xcconfig.write_text(
        '// Generated for an explicit Debug sandbox build; never add as a project default.\n'
        f'BILU_PAYMENT_INFO_bilu = {plist_value}\n'
        'BILU_PAYMENT_INFO_biluShare = $(SRCROOT)/biluShare/Info.plist\n'
        'BILU_PAYMENT_INFO_biluTests =\n'
        'BILU_PAYMENT_INFO_biluUITests =\n'
        'INFOPLIST_FILE = $(BILU_PAYMENT_INFO_$(TARGET_NAME))\n'
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug] = $(inherited) BILU_PAYMENT_SANDBOX\n'
    )
    return xcconfig, plist_path, project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path, help="JSON containing only the sandbox public URL/key")
    parser.add_argument("--derived-data", type=Path, default=Path("/tmp/bilu-payments-sandbox"))
    parser.add_argument("--destination", default="generic/platform=iOS Simulator")
    parser.add_argument("--prepare-only", action="store_true", help="Generate build-only files without invoking Xcode")
    parser.add_argument("--signed", action="store_true", help="Use existing Xcode signing settings for a physical device")
    arguments = parser.parse_args()
    try:
        config = json.loads(arguments.config.read_text())
        derived_data = arguments.derived_data.resolve()
        xcconfig, plist_path, project = generate_configuration(config, derived_data / "SandboxConfiguration")
    except (OSError, ValueError, ET.ParseError) as error:
        parser.error(str(error))
    print(f"Sandbox project: {project}")
    print(f"Build-only Info.plist: {plist_path}")
    print(f"Build-only xcconfig: {xcconfig}")
    if arguments.prepare_only:
        return 0
    command = [
        "xcodebuild", "build", "-project", str(REPOSITORY / "bilu.xcodeproj"),
        "-scheme", "bilu", "-configuration", "Debug", "-xcconfig", str(xcconfig),
        "-destination", arguments.destination, "-derivedDataPath", str(derived_data),
    ]
    if not arguments.signed:
        command.append("CODE_SIGNING_ALLOWED=NO")
    return subprocess.run(command, cwd=REPOSITORY, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
