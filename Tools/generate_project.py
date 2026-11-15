#!/usr/bin/env python3
"""Generate a deterministic Xcode project, using only Python's standard library."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def ref(name): return uid(name)
def add(key, isa, **fields):
    objects[uid(key)] = dict(isa=isa, **fields)
    return uid(key)
def quote(value): return json.dumps(str(value))

def file(path, kind):
    return add(path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')
def build(name, file_id, **kw): return add('build:'+name, 'PBXBuildFile', fileRef=file_id, **kw)
def phase(key, isa, files, **kw):
    return add(key, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0, **kw)

apps = [file(str(p.relative_to(ROOT)), 'sourcecode.swift') for p in sorted((ROOT/'App').glob('*.swift'))]
cpp = [file('Vendor/nwc2xml/'+n+'.cpp','sourcecode.cpp.cpp') for n in ['nwc2xml','nwcfile','nwcobj','xmlsaver','xmlwriter','wxshim']]
cpp.append(file('Converter/ModernNWC.cpp', 'sourcecode.cpp.cpp'))
icon = file('Resources/AppIcon.icns', 'image.icns')
web = file('Resources/Web', 'folder')
licenses = file('Resources/Licenses', 'folder')
languages = sorted(p.stem for p in (ROOT/'Resources').glob('*.lproj'))
localized = []
for filename in ['Localizable.strings', 'Localizable.stringsdict']:
    children = [add('localization:'+lang+':'+filename, 'PBXFileReference', lastKnownFileType='text.plist.strings' if filename.endswith('.strings') else 'text.plist.xml', name=lang, path='Resources/'+lang+'.lproj/'+filename, sourceTree='<group>') for lang in languages]
    localized.append(add('localized:'+filename, 'PBXVariantGroup', children=children, name=filename, sourceTree='<group>'))
fixtures = file('Tests/Fixtures', 'folder')
test = file('Tests/ViewerTests.swift', 'sourcecode.swift')
app_product = add('appProduct','PBXFileReference', explicitFileType='wrapper.application', path='NWC Viewer.app', sourceTree='BUILT_PRODUCTS_DIR')
helper_product = add('helperProduct','PBXFileReference', explicitFileType='compiled.mach-o.executable', path='nwc2xml', sourceTree='BUILT_PRODUCTS_DIR')
test_product = add('testProduct','PBXFileReference', explicitFileType='wrapper.cfbundle', path='NWCViewerTests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
products = add('products','PBXGroup', children=[app_product,helper_product,test_product], name='Products',sourceTree='<group>')
main = add('main','PBXGroup', children=apps+cpp+localized+[icon,web,licenses,test,fixtures,products], sourceTree='<group>')

base = dict(ALWAYS_SEARCH_USER_PATHS='NO',MACOSX_DEPLOYMENT_TARGET='13.0', SDKROOT='macosx', SWIFT_VERSION='5.0', CLANG_CXX_LANGUAGE_STANDARD='c++11', CODE_SIGN_IDENTITY='-', CODE_SIGN_STYLE='Manual', ENABLE_USER_SCRIPT_SANDBOXING='YES')
def configs(name, extras):
    refs=[]
    for mode in ['Debug','Release']:
        settings = dict(base, **extras)
        settings.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode=='Debug' else '-O', GCC_OPTIMIZATION_LEVEL='0' if mode=='Debug' else 's', DEBUG_INFORMATION_FORMAT='dwarf' if mode=='Debug' else 'dwarf-with-dsym', ENABLE_TESTABILITY='YES' if mode=='Debug' else 'NO')
        refs.append(add(name+mode,'XCBuildConfiguration', name=mode, buildSettings=settings))
    return add(name+'configs','XCConfigurationList', buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

def dependency(name, target):
    proxy = add(name+'proxy','PBXContainerItemProxy', containerPortal=ref('project'), proxyType=1, remoteGlobalIDString=ref(target), remoteInfo=target)
    return add(name+'dependency','PBXTargetDependency', target=ref(target), targetProxy=proxy)

helper_phases=[phase('helperSources','PBXSourcesBuildPhase',[build('cpp'+str(i),f) for i,f in enumerate(cpp)]),phase('helperFrameworks','PBXFrameworksBuildPhase',[])]
add('helper','PBXNativeTarget', name='nwc2xml', productName='nwc2xml', productReference=helper_product, productType='com.apple.product-type.tool', buildConfigurationList=configs('helper',dict(PRODUCT_NAME='nwc2xml',SKIP_INSTALL='YES',OTHER_LDFLAGS=['-lz','-liconv'],GCC_WARN_INHIBIT_ALL_WARNINGS='YES')), buildPhases=helper_phases, buildRules=[], dependencies=[])
copy=phase('copyHelper','PBXCopyFilesBuildPhase',[build('helperCopy',helper_product,settings={'ATTRIBUTES':['CodeSignOnCopy']})],dstPath='Contents/Helpers', dstSubfolderSpec=1, name='Embed converter')
app_phases=[phase('appSources','PBXSourcesBuildPhase',[build('swift'+str(i),f) for i,f in enumerate(apps)]),phase('appResources','PBXResourcesBuildPhase',[build('icon',icon),build('web',web),build('licenses',licenses)]+[build('localized:'+str(i),f) for i,f in enumerate(localized)]),phase('appFrameworks','PBXFrameworksBuildPhase',[]),copy]
add('app','PBXNativeTarget', name='NWCViewer', productName='NWC Viewer', productReference=app_product, productType='com.apple.product-type.application', buildConfigurationList=configs('app',dict(PRODUCT_NAME='NWC Viewer',PRODUCT_MODULE_NAME='NWCViewer',PRODUCT_BUNDLE_IDENTIFIER='com.quentinlesceller.nwcviewer',INFOPLIST_FILE='Resources/Info.plist',ENABLE_APP_SANDBOX='NO',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks'])), buildPhases=app_phases, buildRules=[], dependencies=[dependency('apphelper','helper')])
test_phases=[phase('testSources','PBXSourcesBuildPhase',[build('test',test)]),phase('testResources','PBXResourcesBuildPhase',[build('fixtures',fixtures)]),phase('testFrameworks','PBXFrameworksBuildPhase',[])]
add('tests','PBXNativeTarget',name='NWCViewerTests',productName='NWCViewerTests',productReference=test_product,productType='com.apple.product-type.bundle.unit-test',buildConfigurationList=configs('tests',dict(PRODUCT_NAME='NWCViewerTests',PRODUCT_BUNDLE_IDENTIFIER='org.example.NWCViewerTests',GENERATE_INFOPLIST_FILE='YES',TEST_HOST='$(BUILT_PRODUCTS_DIR)/NWC Viewer.app/Contents/MacOS/NWC Viewer',BUNDLE_LOADER='$(TEST_HOST)',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks','@loader_path/../Frameworks'])),buildPhases=test_phases,buildRules=[],dependencies=[dependency('testsapp','app')])
add('project','PBXProject',attributes={'LastUpgradeCheck':'1600'},buildConfigurationList=configs('project',{}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=languages+['Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[ref('app'),ref('helper'),ref('tests')])

def serialize(value):
    if isinstance(value,dict): return '{ '+ ' '.join(f'{quote(k)} = {serialize(v)};' for k,v in value.items())+' }'
    if isinstance(value,list): return '('+ ', '.join(serialize(v) for v in value)+')'
    if isinstance(value,int): return str(value)
    # Object identifiers must be unquoted references; other strings may be quoted.
    return value if value in objects else quote(value)
project=ROOT/'NWCViewer.xcodeproj'
project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=ref('project')))+'\n')
schemes=project/'xcshareddata/xcschemes'
schemes.mkdir(parents=True,exist_ok=True)
def br(target,product,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(target)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:NWCViewer.xcodeproj"/>'
(schemes/'NWCViewer.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{br('app','NWC Viewer.app','NWCViewer')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{br('tests','NWCViewerTests.xctest','NWCViewerTests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{br('app','NWC Viewer.app','NWCViewer')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{br('app','NWC Viewer.app','NWCViewer')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
