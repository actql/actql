import assert from 'node:assert/strict';
import {hash} from '../../inventory.mjs';
import {boundCurrentOverlay,currentFixture} from './current-overlay.mjs';
import {checkParentCensus} from './bounds.mjs';
import {inspectCurrentChain} from './current-inspect.mjs';
import {inspectProviderConstruction} from './provider-construction.mjs';
import {checkPreparationArraySource,inspectPreparationStorage} from './preparation-arrays.mjs';
import {nativeProfile} from '../backing/source.mjs';
import {parseTestExecution} from '../../../../scripts/test-execution.mjs';
export function auditCurrentChain(report,current,read) {
  assert.equal(report.version,'actql-current-chain-native-diagnostic/0.1');
  assert.match(report.revision,/^[0-9a-f]{40}$/);
  assert.equal(report.unconditionalAllocationBytes,false,'Unsupported unconditional capacity guarantee');
  assert.equal(report.target,'native','Requested Native evidence belongs to another target');
  assert.equal(report.authority,'local-physical-finite-correspondence');
  assert.equal(report.reuseAuthorized,false);
  assert.equal(report.restored,true,'Source restoration not accepted');
  assert.equal(report.source.digest,hash(JSON.stringify(report.source.sources)));
  assert.deepEqual(report.source,current,'Stale or changed source');
  checkParentCensus(read);
  checkPreparationArraySource(read);
  const {overlay:overlays,boundary,buildIdentity}=boundCurrentOverlay(read,current);
  assert.deepEqual(report.boundary,boundary,'Changed compiled source boundary');
  assert.equal(report.buildIdentity,buildIdentity);
  assert.deepEqual(report.overlayDigests,Object.fromEntries(Object.entries(overlays).map(([p,t])=>[p,hash(t)])), 'Changed actual observation source');
  const expected=Object.fromEntries(Object.entries({...current.sources,...report.overlayDigests}).toSorted(([a],[b])=>a.localeCompare(b,'en')));
  assert.deepEqual(report.executedSource.sources,expected,'Different source executed');
  assert.equal(report.executedSource.digest,hash(JSON.stringify(report.executedSource.sources)));
  assert.deepEqual(report.command,['moon','test','--target','native',currentFixture,'--deny-warn']);
  assert.equal(report.exit,0);
  assert.equal(report.logPath,`.artifacts/relation-pipeline/current-chain-native/logs/${report.logDigest}.log`);
  const log=read(report.logPath).toString();assert.equal(hash(log),report.logDigest,'Detached actual Native log');
  const markers=log.split('\n').filter(l=>l.startsWith('ACTQL_CHAIN_BUILD:'));
  assert.deepEqual(markers,[`ACTQL_CHAIN_BUILD:${buildIdentity}`],'Executed fixture boundary differs');
  const parsed=parseTestExecution('moon',log);
  assert(parsed.success);assert.equal(parsed.counts.tests,1);assert.equal(parsed.counts.passed,1);assert.equal(parsed.counts.failed,0);
  const records=log.split('\n').filter(l=>l.startsWith('ACTQL_CHAIN_NATIVE:')).map(l=>JSON.parse(l.slice(19)));
  assert.deepEqual(report.records,records,'Facts differ from actual archived log');
  const prefix='ACTQL_PREPARATION_STORAGE:';
  const storageFacts=log.split('\n').filter(l=>l.startsWith(prefix)).map(l=>JSON.parse(l.slice(prefix.length)));
  assert.deepEqual(report.preparationStorageFacts,storageFacts,'Preparation facts differ from actual archived log');
  const preparationStorage=inspectPreparationStorage(storageFacts);
  const providerFacts=log.split('\n').filter(l=>l.startsWith('ACTQL_PIPELINE_FAULT:')).map(l=>JSON.parse(l.slice(21)));
  const provider=inspectProviderConstruction(providerFacts.filter(f=>f.kind==='provider construction observation'),read,'native');
  assert.equal(Object.keys(report.artifacts).length>0,true,'Missing actual executed binary');
  assert.deepEqual(Object.keys(report.artifacts).toSorted(),Object.keys(report.archives).toSorted());
  for(const [p,digest] of Object.entries(report.artifacts)) {
    assert(p.startsWith('_build/native/debug/test/connectors/local/'));
    assert.equal(hash(read(report.archives[p])),digest,'Executed binary changed');
  }
  const exe=report.archives['_build/native/debug/test/connectors/local/local.whitebox_test.exe'];assert(exe,'Missing actual Native whitebox executable');
  const binary=read(exe);
  const marker=Buffer.from(`ACTQL_CHAIN_BUILD:${buildIdentity}`,'utf16le');
  assert(binary.includes(marker),'Compiled fixture marker absent from executed binary');
  if(report.runtime.platform==='darwin-arm64') {assert.equal(binary.readUInt32LE(0),0xfeedfacf);assert.equal(binary.readUInt32LE(4),0x0100000c);}
  else {assert.equal(report.runtime.platform,'linux-x64');assert.equal(binary.subarray(0,4).toString('hex'),'7f454c46');assert.equal(binary[4],2);assert.equal(binary.readUInt16LE(18),62);}
  const pin=JSON.parse(read('toolchain.json'));assert.deepEqual(report.toolchain,pin);
  assert.deepEqual(report.runtime.archive,pin.archives[report.runtime.platform]);
  assert.deepEqual(report.runtime.sources,{...nativeProfile.sources,...nativeProfile.platformBinaries[report.runtime.platform]});
  assert.equal(report.runtime.profileDigest,hash(JSON.stringify(nativeProfile)));
  return {chain:inspectCurrentChain(records),providerConstruction:provider,preparationStorage,
    scientificExecution:'one fixed-source Native fixture; no new execution is inferred from this audit',
    completePhysicalUpper:false};
}
