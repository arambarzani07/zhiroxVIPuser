#!/usr/bin/env bash
set -euo pipefail
umask 077
work="$(mktemp -d)"
cid=""
cleanup() {
  if [[ -n "$cid" ]]; then docker rm -f "$cid" >/dev/null 2>&1 || true; fi
  rm -rf -- "$work"
}
trap cleanup EXIT
# No production URLs or secrets. Docker has no published ports and no external network.
cid="$(docker run --rm -d --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17)"
for i in $(seq 1 60); do
  if docker exec "$cid" pg_isready -U postgres -d postgres >/dev/null 2>&1 && docker exec "$cid" psql -X -U postgres -d postgres -Atqc 'SELECT 1' >/dev/null 2>&1; then break; fi
  sleep 1
done
docker exec "$cid" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c 'CREATE DATABASE rehearsal_source'
docker exec -i "$cid" psql -X -v ON_ERROR_STOP=1 -U postgres -d rehearsal_source <<'SQL'
CREATE TABLE public.fixture (id integer PRIMARY KEY, label text NOT NULL, amount integer NOT NULL);
INSERT INTO public.fixture VALUES (1,'SYNTHETIC A',1250),(2,'SYNTHETIC B',2750);
ALTER TABLE public.fixture ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_select ON public.fixture FOR SELECT USING (false);
SQL
docker exec "$cid" pg_dump -U postgres -d rehearsal_source -Fc > "$work/source.dump"
test -s "$work/source.dump"
export ZHIROX_BACKUP_KEY_B64="$(python -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())')"
python "$1/scripts/encrypt_external_backup.py" "$work/source.dump" "$work/encrypted.zhxb"
python "$1/scripts/verify_external_backup.py" "$work/encrypted.zhxb" "$work/verified.dump"
cmp "$work/source.dump" "$work/verified.dump"
echo 'BACKUP_REHEARSAL: roundtrip bytes PASS'
python - "$work/encrypted.zhxb" "$work/tampered.zhxb" <<'PY'
import pathlib,sys
p=bytearray(pathlib.Path(sys.argv[1]).read_bytes())
p[-1]^=1
pathlib.Path(sys.argv[2]).write_bytes(p)
PY
if python "$1/scripts/verify_external_backup.py" "$work/tampered.zhxb" "$work/rejected.dump" > /dev/null 2>&1; then exit 1; fi
test ! -e "$work/rejected.dump"
echo 'BACKUP_REHEARSAL: tamper rejection PASS'
if ZHIROX_BACKUP_KEY_B64="$(python -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())')" python "$1/scripts/verify_external_backup.py" "$work/encrypted.zhxb" "$work/wrong-key.dump" > /dev/null 2>&1; then exit 1; fi
test ! -e "$work/wrong-key.dump"
echo 'BACKUP_REHEARSAL: wrong key rejection PASS'
unset ZHIROX_BACKUP_KEY_B64
docker exec -i "$cid" pg_restore --list < "$work/verified.dump" >/dev/null
docker exec "$cid" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c 'CREATE DATABASE rehearsal_target'
docker exec -i "$cid" pg_restore --exit-on-error -U postgres -d rehearsal_target < "$work/verified.dump"
check="$(docker exec "$cid" psql -X -v ON_ERROR_STOP=1 -U postgres -d rehearsal_target -Atqc "SELECT (SELECT count(*) FROM public.fixture)||':'||(SELECT sum(amount) FROM public.fixture)||':'||(SELECT relrowsecurity FROM pg_class WHERE oid='public.fixture'::regclass)||':'||(SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='fixture')")"
test "$check" = '2:4000:true:1'
echo 'BACKUP_REHEARSAL: fresh restore + rows + total + RLS + policy PASS'
