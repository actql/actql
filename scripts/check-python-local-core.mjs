// Focused portable ABI acceptance. It does not claim Run admission or recovery.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
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
  const module=join(target,'wasm/release/build/client_host_wasm/client_host_wasm.wasm');
  const digest=createHash('sha256').update(await readFile(module)).digest('hex');
  const output=run(python,['scripts/fixtures/python-local-buffer-abi.py',module]);
  const result=JSON.parse(output);
  assert.equal(result.success,true);
  assert.equal(result.module_sha256,digest);
  const receipt=join(root,'_build/python-local-core/artifacts',source.slice(0,9));
  await mkdir(receipt,{recursive:true});
  await writeFile(join(receipt,'receipt.json'),JSON.stringify({source_sha:source,module,
    module_sha256:digest,moonc:run('moonc',['-v']),python:run(python,['--version']),result},null,2)+'\n');
}else{
  process.exitCode=await runLocalCheck({root,heavy:true,timeoutSeconds:240,graceSeconds:5,steps:[{
    name:'Actual Python/Core buffer ABI',command:process.execPath,
    args:[fileURLToPath(import.meta.url),'--build-and-consume'],
  }]});
}
