#!/usr/bin/env python3
"""Optional browser regression tests; see README for test-only dependencies.
Chromium verifies the renderer/CSS; the XCTest suite separately tests WKWebView.
"""
from pathlib import Path
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from threading import Thread
import os
import subprocess
import tempfile
import unittest
from playwright.sync_api import sync_playwright
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args): pass

class RendererTests(unittest.TestCase):
    def test_voice_selection_and_reused_layout(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(ROOT/'Resources/Web')))
        Thread(target=server.serve_forever, daemon=True).start()
        try:
            with sync_playwright() as p, tempfile.TemporaryDirectory() as d:
                options = {'headless': True}
                if os.environ.get('CHROMIUM_BINARY'): options['executable_path'] = os.environ['CHROMIUM_BINARY']
                browser = p.chromium.launch(**options)
                page = browser.new_page()
                page.goto(f'http://127.0.0.1:{server.server_port}/index.html')
                info=page.evaluate('(xml)=>viewer.load(xml,4)',(ROOT/'Tests/Fixtures/Voices.musicxml').read_text())
                self.assertEqual(info['renderedPartCount'],3)
                alto=page.evaluate('viewer.configure(4,["alto"])')
                self.assertEqual(alto['selectedPartIDs'],['alto'])
                self.assertEqual(alto['renderedPartCount'],1)
                self.assertEqual(alto['sourceMeasureCount'],4)
                self.assertEqual(alto['measuresPerLine'],[4])
                for choice in [2,4]:
                    updated=page.evaluate('(n)=>viewer.configure(n,["alto"])',choice)
                    self.assertEqual(updated['parses'],alto['parses'])
                    self.assertEqual(updated['renderedPartCount'],1)
                output=Path(d)/'alto.pdf'
                page.pdf(path=str(output),prefer_css_page_size=True)
                text=''.join(p.extract_text() for p in PdfReader(output).pages)
                self.assertIn('AltoTest',text)
                self.assertNotIn('SopranoTest',text)
                self.assertNotIn('BassTest',text)
                for ids in [[],['missing']]:
                    rejected=page.evaluate('(ids)=>viewer.configure(4,ids).then(()=>false,()=>true)',ids)
                    self.assertTrue(rejected)
                    self.assertEqual(page.evaluate('viewer.layoutInfo().selectedPartIDs'),['alto'])
                info=page.evaluate('viewer.configure(4,null)')
                self.assertEqual(info['renderedPartCount'],3)
                self.assertEqual(info['sourceMeasureCount'],4)
                browser.close()
        finally:
            server.shutdown(); server.server_close()

    def test_offline_render_zoom_and_paginated_pdf(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(ROOT/'Resources/Web')))
        Thread(target=server.serve_forever, daemon=True).start()
        try:
            with sync_playwright() as p, tempfile.TemporaryDirectory() as d:
                options = {'headless': True}
                if os.environ.get('CHROMIUM_BINARY'): options['executable_path'] = os.environ['CHROMIUM_BINARY']
                browser = p.chromium.launch(**options)
                page = browser.new_page()
                errors, external_requests = [], []
                page.on('pageerror', lambda e: errors.append(str(e)))
                origin = f'http://127.0.0.1:{server.server_port}'
                page.on('request', lambda r: external_requests.append(r.url) if not r.url.startswith(origin) else None)
                page.goto(origin+'/index.html')
                for fixture in sorted((ROOT/'Tests/Fixtures').glob('*.nwc')):
                    score = Path(d)/fixture.name
                    score.write_bytes(fixture.read_bytes())
                    subprocess.run([str(ROOT/'Converter/score-reader'), str(score)], check=True, capture_output=True, timeout=20)
                    page.evaluate('(xml)=>window.viewer.load(xml)', score.with_suffix('.xml').read_text())
                    # A fixed count must reflow music, not merely cap the old layout.
                    for count in [2, 3, 4, 6, 8, 0]:
                        page.evaluate('([xml,count])=>window.viewer.load(xml,count)', [score.with_suffix('.xml').read_text(),count])
                        info=page.evaluate('window.viewer.layoutInfo()')
                        lines=info['measuresPerLine']
                        self.assertTrue(lines)
                        if count:
                            self.assertTrue(all(n==count for n in lines[:-1]),(fixture.name,count,lines))
                            self.assertLessEqual(lines[-1],count)
                    # Export the default four-measure layout at different screen zooms.
                    page.evaluate('(xml)=>window.viewer.load(xml,4)',score.with_suffix('.xml').read_text())
                    pages = page.locator('.music-page svg').count()
                    self.assertGreater(pages, 0)
                    dimensions=page.locator('.music-page svg').first.evaluate('(s)=>[s.viewBox.baseVal.width,s.viewBox.baseVal.height]')
                    self.assertAlmostEqual(dimensions[0]/dimensions[1],210/297,places=3)
                    for zoom in [0.5, 1, 2]:
                        page.evaluate('(value)=>window.viewer.zoom(value)', zoom)
                        self.assertEqual(float(page.locator('#score').evaluate('(s)=>s.style.zoom')),zoom)
                        output=Path(d)/f'{fixture.stem}-{zoom}.pdf'
                        page.pdf(path=str(output), prefer_css_page_size=True)
                        pdf=PdfReader(output)
                        self.assertEqual(len(pdf.pages),pages)
                        for pdfpage in pdf.pages:
                            self.assertAlmostEqual(float(pdfpage.mediabox.width),595.28,delta=1)
                            self.assertAlmostEqual(float(pdfpage.mediabox.height),841.89,delta=1)
                self.assertEqual(errors,[])
                self.assertEqual(external_requests,[])
                browser.close()
        finally:
            server.shutdown()
            server.server_close()

if __name__ == '__main__': unittest.main(verbosity=2)
