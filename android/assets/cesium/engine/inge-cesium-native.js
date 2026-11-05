/* InGe Earth: one Cesium viewport, no web UI. See docs/INGE_CESIUM_20261105.md. */
(function () {
    "use strict";
    const C = window.Cesium;
    let viewer, tileset, sourceGeneration = 0, visible = true, pending = 0, lastPost = 0;
    let budget = {gpuMiB: 32, maxLevel: 15, pixelError: 14, parallel: 1}, layer = "rocktree", lastSnapshot = 0, lastCollision = 0;
    const overlays = [], features = []; let borders, bordersLoading = false;
    const send = data => { if (window.InGeCesiumNative) window.InGeCesiumNative.post(JSON.stringify(data)); };
    const error = code => send({type: "error", code});
    function stars() {
        const canvas = document.getElementById("claudeStars"), scale = window.devicePixelRatio || 1;
        const w = innerWidth, h = innerHeight; canvas.width = Math.round(w * scale); canvas.height = Math.round(h * scale);
        const c = canvas.getContext("2d"); c.scale(scale, scale);
        // Claude's original QML Canvas algorithm: same seed, density, colours and sizes.
        let seed = 7; const rnd = () => { seed = seed * 16807 % 2147483647; return seed / 2147483647; };
        for (let i = 0, count = Math.round(w * h / 2600); i < count; ++i) {
            const big = rnd() > .93; c.globalAlpha = .25 + .75 * rnd();
            c.fillStyle = rnd() > .85 ? "#CFE3FF" : "#FFFFFF";
            c.beginPath(); c.arc(rnd() * w, rnd() * h, big ? 1.3 : .7, 0, 2 * Math.PI); c.fill();
        }
    }
    function report(force) {
        if (!viewer || !visible || (!force && performance.now() - lastPost < 200)) return;
        lastPost = performance.now(); const p = viewer.camera.positionCartographic, height = Math.max(0, p.height);
        send({type: "state", latitude: C.Math.toDegrees(p.latitude), longitude: C.Math.toDegrees(p.longitude), altitude: 0,
            cameraAltitude: height, heading: C.Math.toDegrees(viewer.camera.heading), resolutionMetres: 0,
            metresPerPixel: 2 * height * Math.tan(viewer.camera.frustum.fovy / 2) / Math.max(1, innerHeight),
            pending, source: layer, gpuMiB: tileset ? tileset.totalMemoryUsageInBytes / 1048576 : 0});
    }
    function setBudget(value) {
        budget = value || budget; viewer.resolutionScale = budget.gpuMiB <= 32 ? .75 : 1;
        viewer.targetFrameRate = budget.gpuMiB >= 112 ? 60 : 30;
        viewer.scene.globe.maximumScreenSpaceError = Math.max(2, budget.pixelError);
        viewer.scene.skyAtmosphere.show = budget.gpuMiB > 32;
        C.RequestScheduler.maximumRequestsPerServer = Math.max(1, Math.min(4, budget.parallel));
        if (tileset) {
            tileset.maximumScreenSpaceError = budget.pixelError;
            tileset.cacheBytes = budget.gpuMiB * 1048576;
            tileset.maximumCacheOverflowBytes = Math.floor(budget.gpuMiB * 1048576 / 4);
        }
        if (borders) borders.show = budget.gpuMiB >= 112;
        else if (budget.gpuMiB >= 112 && !bordersLoading) {
            bordersLoading = true;
            C.GeoJsonDataSource.load("data/boundaries-110m.geojson", {stroke: C.Color.fromCssColorString("#E8ED32"), strokeWidth: 1, clampToGround: true, credit: "Natural Earth · public domain"})
                .then(data => { borders = data; borders.show = budget.gpuMiB >= 112; viewer.dataSources.add(data); viewer.scene.requestRender(); })
                .catch(() => error("CESIUM_BOUNDARIES_LOAD_FAILED"));
        }
        viewer.scene.requestRender();
    }
    async function setSource(name, date) {
        const generation = ++sourceGeneration; layer = name; pending = 1;
        if (tileset) { viewer.scene.primitives.remove(tileset); tileset = undefined; }
        while (overlays.length) viewer.imageryLayers.remove(overlays.pop(), true);
        const sentinel = name === "sentinel", hls = name === "landsat";
        const provider = new C.WebMapServiceImageryProvider({
            url: sentinel ? "https://tiles.maps.eox.at/wms" : "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi",
            layers: sentinel ? "s2cloudless" : hls ? "HLS_L30_Nadir_BRDF_Adjusted_Reflectance" : "BlueMarble_NextGeneration",
            parameters: {service: "WMS", format: "image/png", transparent: hls, version: "1.1.1", ...(hls ? {time: date && date !== "auto" ? date : new Date(Date.now()-4*86400000).toISOString().slice(0,10)} : {})},
            tilingScheme: new C.GeographicTilingScheme(), maximumLevel: sentinel ? 14 : hls ? 12 : 8,
            credit: sentinel ? "EOxCloudless by EOX IT Services GmbH · Copernicus Sentinel 2016 · CC BY 4.0" : "NASA / USGS"
        });
        provider.errorEvent.addEventListener(() => error(sentinel ? "CESIUM_EOX_TILE_ERROR" : "CESIUM_NASA_TILE_ERROR"));
        overlays.push(viewer.imageryLayers.addImageryProvider(provider));
        try {
            if (name === "rocktree") {
                const next = await C.Cesium3DTileset.fromUrl("/earth-data/p" + budget.maxLevel + "/root.json", {
                    maximumScreenSpaceError: budget.pixelError, cacheBytes: budget.gpuMiB * 1048576,
                    maximumCacheOverflowBytes: Math.floor(budget.gpuMiB * 1048576 / 4), enableCollision: true,
                    cullRequestsWhileMoving: true, preloadWhenHidden: false, preloadFlightDestinations: false,
                    skipLevelOfDetail: false, shadows: C.ShadowMode.DISABLED
                });
                if (generation !== sourceGeneration || !visible) { next.destroy(); return; }
                tileset = viewer.scene.primitives.add(next);
                next.tileFailed.addEventListener(() => { if (generation === sourceGeneration) error("CESIUM_ROCKTREE_TILE_FAILED"); });
                next.loadProgress.addEventListener((requests, processing) => { if (generation === sourceGeneration) { pending = requests + processing; report(false); } });
            }
            pending = 0; viewer.scene.requestRender(); report(true);
        } catch (_) { if (generation === sourceGeneration) { pending = 0; error("CESIUM_ROCKTREE_SOURCE_FAILED"); report(true); } }
    }
    function goTo(latitude, longitude, height) {
        if (![latitude, longitude, height].every(Number.isFinite)) return;
        longitude = (longitude + 540) % 360 - 180;
        viewer.camera.setView({destination: C.Cartesian3.fromDegrees(longitude, Math.max(-89.99, Math.min(89.99, latitude)), Math.max(budget.gpuMiB <= 32 ? 2000 : 80, Math.min(50000000, height))),
            orientation: {heading: viewer.camera.heading || 0, pitch: -Math.PI / 2, roll: 0}});
    }
    function pick(value) {
        const point = new C.Cartesian2(value.x, value.y); let position;
        if (viewer.scene.pickPositionSupported && C.defined(viewer.scene.pick(point))) position = viewer.scene.pickPosition(point);
        if (!position) position = viewer.scene.globe.pick(viewer.camera.getPickRay(point), viewer.scene);
        if (!position) return;
        const p = C.Cartographic.fromCartesian(position);
        send({type: "position", intent: value.intent, latitude: C.Math.toDegrees(p.latitude), longitude: C.Math.toDegrees(p.longitude), altitude: p.height});
    }
    function drawFeatures(layers) {
        while (features.length) viewer.entities.remove(features.pop());
        for (const item of layers || []) {
            const positions = C.Cartesian3.fromDegreesArrayHeights(item.points.flatMap(p => [p.longitude, p.latitude, p.altitude || 0]));
            if (!positions.length) continue;
            const color = C.Color.fromCssColorString(item.color || "#FFCC54").withAlpha(item.alpha === undefined ? 1 : item.alpha);
            const options = {name: item.name};
            if (item.kind === "Point") { options.position = positions[0]; options.point = {pixelSize: 9, color, outlineColor: C.Color.BLACK, outlineWidth: 1, disableDepthTestDistance: Number.POSITIVE_INFINITY}; }
            else if (item.kind === "Polygon" && positions.length >= 3) {
                options.polygon = {hierarchy: new C.PolygonHierarchy(positions, (item.holes || []).map(r => new C.PolygonHierarchy(C.Cartesian3.fromDegreesArrayHeights(r.flatMap(p => [p.longitude, p.latitude, p.altitude || 0]))))), material: color.withAlpha(.3), outline: true, outlineColor: color};
            } else options.polyline = {positions, width: 3, material: color, clampToGround: true};
            features.push(viewer.entities.add(options));
        }
    }
    function command(message) {
        if (!viewer) return;
        const p = viewer.camera.positionCartographic, latitude = C.Math.toDegrees(p.latitude), longitude = C.Math.toDegrees(p.longitude), height = p.height;
        switch (message.op) {
        case "budget": { const changed = budget.maxLevel !== message.value.maxLevel; setBudget(message.value); if (changed && layer === "rocktree") setSource(layer); break; }
        case "source": setSource(message.layer, message.date); break;
        case "goto": goTo(message.latitude, message.longitude, message.height || 120000); break;
        case "orbit": { const speed = Math.max(1e-6, Math.min(.006, height / 6378137 * .002)); viewer.camera.rotateLeft(message.x * speed); viewer.camera.rotateUp(message.y * speed); break; }
        case "pan": { const step = 2 * height * Math.tan(viewer.camera.frustum.fovy / 2) / Math.max(1, innerHeight) / 6378137;
            goTo(latitude + C.Math.toDegrees(message.y * step), longitude - C.Math.toDegrees(message.x * step / Math.max(.02, Math.cos(p.latitude))), height); break; }
        case "zoom": goTo(latitude, longitude, height / message.scale); break;
        case "rotate": viewer.camera.setView({orientation: {heading: viewer.camera.heading + message.radians, pitch: viewer.camera.pitch, roll: 0}}); break;
        case "pick": pick(message); break;
        case "features": drawFeatures(message.layers); break;
        case "visible": { const wasVisible = visible; visible = !!message.value; viewer.useDefaultRenderLoop = visible; if (!visible) ++sourceGeneration; else if (!wasVisible) send({type: "ready", engine: "Cesium", version: C.VERSION}); break; }
        case "action": {
            const name = message.name;
            if (name === "reset") goTo(-9.2, -75, 24000000);
            else if (name === "peru") goTo(-9.2, -75, 2800000);
            else if (name === "southAmerica") goTo(-15, -60, 6500000);
            else if (name === "lima") goTo(-12.0464, -77.0428, 120000);
            else if (name === "zoomIn" || name === "zoomOut") goTo(latitude, longitude, height * (name === "zoomIn" ? .75 : 1.333333));
            else if (name === "north") viewer.camera.setView({orientation: {heading: 0, pitch: viewer.camera.pitch, roll: 0}});
            else if (name === "rotateLeft" || name === "rotateRight") viewer.camera.rotateLeft(name === "rotateLeft" ? .25 : -.25);
            else if (name === "tiltUp" || name === "tiltDown") viewer.camera.lookUp(name === "tiltUp" ? .1 : -.1);
            else if (name.startsWith("pan") || name === "forward" || name === "backward") command({op: "pan", x: name === "panLeft" ? -50 : name === "panRight" ? 50 : 0, y: name === "panDown" || name === "backward" ? -50 : 50});
            break;
        }
        }
        viewer.scene.requestRender(); report(true);
    }
    window.InGeCesiumCommand = value => { try { command(value); } catch (_) { error("CESIUM_COMMAND_FAILED"); } };
    window.InGeEarthEngineSetVisible = value => command({op: "visible", value});
    try {
        stars(); window.addEventListener("resize", () => { stars(); if (viewer) { viewer.resize(); viewer.scene.requestRender(); } });
        C.Ion.defaultAccessToken = "";
        viewer = new C.Viewer("cesiumContainer", {baseLayer: false, terrainProvider: new C.EllipsoidTerrainProvider(), animation: false, timeline: false,
            baseLayerPicker: false, geocoder: false, homeButton: false, sceneModePicker: false, navigationHelpButton: false,
            fullscreenButton: false, infoBox: false, selectionIndicator: false, skyBox: false,
            requestRenderMode: true, maximumRenderTimeChange: Infinity, shouldAnimate: false, targetFrameRate: 30,
            contextOptions: {webgl: {alpha: true, antialias: false, preserveDrawingBuffer: false}}});
        viewer.scene.backgroundColor = C.Color.TRANSPARENT;
        viewer.scene.globe.enableLighting = false; viewer.scene.globe.depthTestAgainstTerrain = true;
        viewer.scene.screenSpaceCameraController.enableInputs = false;
        viewer.scene.screenSpaceCameraController.enableCollisionDetection = true;
        viewer.scene.screenSpaceCameraController.minimumZoomDistance = 80;
        viewer.camera.constrainedAxis = C.Cartesian3.UNIT_Z;
        const base = new C.UrlTemplateImageryProvider({url: C.buildModuleUrl("Assets/Textures/NaturalEarthII/{z}/{x}/{reverseY}.jpg"), tilingScheme: new C.GeographicTilingScheme(), maximumLevel: 2, credit: "Natural Earth · base mundial incorporada"});
        viewer.imageryLayers.addImageryProvider(base);
        viewer.scene.renderError.addEventListener(() => error("CESIUM_RENDER_ERROR"));
        viewer.scene.postRender.addEventListener(() => {
            report(false);
            const now = performance.now(), p = viewer.camera.positionCartographic;
            if (p.height < 20000 && viewer.scene.sampleHeightSupported && now - lastCollision > 250) {
                lastCollision = now;
                const ground = viewer.scene.sampleHeight(p, features);
                if (Number.isFinite(ground) && p.height < ground + 80) goTo(C.Math.toDegrees(p.latitude), C.Math.toDegrees(p.longitude), ground + 80);
            }
            // Bounded, low-resolution image for the EXISTING QML glass captures.
            // It is never used to display the globe or replace a failed renderer.
            if (budget.gpuMiB > 32 && now - lastSnapshot > 1000) {
                lastSnapshot = now;
                try {
                    const thumbnail = document.createElement("canvas"); thumbnail.width = 180; thumbnail.height = Math.round(180 * innerHeight / Math.max(1, innerWidth));
                    const paint = thumbnail.getContext("2d"); paint.fillStyle = "#000"; paint.fillRect(0, 0, thumbnail.width, thumbnail.height);
                    paint.drawImage(document.getElementById("claudeStars"), 0, 0, thumbnail.width, thumbnail.height);
                    paint.drawImage(viewer.canvas, 0, 0, thumbnail.width, thumbnail.height);
                    const uri = thumbnail.toDataURL("image/jpeg", .45); if (uri.length < 28000) send({type: "backdrop", uri});
                } catch (_) { error("CESIUM_GLASS_CAPTURE_FAILED"); }
            }
        });
        goTo(-9.2, -75, 24000000); setBudget(budget);
        send({type: "ready", engine: "Cesium", version: C.VERSION}); report(true);
    } catch (_) { error("CESIUM_WEBGL_INITIALIZATION_FAILED"); }
}());
