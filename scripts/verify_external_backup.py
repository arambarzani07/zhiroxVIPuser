"""Verify/decrypt a ZHIROX archive locally, then inspect with pg_restore -l.

Never use a production database as the restore-test target.
"""

import base64
import os
import pathlib
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: verify_external_backup.py ARCHIVE OUTPUT.dump")
    key = base64.b64decode(os.environ["ZHIROX_BACKUP_KEY_B64"], validate=True)
    if len(key) != 32:
        raise SystemExit("ZHIROX_BACKUP_KEY_B64 must encode exactly 32 bytes")
    blob = pathlib.Path(sys.argv[1]).read_bytes()
    if not blob.startswith(b"ZHXB1"):
        raise SystemExit("Unrecognized archive format")
    dump = AESGCM(key).decrypt(blob[5:17], blob[17:], b"zhirox-backup-v1")
    if not dump.startswith(b"PGDMP"):
        raise SystemExit("Decrypted content is not a PostgreSQL custom dump")
    pathlib.Path(sys.argv[2]).write_bytes(dump)
    print("Backup authenticated; inspect with pg_restore --list OUTPUT.dump")


if __name__ == "__main__":
    main()
