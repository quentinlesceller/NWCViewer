#!/usr/bin/env python3
"""Portable integration tests for the real binary converter; no Python packages."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
import unittest
import zlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'Vendor/nwc2xml/nwc2xml'

class ConverterTests(unittest.TestCase):
    def test_binary_fixtures(self):
        for fixture in sorted((ROOT/'Tests/Fixtures').glob('*.nwc')):
            with self.subTest(fixture=fixture.name), tempfile.TemporaryDirectory() as d:
                original = fixture.read_bytes()
                self.assertTrue(original.startswith((b'[NWZ]\0', b'[NoteWorthy ArtWare]')))
                score = Path(d) / "Choir 日本語 ' $file ;.nwc"
                score.write_bytes(original)
                result = subprocess.run([str(HELPER), str(score)], capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                xml = ET.parse(score.with_suffix('.xml')).getroot()
                self.assertEqual(xml.tag, 'score-partwise')
                self.assertGreater(len(xml.findall('.//note')), 0)
                self.assertEqual(score.read_bytes(), original)
                self.assertFalse(fixture.with_suffix('.xml').exists())

    def test_bad_files_return_failure(self):
        for bad in [b'', b'[NWZ]\0broken', b'!NoteWorthyComposer(2.75)\n', b'not a score']:
            with self.subTest(data=bad), tempfile.TemporaryDirectory() as d:
                file = Path(d)/'bad.nwc'
                file.write_bytes(bad)
                result = subprocess.run([str(HELPER), str(file)], capture_output=True, timeout=20)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(file.with_suffix('.xml').exists())

    def test_unsupported_version(self):
        binary = bytearray((ROOT/'Tests/Fixtures/Uncompressed.nwc').read_bytes())
        offset = len(b'[NoteWorthy ArtWare]\0\0\0[NoteWorthy Composer]\0')
        binary[offset:offset+2] = b'\xff\x7f'
        with tempfile.TemporaryDirectory() as d:
            file=Path(d)/'future.nwc'
            file.write_bytes(binary)
            result=subprocess.run([str(HELPER),str(file)],capture_output=True,timeout=20)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(file.with_suffix('.xml').exists())

    def test_expansion_limit(self):
        with tempfile.TemporaryDirectory() as d:
            file = Path(d)/'oversized.nwc'
            file.write_bytes(b'[NWZ]\0' + zlib.compress(b'\0' * (33 * 1024 * 1024)))
            result = subprocess.run([str(HELPER), str(file)], capture_output=True, timeout=20,
                                    env=dict(__import__('os').environ, TMPDIR=d))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(Path(d).iterdir()), [file])

    def test_vendor_checksums(self):
        for line in (ROOT/'Vendor/SHA256SUMS').read_text().splitlines():
            expected, path = line.split('  ',1)
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), expected, path)

if __name__ == '__main__': unittest.main(verbosity=2)
