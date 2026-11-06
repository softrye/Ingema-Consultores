"use strict";
const fs=require("fs"),path=require("path"),vm=require("vm"),assert=require("assert");
const base=path.resolve(__dirname,"../.."),r=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(base,"qml/Mobile/lib/CalicataRules.js"),"utf8").replace(/^\s*\.pragma.*$/mg,""),r);
const row={primary_sucs:"GW",lab_confirmed_aashto:"A-1-a"};
let g=r.calicataGraphicPattern(row);assert.deepStrictEqual(Array.from(g.layers,x=>x.system),["SUCS","AASHTO"]);
assert.ok(g.label.includes("GW") && g.label.includes("A-1-a"));
g=r.calicataGraphicPattern({...row,is_composite:true,secondary_sucs:"GM"});assert.strictEqual(g.layers.length,3);
assert.strictEqual(r.calicataGraphicPattern({lab_confirmed_aashto:"A-1-a"}).layers.length,1);
assert.strictEqual(r.calicataGraphicPattern({primary_sucs:"GW"}).layers.length,1);
assert.strictEqual(r.calicataGraphicPattern({}).layers.length,0);
const qrc=fs.readFileSync(path.join(base,"resources.qrc"),"utf8");
for (const code of r.aashtoCodes) {
 const p=r.aashtoSymbolUrl(code);assert.ok(p.startsWith("qrc:/AASHTO/"));
 const file=path.join(base,p.replace("qrc:/",""));assert.ok(fs.existsSync(file));
 const svg=fs.readFileSync(file,"utf8");assert.ok(svg.includes("AASHTO") && svg.includes(code));
 assert.ok(qrc.includes(`alias="${code}.svg">AASHTO/${code}.svg`));
}
assert.strictEqual(r.aashtoSymbolUrl("bogus"),"");
assert.strictEqual(r.labProjection(row).sucs,"GW","SUCS classification itself must stay unchanged");
console.log("AASHTO graphics: combined bands, all groups/resources and unchanged classification passed");

// Exercise the actual integer column partition expression shared by PDF/Excel.
const native=fs.readFileSync(path.join(base,"androidcalicataexporter.cpp"),"utf8");
const expression=native.match(/const int last = (keys\.size\(\) == 1[^;]+);/)[1].replace(/keys\.size\(\)/g,"n");
const lastColumn=new Function("n","i","return "+expression);
for (const [n,expected] of [[1,[[5,9]]],[2,[[5,7],[8,9]]],[3,[[5,6],[7,7],[8,9]]]]) {
 let first=5,actual=[];for(let i=0;i<n;i++){const last=lastColumn(n,i);actual.push([first,last]);first=last+1;}
 assert.deepStrictEqual(actual,expected);
}
console.log("Native graphic column partition: 1, 2 and 3 bands passed (no compilation)");
