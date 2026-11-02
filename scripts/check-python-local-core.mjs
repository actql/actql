// Focused portable ABI acceptance. It does not claim Run admission or recovery.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile,mkdir,readFile,writeFile} from 'node:fs/promises';
import {constants,readFileSync} from 'node:fs';
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
const resultPublicationBoundary=process.argv.includes('--result-publication-boundary');
assert.ok([physicalBoundary,dispatchBoundary,submissionBoundary,sourcePublicationBoundary,invocationBoundary,resultPublicationBoundary].filter(Boolean).length<=1,
  'Select one focused boundary');

// Every selected current fixture declares what its fuel observation establishes.
// Version/package version and default-fuel performance are independent facts.
const fixtureModes = Object.freeze({
  'contract': 'actual artifact shape; synthetic entry refusal only',
  'buffer': 'unmetered transfer/cleanup custody',
  'platform-vm': 'raw same-VM Root/input-pool/current/borrower; no installed image or Request/Run',
  'buffer-packed': 'unmetered raw Wasmtime i64 transport; no Run or physical ACK',
  'original-bulk': 'unmetered raw original-memory block ABI; no funded Host/Run or physical ACK',
  'preparation': 'unmetered positive; separate metered5k interruption',
  'runtime': '100M instances; separate5k transfer trap and explicit cleanup funding',
  'workspace': '100M instance; reservation/stop/cleanup',
  'source-environment': 'two independent100M instances; refusal batch then positive lifetime',
  'run': 'unmetered positive; distinct metered instance with explicit setup/5k interruption/100M cleanup',
  'material': 'explicit private diagnostic fuel; no default100M claim',
  'submission': '100M per independent instance; original identity/storage',
  'dispatch': 'unmetered private process recovery decisions',
  'native-result': 'unmetered private Native/Compute/Result; no default fuel claim',
});

function run(command,args,timeout=60000){
  const result=spawnSync(command,args,{cwd:root,env:{...process.env,PYTHONPATH:''},
    encoding:'utf8',timeout,maxBuffer:8*1024*1024});
  if(result.stdout)process.stdout.write(result.stdout);
  if(result.stderr)process.stderr.write(result.stderr);
  assert.equal(result.error,undefined);
  assert.equal(result.signal,null);
  assert.equal(result.status,0,`${command} failed`);
  const selected = /^scripts\/fixtures\/python-local-(.+)-abi\.py$/u.exec(args[0] ?? '');
  if (command === python && selected) {
    assert.ok(Object.hasOwn(fixtureModes,selected[1]),'Unclassified current ABI fixture');
    const report = JSON.parse(result.stdout.trim());
    const hash = path => createHash('sha256').update(readFileSync(join(root,path))).digest('hex');
    const declaration = readFileSync(join(root,'packages/python-sdk/src/actql_sdk/_local_wasm_abi.py'),'utf8');
    const abi = Number(/^LOCAL_CORE_ABI = (\d+)$/mu.exec(declaration)?.[1]);
    assert.ok(Number.isSafeInteger(abi));
    assert.equal(report.module_sha256,createHash('sha256').update(readFileSync(args[1])).digest('hex'));
    report.interface = {abi,fixture:args[0],fixture_sha256:hash(args[0]),
      wrapper_sha256:hash('packages/python-sdk/src/actql_sdk/_local_core.py'),
      declaration_sha256:hash('packages/python-sdk/src/actql_sdk/_local_wasm_abi.py'),
      mode:fixtureModes[selected[1]],default_fuel_acceptance:false};
    console.log(JSON.stringify({fixture_interface:report.interface,module_sha256:report.module_sha256}));
    return JSON.stringify(report);
  }
  return result.stdout.trim();
}

