"""Planet source/resource integrity. Does not build or launch Android."""
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
BASE='04671e3a93b40148611424b286099e0a0d031227'


def read(path):
    return (ROOT/path).read_text(encoding='utf-8-sig')


def check(name,ok):
    if not ok:
        raise AssertionError(name)
    print('STATIC_PASS '+name)


def jpeg_size(data):
    assert data[:2]==b'\xff\xd8'
    pos=2
    while pos<len(data):
        while data[pos]==0xff:
            pos+=1
        marker=data[pos];pos+=1
        if marker in (0xd8,0xd9):
            continue
        size=struct.unpack_from('>H',data,pos)[0]
        if marker in (0xc0,0xc1,0xc2):
            height,width=struct.unpack_from('>HH',data,pos+3)
            return width,height
        pos+=size
    raise AssertionError('JPEG dimensions unavailable')


def main():
    controller=read('src/retroplasma/RetroplasmaController.cpp')
    camera=read('src/retroplasma/RetroplasmaCamera.cpp')
    planet=read('src/retroplasma/RetroplasmaPlanet.cpp')
    provider=read('src/retroplasma/RetroplasmaPlanetProvider.cpp')
    scheduler=read('src/retroplasma/RetroplasmaTileScheduler.cpp')
    view=read('qml/Mobile/RetroplasmaEarthView.qml')
    home=read('qml/Mobile/HomeScreen.qml')
    module=read('src/retroplasma/CMakeLists.txt')
    record=json.loads(read('src/retroplasma/resources/earth/provenance.json'))
    image=(ROOT/'src/retroplasma/resources/earth/blue-marble-global-2048.jpg').read_bytes()
    check('NASA source asset SHA256 and actual 2048x1024 JPEG',hashlib.sha256(image).hexdigest()==record['sha256'] and jpeg_size(image)==(2048,1024))
    check('real NASA official global layer and attribution',record['source'].startswith('https://gibs.earthdata.nasa.gov/') and 'BlueMarble_NextGeneration' in record['source'] and 'NASA' in record['credit'] and 'sourceName' in view)
    check('default open initializes global Earth rather than local synthetic scene','openPlanet();emit changed();' in controller and 'inge-earth://global' in controller and 'sample/scene.json' not in controller+view)
    check('WGS84 ellipsoid ECEF and normalized graphics coordinates','geodeticToEcef({lat,lon,shell})' in planet and 'EarthRadius=6378137.0' in read('src/retroplasma/RetroplasmaPlanet.h') and 'p.z/EarthRadius' in read('src/retroplasma/RetroplasmaPlanet.h'))
    check('full segmented surface covers all longitudes and both poles','y<4' in provider and 'x<8' in provider and '-180+x*45.0,-90+y*45.0' in provider and 'planetMesh' in provider)
    check('satellite sector UV and outward indexed mesh','vertex.uv[0]=float(u)' in planet and 'vertex.uv[1]=float(v)' in planet and 'out.indices.insert' in planet and 'col<=steps' in planet)
    check('orbital camera, near/far depth and antimeridian interpolation','resetPlanet' in camera and '22000000' in camera and 'std::remainder(p.longitude' in camera and 'north=north*std::cos(m_heading)' in camera and 'nearPlane' in camera)
    check('finite imagery zoom limit, source resolution shown','40000.0' in camera and 'Resolución más fina cargada' in controller and 'coveragePercent>0' in controller)
    check('official GIBS WMS geographic axes, regional Blue Marble and Landsat date','EPSG:4326' in provider and 'arg(lod.sector.south' in provider and 'HLS_L30_Nadir_BRDF_Adjusted_Reflectance' in provider and 'q.addQueryItem(QStringLiteral("TIME"),lod.date)' in provider)
    check('LOD native resolution caps and protected permanent all-world coverage','maxLevel=detail?9:5' in scheduler and 'draw(key); // Pinned all-world coverage' in scheduler and 'remoteRequests++>=96' in scheduler and 'planetSectorVisible' in scheduler)
    check('regional base under HLS gaps and separated shells','base.layer=QStringLiteral("blue-marble")' in scheduler and 'distance-.25' in scheduler and 'QLatin1String("landsat")?250:50' in provider and 'discard' in read('src/retroplasma/shaders/terrain.frag'))
    check('bounded/cancellable official-only network and disk cache','setMaximumCacheSize(128*1024*1024)' in provider and 'std::min<qint64>(15000,30000-searchClock.elapsed())' in provider and 'ManualRedirectPolicy' in provider and 'cancel.load()' in provider and '4*1024*1024' in provider)
    check('same native viewport, source packaging and dependencies','RetroplasmaPlanetProvider.cpp' in module and '/resources/earth/*' in module and 'Qt6::Network' in module and 'RetroplasmaView {' in view)
    check('shared GPS only, gestures and geographic Dock controls','Perms.requestImmediateLocationUpdate()' in view and 'otherGpsClientActive' in view and 'Qt.callLater(root.completeGpsFix)' in view and 'earth.gps' in home and 'earth.peru' in home and 'earth.lima' in home and 'rotateView' in view)
    allowed=('src/retroplasma/','tests/retroplasma/','docs/','scripts/verify_earth_planetary_static.py','qml/Mobile/HomeScreen.qml','qml/Mobile/RetroplasmaEarthView.qml')
    changed=subprocess.check_output(['git','diff','--name-only','--no-renames',BASE],cwd=ROOT).decode().splitlines()
    unexpected=[name for name in changed if not name.startswith(allowed)]
    if unexpected:
        print('Unexpected paths: '+', '.join(unexpected),file=sys.stderr)
    check('protected services, backend, manifest, JNI and Cesium untouched',not unexpected)
    check('no screen capture/secondary app and no synthetic startup','MediaProjection' not in provider+controller+view and 'FusionBridge' not in controller+home and 'terreno de prueba CC0' not in view)
    print('16 planetary source/resource checks passed; this does not certify Android rendering.')


if __name__=='__main__':
    try:
        main()
    except (AssertionError,OSError,KeyError,ValueError) as error:
        print('STATIC_FAIL '+str(error),file=sys.stderr)
        sys.exit(1)
