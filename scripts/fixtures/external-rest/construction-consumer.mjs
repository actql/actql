// Run only after the caller has verified one coherent normal installation.
// Product imports resolve from that installation, never from checkout source.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import {observeOwnScopedStateFds} from './conformance.mjs';
import {lstat} from 'node:fs/promises';
import {externalRestProgram, externalRestProvider} from './provider.fixture.mjs';
import {loadExternalRestModules} from './installed-modules.mjs';

const [configurationPath, phase] = process.argv.slice(2);
assert(configurationPath && phase === 'construct',
  'Usage: consumer.mjs <fresh-own-configuration.json> construct');
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const consumerRoot = resolve(configuration.consumerRoot);
const {connect, publicSdk, connectorTable, paths: productModules,
  loadedInstallationExports} = await loadExternalRestModules({consumerRoot,
  connectorPackage: configuration.connectorPackage});
const outputRoot = resolve(configuration.outputRoot, phase);
await mkdir(outputRoot, {recursive: true});
await writeFile(join(outputRoot, 'installation-module.json'), JSON.stringify({
  productModules, loadedInstallationExports, generatedInstallationLoaded: true,
  HostOpened: false,
}, null, 2) + '\n', {flag: 'wx'});
const startedAt = new Date().toISOString(), started = performance.now();
const sourceProfileKeys = ['authorization', 'directory', 'sourceProfilePath', 'sourceProfilePaths'];
assert(configuration.installation && Object.keys(configuration.installation)
  .every(key => sourceProfileKeys.includes(key)), 'Only original public installation configuration is accepted');
const failureData = (value, depth = 0) => {
  if (value === null || ['string','boolean','number'].includes(typeof value)) return value;
  if (depth >= 3 || value === undefined) return {omitted: typeof value};
  if (Array.isArray(value)) return value.slice(0,8).map(item => failureData(item,depth+1));
  if (typeof value !== 'object') return {omitted: typeof value};
  const fields = Object.getOwnPropertyDescriptors(value), output = {};
  for (const name of ['name','message','code','cleanupPending','cause','primaryFailure','errors']) {
    const field = fields[name];
    if (field && Object.hasOwn(field,'value')) output[name] = failureData(field.value,depth+1);
    else if (field) output[name] = {accessorNotInvoked:true};
  }
  return output;
};
let secretResolutions = 0, client, rejected = false, primary;
try {
  client = await connect({mode:'local',owner:'local',installation:{
    ...configuration.installation,connectorTable,
    async resolveSourceSecret() { secretResolutions++; return readFile(configuration.fixtureSecretPath,'utf8'); },
  }});
} catch (cause) { rejected = true; primary = cause; }
const publicFields = primary && typeof primary==='object' ? Object.getOwnPropertyDescriptors(primary) : {};
const handleField=publicFields.cleanupHandle;
const cleanupHandleObservation=handleField===undefined?{present:false}:Object.hasOwn(handleField,'value')?{present:true,type:typeof handleField.value,methodOrAuthorityNotInvoked:true}:{present:true,accessorNotInvoked:true};
const record = {cleanupHandleObservation,expectedConstructionRejectionObserved:rejected,clientReturned:client!==undefined,
  sourceSubmissions:0,publicCloseAttempted:false,publicCloseAcknowledged:false,
  knownOwnerNonacceptanceProved:false,secretResolutions,
  ...(rejected?{primary:failureData(primary)}:{})};
// Unexpectedly returned Client still gets its original FIRST close. No
// initialization rejection is ever re-labelled a public close ACK.
if (client) {
  record.publicCloseAttempted=true;
  try { await client.close(); record.publicCloseAcknowledged=true; }
  catch (cause) { record.firstCloseFailure=failureData(cause); }
}
record.fd = observeOwnScopedStateFds(configuration.stateRoots);
record.rootExistence = [];
for (const root of configuration.stateRoots) {
  try { record.rootExistence.push({root,exists:true,directory:(await lstat(root)).isDirectory()}); }
  catch (cause) { if(cause.code!=='ENOENT')throw cause;record.rootExistence.push({root,exists:false}); }
}
const existing = record.fd.observations.filter((_,i)=>record.rootExistence[i].exists);
record.createdScopesFd0 = existing.length>0 && existing.every(item=>item.exactEmpty);
record.absentScopesNotCountedAsFd0 = record.rootExistence.filter(item=>!item.exists).map(item=>item.root);
await writeFile(join(outputRoot,'construction-observation.json'),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
assert.equal(rejected,true,'Both valid profiles unexpectedly passed binding uniqueness');
assert.equal(client,undefined);
assert.equal(record.publicCloseAttempted,false);
assert.equal(secretResolutions,0);
// The exact expected duplicate-binding string is Source DATA supplied by
// the owning review, not a generic error/code whitelist or nonacceptance proof.
const oracle=JSON.parse(await readFile(configuration.constructionOraclePath,'utf8'));
assert.equal(typeof oracle.expectedDuplicateBindingMessage,'string');
assert(oracle.expectedDuplicateBindingMessage.length>0);
assert.equal(typeof oracle.expectedPublicWrapper,'string');
assert(oracle.expectedPublicWrapper.length>0);
assert.equal(record.primary?.code,oracle.expectedPublicWrapper,
  'The actual initialization wrapper code did not match the selected constructor oracle');
assert.equal(record.primary?.message,oracle.expectedPublicWrapper,
  'The actual initialization wrapper message did not match the selected constructor oracle');
assert.equal(Object.getOwnPropertyDescriptor(record.primary,'primaryFailure')?.value?.message,
  oracle.expectedDuplicateBindingMessage,
  'The original own primaryFailure did not expose the expected construction seam');
assert.equal(Object.getOwnPropertyDescriptor(record.primary,'cause')?.value?.message,
  oracle.expectedDuplicateBindingMessage,
  'The captured original cause did not expose the expected construction seam');
assert.equal(record.createdScopesFd0,true,'Created Source/Host scopes retain physical descriptors');
assert.notEqual(publicFields.cleanupPending?.value,true,'Construction failure retains pending cleanup');
await writeFile(join(outputRoot,'outcome.json'),JSON.stringify({passed:true,
  actualRejection:record.primary,noClientOrPublicClose:true,createdScopesFd0:true,
  allOriginalScopesFd0:record.fd.scopedStateFd0,absentScopesNotCountedAsFd0:record.absentScopesNotCountedAsFd0,
  noKnownNonacceptanceInference:true},null,2)+'\n',{flag:'wx'});
