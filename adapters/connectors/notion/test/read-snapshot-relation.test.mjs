import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {metadataDiscoveryFixture} from './installation-metadata-discovery.fixture.mjs';

const limits=[65536,8192,32];
const hash=wire=>'sha256:'+createHash('sha256').update(wire).digest('hex');

// The metadata fixture has actual Common/Account/Credential/SQLite/local TLS
// with explicit private issuer/material and response-ticket doubles. Restoring
// a declaration here is DATA admission, not a normal installed reader or grant.
test('actual saved database schema enters the existing Common row-source declaration without rediscovery',async t=>{
  const f=await metadataDiscoveryFixture(t);
  await f.run(async x=>{
    const reader=x.reader({systemColumns:true}),observed=await reader.read(),p=x.provider;
    const snapshot=checked(p.notionCaptureDatabaseReadSnapshot(observed.selection,observed.source,observed.readContracts,...limits));
    const specification=checked(p.notionDatabaseReadSnapshotRelationSpecification(snapshot,'tasks',...limits));
    const restore=expected=>checked(common.clientProgramRowSourceRestoreRelationDeclaration(
      'original-notion','notion','notion/0.1',specification,expected));
    const declaration=restore(undefined);
    const declared=JSON.parse(common.clientProgramRowSourceDeclarationJson(declaration));
    const repeated=JSON.parse(common.clientProgramRowSourceDeclarationJson(restore(declared.catalog_cid)));
    assert.deepEqual(repeated,declared);
    assert.equal(declared.views.length,1);assert.equal(declared.views[0].resource,'tasks');
    const originalSchema=JSON.parse(observed.schemaWire);
    const view=JSON.parse(specification).views[0];
    assert.deepEqual(JSON.parse(view.schema_wire),originalSchema.fields);
    assert.equal(view.schema_cid,hash(view.schema_wire));
    assert.notEqual(view.schema_cid,hash(observed.schemaWire));
    const carrier=declared.contracts.map(JSON.parse).find(value=>value.cid===declared.views[0].carrier_schema_cid);
    assert.deepEqual(carrier.body.fields,originalSchema.fields);
    assert.equal(Object.hasOwn(view,'facts_wire'),false);
    assert.equal(Object.hasOwn(view,'acquisition_wire'),false);
    assert.throws(()=>restore('sha256:'+'0'.repeat(64)));
    assert.equal(f.state.requests.length,2);
    assert.equal(reader.observe().cleanupConfirmed,false);
    assert.equal(checked(p.notionDatabaseReadSnapshotWire(snapshot)).length>0,true);
  });
});
