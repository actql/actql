import assert from 'node:assert/strict';
import test from 'node:test';
import {metadataDiscoveryFixture} from './installation-metadata-discovery.fixture.mjs';

test('actual Notion pre-schema discovery consumes one original Host metadata Subject without a fake Program Run',async t=>{
  const f=await metadataDiscoveryFixture(t);
  await f.run(async original=>{
    const reader=original.reader(),result=await reader.read();
    assert.equal(result.declaration,original.declaration);
    assert.equal(original.provider.notionReadSourceSelectionMatches(result.selection,result.declaration,result.database),true);
    assert.equal(original.provider.notionDataSourceReadMatches(result.readContracts,result.declaration,result.source),true);
    assert.deepEqual(f.state.requests.map(x=>[x.method,x.path]),[['GET','/v1/databases/db'],['GET','/v1/data_sources/s']]);
    assert.equal(f.state.requests.every(x=>x.originalMaterial&&x.version==='2026-03-11'),true);
    assert.deepEqual(result.responseCharges,f.state.charges);assert.equal(f.state.observations.length,2);
    assert.equal(reader.observe().cleanupConfirmed,false);
    const subject=original.control.subjectFields();assert.equal(Object.keys(subject).length,11);
    assert.equal(subject.declarationSourceCid,original.provider.notionReadDatabaseDeclarationSourceCid(original.declaration));
    assert.equal(Object.hasOwn(subject,'runInvocationCid'),false);assert.equal(Object.hasOwn(subject,'taskAttempt'),false);
    assert.equal(f.journal.recover().filter(x=>x.outcome==='succeeded').length,2);
  });
});
