"""Executable SQL checks. These do NOT execute or validate the Dart implementation."""
import pathlib, sqlite3, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
SCHEMA=(ROOT/'packages/local_store/lib/schema.sql').read_text()
class SchemaTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.path=pathlib.Path(self.tmp.name)/'db.sqlite'
        self.db=sqlite3.connect(self.path); self.db.execute('PRAGMA foreign_keys=ON');self.db.executescript(SCHEMA)
        self.db.execute('INSERT INTO spaces VALUES(?,?,?)',('s','Space','owner'));self.db.commit()
    def tearDown(self):self.db.close();self.tmp.cleanup()
    def test_embedded_schema_matches(self):
        dart=(ROOT/'packages/local_store/lib/local_store.dart').read_text()
        self.assertEqual(dart.split('const schema = r"""')[1].split('""";')[0],SCHEMA)
    def test_membership_foreign_key(self):
        with self.assertRaises(sqlite3.IntegrityError): self.db.execute("INSERT INTO memberships(space,actor,name,role) VALUES('missing','a','A','member')")
    def test_unique_event_and_transaction_rollback(self):
        row=('s','e','owner','{}',1)
        self.db.execute('INSERT INTO events(space,id,actor,body,committed) VALUES(?,?,?,?,?)',row);self.db.commit()
        with self.assertRaises(sqlite3.IntegrityError):
            with self.db:self.db.execute('INSERT INTO events(space,id,actor,body,committed) VALUES(?,?,?,?,?)',row)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM events').fetchone()[0],1)
    def test_outbox_persistence(self):
        self.db.execute("INSERT INTO outbox VALUES('s','pending','{}',NULL)");self.db.commit();self.db.close()
        self.db=sqlite3.connect(self.path);self.assertEqual(self.db.execute('SELECT id FROM outbox').fetchone()[0],'pending')
    def test_activity_cursor_scoped_to_space(self):
        self.db.execute("INSERT INTO spaces VALUES('other','Other','host2')")
        for space in ['s','other']:self.db.execute('INSERT INTO activity VALUES(?,?,?,?)',(space,1,'a','{}'))
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM activity').fetchone()[0],2)
    def test_integrity(self):self.assertEqual(self.db.execute('PRAGMA integrity_check').fetchone()[0],'ok')
if __name__=='__main__':unittest.main(verbosity=2)
