#!/usr/bin/env python3
"""Validate and install explicitly supplied Apple keys; dry run unless --apply.

Only the two authorized Bilu projects and Apple credential secret names are used.
Private key material is never passed on a command line or printed. No file search,
key creation, key download, key revocation, or commerce activation is performed.
"""

import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROJECTS = {
    "production": "yysxjtexwlnvoptxcxlp",
    "sandbox": "stddielncxelpqangfyk",
}
ISSUER_ID = "99003f27-77dc-457b-bc50-227da56e599c"
TEAM_ID = "P29NUSYG5X"
REVOKED_IAP_KEYS = {"5GTTF9MDXU"}
MAX_KEY_BYTES = 8_192
EC_P256_ALGORITHM = bytes.fromhex("06072a8648ce3d020106082a8648ce3d030107")
KEY_ID_PATTERN = re.compile(r"[A-Z0-9]{10}\Z")
PEM_PATTERN = re.compile(
    rb"-----BEGIN PRIVATE KEY-----\r?\n([A-Za-z0-9+/=\r\n]+)"
    rb"\r?\n-----END PRIVATE KEY-----\s*\Z"
)


class SetupError(Exception):
    """Messages are fixed operational descriptions, never subprocess output."""


def outside_repository(path):
    resolved = path.expanduser().resolve()
    if resolved == ROOT or ROOT in resolved.parents:
        raise SetupError("Key and backup paths must be outside the repository.")
    for ancestor in (resolved, *resolved.parents):
        if (ancestor / ".git").exists():
            raise SetupError("Key and backup paths must be outside Git checkouts.")
    return resolved


def der_item(data, offset):
    if offset + 2 > len(data):
        raise SetupError("The key is not an unencrypted P-256 PKCS#8 private key.")
    tag, length = data[offset], data[offset + 1]
    start = offset + 2
    if length & 0x80:
        count = length & 0x7F
        if not 1 <= count <= 4 or start + count > len(data):
            raise SetupError("The private-key DER encoding is invalid.")
        length = int.from_bytes(data[start:start + count], "big")
        start += count
    end = start + length
    if end > len(data):
        raise SetupError("The private-key DER encoding is incomplete.")
    return tag, data[start:end], end


def validate_pkcs8(data, openssl):
    match = PEM_PATTERN.fullmatch(data)
    if not match:
        raise SetupError("Supply an unencrypted PKCS#8 .p8 private key.")
    try:
        der = base64.b64decode(re.sub(rb"\s", b"", match[1]), validate=True)
    except ValueError:
        raise SetupError("The private-key PEM encoding is invalid.") from None
    tag, sequence, end = der_item(der, 0)
    if tag != 0x30 or end != len(der):
        raise SetupError("The key must contain exactly one PKCS#8 object.")
    version_tag, version, offset = der_item(sequence, 0)
    algorithm_tag, algorithm, offset = der_item(sequence, offset)
    private_tag, private_key, _ = der_item(sequence, offset)
    if (
        version_tag != 0x02 or version != b"\x00" or algorithm_tag != 0x30
        or algorithm != EC_P256_ALGORITHM or private_tag != 0x04 or not private_key
    ):
        raise SetupError("The key must be an unencrypted P-256 PKCS#8 key.")
    try:
        checked = subprocess.run(
            [openssl, "pkey", "-check", "-noout"], input=data,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=10, check=False,
        )
        if checked.returncode:
            raise SetupError("OpenSSL could not validate the private key.")
        public = subprocess.run(
            [openssl, "pkey", "-pubout", "-outform", "DER"], input=data,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            timeout=10, check=False,
        )
        if public.returncode or not public.stdout:
            raise SetupError("OpenSSL could not derive the public key.")
        return public.stdout
    except (OSError, subprocess.TimeoutExpired):
        raise SetupError("Local OpenSSL validation failed; no secrets were installed.") from None


def read_key(path, key_id, openssl):
    if not KEY_ID_PATTERN.fullmatch(key_id):
        raise SetupError("Apple key IDs must contain exactly 10 uppercase letters or digits.")
    supplied = path.expanduser().absolute()
    outside_repository(supplied)
    if supplied.suffix.lower() != ".p8":
        raise SetupError("Supply the explicitly downloaded .p8 key file.")
    named = re.match(r"(?:SubscriptionKey|AuthKey)_([A-Z0-9]{10})(?:\b|_)", supplied.name)
    if named and named[1] != key_id:
        raise SetupError("The supplied key ID disagrees with the Apple download filename.")
    try:
        descriptor = os.open(supplied, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                raise SetupError("The key path must be a regular file, not a link or device.")
            data = source.read(MAX_KEY_BYTES + 1)
    except OSError:
        raise SetupError("The explicit key file cannot be read; links are not accepted.") from None
    if not data or len(data) > MAX_KEY_BYTES:
        raise SetupError("The key file has an invalid size.")
    public = validate_pkcs8(data, openssl)
    return data.decode("ascii").strip() + "\n", public


def private_directory(path):
    destination = outside_repository(path)
    absolute = path.expanduser().absolute()
    for component in (absolute, *absolute.parents):
        if component.is_symlink():
            raise SetupError("The protected backup path cannot contain symbolic links.")
    # New parent directories are private too. Existing parent directories are not
    # modified; an existing final directory must already have safe permissions.
    previous_mask = os.umask(0o077)
    try:
        destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    finally:
        os.umask(previous_mask)
    metadata = destination.lstat()
    if (
        not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid()
        or stat.S_IMODE(metadata.st_mode) != 0o700
    ):
        raise SetupError("The backup directory must be owned by you with mode 0700.")
    return destination


def backup_key(directory, name, value):
    path = directory / name
    data = value.encode("ascii")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(descriptor, "rb") as existing:
                metadata = os.fstat(existing.fileno())
                if (
                    not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                    or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_nlink != 1
                    or existing.read(MAX_KEY_BYTES + 1) != data
                ):
                    raise SetupError("An existing backup differs or has unsafe permissions; it was not overwritten.")
        except OSError:
            raise SetupError("The existing backup cannot be safely read; it was not overwritten.") from None
        return
    with os.fdopen(descriptor, "wb") as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())


