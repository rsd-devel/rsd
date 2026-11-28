from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CONVERTER = Path(__file__).resolve().parents[1] / "KanataConverter.py"


class TestKanataConverter(unittest.TestCase):
    def test_fetch_flush_with_and_without_legacy_request_records(self):
        for legacy in (False, True):
            with self.subTest(legacy=legacy), tempfile.TemporaryDirectory() as tmp:
                src = Path(tmp) / "rsd.log"
                dest = Path(tmp) / "kanata.log"
                records = ["RSD_Kanata\t0", "C\t1"]
                if legacy:
                    records += ["S\t0\t1\t0\t0\t1\t0\t", "S\t0\t1\t0\t0\t2\t0\t"]
                # The first instruction arrives flushed. The second stalls at Fetch
                # and is flushed one cycle later, after it was already visible.
                records += ["C\t1", "S\t1\t1\t0\t1\t1\t0\t",
                            "S\t1\t1\t1\t1\t2\t0\t", "C\t1",
                            "S\t1\t1\t0\t1\t2\t0\t"]
                src.write_text("\n".join(records) + "\n")
                subprocess.run([sys.executable, "-B", CONVERTER, src, dest], check=True)
                events = dest.read_text().splitlines()
                self.assertEqual([row for row in events if row.startswith("I\t")],
                                 ["I\t0\t8\t0"])
                self.assertEqual("S\t0\t0\tBp" in events, legacy)
                self.assertIn("S\t0\t0\tF", events)
                self.assertIn("S\t0\t1\tstl", events)
                self.assertIn("R\t0\t0\t1", events)
