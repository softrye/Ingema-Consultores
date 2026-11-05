'use strict';
// Web reference: ingeplus-main (1).zip @ 2026-11-04
// projectCalicataStrataService.ts, projectCalicataSamplesService.ts,
// CalicataDetailPanel.tsx, sheetPresentation.ts. Static only; no Android build.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const Rules=vm.createContext({});
vm.runInContext(fs.readFileSync('qml/Mobile/lib/CalicataRules.js','utf8').replace(/^\.pragma library\s*/,''),Rules);
const qml=fs.readFileSync('qml/Mobile/pages/CalicataFormPage.qml','utf8');
const cloud=fs.readFileSync('calicatacloudservice.cpp','utf8');
const document=fs.readFileSync('calicatadocument.cpp','utf8');
const check=(description,condition)=>{assert.ok(condition,description);console.log('PASS',description)};
const eq=(a,b)=>assert.equal(a,b);
function method(name){const m=qml.match(new RegExp('function '+name+'\\([^]*?^    }','m'));assert.ok(m,'missing QML method '+name);return m[0];}
const same=(a,b)=>eq(JSON.stringify([...a]),JSON.stringify(b));

same(Rules.WEB_MOISTURE_CODES,['SECO','BAJO','MEDIO','AGUA']);
same(Rules.WEB_CONSISTENCY_CODES,['SUELTO','MEDIANAMENTE_DENSO','RIGIDO','MUY_RIGIDO']);
same(Rules.WEB_EXCAVABILITY_CODES,['RENDIMIENTO_BAJO','RENDIMIENTO_MEDIO','RENDIMIENTO_ALTO','RENDIMIENTO_MUY_ALTO']);
check('Exact Web catalog slugs',true);
eq(Rules.webMoistureCode(3),'AGUA');
eq(Rules.webMoistureCode('Agua'),'AGUA');
eq(Rules.webConsistencyCode('Medianamente densa'),'MEDIANAMENTE_DENSO');
eq(Rules.webConsistencyCode('Medianamente denso'),'MEDIANAMENTE_DENSO');
eq(Rules.webConsistencyCode('Rígido'),'RIGIDO');
eq(Rules.webConsistencyCode('Densa'),''); // ambiguous legacy: preserve, don't invent
eq(Rules.webExcavabilityCode('Rend. bajo'),'RENDIMIENTO_BAJO');
eq(Rules.webExcavabilityCode(3),'RENDIMIENTO_MUY_ALTO');
eq(Rules.webCatalogLabel('RENDIMIENTO_MUY_ALTO'),'Rendimiento muy alto');
check('Legacy aliases map only when unequivocal',true);

const root={_newLabUuid:()=> 'synthetic-stratum-id', _assignedStratumIds:false,
  _enumIndex:(val,labels)=>labels.indexOf(val),estItems:['Baja','Media','Alta','Muy Alta']};
const context=vm.createContext({Rules,root,JSON,Object,String,Number,Date,Math,isFinite});
for(const name of ['_defaultCorte','_normalizeCorte'])vm.runInContext(method(name),context);
const old={humedad:'Agua',excavabilidad:'Rend. bajo',consistency:'Medianamente densa',
  estabilidad:'Alta',muestra_desde:null,muestra_hasta:null,de:'0.00',a:'2.00'};
const migrated=context._normalizeCorte(old);
eq(migrated.moisture_condition,'AGUA');
eq(migrated.excavability,'RENDIMIENTO_BAJO');
eq(migrated.consistency_compaction,'MEDIANAMENTE_DENSO');
eq(migrated.muestra_desde,'');
eq(migrated.muestra_hasta,'');
const historical=JSON.parse(migrated._extraJson);
eq(historical.consistency,'Medianamente densa');
eq(historical.humedad,'Agua');
eq(historical.humedad_legacy_original,'Agua');
eq(historical.excavabilidad_legacy_original,'Rend. bajo');
eq(historical.estabilidad_legacy_original,'Alta');
const unrecognized=context._normalizeCorte({...old,consistency:'Densa'});
eq(unrecognized.consistency_compaction,'');
eq(JSON.parse(unrecognized._extraJson).consistency,'Densa');
const cleared=context._normalizeCorte({...old,consistency_compaction:'',consistency_web_selected:true});
eq(cleared.consistency_compaction,'');
const incoming=context._normalizeCorte({
 moisture_condition:'BAJO',consistency_compaction:'RIGIDO',excavability:'RENDIMIENTO_ALTO',
 humedad:-1,excavabilidad:-1});
