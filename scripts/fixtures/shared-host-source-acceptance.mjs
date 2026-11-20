// Existing installed-CI orchestration, not a Host, reader or recovery owner.
// Both fault cases use normal packages and the original public Host fixture.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir, lstat, access} from 'node:fs/promises';
import {execFile, spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {join, resolve} from 'node:path';
import {userInfo} from 'node:os';
import {setTimeout as delay} from 'node:timers/promises';
import {createInstalledFamilyScenario} from './external-rest/fixture-source/adapters/host-node/fixtures/installed-family-scenario.fixture.mjs';
import {externalRestDefinition, externalRestProvider, externalRestProgram} from './external-rest/provider.fixture.mjs';
import {externalRestConfiguration} from './external-rest/configuration.mjs';
import {publishStandardRestBarrier} from './external-rest/cancel-conformance.mjs';
import {runNativeInstallCommand} from '../test-native-standalone-install.mjs';
import {verifyNodeBenchmarkPackages} from '../benchmark-node-operations.mjs';
import {inventory} from '../package-release.mjs';
import {normalNpmPackJsonArgs, parseNpmPackJson} from '../packed-client-packages.mjs';
import {fileURLToPath} from 'node:url';
import {checkoutState, CLIENT_PACKAGES, packedClientPackage} from '../packed-client-packages.mjs';
import {verifyNativeCliRelease} from '../native-cli-release.mjs';
import {verifyNativeStandaloneInstallation} from '../release-native-install.mjs';
import {platformKey, macOSProductVersion} from '../../packages/native-cli/bin/actql.mjs';
import {unpack} from '../package-release.mjs';
const source = fileURLToPath(new URL('../../', import.meta.url));
const runtime = source;
const read = async path => JSON.parse(await readFile(path, 'utf8'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const tool = promisify(execFile);

// The existing Native installed CI owner selects these two affected cases.
// No producer, normal package fallback or product service is supplied here.
export const sharedHostSourceScenarios = Object.freeze(['client-crash', 'owner-crash']);

async function crashOwnedHost(descriptor, env, cwd, save) {
 const args=[join(source,'scripts/fixtures/shared-host-source-cancel.mjs'),descriptor];
 const child=spawn(process.execPath,args,{cwd,env,stdio:['ignore','pipe','pipe']});
 const record={pid:child.pid,command:process.execPath,args,startedAt:new Date().toISOString(),stdout:'',stderr:'',
  hostCloseAttempted:'UNOBSERVED',hostCloseAck:false};
 let bytes=0,lines='',failure;
 const terminate=reason=>{record.terminationReason=reason;child.kill('SIGTERM');};
 const timer=setTimeout(()=>terminate('original-child-timeout'),30_000);
 child.stdout.on('data',chunk=>{
  bytes+=chunk.length;if(bytes>8*1024*1024){terminate('output-limit');return;}
  record.stdout+=chunk;lines+=chunk;
  let end;
  while((end=lines.indexOf('\n'))!==-1){
   const line=lines.slice(0,end);lines=lines.slice(end+1);
   let body;try{body=JSON.parse(line);}catch{continue;}
   if(body.stage!=='owner-crash-ready')continue;
   try{
    assert.equal(body.pid,child.pid);assert.equal(record.boundary,undefined);
    record.boundary=body;record.boundaryObservedAt=new Date().toISOString();
    record.signalSendStartedAt=new Date().toISOString();
    record.signalAccepted=child.kill('SIGKILL');record.signalSentAt=new Date().toISOString();
    assert.equal(record.signalAccepted,true);
   }catch(error){failure=error;terminate('invalid-owned-boundary');}
  }
 });
 child.stderr.on('data',chunk=>{bytes+=chunk.length;if(bytes>8*1024*1024)terminate('output-limit');else record.stderr+=chunk;});
 child.once('exit',(code,signal)=>{record.ownerExit={at:new Date().toISOString(),code,signal};});
 await new Promise((resolve,reject)=>{
  child.once('error',error=>{clearTimeout(timer);reject(error);});
  child.once('close',(code,signal)=>{clearTimeout(timer);Object.assign(record,{code,signal,streamsClosedAt:new Date().toISOString()});resolve();});
 });
 if(record.boundary&&record.signal==='SIGKILL')record.hostCloseAttempted=false;
 await save('owner-crash-command.json',record);
 if(failure)throw failure;
 assert(record.boundary);assert.equal(record.code,null);assert.equal(record.signal,'SIGKILL');assert.equal(record.terminationReason,undefined);
 return record;
}

export async function runSharedHostSourceAcceptance({outputRoot, nativeDirectory, scenario} = {}) {
 assert(sharedHostSourceScenarios.includes(scenario), 'Unsupported shared Source acceptance scenario');
 assert(process.env.ACTQL_PACKED_CLIENT_PACKAGES, 'Use the original normal Client producer; no fallback build');
 const fixed=checkoutState(source);assert.equal(fixed.clean,true);
 const native=await verifyNativeCliRelease(nativeDirectory);assert.equal(native.sourceSha,fixed.revision);
 const output=outputRoot;await mkdir(output);
 const save=(name,value)=>writeFile(join(output,name),JSON.stringify(value,null,2)+'\n',{flag:'wx'});
 const inputCopies=join(output,'normal-inputs');await mkdir(inputCopies);
 const normalManifestPath=join(process.env.ACTQL_PACKED_CLIENT_PACKAGES,'packed-client-packages.json');
 const originalManifest=await read(normalManifestPath);assert.equal(originalManifest.revision,fixed.revision);
 const nodeTarballs=[],packages=[];
 for(const name of CLIENT_PACKAGES){
  await packedClientPackage({repository:source,name,destination:inputCopies,
   pack(){throw Error('Shared Host CI consumes only the existing normal producer');}});
  const file=`actql-${name}-0.0.0-development.tgz`,path=join(inputCopies,file),bytes=await readFile(path);
  assert.equal(hash(bytes),originalManifest.tarballs[name]);nodeTarballs.push(path);
  const extracted=await unpack(path,join(output,`original-${name}`));
  packages.push({name:`@actql/${name}`,file,bytes:bytes.length,sha256:hash(bytes),
   integrity:'sha512-'+createHash('sha512').update(bytes).digest('base64'),files:await inventory(extracted)});
 }
 // Derived comparison DATA only; the canonical producer manifest above remains
 // the source/digest authority, and no replacement manifest is emitted.
 const normalComparison={packages};
 await save('original-software-inputs.json',{source:fixed.revision,normalManifestPath,
  normalManifestSha256:hash(await readFile(normalManifestPath)),nativeDirectory});
 const consumer=join(output,'consumer');await assert.rejects(lstat(consumer),{code:'ENOENT'});
 const originalProvider=externalRestProvider({mode:'paged'}),cleanupRelease=Promise.withResolvers();
 const markerPaths={first:join(output,'page-first-entered.json'),second:join(output,'page-second-entered.json')};
 const env={...process.env,npm_config_cache:join(output,'npm-cache')};
 const commands=[],report={passed:false,runtimeHostSource:fixed.revision,nativeClientSource:native.sourceSha,fixtureSource:fixed.revision,commands};
 let family,before,pluginFiles,pluginRoot,hostCommand,primary,failed=false,pageCount=0;
 const run=async(name,command,args,cwd)=>{
  const startedAt=new Date().toISOString();
  try{const r=await tool(command,args,{cwd,env,maxBuffer:8*1024*1024});commands.push({name,command,args,startedAt,endedAt:new Date().toISOString(),code:0});await save(name+'.json',{stdout:r.stdout,stderr:r.stderr});return r.stdout;}
  catch(error){commands.push({name,command,args,startedAt,endedAt:new Date().toISOString(),code:error.code});await save(name+'.json',{stdout:String(error.stdout??''),stderr:String(error.stderr??''),message:error.message});throw error;}
 };
 const releaseMarker=async (path,stop)=>{
  const signal=AbortSignal.any([AbortSignal.timeout(30_000),stop]);
  while(true){signal.throwIfAborted();try{await access(path);return;}catch(error){if(error.code!=='ENOENT')throw error;}await delay(10,undefined,{signal});}
 };
 const provider=Object.freeze({...originalProvider,async handle(request){
  const reply=originalProvider.handle(request);
  if(request.target==='/v1/customers?after=page-2'){
   const phase=['first','second'][pageCount++];assert(phase,'No third independent second-page request');
   await publishStandardRestBarrier(markerPaths[phase],JSON.stringify({page:2,phase,replyHeld:true,enteredAt:new Date().toISOString(),holdTimeoutMs:30_000,requests:originalProvider.requests()})+'\n');
   const stop=new AbortController();
   try{await Promise.race([releaseMarker(join(output,'public',`release-${phase}.json`),stop.signal),
    releaseMarker(join(output,'public','fixture-release-all.json'),stop.signal),cleanupRelease.promise]);}
   finally{stop.abort();}
  }
  return reply;
 }});
 const account={version:'actql-execution-account-config/0.1',account_id:'shared-source-cancel',entries:[
  {entry_id:'compute-write',outcome:'allow',principal:{any_of:[userInfo().username]},connection:{any_of:['actql-remote-host']},resource:{any_of:['row-source-acquired']},operation:{any_of:['write']},exclusions:[]},
  {entry_id:'result-rows-read',outcome:'allow',principal:{any_of:[userInfo().username]},connection:{any_of:['actql-remote-host']},resource:{any_of:['result/rows']},operation:{any_of:['read']},exclusions:[]},
  {entry_id:'run-read',outcome:'allow',principal:{any_of:[userInfo().username]},connection:{any_of:['actql-remote-host']},resource:{any_of:['run']},operation:{any_of:['read']},exclusions:[]},
  {entry_id:'source-customers-read',outcome:'allow',principal:{any_of:[userInfo().username]},connection:{any_of:['acme:rest-acme']},resource:{any_of:['customers']},operation:{any_of:['acme:rest:read','read']},exclusions:[]}
 ]};
 try{
  family=await createInstalledFamilyScenario(undefined,{scratchParent:output,scenario:{id:'shared-source-cancel'},accountConfigurationWire:JSON.stringify(account),provider,maxRequestBytes:4096});
  await save('authored-account.json',account);
  await save('fixture-paths.json',{paths:family.paths,origin:family.resourceHttps.origin});
  // Author validation resolves the same installed public package from its
  // consumer ancestor. Establish and verify it before invoking the author CLI.
  await mkdir(consumer);await writeFile(join(consumer,'package.json'),'{"private":true,"type":"module"}\n');
  await run('install-normal-five','npm',['install','--offline','--no-audit','--no-fund',
   ...nodeTarballs],consumer);
  const authorFramework=await verifyNodeBenchmarkPackages(normalComparison,normalManifestPath,consumer);
  await save('author-installed-normal-five.json',authorFramework);
  const author=join(consumer,'author'),packageRoot=join(output,'connector-package');
  await run('author-init',process.execPath,[join(runtime,'scripts/connector.mjs'),'init',author,'acme'],runtime);
  const definition=join(author,'connector.json');await writeFile(definition,JSON.stringify(externalRestDefinition(family.resourceHttps.origin))+'\n');
  await run('author-build',process.execPath,[join(runtime,'scripts/connector.mjs'),'build',definition,packageRoot],runtime);
  pluginFiles=await inventory(packageRoot);
  const artifacts=join(output,'artifacts');await mkdir(artifacts);
  const packed=parseNpmPackJson(await run('pack-connector','npm',normalNpmPackJsonArgs(['pack','--offline','--json','--pack-destination',artifacts]),packageRoot))[0];
  assert.equal(packed.name,'@actql-connectors/acme');const connectorTar=join(artifacts,packed.filename);
  const bytes=await readFile(connectorTar);assert.equal(packed.integrity,'sha512-'+createHash('sha512').update(bytes).digest('base64'));
  await run('install-native-connector','npm',['install','--offline','--no-audit','--no-fund',
   ...native.packages.map(p=>join(nativeDirectory,p.file)),connectorTar],consumer);
  const installed=async()=>{
   const n=[];for(const p of native.packages){const files=await inventory(join(consumer,'node_modules',p.name));assert.deepEqual(files,p.files);n.push({name:p.name,files});}
   const framework=await verifyNodeBenchmarkPackages(normalComparison,normalManifestPath,consumer);
   assert.deepEqual(framework,authorFramework);
   const connector=await inventory(join(consumer,'node_modules/@actql-connectors/acme'));assert.deepEqual(connector,pluginFiles);
   return {native:n,framework,connector};
  };
  before=await installed();await save('installed-before.json',before);pluginRoot=installed;
  const glibc=process.platform==='linux'?process.report.getReport().header.glibcVersionRuntime:undefined;
  const platform=platformKey({platform:process.platform,arch:process.arch,glibc});
  const artifact=native.artifacts.find(value=>value.platform===platform);
  const nativePackage=native.packages.find(value=>value.name===native.platforms[platform].package);
  assert(artifact&&nativePackage);
  const admitted=await verifyNativeStandaloneInstallation(join(consumer,'node_modules',nativePackage.name),
   {...nativePackage,platform},artifact,native.sourceSha,native.cohort.packageVersion,
   {glibc,macOS:process.platform==='darwin'?macOSProductVersion():undefined});
  await save('direct-native-admission.json',admitted);
  const prepared=externalRestConfiguration(family,{connectorId:'rest-acme',profileVersion:'actql-installed-acme-rest-source/0.1'});
  for(const [name,value]of Object.entries(prepared.files))await family.writeProjectInput(name,JSON.stringify(value));
  // Select the existing declared records view. These lifetime cases do not
  // also qualify implicit-view selection.
  const program=externalRestProgram('rest-acme');program.stages[0].inputs.customers.view='records';
  const programPath=await family.writeProjectInput('cancel-program.json',JSON.stringify(program));
  const publicRoot=join(output,'public');await mkdir(publicRoot);
  await run('own-tls','openssl',['req','-x509','-nodes','-newkey','rsa:2048','-keyout','host.key','-out','host.crt','-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1','-addext','extendedKeyUsage=serverAuth,clientAuth'],publicRoot);
  const descriptor=join(output,'host-input.json');await save('host-input.json',{consumerRoot:consumer,
   outputRoot:publicRoot,installation:prepared.installation,connectorPackage:'@actql-connectors/acme',
   fixtureSecretPath:family.providerTokenPath,certificate:join(publicRoot,'host.crt'),privateKey:join(publicRoot,'host.key'),
   executable:join(consumer,'node_modules/.bin/actql'),nativeCrashExecutable:admitted.executable,programPath,scenario,
   clientScript:join(source,'scripts/fixtures/shared-host-source-client.mjs'),pageEntered:markerPaths});
  const childEnv={...env,HOME:family.paths.home,NODE_EXTRA_CA_CERTS:join(publicRoot,'host.crt')};
  if(scenario==='client-crash'){
  const flight=runNativeInstallCommand(process.execPath,[join(source,'scripts/fixtures/shared-host-source-cancel.mjs'),descriptor],
   {cwd:publicRoot,env:childEnv,state:family.root});
  const settled=flight.then(value=>({value}),cause=>({failed:true,cause}));
  const terminal=await settled;
  if(terminal.failed){if(terminal.cause.commandRecord)await save('host-command.json',terminal.cause.commandRecord);throw terminal.cause;}
  hostCommand=terminal.value;await save('host-command.json',hostCommand);
  const observed=await read(join(publicRoot,'shared-source-cancel-result.json'));assert.equal(observed.passed,true);
  assert.equal(observed.firstSourceSurvivedClientCrash,true);assert.equal(observed.otherRunUnaffected,true);
  const crashed=await read(join(publicRoot,'native-client-crash.json'));assert.equal(crashed.signal,'SIGKILL');assert.equal(crashed.publicCloseAttempted,false);
  const recovery=await read(join(publicRoot,'source-recover-first-report.json'));assert.equal(recovery.publicStartSource,0);assert.equal(recovery.publicAttach,1);
  assert.equal(hostCommand.close.scopedStateFd0,true);assert.equal(hostCommand.closeObservationAcknowledged,true);
  assert.deepEqual(originalProvider.requests(),[{method:'GET',target:'/v1/customers'},{method:'GET',target:'/v1/customers?after=page-2'},
   {method:'GET',target:'/v1/customers'},{method:'GET',target:'/v1/customers?after=page-2'}]);
  } else {
  await crashOwnedHost(descriptor, childEnv, publicRoot, save);
  // Release only the old fixture reply after the actual Owner has exited.
  // The new Owner must recover through ordinary admission without a lock edit.
  await publishStandardRestBarrier(join(publicRoot,'release-second.json'),JSON.stringify({afterActualOwnerExit:true})+'\n');
  const recoveredRoot=join(output,'recovered');await mkdir(recoveredRoot);
  const originalConfiguration=await read(descriptor);
  const recoveredDescriptor=join(output,'owner-restart-input.json');
  await save('owner-restart-input.json',{...originalConfiguration,outputRoot:recoveredRoot,
   originalRefRoot:publicRoot,scenario:'owner-recover'});
  hostCommand=await runNativeInstallCommand(process.execPath,[join(source,'scripts/fixtures/shared-host-source-cancel.mjs'),recoveredDescriptor],
   {cwd:recoveredRoot,env:childEnv,state:family.root});
  await save('host-command.json',hostCommand);
  const observed=await read(join(recoveredRoot,'shared-source-cancel-result.json'));assert.equal(observed.passed,true);
  assert.equal(observed.completedOriginalSaved,true);assert.equal(observed.interruptedOriginalStatusObserved,true);
  assert.equal(observed.dispatchObservations,0);
  const completed=await read(join(recoveredRoot,'source-recover-first-report.json'));
  const interrupted=await read(join(recoveredRoot,'source-observe-second-report.json'));
  for(const actor of [completed,interrupted]){assert.equal(actor.publicStartSource,0);assert.equal(actor.publicAttach,1);assert.equal(actor.clientCloseReturned,true);}
  assert.deepEqual(await read(join(recoveredRoot,'source-recover-first-rows.json')),await read(join(publicRoot,'source-recover-first-rows.json')));
  const interruptedStatus=await read(join(recoveredRoot,'source-observe-second-status.json'));
  await save('interrupted-original-status.json',interruptedStatus);
  // This profile retains uncertain interrupted work without replay. Do not
  // accept a fabricated success, cancellation or physical-stop acknowledgement.
  assert.equal(interruptedStatus.status,'needs_reconciliation');
  assert.equal(interruptedStatus.result_available,false);
  assert.equal(interruptedStatus.control.cancellation_requested,false);
  assert.equal(interruptedStatus.control.physical_stop,'unknown');
  assert.equal(hostCommand.close.scopedStateFd0,true);assert.equal(hostCommand.closeObservationAcknowledged,true);
  assert.deepEqual(originalProvider.requests(),[{method:'GET',target:'/v1/customers'},{method:'GET',target:'/v1/customers?after=page-2'},
   {method:'GET',target:'/v1/customers'},{method:'GET',target:'/v1/customers?after=page-2'}]);
  }
  report.passed=true;report.caseScope=scenario==='owner-crash'?'completed original Saved plus one held Read; own Host crash; ordinary reopen/Saved/status without replay':'own Native client crash; same-ref recovery without resubmit; other Run continues';report.hostCloseReturned=true;report.aliveScopedFd0=true;
 }catch(error){if(error.commandRecord)await save('failed-host-command.json',error.commandRecord);failed=true;primary=error;report.failure={name:error?.name,code:error?.code,message:error?.message};}
 finally{
  cleanupRelease.resolve();report.providerRequests=originalProvider.requests();
  if(before!==undefined){try{const after=await pluginRoot();await save('installed-after.json',after);assert.deepEqual(after,before);report.packagesUnchanged=true;}catch(error){primary=failed?new AggregateError([primary,error]):error;failed=true;report.passed=false;}}
  if(family!==undefined){try{await family.https.close();report.fixtureTLSClosed=true;}catch(error){primary=failed?new AggregateError([primary,error]):error;failed=true;report.passed=false;}}
  await save('result.json',report);
 }
 if(failed)throw primary;
 return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
 assert.equal(process.argv.length, 3, 'usage: shared-host-source-acceptance.mjs <fresh-case-input.json>');
 await runSharedHostSourceAcceptance(await read(process.argv[2]));
}