if(process.argv.includes('--build-and-consume')){
  assert.equal(run('git',['status','--porcelain']),'','Use committed ABI source');
  for(const generator of ['generate-local-wasm-abi.py','generate-local-native-runtime-binding.py',
    'generate-local-native-shim-bindings.py','generate-local-native-memory-binding.py',
    'generate-local-duckdb-binding.py'])run(python,['scripts/'+generator,'--check']);
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
  let moduleOriginal;
  if(physicalBoundary){
    assert.ok(process.env.MOON_HOME,'Select the original pinned compiler directory');
    const file=join(receipt,'module-original.json');
    run(python,['scripts/produce-python-local-runtime.py','--record-module-original',
      '--source',source,'--compiled-source',source,'--module',module,
      '--link-response',built+'.rsp','--moon-home',process.env.MOON_HOME,'--destination',file]);
    moduleOriginal=JSON.parse(await readFile(file,'utf8'));
    assert.equal(moduleOriginal.scope,'compile_only_module_inputs');
    assert.equal(moduleOriginal.source_sha,source);
    assert.equal(moduleOriginal.module_sha256,digest);
  }
  const contract=JSON.parse(run(python,['scripts/fixtures/python-local-contract-abi.py',module]));
  assert.equal(contract.success,true);
  assert.equal(contract.module_sha256,digest);
  assert.equal(contract.rejection_cases.length,7);
  const output=run(python,['scripts/fixtures/python-local-buffer-abi.py',module]);
  const result=JSON.parse(output);
  assert.equal(result.success,true);
  assert.equal(result.module_sha256,digest);
  const packed=JSON.parse(run(python,['scripts/fixtures/python-local-buffer-packed-abi.py',module]));
  assert.equal(packed.success,true);
  assert.equal(packed.module_sha256,digest);
  assert.deepEqual(packed.cases,['original_wasmtime_i64_packed_transport']);
  const bulk=JSON.parse(run(python,['scripts/fixtures/python-local-original-bulk-abi.py',module]));
  assert.equal(bulk.success,true);
  assert.equal(bulk.module_sha256,digest);
  assert.deepEqual(bulk.cases,['original_wasmtime_bounded_block_transport']);
  if(resultPublicationBoundary){
    const library=process.env.ACTQL_PYTHON_DUCKDB_LIBRARY;
    const libraryDigest=process.env.ACTQL_PYTHON_DUCKDB_SHA256;
    assert.ok(library && /^[0-9a-f]{64}$/u.test(libraryDigest ?? ''),
      'Select the exact standalone DuckDB test library and digest');
    assert.equal(createHash('sha256').update(await readFile(library)).digest('hex'),libraryDigest);
    const physical=JSON.parse(run(python,['scripts/fixtures/python-local-runtime-abi.py',module]));
    assert.equal(physical.success,true);
    assert.equal(physical.module_sha256,digest);
    const native=JSON.parse(run(python,['scripts/fixtures/python-local-native-result-abi.py',
      module,library,libraryDigest,'--bounded-inventory-root','--source-publication',
      '--explicit-view','--final-publication'],120000));
    assert.equal(native.success,true);
    assert.equal(native.module_sha256,digest);
    assert.equal(native.cases.length,14);
    assert.equal(native.publication_preflight_cases.length,4);
    assert.equal(native.source_publication_cases.length,11);
    assert.equal(native.result_publication_cases.length,11);
    assert.equal(native.explicit_authored_view,true);
    assert.equal(native.source_queries,3);
    const record={source_sha:source,module,module_sha256:digest,contract,
      scope:'private_original_result_snapshot_manifest_receipt_capture',
      moonc:run('moonc',['-v']),python:run(python,['--version']),result,physical,native,
      public_local_acceptance:false,durable_run_acceptance:false,
      default_fuel_acceptance:false,global_memory_accounting:false};
    const file=join(receipt,'result-publication-boundary-receipt.json');
    try{
      await writeFile(file,JSON.stringify(record,null,2)+'\n',{flag:'wx'});
    }catch(error){
      if(error.code!=='EEXIST')throw error;
      assert.deepEqual(JSON.parse(await readFile(file,'utf8')),record,
        'Do not replace an existing fixed-source Result publication receipt');
    }
  }else if(sourcePublicationBoundary || invocationBoundary){
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
    assert.equal(native.publication_preflight_cases.length,4);
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
      assert.equal(explicit.publication_preflight_cases.length,4);
      assert.equal(explicit.source_publication_cases.length,11);
      Object.assign(invocationEvidence,{material,explicit});
    }
    const record={source_sha:source,module,module_sha256:digest,contract,
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
    const record={source_sha:source,module,module_sha256:digest,contract,
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
    const record={source_sha:source,module,module_sha256:digest,contract,
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
    const platformVm=JSON.parse(run(python,['scripts/fixtures/python-local-platform-vm-abi.py',module]));
    assert.equal(platformVm.success,true);
    assert.equal(platformVm.cases.length,3);
    assert.equal(platformVm.module_sha256,digest);
    const physical=JSON.parse(run(python,['scripts/fixtures/python-local-runtime-abi.py',module]));
    assert.equal(physical.success,true);
    assert.equal(physical.module_sha256,digest);
    const workspace=JSON.parse(run(python,['scripts/fixtures/python-local-workspace-abi.py',module]));
    assert.equal(workspace.success,true);
    assert.equal(workspace.module_sha256,digest);
    const record={source_sha:source,module,module_sha256:digest,contract,
      scope:'physical_buffer_bridge_workspace_only',
      moonc:run('moonc',['-v']),python:run(python,['--version']),result,physical,workspace,
      module_original:moduleOriginal,
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
  const record={source_sha:source,module,module_sha256:digest,contract,
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
      ...(invocationBoundary?['--publication-invocation-boundary']:[]),
      ...(resultPublicationBoundary?['--result-publication-boundary']:[])],
  }]});
}
