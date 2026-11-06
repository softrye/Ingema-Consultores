"use strict";
const fs=require("fs"),path=require("path"),vm=require("vm"),assert=require("assert");
const root=path.resolve(__dirname,"../.."),r=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root,"qml/Mobile/lib/CalicataRules.js"),"utf8").replace(/^\s*\.pragma.*$/mg,""),r);
const rows=[{id:"E1",local_stratum_id:"local1",remote_stratum_id:"remote1",remote_sample_id:"sample1",remote_lab_result_id:"lab1",remote_sequence_number:1,de:"0.00",a:"0.50",descripcion:"Upper",primary_sucs:"GW",sample_code:"M1",muestra_desde:"0.10",muestra_hasta:"0.40"},
{id:"E2",local_stratum_id:"local2",remote_stratum_id:"remote2",remote_sample_id:"sample2",remote_lab_result_id:"lab2",remote_sequence_number:2,de:"0.50",a:"1.50",descripcion:"Lower",primary_sucs:"CL",sample_code:"M2",muestra_desde:"0.70",muestra_hasta:"1.20"},
{id:"E3",de:"1.50",a:"",descripcion:"Pending"}];
const original=JSON.stringify(rows);let moved=r.swapStratumSlotsLikeWeb(rows,0,1);assert.ok(moved);
assert.strictEqual(moved[0].descripcion,"Lower");assert.strictEqual(moved[1].descripcion,"Upper");assert.strictEqual(moved[0].primary_sucs,"CL");
assert.strictEqual(moved[0].a,"1.00");assert.strictEqual(moved[1].de,"1.00");assert.strictEqual(moved[1].a,"1.50");
assert.strictEqual(moved[0].muestra_desde,"0.20");assert.strictEqual(moved[0].muestra_hasta,"0.70");assert.strictEqual(moved[1].muestra_desde,"1.10");
for(let i=0;i<2;i++)for(const key of ["id","local_stratum_id","remote_stratum_id","remote_sample_id","remote_lab_result_id","remote_sequence_number"])assert.strictEqual(moved[i][key],rows[i][key],"Stable slot: "+key);
assert.strictEqual(JSON.stringify(moved[2]),JSON.stringify(rows[2]));assert.strictEqual(JSON.stringify(rows),original);
assert.strictEqual(r.swapStratumSlotsLikeWeb(rows,1,2),null,"Cannot invent thickness for unfinished pair");
assert.strictEqual(r.swapStratumSlotsLikeWeb(rows,0,2),null);assert.strictEqual(r.swapStratumSlotsLikeWeb(rows,-1,0),null);
const back=r.swapStratumSlotsLikeWeb(JSON.parse(JSON.stringify(moved)),1,0);assert.strictEqual(JSON.stringify(back),original,"Round trip preserves data");
console.log("Web-compatible move: thickness/material/lab travel, slot UUIDs stay, pending unrelated stratum preserved");

const qml=fs.readFileSync(path.join(root,"qml/Mobile/pages/CalicataFormPage.qml"),"utf8");
function fn(name){let a=qml.indexOf("function "+name+"("),start=qml.indexOf("{",a),depth=0;assert.ok(a>=0);for(let i=start;i<qml.length;i++){if(qml[i]==="{")depth++;else if(qml[i]==="}"&&--depth===0)return qml.slice(a,i+1);}throw Error(name);}
let modelRows=JSON.parse(original),sets=[],renumbered=false;
const model={get:i=>modelRows[i],get count(){return modelRows.length;},set:(i,row)=>{sets.push(i);modelRows[i]=row;}};
const ctx=vm.createContext({cortesModel:model,Rules:r,corteToPlainObject:x=>x,_normalizeCorte:x=>x,renumerarCortesYIntervalos:()=>renumbered=true,showInfo:()=>assert.fail("Unexpected move error")});
vm.runInContext(fn("_swapCorteContent"),ctx);assert.strictEqual(ctx._swapCorteContent(0,1),true);
assert.deepStrictEqual(sets,[0,1]);assert.strictEqual(renumbered,true);assert.strictEqual(modelRows[0].remote_stratum_id,"remote1");
console.log("UI move path: updates exactly the two existing slots without clearing the model");

assert.strictEqual(r.swapStratumSlotsLikeWeb(rows,0.5,1.5),null);
const lookupRoot={corteToPlainObject:x=>x};const lookup=vm.createContext({root:lookupRoot,cortesModel:model});
vm.runInContext(fn("stratumIndexForKeys"),lookup);
modelRows.unshift({local_stratum_id:"new"});assert.strictEqual(lookup.stratumIndexForKeys("local1","remote1"),1);
assert.strictEqual(lookup.stratumIndexForKeys("missing",""),-1);
console.log("Stable action lookup after a concurrent insertion passed");