def install(secrets, projects, backup_directory, runner=subprocess.run):
    binary = shutil.which("supabase")
    if not binary:
        raise SetupError("The Supabase CLI is required for --apply.")
    # Only this invocation's named Apple secrets are sent. No flags, auth settings,
    # provider keys, migrations, or function deployments are changed here.
    child_environment = dict(os.environ)
    child_environment.pop("SUPABASE_DEBUG", None)
    child_environment.pop("DEBUG", None)
    completed = []
    with tempfile.TemporaryDirectory(prefix=".install-", dir=backup_directory) as temporary:
        os.chmod(temporary, 0o700)
        env_file = Path(temporary) / "apple-secrets.env"
        descriptor = os.open(env_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(descriptor, "w", encoding="ascii") as output:
                for name, value in secrets.items():
                    output.write(f"{name}={json.dumps(value, ensure_ascii=True)}\n")
                output.flush()
                os.fsync(output.fileno())
            for project in projects:
                try:
                    result = runner(
                        [binary, "secrets", "set", "--project-ref", PROJECTS[project], "--env-file", str(env_file)],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=90, check=False, env=child_environment,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    raise SetupError(
                        f"Installation for {project} did not confirm success. Already confirmed: {', '.join(completed) or 'none'}. "
                        "The destination may have accepted the request; rerunning the same keys is safe. CLI output was suppressed."
                    ) from None
                if result.returncode:
                    raise SetupError(
                        f"Installation for {project} did not confirm success. Already confirmed: {', '.join(completed) or 'none'}. "
                        "Verify CLI access and rerun the same keys. CLI output was suppressed."
                    )
                completed.append(project)
                print(f"Installed Apple secret names on {project} ({PROJECTS[project]}).")
        finally:
            env_file.unlink(missing_ok=True)


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", choices=[*PROJECTS, "both"], required=True)
    parser.add_argument("--iap-key", type=Path, required=True)
    parser.add_argument("--iap-key-id", required=True)
    parser.add_argument("--issuer-id", choices=[ISSUER_ID], default=ISSUER_ID)
    parser.add_argument("--sign-in-key", type=Path)
    parser.add_argument("--sign-in-key-id")
    parser.add_argument("--team-id", choices=[TEAM_ID], default=TEAM_ID)
    parser.add_argument("--backup-dir", type=Path, default=Path.home() / ".local/share/bilu/apple-keys")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Install the validated keys; otherwise only validate and describe destinations.")
    mode.add_argument("--dry-run", action="store_true", help="Explicit dry run (the default).")
    return parser.parse_args(argv)


def execute(options, runner=subprocess.run):
    if options.iap_key_id in REVOKED_IAP_KEYS:
        raise SetupError("That In-App Purchase key was revoked. Supply a newly downloaded active key.")
    if bool(options.sign_in_key) != bool(options.sign_in_key_id):
        raise SetupError("Supply both --sign-in-key and --sign-in-key-id, or neither.")
    openssl = shutil.which("openssl")
    if not openssl:
        raise SetupError("OpenSSL is required for local P-256 key validation.")
    backup_path = outside_repository(options.backup_dir)
    purchase_key, purchase_public = read_key(options.iap_key, options.iap_key_id, openssl)
    secrets = {
        "APP_STORE_ISSUER_ID": options.issuer_id,
        "APP_STORE_KEY_ID": options.iap_key_id,
        "APP_STORE_PRIVATE_KEY_P8": purchase_key,
    }
    backups = [(f"iap-{options.iap_key_id}.p8", purchase_key)]
    if options.sign_in_key:
        sign_in_key, sign_in_public = read_key(options.sign_in_key, options.sign_in_key_id, openssl)
        if sign_in_public == purchase_public or options.sign_in_key_id == options.iap_key_id:
            raise SetupError("Use a distinct Sign in with Apple key and key ID.")
        secrets.update({
            "BILU_SIGN_IN_APPLE_TEAM_ID": options.team_id,
            "BILU_SIGN_IN_APPLE_KEY_ID": options.sign_in_key_id,
            "BILU_SIGN_IN_APPLE_PRIVATE_KEY": sign_in_key,
        })
        backups.append((f"sign-in-with-apple-{options.sign_in_key_id}.p8", sign_in_key))
    projects = list(PROJECTS) if options.project == "both" else [options.project]
    print("Apply destinations:" if options.apply else "Dry-run destinations:")
    for project in projects:
        print(f"  {project} ({PROJECTS[project]})")
    print("Secret names: " + ", ".join(sorted(secrets)))
    print(f"Protected backup destination: {backup_path}")
    if not options.apply:
        return
    protected = private_directory(options.backup_dir)
    for name, value in backups:
        backup_key(protected, name, value)
    install(secrets, projects, protected, runner)


def main(argv=None):
    try:
        execute(arguments(argv))
        return 0
    except (SetupError, OSError) as error:
        message = str(error) if isinstance(error, SetupError) else "A local filesystem operation failed; private data was not printed."
        print(f"Setup stopped: {message}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Setup interrupted; any in-flight project update may have completed. Rerun the same keys to reconcile.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
