#!/usr/bin/env python3
"""Check complete, valid translations and compatible formatting placeholders on macOS."""
from pathlib import Path
import json, plistlib, re, subprocess
root=Path(__file__).resolve().parents[1]/'Resources'
base=None
for folder in sorted(root.glob('*.lproj')):
    values=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(folder/'Localizable.strings')]))
    if base is None:
        base=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(root/'en.lproj/Localizable.strings')]))
    assert values.keys()==base.keys(), f'Missing/extra keys: {folder.name}'
    for key,value in values.items():
        assert value.strip(), (folder.name,key)
        assert re.findall(r'%(?:@|ld|d|s)',key)==re.findall(r'%(?:@|ld|d|s)',value), (folder.name,key)
    plural=plistlib.loads((folder/'Localizable.stringsdict').read_bytes())['page_count']
    assert plural['pages']['NSStringFormatValueTypeKey']=='ld'
    for form in ['one','other']: assert '%ld' in plural['pages'][form]
    print(folder.name+': '+str(len(values))+' labels/errors and plural forms verified')
