import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedSourceIdentity} from './installed-source.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
const describeWire = await readFile(new URL('../connectors/salesforce/test/fixtures/account-initialization-describe.json', import.meta.url), 'utf8');
assert.equal(Buffer.byteLength(describeWire), 251217);
const describeDocument = JSON.parse(describeWire);
assert.equal(describeDocument.fields.length, 71);
test('sanitized full Salesforce metadata prefix fits one original parent after native completion',async t=>{
 const events=[], f=await boundConstructionActualFixture(t,{capacityEvents:events}),phases=[];
 const source=await f.salesforceProfile('source',{describeDocument: describeWire});
 const sourceGeneration = JSON.parse(await readFile(source.value.publicationPath, 'utf8'));
 assert.equal(Buffer.from(sourceGeneration.evidence.describeBodyBase64[0], 'base64').toString('utf8'), describeWire,
  'the actual typed Catalog receives the complete independent fixed wire');
 const view=source.publication.declared.views[0];
 const body=source.publication.declared.source_views.map(JSON.parse).find(x=>x.contract_cid===view.view_cid);
 assert(body);
 source.value.queryAliases=[{name:'salesforce.accounts',sourceRef:view.source_ref,sourceViewContractCid:view.view_cid,schemaContractCid:body.output.schema.cid}];
 await writeFile(source.path,JSON.stringify(source.value));
 const effect=await f.salesforceProfile('effect',{describeDocument: describeWire});
 const exchanges=[source.exchanges(),effect.exchanges()];
 let failure;
 try{
  await installedSourceIdentity(source.path,{configurationReader:installedSourceConfigurationReader(f.services),moon:f.moon});
  phases.push({phase:'initial-identity',eventCount:events.length});
  await f.load(source);phases.push({phase:'complete-source',eventCount:events.length});
  await f.load(effect);phases.push({phase:'complete-effect',eventCount:events.length});
  assert.deepEqual([source.exchanges(),effect.exchanges()],exchanges);
  assert.equal(f.secretReads(),0);assert.equal(f.sources.length,2);
  assert(events.every(e=>e.accepted&&e.peak<=536870912n));
  await f.close();assert.equal(f.pending(),false);assert.equal(f.retire(),true);
 }catch(error){failure=error;}
 await writeFile('_build/salesforce-approval/public-prefix-component.json',JSON.stringify({scope:'public sanitized full metadata fixture, initial identity and Source+Effect on the real unchanged parent; no public Run or real Salesforce call',passed:!failure,phases,events},(_k,v)=>typeof v==='bigint'?v.toString():v,2)+'\n',{flag:'wx'});
 if(failure)throw failure;
});