eq(incoming.humedad,1);eq(incoming.excavabilidad,2);
eq(incoming.consistency_compaction,'RIGIDO');
check('Web -> Android and legacy -> Web reading, no original destroyed',true);

eq(Rules.webDepth2('1,2'),'1.20');
eq(Rules.webDepth2('1.235'),null);
eq(Rules.webDepth2(''),'');
eq(Rules.webSampleIntervalError('1.00','1.55','1.00','2.00'),'');
eq(Rules.webSampleIntervalError('','','1.00','2.00'),'');
eq(Rules.webSampleIntervalError('1.40','1.20','1.00','2.00'),'Desde debe ser menor que Hasta.');
eq(Rules.webSampleIntervalError('0.50','1.20','1.00','2.00'),'El intervalo debe estar dentro del estrato.');
eq(Rules.webSampleIntervalError('1.00','2.01','1.00','2.00'),'El intervalo debe estar dentro del estrato.');
check('Nullable samples, numeric precision and valid interval ordering',true);

check('Duplicating a stratum carries canonical web fields without sample intervals',
  method('duplicateStratum').includes('"moisture_condition"')
  &&method('duplicateStratum').includes('"consistency_compaction"')
  &&method('duplicateStratum').includes('"excavability"'));
check('Android picker writes Web slugs and keeps local stability only',
  qml.includes('setCanonicalStratumConsistency')&&qml.includes('Rules.WEB_CONSISTENCY_CODES.map(Rules.webCatalogLabel)')
  &&qml.includes('cortesModel.setProperty(prfEditorCard.idx, "moisture_condition"')
  &&qml.includes('cortesModel.setProperty(prfEditorCard.idx, "excavability"')
  &&!qml.match(/readonly property var liveStratumFields: *\[[^\]]*"stability"/));
check('Realtime Web payload reads exact canonical columns',
  qml.includes('moisture_condition: root._liveValue(hum)')
  &&qml.includes('consistency_compaction: root._liveValue(Rules.webConsistencyCode(row.consistency_compaction))')
  &&qml.includes('excavability: root._liveValue(exc)')
  &&qml.includes('case "consistency_compaction":')
  &&qml.includes('cortesModel.setProperty(i, "consistency_compaction", consistencyCode)'));
check('Cloud sample RPC sends NULL for absent depth, no stratum fallback',
  cloud.includes('const QVariant sampleFrom = nullableNumber(localRow.value(QStringLiteral("muestra_desde")))')
  &&cloud.includes('const QVariant sampleTo = nullableNumber(localRow.value(QStringLiteral("muestra_hasta")))')
  &&!cloud.includes('if (!sampleFrom.isValid()) sampleFrom = nullableDepth'));
check('Cloud columns match Web and never invent stability',
  cloud.includes('p_moisture_condition')&&cloud.includes('p_consistency_compaction')
  &&cloud.includes('p_excavability')&&!cloud.includes('p_stability'));
check('Groundwater local document preserves old depth, Web sync uses typed number',
  document.includes('const bool foundDepth = storedDepth.isValid()')
  &&!document.includes('header[QStringLiteral("groundwater_depth_m")] = QVariant();')
  &&qml.includes('h.groundwater_depth_m = water.length ? Rules.parseDecimalSafe(water) : null')
  &&cloud.includes('changes[QStringLiteral("groundwater_depth_m")]'));
check('Web lacks a synced visibility column: keep local profile preference',
  qml.includes('profileSetup.show_water_table !== false')
  &&qml.includes('h.profile_setup = Object.assign({}, root.profileSetup || {})')
  &&!cloud.includes('p_show_water_table'));
console.log('PASS Web/Android stratum, groundwater and sample contract (static only)');
