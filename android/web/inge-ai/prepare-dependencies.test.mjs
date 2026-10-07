import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareDependencies} from './prepare-dependencies.mjs';
async function fixture(installed = false) {
  const root = await mkdtemp(join(tmpdir(), 'inge-dependencies-test-'));
  await writeFile(join(root,'package.json'), JSON.stringify({dependencies:{tool:'1.0.0'}}));
  await writeFile(join(root,'package-lock.json'), JSON.stringify({packages:{'':{},'node_modules/tool':{version:'1.0.0'}}}));
  const install = async (version='1.0.0') => {
    await mkdir(join(root,'node_modules/tool'),{recursive:true});
    await writeFile(join(root,'node_modules/tool/package.json'),JSON.stringify({version}));
  };
  if (installed) await install();
  return {root,install};
}
test('complete locked dependencies are reused without npm or unlink', async () => {
  const {root}=await fixture(true);
  await prepareDependencies({root,runInstall:()=>{throw new Error('npm must not run');}});
  await prepareDependencies({root,runInstall:()=>{throw new Error('npm must not run on rebuild');}});
});
test('a partial installation is repaired once; subsequent builds reuse it', async () => {
  const {root,install}=await fixture(); let calls=0;
  const runInstall=async()=>{calls++;await install();};
  await prepareDependencies({root,runInstall}); await prepareDependencies({root,runInstall});
  assert.equal(calls,1);
});
test('changed locked versions trigger preparation and are verified', async () => {
  const {root,install}=await fixture(true);
  await writeFile(join(root,'package-lock.json'),JSON.stringify({packages:{'':{},'node_modules/tool':{version:'2.0.0'}}}));
  let calls=0; await prepareDependencies({root,runInstall:async()=>{calls++;await install('2.0.0');}});
  assert.equal(calls,1);
});
test('installation failures stop the build and do not mark dependencies ready', async () => {
  const {root}=await fixture();
  await assert.rejects(prepareDependencies({root,runInstall:async()=>{throw new Error('EBUSY');}}),/EBUSY/);
  await assert.rejects(readFile(join(root,'node_modules/.inge-dependencies.sha256')),/ENOENT/);
});
test('missing platform-specific optional packages for another OS do not reinstall', async () => {
  const {root}=await fixture(true);
  const other=process.platform==='win32'?'darwin':'win32';
  await writeFile(join(root,'package-lock.json'),JSON.stringify({packages:{'':{},'node_modules/tool':{version:'1.0.0'},'node_modules/other-native':{version:'1',optional:true,os:[other]}}}));
  await prepareDependencies({root,runInstall:()=>{throw new Error('platform package must be skipped');}});
});
test('npm normalizing Windows line endings does not count as a lockfile change', async () => {
  const {root,install}=await fixture();
  const locked=JSON.stringify({packages:{'':{},'node_modules/tool':{version:'1.0.0'}}},null,2);
  await writeFile(join(root,'package-lock.json'),locked.replaceAll('\n','\r\n'));
  await prepareDependencies({root,runInstall:async()=>{await install();await writeFile(join(root,'package-lock.json'),locked);}});
});
test('simultaneous preparations serialize and install only once', async () => {
  const {root,install}=await fixture(); let calls=0;
  const runInstall=async()=>{calls++;await new Promise(resolve=>setTimeout(resolve,20));await install();};
  await Promise.all([prepareDependencies({root,runInstall}),prepareDependencies({root,runInstall})]);
  assert.equal(calls,1);
});
test('a real lockfile change during installation is not silently accepted', async () => {
  const {root,install}=await fixture();
  await assert.rejects(prepareDependencies({root,runInstall:async()=>{
    await install(); await writeFile(join(root,'package-lock.json'),JSON.stringify({packages:{'':{},'node_modules/tool':{version:'9.0.0'}}}));
  }}),/modificó package-lock/);
});
