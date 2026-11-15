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
 const f=await boundConstructionActualFixture(t),phases=[];
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
  phases.push({phase:'initial-identity'});
  await f.load(source);phases.push({phase:'complete-source'});
  await f.load(effect);phases.push({phase:'complete-effect'});
  assert.deepEqual([source.exchanges(),effect.exchanges()],exchanges);
  assert.equal(f.secretReads(),0);assert.equal(f.sources.length,2);
  await f.close();assert.equal(f.pending(),false);assert.equal(f.retire(),true);
 }catch(error){failure=error;}
 t.diagnostic(JSON.stringify({passed:!failure,phases}));
 if(failure)throw failure;
});
