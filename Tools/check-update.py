#!/usr/bin/env python3
"""Verify a prepared feed/archive and prove that modified copies are rejected."""
import argparse
import plistlib
import re
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import urlparse, unquote
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('updates', type=Path)
parser.add_argument('--info-plist', type=Path, default=Path(__file__).resolve().parents[1] / 'Resources/Info.plist')
args = parser.parse_args()
public_key = plistlib.loads(args.info_plist.read_bytes())['SUPublicEDKey']
feed = args.updates / 'appcast.xml'
content, marker, block = feed.read_bytes().rpartition(b'<!-- sparkle-signatures:\n')
assert marker, 'Feed has no signature'
feed_signature = re.search(rb'edSignature:\s*(\S+)', block).group(1).decode()
assert len(content) == int(re.search(rb'length:\s*(\d+)', block).group(1))
enclosure = ET.parse(feed).find('./channel/item/enclosure')
assert enclosure is not None
archive = args.updates / unquote(Path(urlparse(enclosure.attrib['url']).path).name)
signature = enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature']
assert archive.stat().st_size == int(enclosure.attrib['length'])
with tempfile.TemporaryDirectory(prefix='NWCViewer-update-test-') as tmp:
    verifier = Path(tmp) / 'verify-signature'
    subprocess.run(['xcrun', 'swiftc', str(Path(__file__).with_name('verify-signature.swift')),
                    '-o', str(verifier)], check=True)
    verify = [str(verifier), public_key]
    feed_content = Path(tmp) / 'feed-content'
    feed_content.write_bytes(content)
    subprocess.run(verify + [str(feed_content), feed_signature], check=True)
    subprocess.run(verify + [str(archive), signature], check=True)
    bad_feed = Path(tmp) / 'changed-feed'
    assert b'<title>' in content
    bad_feed.write_bytes(content.replace(b'<title>', b'<title>Changed ', 1))
    bad_archive = Path(tmp) / archive.name
    bad_archive.write_bytes(archive.read_bytes() + b'tampered')
    for command in [verify + [str(bad_feed), feed_signature], verify + [str(bad_archive), signature]]:
        result = subprocess.run(command, capture_output=True)
        assert result.returncode == 1, 'Modified update unexpectedly passed verification'
print('Feed and archive signatures valid; tampered feed and archive rejected.')
