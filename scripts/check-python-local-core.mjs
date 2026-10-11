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
const physicalBoundary=process.argv.includes('--physical-boundary');
const dispatchBoundary=process.argv.includes('--dispatch-boundary');
const submissionBoundary=process.argv.includes('--submission-boundary');
const invocationBoundary=process.argv.includes('--publication-invocation-boundary');
const sourcePublicationBoundary=process.argv.includes('--source-publication-boundary');
assert.ok([physicalBoundary,dispatchBoundary,submissionBoundary,sourcePublicationBoundary,invocationBoundary].filter(Boolean).length<=1,
  'Select one focused boundary');

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
  if(sourcePublicationBoundary || invocationBoundary){
    const library=process.env.ACTQL_PYTHON_DUCKDB_LIBRARY;
    const libraryDigest=process.env.ACTQL_PYTHON_DUCKDB_SHA256;
    assert.ok(library && /^[0-9a-f]{64}$/u.test(libraryDigest ?? ''),
      'Select the exact standalone DuckDB test library and digest');
    assert.equal(createHash('sha256').update(await readFile(library)).digest('hex'),libraryDigest);
    const physical=JSON.parse(run(python,['scripts/fixtures/python-local-runtime-abi.py',module]));
    assert.equal(physical.success,true);
    assert.equal(physical.module_sha256,digest);
    const native=JSON.parse(run(python,['scripts/fixtures/python-local-native-result-abi.py',
      module,library,libraryDigest,'--bounded-inventory-root','--source-publication'],120000));
    assert.equal(native.success,true);
    assert.equal(native.module_sha256,digest);
    assert.equal(native.cases.length,14);
    assert.equal(native.source_publication_cases.length,11);
    const invocationEvidence={};
    if(invocationBoundary){
      const material=JSON.parse(run(python,['scripts/fixtures/python-local-material-abi.py',module]));
      assert.equal(material.success,true);
      assert.equal(material.module_sha256,digest);
      assert.equal(material.material_cases,9);
      const explicit=JSON.parse(run(python,['scripts/fixtures/python-local-native-result-abi.py',
        module,library,libraryDigest,'--bounded-inventory-root','--source-publication','--explicit-view'],120000));
      assert.equal(explicit.success,true);
      assert.equal(explicit.module_sha256,digest);
      assert.equal(explicit.explicit_authored_view,true);
      assert.equal(explicit.normalization_completion_free,true);
      assert.equal(explicit.cases.length,14);
      assert.equal(explicit.source_publication_cases.length,11);
      Object.assign(invocationEvidence,{material,explicit});
    }
    const record={source_sha:source,module,module_sha256:digest,
      scope:invocationBoundary?'private_original_normalization_and_captured_invocation':'private_captured_source_publication_facts',
      moonc:run('moonc',['-v']),python:run(python,['--version']),result,physical,native,...invocationEvidence,
      public_local_acceptance:false,durable_run_acceptance:false,
      default_fuel_acceptance:false,global_memory_accounting:false};
    const file=join(receipt,invocationBoundary?'publication-invocation-boundary-receipt.json':'source-publication-boundary-receipt.json');
    try{
      await writeFile(file,JSON.stringify(record,null,2)+'\n',{flag:'wx'});
    }catch(error){
      if(error.code!=='EEXIST')throw error;
      assert.deepEqual(JSON.parse(await readFile(file,'utf8')),record,
        'Do not replace an existing fixed-source Source publication receipt');
    }
  }else if(submissionBoundary){
    const submission=JSON.parse(run(python,['scripts/fixtures/python-local-submission-abi.py',module]));
    assert.equal(submission.success,true);
    assert.equal(submission.module_sha256,digest);
    assert.equal(submission.cases.length,11);
    const record={source_sha:source,module,module_sha256:digest,
      scope:'private_submission_owner_identity_and_physical_authentication',
      moonc:run('moonc',['-v']),python:run(python,['--version']),result,submission,
      public_local_acceptance:false,durable_run_acceptance:false};
    const file=join(receipt,'submission-boundary-receipt.json');
    try{
      await writeFile(file,JSON.stringify(record,null,2)+'\n',{flag:'wx'});
    }catch(error){
      if(error.code!=='EEXIST')throw error;
      assert.deepEqual(JSON.parse(await readFile(file,'utf8')),record,
        'Do not replace an existing fixed-source Submission receipt');
    }
  }else if(dispatchBoundary){
    const dispatch=JSON.parse(run(python,['scripts/fixtures/python-local-dispatch-abi.py',module],180000));
    assert.equal(dispatch.success,true);
    assert.equal(dispatch.module_sha256,digest);
    assert.equal(dispatch.processes.length,6);
    const record={source_sha:source,module,module_sha256:digest,
      scope:'private_original_dispatch_reconciliation_only',
      moonc:run('moonc',['-v']),python:run(python,['--version']),result,dispatch,
      public_local_acceptance:false,durable_run_acceptance:false,
      default_fuel_acceptance:false};
    const file=join(receipt,'dispatch-boundary-receipt.json');
    try{
      await writeFile(file,JSON.stringify(record,null,2)+'\n',{flag:'wx'});
    }catch(error){
      if(error.code!=='EEXIST')throw error;
      assert.deepEqual(JSON.parse(await readFile(file,'utf8')),record,
        'Do not replace an existing fixed-source dispatch receipt');
    }
  }else if(physicalBoundary){
    const physical=JSON.parse(run(python,['scripts/fixtures/python-local-runtime-abi.py',module]));
    assert.equal(physical.success,true);
    assert.equal(physical.module_sha256,digest);
    const workspace=JSON.parse(run(python,['scripts/fixtures/python-local-workspace-abi.py',module]));
    assert.equal(workspace.success,true);
    assert.equal(workspace.module_sha256,digest);
    const record={source_sha:source,module,module_sha256:digest,
      scope:'physical_buffer_bridge_workspace_only',
      moonc:run('moonc',['-v']),python:run(python,['--version']),result,physical,workspace,
      positive_native_result_acceptance:false,public_local_acceptance:false};
    const file=join(receipt,'physical-boundary-receipt.json');
    try{
      await writeFile(file,JSON.stringify(record,null,2)+'\n',{flag:'wx'});
    }catch(error){
      if(error.code!=='EEXIST')throw error;
      assert.deepEqual(JSON.parse(await readFile(file,'utf8')),record,
        'Do not replace an existing fixed-source physical receipt');
    }
  }else{
  const preparation=JSON.parse(run(python,['scripts/fixtures/python-local-preparation-abi.py',module]));
  assert.equal(preparation.success,true);
  assert.equal(preparation.module_sha256,digest);
  const physical=JSON.parse(run(python,['scripts/fixtures/python-local-runtime-abi.py',module]));
  assert.equal(physical.success,true);
  assert.equal(physical.module_sha256,digest);
  const workspace=JSON.parse(run(python,['scripts/fixtures/python-local-workspace-abi.py',module]));
  assert.equal(workspace.success,true);
  assert.equal(workspace.module_sha256,digest);
  const sourceEnvironment=JSON.parse(run(python,['scripts/fixtures/python-local-source-environment-abi.py',module]));
  assert.equal(sourceEnvironment.success,true);
  assert.equal(sourceEnvironment.module_sha256,digest);
  const runPreparation=JSON.parse(run(python,['scripts/fixtures/python-local-run-abi.py',module]));
  assert.equal(runPreparation.success,true);
  assert.equal(runPreparation.module_sha256,digest);
  const materials=JSON.parse(run(python,['scripts/fixtures/python-local-material-abi.py',module]));
  assert.equal(materials.success,true);
  assert.equal(materials.module_sha256,digest);
  const record={source_sha:source,module,module_sha256:digest,
    moonc:run('moonc',['-v']),python:run(python,['--version']),result,preparation,physical,workspace,source_environment:sourceEnvironment,run_preparation:runPreparation,materials};
  try {
    await writeFile(join(receipt,'receipt.json'),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
  } catch (error) {
    if(error.code!=='EEXIST')throw error;
    assert.deepEqual(JSON.parse(await readFile(join(receipt,'receipt.json'),'utf8')),record,
      'Do not replace an existing fixed-source receipt');
  }
  }
}else{
  process.exitCode=await runLocalCheck({root,heavy:true,timeoutSeconds:240,graceSeconds:5,steps:[{
    name:physicalBoundary?'Actual Python/Core physical boundary':'Actual Python/Core buffer ABI',command:process.execPath,
    args:[fileURLToPath(import.meta.url),'--build-and-consume',...(physicalBoundary?['--physical-boundary']:[]),
      ...(dispatchBoundary?['--dispatch-boundary']:[]),
      ...(submissionBoundary?['--submission-boundary']:[]),
      ...(sourcePublicationBoundary?['--source-publication-boundary']:[]),
      ...(invocationBoundary?['--publication-invocation-boundary']:[])],
  }]});
}
