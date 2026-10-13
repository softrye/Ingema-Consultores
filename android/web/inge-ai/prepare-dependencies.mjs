import {readFile, writeFile, mkdir, open, unlink, realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {isDeepStrictEqual} from 'node:util';

function applies(rules, value) {
  if (!rules?.length) return true;
  const positive=rules.filter(rule=>!rule.startsWith('!'));
  return !rules.includes(`!${value}`) && (!positive.length || positive.includes(value));
}
async function missingPackages(root, lock) {
  const missing=[];
  for (const [path, metadata] of Object.entries(lock.packages)) {
    if (!path.startsWith('node_modules/') || !metadata.version) continue;
    if (!applies(metadata.os,process.platform) || !applies(metadata.cpu,process.arch)) continue;
    try {
      const installed=JSON.parse(await readFile(join(root,path,'package.json'),'utf8'));
      if (installed.version!==metadata.version) missing.push(path);
    } catch { missing.push(path); }
  }
  return missing;
}
async function acquire(root) {
  const path=join(root,'.inge-install.lock'); const deadline=Date.now()+120000;
  while (true) {
    try {
      const handle=await open(path,'wx'); await handle.writeFile(JSON.stringify({pid:process.pid}));
      return async()=>{await handle.close();await unlink(path);};
    } catch (error) {
      if (error.code!=='EEXIST') throw error;
      try {
        const owner=JSON.parse(await readFile(path,'utf8'));
        if (Number.isInteger(owner.pid) && owner.pid>0) {
          try { process.kill(owner.pid,0); } catch (probe) { if (probe.code==='ESRCH') {await unlink(path);continue;} }
        }
      } catch { /* another process may still be writing its lock */ }
      if (Date.now()>deadline) throw new Error('Otra preparación de InGe+ IA sigue en curso. Espera a que termine.');
      await new Promise(resolve=>setTimeout(resolve,100));
    }
  }
}
async function installWithNpm(root, npm) {
  // Invoke npm's JS entry point through Node, without cmd/PowerShell shell quoting.
  const path=await realpath(npm);
  const cli=path.endsWith('.cmd') ? join(dirname(path),'node_modules/npm/bin/npm-cli.js') : path;
  await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[cli,'install','--include=dev','--include=optional','--ignore-scripts','--no-audit','--no-fund'],{cwd:root,stdio:'inherit',shell:false});
    child.once('error',reject);
    child.once('exit',(code,signal)=>code===0?resolve():reject(new Error(`npm install falló (${code??signal}). No se generarán recursos incompletos.`)));
  });
}
export async function prepareDependencies({root, npm, runInstall=()=>installWithNpm(root,npm)}) {
  const release=await acquire(root);
  try {
    const manifest=await readFile(join(root,'package.json'),'utf8');
    const locked=await readFile(join(root,'package-lock.json'),'utf8');
    const lock=JSON.parse(locked);
    const missing=await missingPackages(root,lock);
    if (missing.length) {
      console.log(`InGe+ IA: preparando ${missing.length} dependencias ausentes o distintas del lockfile.`);
      await runInstall();
      if (!isDeepStrictEqual(JSON.parse(await readFile(join(root,'package-lock.json'),'utf8')),lock))
        throw new Error('npm modificó package-lock.json. Revisa el cambio antes de generar la interfaz.');
      const remaining=await missingPackages(root,lock);
      if (remaining.length) throw new Error(`Instalación incompleta: ${remaining.slice(0,3).join(', ')}.`);
    } else console.log('InGe+ IA: dependencias verificadas; se reutilizan sin reinstalar.');
    const fingerprint=createHash('sha256').update(JSON.stringify(JSON.parse(manifest))).update(JSON.stringify(lock)).digest('hex');
    const stamp=join(root,'node_modules/.inge-dependencies.sha256');
    await mkdir(dirname(stamp),{recursive:true});
    let previous=''; try {previous=await readFile(stamp,'utf8');} catch {}
    if (previous!==fingerprint) await writeFile(stamp,fingerprint);
  } finally { await release(); }
}
if (process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const npm=process.argv[process.argv.indexOf('--npm')+1];
  if (!process.argv.includes('--npm') || !npm) {console.error('Falta --npm con la ruta de npm.');process.exitCode=1;}
  else prepareDependencies({root:dirname(fileURLToPath(import.meta.url)),npm}).catch(error=>{console.error(error.message);process.exitCode=1;});
}
