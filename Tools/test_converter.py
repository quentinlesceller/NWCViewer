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
HELPER = ROOT / 'Converter/score-reader'

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

    def test_modern_notation_and_measure_alignment(self):
        with tempfile.TemporaryDirectory() as d:
            file = Path(d)/'modern.nwc'
            file.write_bytes((ROOT/'Tests/Fixtures/Modern275.nwc').read_bytes())
            subprocess.run([str(HELPER),str(file)],check=True,capture_output=True)
            xml = ET.parse(file.with_suffix('.xml'))
            measures = xml.findall('.//part/measure')
            self.assertEqual(len(measures),5)
            self.assertEqual([sum(int(n.findtext('duration','0')) for n in m.findall('note') if n.find('chord') is None) for m in measures], [1920,720,720,720,720])
            self.assertEqual(measures[1].findtext('attributes/time/beats'),'3')
            self.assertEqual(measures[0].find('note/accidental').attrib,{'parentheses':'yes'})
            self.assertEqual([n.findtext('pitch/alter') for n in measures[0].findall('note')],['1','1'])
            self.assertEqual(measures[0].findall('note')[1].find('tie').attrib['type'],'stop')
            self.assertEqual(len(xml.findall('.//time-modification')),3)
            self.assertEqual(xml.findtext('.//lyric/text'),'Bon')

    def test_legacy_lyrics_and_polyphony(self):
        with tempfile.TemporaryDirectory() as directory:
            def read(name):
                path = Path(directory) / 'score.nwc'
                path.write_bytes((ROOT/'Tests/Fixtures'/name).read_bytes())
                subprocess.run([str(HELPER), str(path)], check=True, capture_output=True)
                return ET.parse(path.with_suffix('.xml'))
            lyrics = read('syllables.nwc').findall('.//lyric')
            self.assertEqual([(v.findtext('text'), v.findtext('syllabic')) for v in lyrics],
                             [('A', 'begin'), ('mer', 'middle'), ('i', 'middle'), ('ca', 'end')])
            score = read('Flee.nwc')
            self.assertEqual([(len(p.findall('measure')), len(p.findall('.//note')))
                              for p in score.findall('part')], [(18, 148), (18, 143)])
            self.assertTrue(score.findall('.//backup'))
            score = read('St._Stephen.nwc')
            last = score.findall('part/measure')[2].findall('note')[-1]
            self.assertEqual([last.findtext('pitch/'+k) for k in ('step', 'alter', 'octave')],
                             ['C', '1', '5'])

    def test_single_note_across_legacy_layouts(self):
        # Independent, minimal scores exercise every supported binary header and note width.
        def word(n):
            return n.to_bytes(2, 'little')
        versions = [(0x11e, 26), (0x132, 28), (0x137, 29), (0x146, 30),
                    (0x14b, 31), (0x200, 39), (0x201, 39)]
        for version, staff_size in versions:
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                raw = bytearray(b'[NoteWorthy ArtWare]\0\0\0[NoteWorthy Composer]\0' + word(version))
                raw += bytes(16) + b'Title\0Author\0' + bytes(3 + (version >= 0x200))
                raw += bytes(11) + b'1 1 1 1\0' + bytes(3)
                if version > 0x11e:
                    raw += b'\xff' * 32 + bytes(1)
                if version >= 0x200:
                    raw += b'Font\0'
                raw += word(16)
                fonts = 0 if version == 0x11e else 10 if version <= 0x146 else 12
                raw += (b'Font\0' + bytes(4)) * fonts
                raw += bytes(4) + word(1) + b'Alto\0'
                if version >= 0x200:
                    raw += b'Alto\0Choir\0'
                raw += b'Choir\0' + bytes(staff_size) + word(0) + word(0)
                raw += word(3 if version > 0x132 else 1)
                raw += word(8) + bytes(version >= 0x146)
                raw += bytes([2, 0, 0, 0, 0, 0, 0, 5]) + bytes(2 if version <= 0x146 else 0)
                path = Path(directory)/'score.nwc'
                path.write_bytes(raw)
                subprocess.run([str(HELPER), str(path)], check=True, capture_output=True)
                score = ET.parse(path.with_suffix('.xml'))
                self.assertEqual(score.findtext('.//part-name'), 'Alto')
                self.assertEqual(score.findtext('.//note/pitch/step'), 'B')
                self.assertEqual(score.findtext('.//note/type'), 'quarter')

    def test_incomplete_legacy_records_leave_no_output(self):
        raw = (ROOT/'Tests/Fixtures/Uncompressed.nwc').read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'score.nwc'
            for length in [47, 80, 500, 675, len(raw)-1]:
                path.write_bytes(raw[:length])
                result = subprocess.run([str(HELPER), str(path)], capture_output=True)
                self.assertNotEqual(result.returncode, 0, length)
                self.assertFalse(path.with_suffix('.xml').exists())

    def test_mixed_key_signature(self):
        source = zlib.decompress((ROOT/'Tests/Fixtures/Modern275.nwc').read_bytes()[6:])
        start = source.index(b'|AddStaff')
        record = source.index(b'\n', start) + 1
        source = source[:record] + b'|Key|Signature:Bb,F#\n' + source[record:]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'custom.nwc'
            path.write_bytes(source)
            subprocess.run([str(HELPER), str(path)], check=True, capture_output=True)
            key = ET.parse(path.with_suffix('.xml')).find('.//key')
            self.assertEqual([(e.tag, e.text) for e in key], [
                ('key-step', 'B'), ('key-alter', '-1'), ('key-step', 'F'), ('key-alter', '1')
            ])

    def test_modern_unsupported_record_fails_without_partial_output(self):
        source=zlib.decompress((ROOT/'Tests/Fixtures/Modern275.nwc').read_bytes()[6:])
        for payload in [source.replace(b'|Note|Dur:Half', b'|RestChord|Dur:Half',1),source.replace(b'!NoteWorthyComposer-End',b'')]:
            with tempfile.TemporaryDirectory() as d:
                file=Path(d)/'invalid.nwc'
                file.write_bytes(b'[NWZ]\0'+zlib.compress(payload))
                result=subprocess.run([str(HELPER),str(file)],capture_output=True)
                self.assertNotEqual(result.returncode,0)
                self.assertFalse(file.with_suffix('.xml').exists())

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
