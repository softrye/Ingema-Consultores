"""Source/resource checks only. Does not invoke Qt tools, a compiler, or Android."""
from pathlib import Path
import json
import itertools
import math
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[1]
BASE = '7fd2027106eb26bbb4e4cef5aea135bc300a2d62'
RP = ROOT / 'src/retroplasma'
passed = 0


def read(path):
    return (ROOT / path).read_text(encoding='utf-8-sig')


def check(name, condition):
    global passed
    if not condition:
        raise AssertionError(name)
    passed += 1
    print(f'STATIC_PASS {name}')


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def balanced(text):
    # Lexical delimiter check, not a C++/QML parser or compilation claim.
    text = re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '', text)
    stack = []
    pairs = {')': '(', ']': '[', '}': '{'}
    for char in text:
        if char in '([{':
            stack.append(char)
        elif char in ')]}':
            if not stack or stack.pop() != pairs[char]:
                return False
    return not stack


def assets_valid():
    directory = RP / 'resources/sample'
    scene = json.loads((directory / 'scene.json').read_text(encoding='utf-8'))
    assert scene['format'] == 'inge-retroplasma-scene-v1'
    assert scene['license'] == 'CC0-1.0' and scene['source']
    assert abs(scene['origin']['latitude']) <= 90 and abs(scene['origin']['longitude']) <= 180
    nodes = {node['id']: node for node in scene['nodes']}
    assert len(nodes) == len(scene['nodes']) == 5
    meshes = set()
    for node in nodes.values():
        box = node['bounds']
        assert len(box) == 6 and all(math.isfinite(v) and abs(v) <= 100000 for v in box)
        assert all(box[i] <= box[i+3] for i in range(3))
        parent = node.get('parent')
        if parent:
            outer = nodes[parent]['bounds']
            assert all(outer[i] <= box[i] and box[i+3] <= outer[i+3] for i in range(3))
        chain = set()
        current = node
        while current.get('parent'):
            assert current['id'] not in chain
            chain.add(current['id'])
            current = nodes[current['parent']]
        assert sum(n.get('parent') == node['id'] for n in nodes.values()) <= 8
        children = [n['bounds'] for n in nodes.values() if n.get('parent') == node['id']]
        if children:
            samples = []
            for axis in range(3):
                edges = sorted({box[axis],box[axis+3],*(b[axis] for b in children),*(b[axis+3] for b in children)})
                samples.append([(a+b)/2 for a,b in zip(edges,edges[1:])] or [box[axis]])
            assert all(any(all(b[i]-.02 <= point[i] <= b[i+3]+.02 for i in range(3)) for b in children)
                       for point in itertools.product(*samples)), 'sample children do not cover parent'
        errors = [lod['error'] for lod in node['lods']]
        assert errors == sorted(errors, reverse=True) and all(e >= 0 for e in errors)
        for lod in node['lods']:
            for key in ('mesh', 'texture'):
                relative = lod[key]
                assert ':' not in relative and '..' not in Path(relative).parts and not Path(relative).is_absolute()
                assert (directory / relative).is_file()
            mesh = directory / lod['mesh']
            meshes.add(mesh)
            positions, uvs, faces = [], [], []
            for line in mesh.read_text(encoding='utf-8').splitlines():
                fields = line.split()
                if not fields or fields[0].startswith('#'):
                    continue
                if fields[0] == 'v':
                    p = [float(v) for v in fields[1:4]]
                    assert len(p) == 3 and all(math.isfinite(v) for v in p)
                    assert all(box[i]-.02 <= p[i] <= box[i+3]+.02 for i in range(3))
                    positions.append(p)
                elif fields[0] == 'vt':
                    uv = [float(v) for v in fields[1:3]]
                    assert len(uv) == 2 and all(math.isfinite(v) for v in uv)
                    uvs.append(uv)
                elif fields[0] == 'f':
                    corners = [corner.split('/') for corner in fields[1:]]
                    assert len(corners) == 3
                    assert all(0 < int(c[0]) <= len(positions) and 0 < int(c[1]) <= len(uvs) for c in corners)
                    faces.append(corners)
            assert 0 < len(positions) <= 65535 and faces and uvs
            for face in faces:
                a, b, c = [positions[int(corner[0])-1] for corner in face]
                # ENU up is z; CCW top faces survive back-face culling after ENU -> render.
                assert (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]) > 0
    assert len(meshes) == 10
    png = (directory / 'terrain.png').read_bytes()
    assert png[:8] == b'\x89PNG\r\n\x1a\n'
    offset, compressed, dimensions = 8, bytearray(), None
    while offset < len(png):
        size = struct.unpack_from('>I', png, offset)[0]
        kind = png[offset+4:offset+8]
        data = png[offset+8:offset+8+size]
        crc = struct.unpack_from('>I', png, offset+8+size)[0]
        assert zlib.crc32(kind+data) & 0xffffffff == crc
        if kind == b'IHDR':
            dimensions = struct.unpack('>IIBBBBB', data)
        if kind == b'IDAT':
            compressed.extend(data)
        offset += size + 12
    width, height, depth, color, *_ = dimensions
    assert 0 < width <= 1024 and 0 < height <= 1024 and depth == 8 and color in (2, 6)
    raw = zlib.decompress(compressed)
    channels = 3 if color == 2 else 4
    assert len(raw) == height*(1+width*channels) and len(set(raw)) > 64
    return True


