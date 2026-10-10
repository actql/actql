// Focused portable ABI acceptance. It does not claim Run admission or recovery.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile,mkdir,readFile,writeFile} from 'node:fs/promises';
import {constants} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runLocalCheck} from './local-checks-guard.mjs';

const root=fileURLToPath(new URL('../',import.meta.url));
const python=process.env.ACTQL_PYTHON_LOCAL;
assert.ok(python,'Select the isolated Python Wasmtime environment');

function run(command,args,timeout=60000){
  const result=spawnSync(command,args,{cwd:root,env:{...process.env,PYTHONPATH:''},
    encoding:'utf8',timeout,maxBuffer:8*1024*1024});
  if(result.stdout)process.stdout.write(result.stdout);
  if(result.stderr)process.stderr.write(result.stderr);
  assert.equal(result.error,undefined);
  assert.equal(result.signal,null);
  assert.equal(result.status,0,`${command} failed`);
  return result.stdout.trim();
}

if(process.argv.includes('--build-and-consume')){
  assert.equal(run('git',['status','--porcelain']),'','Use committed ABI source');
  const source=run('git',['rev-parse','HEAD']);
  const target=join(root,'_build/python-local-core/wasm');
  run('moon',['build','--target','wasm','--release','src/client_host_wasm','--target-dir',target],120000);
  const built=join(target,'wasm/release/build/client_host_wasm/client_host_wasm.wasm');
  const digest=createHash('sha256').update(await readFile(built)).digest('hex');
  const receipt=join(root,'_build/python-local-core/artifacts',source);
  await mkdir(receipt,{recursive:true});
  // Consume and retain the same immutable module, not the next build's path.
  const module=join(receipt,'client_host_wasm.wasm');
  try {
    await copyFile(built,module,constants.COPYFILE_EXCL);
  } catch (error) {
    if(error.code!=='EEXIST')throw error;
  }
  assert.equal(createHash('sha256').update(await readFile(module)).digest('hex'),
    digest,'The retained artifact must match this fixed-source build');
  const output=run(python,['scripts/fixtures/python-local-buffer-abi.py',module]);
  const result=JSON.parse(output);
  assert.equal(result.success,true);
  assert.equal(result.module_sha256,digest);
  const preparation=JSON.parse(run(python,['scripts/fixtures/python-local-preparation-abi.py',module]));
  assert.equal(preparation.success,true);
  assert.equal(preparation.module_sha256,digest);
  const physical=JSON.parse(run(python,['scripts/fixtures/python-local-runtime-abi.py',module]));
  assert.equal(physical.success,true);
  assert.equal(physical.module_sha256,digest);
  const runPreparation=JSON.parse(run(python,['scripts/fixtures/python-local-run-abi.py',module]));
  assert.equal(runPreparation.success,true);
  assert.equal(runPreparation.module_sha256,digest);
  const materials=JSON.parse(run(python,['scripts/fixtures/python-local-material-abi.py',module]));
  assert.equal(materials.success,true);
  assert.equal(materials.module_sha256,digest);
  const record={source_sha:source,module,module_sha256:digest,
    moonc:run('moonc',['-v']),python:run(python,['--version']),result,preparation,physical,run_preparation:runPreparation,materials};
  try {
    await writeFile(join(receipt,'receipt.json'),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
  } catch (error) {
    if(error.code!=='EEXIST')throw error;
    assert.deepEqual(JSON.parse(await readFile(join(receipt,'receipt.json'),'utf8')),record,
      'Do not replace an existing fixed-source receipt');
  }
}else{
  process.exitCode=await runLocalCheck({root,heavy:true,timeoutSeconds:240,graceSeconds:5,steps:[{
    name:'Actual Python/Core buffer ABI',command:process.execPath,
    args:[fileURLToPath(import.meta.url),'--build-and-consume'],
  }]});
}
