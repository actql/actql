import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,readFile,readdir,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runLocalCheck} from './local-checks-guard.mjs';

const root=fileURLToPath(new URL('../',import.meta.url));
const python=process.env.ACTQL_PYTHON_PROBE;
assert.ok(python,'Select an isolated Python prototype environment');

function run(command,args,cwd,timeout=60000){
  const result=spawnSync(command,args,{cwd,env:{...process.env,PYTHONPATH:''},encoding:'utf8',timeout,maxBuffer:8*1024*1024});
  if(result.stdout)process.stdout.write(result.stdout);
  if(result.stderr)process.stderr.write(result.stderr);
  assert.equal(result.error,undefined);
  assert.equal(result.signal,null);
  assert.equal(result.status,0,`${command} failed`);
  return result.stdout.trim();
}

async function wasmFiles(directory){
  const result=[];
  for(const entry of await readdir(directory,{withFileTypes:true})){
    const path=join(directory,entry.name);
    if(entry.isDirectory())result.push(...await wasmFiles(path));
    else if(entry.name.endsWith('.wasm'))result.push(path);
  }
  return result;
}

if(process.argv.includes('--build-and-consume')){
  assert.equal(run('git',['status','--porcelain'],root),'','Use committed prototype source');
  const source=run('git',['rev-parse','HEAD'],root);
  const fixture=join(root,'experiments/python-local-wasm');
  const scratch=join(root,'_build/python-local-probe');
  await mkdir(scratch,{recursive:true});
  await writeFile(join(scratch,'moon.work'),`members = [${JSON.stringify(root)}, ${JSON.stringify(join(fixture,'module'))}]\n`);
  const compiled=join(scratch,'compiled');
  run('moon',['build','--target','wasm','--release',join(fixture,'module/src'),'--target-dir',compiled],scratch,120000);
  const modules=await wasmFiles(compiled);
  assert.equal(modules.length,1,'One selected foreign-library module must be linked');
  const wasm=await readFile(modules[0]);
  const identity={source_sha:source,wasm_sha256:createHash('sha256').update(wasm).digest('hex'),
    moonc:run('moonc',['-v'],root),target:'wasm',wasmtime:'38.0.0',duckdb:'1.4.1'};
  const payload=join(fixture,'package/src/actql_local_probe');
  await writeFile(join(payload,'core.wasm'),wasm);
  await writeFile(join(payload,'artifact.json'),JSON.stringify(identity,null,2)+'\n');
  const artifacts=join(scratch,'artifacts',source.slice(0,9));
  await mkdir(artifacts,{recursive:true});
  run(python,['-m','build','--wheel','--no-isolation','--outdir',artifacts,join(fixture,'package')],root);
  const wheel=join(artifacts,'actql_local_wasm_probe-0.0.0.dev0-py3-none-any.whl');
  const wheelDigest=createHash('sha256').update(await readFile(wheel)).digest('hex');
  const external=await mkdtemp(join(tmpdir(),'actql-python-local-probe-'));
  run(python,['-m','venv','--without-pip',join(external,'venv')],external);
  const interpreter=join(external,'venv/bin/python');
  run(process.env.ACTQL_UV??'uv',['pip','install','--python',interpreter,wheel],external);
  const receipt=run(interpreter,[join(fixture,'accept.py')],external);
  assert.equal(JSON.parse(receipt).success,true);
  await writeFile(join(artifacts,'receipt.json'),JSON.stringify({identity,wheel,wheel_sha256:wheelDigest,
    external_venv:join(external,'venv'),acceptance:JSON.parse(receipt)},null,2)+'\n');
}else{
  process.exitCode=await runLocalCheck({root,heavy:true,timeoutSeconds:240,graceSeconds:5,steps:[{
    name:'Real Python Wasm callback and wheel feasibility',command:process.execPath,
    args:[fileURLToPath(import.meta.url),'--build-and-consume'],
  }]});
}
