#!/usr/bin/env python3
"""Immutable, fail-closed release bundles for ZHIROX rollback."""
import argparse, hashlib, json, shutil, tarfile, tempfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

SCHEMA, RETAIN = 1, 5

def read(path): return json.loads(Path(path).read_text())
def write(path, value): Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""): h.update(chunk)
    return h.hexdigest()

def latest_migration(repo):
    found = sorted(p.stem.split("_", 1)[0] for p in (repo / "supabase/migrations").glob("*.sql"))
    if not found: raise SystemExit("no database migration found")
    return found[-1]

def policy(repo):
    doc = read(repo / "rollback/managed-functions.json")
    rows = doc.get("functions", [])
    names = [r.get("name") for r in rows]
    if doc.get("schema") != SCHEMA or not rows or names != sorted(names) or len(names) != len(set(names)):
        raise SystemExit("invalid or unsorted managed-functions policy")
    for row in rows:
        if row.get("absent_policy") not in {"block", "safe_to_keep"}:
            raise SystemExit("invalid absent-function policy")
        directory = repo / row["path"]
        if not directory.is_dir() or not (directory / "index.ts").is_file():
            raise SystemExit("missing source for " + row["name"])
    return rows

def safe_extract(archive, destination):
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts:
                raise SystemExit("unsafe rollback archive member")
        tar.extractall(destination, filter="data")

def build(args):
    repo, out = Path(args.repo).resolve(), Path(args.output).resolve()
    rows = policy(repo)
    if out.exists(): shutil.rmtree(out)
    source = out / "repo"
    (source / "supabase/functions").mkdir(parents=True)
    shutil.copy2(repo / "supabase/config.toml", source / "supabase/config.toml")
    shutil.copytree(repo / "supabase/functions/_shared", source / "supabase/functions/_shared")
    (source / "rollback").mkdir()
    shutil.copy2(repo / "rollback/managed-functions.json", source / "rollback/managed-functions.json")
    for row in rows: shutil.copytree(repo / row["path"], source / row["path"])
    ipa, manifest = Path(args.ipa), Path(args.manifest)
    shutil.copy2(ipa, out / ipa.name); shutil.copy2(manifest, out / manifest.name)
    archive = out / "edge-functions.tar.gz"
    with tarfile.open(archive, "w:gz", format=tarfile.PAX_FORMAT) as tar: tar.add(source, arcname="repo")
    # Only upload immutable files. Keeping the staging directory here makes
    # shell globs pass a directory to `gh release create`, which GitHub rejects.
    shutil.rmtree(source)
    files = {ipa.name: sha(out / ipa.name), manifest.name: sha(out / manifest.name), archive.name: sha(archive)}
    meta = {
        "schema": SCHEMA, "rollback_ready": True, "edition": "user",
        "tag": args.tag, "commit": args.commit, "build": int(args.build),
        "minimum_migration": latest_migration(repo),
        "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "ipa": ipa.name, "manifest": manifest.name, "source_archive": archive.name,
        "files": files, "functions": rows,
    }
    write(out / "release-metadata.json", meta)
    files["release-metadata.json"] = sha(out / "release-metadata.json")
    (out / "SHA256SUMS").write_text("".join(f"{digest}  {name}\n" for name, digest in sorted(files.items())))

def validate(bundle, tag=None, commit=None):
    bundle, meta = Path(bundle), read(Path(bundle) / "release-metadata.json")
    if meta.get("schema") != SCHEMA or meta.get("rollback_ready") is not True or meta.get("edition") != "user":
        raise SystemExit("bundle is not rollback-ready")
    if tag and meta.get("tag") != tag: raise SystemExit("tag identity mismatch")
    if commit and meta.get("commit") != commit: raise SystemExit("commit identity mismatch")
    for name, expected in meta.get("files", {}).items():
        if not (bundle / name).is_file() or sha(bundle / name) != expected:
            raise SystemExit("checksum mismatch: " + name)
    with tempfile.TemporaryDirectory() as tmp: safe_extract(bundle / meta["source_archive"], Path(tmp))
    return meta

def index(args):
    meta = read(args.metadata)
    old = read(args.existing) if args.existing and Path(args.existing).is_file() else {"releases": []}
    item = {k: meta[k] for k in ("tag", "commit", "build", "minimum_migration", "created_at")}
    item["metadata_sha256"] = sha(args.metadata)
    rows = [item] + [x for x in old.get("releases", []) if x.get("tag") != item["tag"]]
    write(args.output, {"schema": SCHEMA, "releases": rows[:RETAIN]})

def authorize(args):
    errors = []
    if args.confirmation != "ROLLBACK " + args.target: errors.append("confirmation phrase mismatch")
    if len(args.reason.strip()) < 12: errors.append("reason is too short")
    if args.target == args.active: errors.append("target is already active")
    if args.target not in {x.get("tag") for x in read(args.index).get("releases", [])}:
        errors.append("target is not retained")
    if errors: raise SystemExit("; ".join(errors))

def compatible(args):
    minimum, current = str(read(args.metadata)["minimum_migration"]), str(args.current_migration)
    if minimum > current: raise SystemExit("production schema is older than target requirement")
    crossed = [x for x in read(args.barriers).get("barriers", []) if minimum < str(x.get("migration", "")) <= current]
    if crossed: raise SystemExit("migration rollback barrier crossed: " + ",".join(x["migration"] for x in crossed))

def active(args):
    meta = read(args.metadata)
    value = {k: meta[k] for k in ("schema", "tag", "commit", "build", "created_at")}
    value.update({"promotion_kind": args.kind, "source_tag": args.source_tag or None,
                  "actor": args.actor, "reason": args.reason, "run_id": args.run_id})
    write(args.output, value)

def main():
    root = argparse.ArgumentParser(); sub = root.add_subparsers(dest="cmd", required=True)
    p=sub.add_parser("validate-policy"); p.add_argument("--repo", default=".")
    p=sub.add_parser("build")
    for n in ("output","tag","commit","build","ipa","manifest"): p.add_argument("--"+n, required=True)
    p.add_argument("--repo", default=".")
    p=sub.add_parser("validate"); p.add_argument("--bundle",required=True); p.add_argument("--tag"); p.add_argument("--commit")
    p=sub.add_parser("index"); p.add_argument("--metadata",required=True); p.add_argument("--existing"); p.add_argument("--output",required=True)
    p=sub.add_parser("authorize")
    for n in ("target","confirmation","reason","active","index"): p.add_argument("--"+n,required=True)
    p=sub.add_parser("compatible"); p.add_argument("--metadata",required=True); p.add_argument("--current-migration",required=True); p.add_argument("--barriers",required=True)
    p=sub.add_parser("active-release")
    p.add_argument("--metadata",required=True); p.add_argument("--output",required=True); p.add_argument("--kind",required=True)
    p.add_argument("--source-tag",default=""); p.add_argument("--actor",default=""); p.add_argument("--reason",default=""); p.add_argument("--run-id",default="")
    args=root.parse_args()
    if args.cmd=="validate-policy": policy(Path(args.repo).resolve())
    elif args.cmd=="build": build(args)
    elif args.cmd=="validate": validate(args.bundle,args.tag,args.commit)
    elif args.cmd=="index": index(args)
    elif args.cmd=="authorize": authorize(args)
    elif args.cmd=="compatible": compatible(args)
    else: active(args)
if __name__ == "__main__": main()
