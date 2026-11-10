"use strict";
// Regression: approved fullscreen location map uses the ONE global right-side
// Dock (four tools + labels), never the bottom navigation Dock.
const fs=require("node:fs");
const path=require("node:path");
const assert=require("node:assert/strict");
const base=path.resolve(__dirname,"..","..");
const read=(f)=>fs.readFileSync(path.join(base,f),"utf8");
const map=read("qml/Mobile/pages/CalicataMapEditor.qml");
const host=read("qml/Mobile/pages/CalicatasEditorPage.qml");
const shell=read("qml/Mobile/HomeScreen.qml");
let checks=0;
function verify(text,condition){assert.ok(condition,text);console.log("PASS",text);checks++;}
verify("One global InGeCoreFlow Dock, no second toolbar",map.includes("flow.dockOverride = entry")&&map.includes("vertical: true")&&!map.includes("id: thumbActions"));
for(const [id,label] of [["map.move","Mover punto"],["map.coordinates","Ingresar coordenadas"],["map.gps","Mi ubicación"],["map.center","Centrar"]]){
 verify("Map Dock action "+id,
   map.includes('id: "'+id+'", command: "'+id+'", tapCommand: true')
   &&map.includes('label: "'+label+'"')
   &&map.includes('id === "'+id+'"'));

}
verify("Right centered vertical Dock x/y unchanged",shell.includes("home.width - width - 8 * home.u")&&shell.includes('Math.round((home.height - height) / 2)'));
verify("Global Dock thinner and readable ONLY in vertical mode",
   shell.includes('visible: home.dockVertical && modelData.more !== true')
   &&shell.includes('dockVCellWidth: 60 * u')
   &&shell.includes('dockVCellHeight: 65 * u')
   &&shell.includes('Text.WrapAtWordBoundaryOrAnywhere')
   &&shell.includes('font.pixelSize: 9 * home.u'));
verify("Horizontal Dock geometry unchanged",shell.includes('x: home.dockVertical ? home.width - width - 8 * home.u')&&shell.includes('y: home.dockVertical ? Math.round((home.height - height) / 2)'));
verify("Suppress only when map has no active vertical override",host.includes("root.flow.dockOverride.vertical === true"));
verify("Footer Cancelar and Fijar ubicación side by side",map.includes('id: cancelButton')&&map.includes('text: "Cancelar"')&&map.includes('id: fixButton')&&map.includes('text: "Fijar ubicación"'));
verify("Restore original Dock only after inverse Hero",map.includes("editor._publishDock(false)")&&map.includes("if (_ownedDockOverride && flow.dockOverride === _ownedDockOverride)"));
verify("Switch state after pressed action, without delegate deletion in click",
   map.includes("Qt.callLater(function() { if (editor.open && editor._ownedDockOverride)")
   &&shell.includes("if (!dockPressActive)\n            dockDisplayedSlots = dockSlots"));
verify("Overrides have nonempty commands and the real dock dispatches",
   shell.includes("a.command && String(a.command).length > 0")
   &&shell.includes("dockOverride.command(String(action.id))")
   &&shell.includes('INGE_CALICATA_MAP_DOCK_DISPATCH action=')
   &&map.includes('INGE_CALICATA_MAP_TOOL action='));
verify("Map surface optimization remains (single map)",map.includes("map.parent = mapHost")&&map.includes("if (t >= 0.999 && open && map && map.parent !== mapHost)"));
console.log("PASS",checks,"static regression checks; runtime Android rendering pending user compile");
