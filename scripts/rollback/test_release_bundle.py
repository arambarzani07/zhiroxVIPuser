import io, json, tarfile, tempfile, unittest
from pathlib import Path
from types import SimpleNamespace
from scripts.rollback.release_bundle import authorize, build, compatible, index, safe_extract, validate

class RollbackSafetyTests(unittest.TestCase):
    def test_archive_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive=Path(tmp)/"bad.tar.gz"
            with tarfile.open(archive,"w:gz") as tar:
                info=tarfile.TarInfo("../escape"); info.size=1; tar.addfile(info,io.BytesIO(b"x"))
            with self.assertRaises(SystemExit): safe_extract(archive,Path(tmp)/"out")
    def test_authorization_is_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"index.json"; path.write_text(json.dumps({"releases":[{"tag":"user-r1-a"}]}))
            args=SimpleNamespace(target="user-r1-a",confirmation="wrong",reason="short",active="user-r2-b",index=str(path))
            with self.assertRaises(SystemExit): authorize(args)
    def test_only_five_releases_are_retained(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); old=root/"old.json"; meta=root/"meta.json"; out=root/"out.json"
            old.write_text(json.dumps({"releases":[{"tag":f"old-{i}"} for i in range(7)]}))
            meta.write_text(json.dumps({"tag":"new","commit":"a"*40,"build":8,"minimum_migration":"20260101","created_at":"now"}))
            index(SimpleNamespace(metadata=str(meta),existing=str(old),output=str(out)))
            self.assertEqual(["new","old-0","old-1","old-2","old-3"],[x["tag"] for x in json.loads(out.read_text())["releases"]])
    def test_bundle_detects_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); ipa=root/"ZHIROX-User-9.ipa"; manifest=root/"user-update.json"; out=root/"bundle"
            ipa.write_bytes(b"ipa"); manifest.write_text('{"build_number":9}')
            args=SimpleNamespace(repo=".",output=str(out),tag="user-r9-abcdef0",commit="a"*40,
                build="9",ipa=str(ipa),manifest=str(manifest))
            build(args); validate(out,"user-r9-abcdef0","a"*40)
            (out/ipa.name).write_bytes(b"tampered")
            with self.assertRaises(SystemExit): validate(out,"user-r9-abcdef0","a"*40)
    def test_migration_barrier_blocks_rollback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); meta=root/"meta.json"; barriers=root/"barriers.json"
            meta.write_text(json.dumps({"minimum_migration":"20260101"}))
            barriers.write_text(json.dumps({"barriers":[{"migration":"20260201"}]}))
            args=SimpleNamespace(metadata=str(meta),current_migration="20260301",barriers=str(barriers))
            with self.assertRaises(SystemExit): compatible(args)
if __name__=="__main__": unittest.main()
