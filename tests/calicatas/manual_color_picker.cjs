"use strict";
const fs=require("fs"),path=require("path"),vm=require("vm"),assert=require("assert");
const rules=vm.createContext({});
vm.runInContext(fs.readFileSync(path.resolve(__dirname,"../../qml/Mobile/lib/CalicataRules.js"),"utf8").replace(/^\s*\.pragma.*$/mg,""),rules);
for(const hex of ["#5F4B3F","#D8B64A","#7E748B","#000000","#FFFFFF","#24B4C8",...rules.CALICATA_COLOR_PRESETS.map(x=>x.value)])
 assert.strictEqual(rules.calicataHsvToHex(rules.calicataHexToHsv(hex)),hex);
assert.strictEqual(rules.calicataHsvToHex({hue:0,saturation:0,value:1}),"#FFFFFF");
assert.strictEqual(rules.calicataHsvToHex({hue:0,saturation:1,value:0}),"#000000");
assert.strictEqual(rules.calicataHsvToHex({hue:360,saturation:1,value:1}),"#FF0000");
assert.strictEqual(rules.calicataHsvToHex({hue:-120,saturation:2,value:1}),"#0000FF");
assert.strictEqual(rules.calicataHexToHsv("not a color").value,0);
assert.strictEqual(rules.normalizeCalicataColor("#abcdef"),"#ABCDEF");
assert.strictEqual(rules.normalizeCalicataColor(""),"");
console.log("Manual colour: Web examples, presets, HSV extremes and canonical HEX passed");
