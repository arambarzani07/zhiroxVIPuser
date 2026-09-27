"""Encrypt a PostgreSQL custom-format dump before it leaves the runner.

ZHIROX_BACKUP_KEY_B64 must decode to exactly 32 random bytes. The format is
ZHXB1 + a random 12-byte nonce + AES-256-GCM ciphertext and tag.
"""

import base64
import hashlib
import os
import pathlib
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: encrypt_external_backup.py DUMP ENCRYPTED_OUTPUT")
    key = base64.b64decode(os.environ["ZHIROX_BACKUP_KEY_B64"], validate=True)
    if len(key) != 32:
        raise SystemExit("ZHIROX_BACKUP_KEY_B64 must encode exactly 32 bytes")
    source = pathlib.Path(sys.argv[1])
    dump = source.read_bytes()
    if not dump.startswith(b"PGDMP"):
        raise SystemExit("Input is not a PostgreSQL custom-format dump")
    nonce = os.urandom(12)
    encrypted = b"ZHXB1" + nonce + AESGCM(key).encrypt(nonce, dump, b"zhirox-backup-v1")
    pathlib.Path(sys.argv[2]).write_bytes(encrypted)
    print("Encrypted backup SHA-256:", hashlib.sha256(encrypted).hexdigest())


if __name__ == "__main__":
    main()