def main():
    cmake = read('CMakeLists.txt')
    module = read('src/retroplasma/CMakeLists.txt')
    entry = read('main_mobile.cpp')
    home = read('qml/Mobile/HomeScreen.qml')
    view = read('qml/Mobile/RetroplasmaEarthView.qml')
    item = read('src/retroplasma/RetroplasmaItem.cpp')
    ctrl = read('src/retroplasma/RetroplasmaController.cpp')
    provider = read('src/retroplasma/RetroplasmaDataProvider.cpp')
    scheduler = read('src/retroplasma/RetroplasmaTileScheduler.cpp')
    android = '{http://schemas.android.com/apk/res/android}'
    manifest = ET.fromstring(read('android/AndroidManifest.xml'))
    launchers = manifest.findall('.//category[@'+android+'name="android.intent.category.LAUNCHER"]')
    check('RP-01 module/URI/plugin/source files', 'add_subdirectory(src/retroplasma)' in cmake
          and 'InGeRetroplasma InGeRetroplasmaplugin' in cmake and 'URI InGe.Retroplasma' in module
          and 'import InGe.Retroplasma 1.0' in view
          and all((RP / name).is_file() for name in re.findall(r'\bRetroplasma\w+\.(?:h|cpp)\b', module)))
    check('RP-02 same APK, launcher and sole controller', len(launchers) == 1
          and entry.count('RetroplasmaController earthNative;') == 1
          and entry.count('setContextProperty("EarthNative", &earthNative)') == 1)
    baseline = git('show', BASE+':main_mobile.cpp').decode('utf-8-sig')
    backend = r'QQuickWindow::setGraphicsApi\([^;]+;'
    check('RP-03 native RHI and preserved global backend', '#include <QQuickRhiItem>' in read('src/retroplasma/RetroplasmaItem.h')
          and re.findall(backend, entry) == re.findall(backend, baseline)
          and 'Qt6::GuiPrivate' in module and 'Qt6::Quick' in module)
    vertex, fragment = [read('src/retroplasma/shaders/terrain.'+ext) for ext in ('vert', 'frag')]
    check('RP-04 shader source/resource ABI', all('mat4 mvp;vec4 light;' in shader for shader in (vertex, fragment))
          and 'Qt6' in module and 'qt_add_shaders' in module and '100es,300es,120,150' in module
          and '0,80,uniform' in item and all(':/inge/retroplasma/shaders/terrain.'+ext+'.qsb' in item for ext in ('vert','frag')))
    check('RP-05 mesh/index/bounds limits', 'IndexUInt16' in item and 'out.vertices.size()>65535' in read('src/retroplasma/RetroplasmaGeometryDecoder.cpp')
          and 'RP_MESH_OUTSIDE_NODE_BOUNDS' in ctrl and 'setDepthTest(true)' in item and 'setDepthWrite(true)' in item)
    check('RP-06 ten authorized meshes and PNG CRC/pixels', assets_valid())
    camera = read('src/retroplasma/RetroplasmaCamera.cpp')
    check('RP-07 one camera, interpolation and geographic target', read('src/retroplasma/RetroplasmaController.h').count('inge::rp::Camera m_camera;') == 1
          and 'std::exp' in camera and 'nearPlane' in camera and 'farPlane' in camera and 'm_pendingTarget' in ctrl)
    check('RP-08 mobile gesture bindings', all(handler in view for handler in ('DragHandler','PinchHandler','WheelHandler','onScaleChanged','onRotationChanged','onTranslationChanged'))
          and 'onActiveScaleChanged' not in view and 'onActiveRotationChanged' not in view)
    check('RP-09 existing Dock integration and telemetry guard', 'earth/retroplasma' in home and 'EarthNative.command' in home
          and 'home.earthDockReady !== EarthNative.ready' in home and 'home.dockRouter.complete(dispatchId)' in home
          and all('earth.'+cmd in home for cmd in ('zoomIn','zoomOut','goTo','navigation','coordinates','diagnostics','reset','north')))
    math_header = read('src/retroplasma/RetroplasmaMath.h')
    check('RP-10 double geography and origin-relative vertices', 'double x=0,y=0,z=0' in math_header
          and 'geodeticToEcef' in ctrl and 'ecefToEnu' in ctrl and 'enuToRender' in ctrl)
    check('RP-11 hierarchy and progressive LOD source', 'intersectsFrustum' in scheduler and 'childrenReady' in scheduler
          and 'stable_sort' in scheduler and 'anyResident' in scheduler and 'RP_OCTREE_CHILD_LIMIT' in provider)
    check('RP-12 bounded caches and render-thread resource ownership', 'CacheLimit=64*1024*1024' in ctrl
          and 'budget+selection.tile->bytes>64*1024*1024' in item and 'm_failed.count(selection.key)' in item
          and 'm_rhi!=rhi()' in item and 'm_sceneChanged' in item and 'std::unique_ptr<QRhiGraphicsPipeline>' in item)
    check('RP-13 lifecycle/cancellation/generation source', 'applicationStateChanged' in ctrl and 'm_pool.waitForDone()' in ctrl
          and 'generation!=m_generation' in ctrl and 'cancel->load()' in ctrl and 'Component.onDestruction: EarthNative.close()' in home)
    changed = git('diff', '--name-only', '--no-renames', BASE).decode().splitlines()
    allowed_files = {'CMakeLists.txt','main_mobile.cpp','android/AndroidManifest.xml',
                     'android/src/com/ingema/ingeplus/InGeQtActivity.java','qml/Mobile/HomeScreen.qml',
                     'qml/Mobile/EarthSurfaceHost.qml','qml/Mobile/RetroplasmaEarthView.qml','scripts/verify_fusionbridge_static.py',
                     'scripts/generate_retroplasma_sample.py','scripts/verify_retroplasma_static.py'}
    allowed_prefixes = ('src/retroplasma/','src/fusionbridge/','android/src/com/ingema/ingeplus/fusionbridge/',
                        'labs/fusionbridge-historical/','tests/retroplasma/','tests/fusionbridge/', 'docs/')
    unexpected = [path for path in changed if path not in allowed_files and not path.startswith(allowed_prefixes)]
    if unexpected:
        print('Unexpected paths: '+', '.join(unexpected), file=sys.stderr)
    check('RP-14 protected/shared sources and Cesium unchanged', not unexpected)
    java = '\n'.join(path.read_text(encoding='utf-8-sig') for path in (ROOT / 'android/src').rglob('*.java'))
    check('RP-15 capture excluded from active sources/manifest/QML', 'FusionBridge' not in entry+home+java
          and 'EarthSurfaceHost' not in cmake and 'src/fusionbridge' not in cmake
          and 'MEDIA_PROJECTION' not in read('android/AndroidManifest.xml') and 'com.google.earth' not in read('android/AndroidManifest.xml')
          and not (ROOT / 'android/src/com/ingema/ingeplus/fusionbridge').exists())
    check('lexical delimiters of native module and viewport', all(balanced(p.read_text(encoding='utf-8-sig')) for p in RP.glob('*') if p.suffix in ('.h','.cpp')) and balanced(view))
    active_source = '\n'.join(p.read_text(encoding='utf-8-sig') for p in RP.glob('*') if p.suffix in ('.h','.cpp'))
    check('recoverable decoders and local-only provider', 'abort(' not in active_source and 'RP_LOCAL_OR_QRC_SCENE_REQUIRED' in provider
          and 'decodeBc1' in provider and 'QImageReader' in provider and 'RP_TEXTURE_DECODE_FAILED' in provider)
    check('CPU transition protects resident siblings and reports rejection', 'out.wanted.insert(key(child,l))' in scheduler
          and 'auto protectedKeys=next.wanted' in ctrl and 'RP_CPU_TRANSITION_MEMORY_LIMIT' in ctrl
          and 'm_failed.contains(request.key)' in ctrl and 'if(refine&&!childrenReady)' in scheduler
          and 'if(protectedBytes>CacheLimit)' in ctrl and 'else trimCache(protectedKeys)' in ctrl)
    check('GPU replacement commits only complete draw and retains previous coverage', 'if(replacementReady)' in item
          and 'm_drawKeys=wanted' in item and '!m_drawKeys.count(it->first)' in item and 'RP_GPU_TRANSITION_MEMORY_LIMIT' in item)
    check('partial child coverage rejected by manifest provider', 'childrenCover(*scene,node)' in provider
          and 'RP_CHILD_COVERAGE_INCOMPLETE' in provider)
    check('transparent BC1 cutout and explicit scene retry', 'if(albedo.a<0.5)discard' in fragment
          and 'root.controller.retryScene()' in view and 'void RetroplasmaController::retryScene()' in ctrl)
    print(f'{passed} source/resource checks passed. No build or Android execution performed.')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, ValueError, KeyError) as error:
        print(f'STATIC_FAIL {error}', file=sys.stderr)
        sys.exit(1)
