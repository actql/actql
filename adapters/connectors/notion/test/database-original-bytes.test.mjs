import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {metadataDiscoveryFixture} from './installation-metadata-discovery.fixture.mjs';

const databaseWire=' \r\n{"extra":{"number":9007199254740993.25,"escaped":"\\u0061","unicode":"é😀"},'+
  '"object":"database","id":"db","data_sources":[{"name":"tasks","id":"s"}]}\n';
const sourceWire='\r\n{"extra":9007199254740993.25,"properties":{"text":{"id":"t","name":"text",'+
  '"type":"rich_text","rich_text":{}}},"parent":{"type":"database_id","database_id":"db"},'+
  '"id":"s","object":"data_source"} \n';
const declarationWire=' \r\n{"id":"db","read_contracts":{"t":[{"column":"text","projection":"value",'+
  '"contract":{"type":"string","nullable":false}}]}}\n';
const limits=[16384,1024,20,8,8,128,128];

function exactResponses(f){
  f.state.reply=(request,response)=>response.writeHead(200,{'content-type':'application/json'}).
    end(request.url==='/v1/databases/db'?databaseWire:sourceWire);
}

test('actual original database schema and declaration retain exact bytes through the same observed selection',async t=>{
  const f=await metadataDiscoveryFixture(t);exactResponses(f);
  await f.run(async x=>{
    const reader=x.reader(),result=await reader.read(),p=x.provider;
    assert.equal(checked(p.notionDatabaseOriginalJson(result.database,Buffer.byteLength(databaseWire))),databaseWire);
    assert.equal(checked(p.notionDataSourceOriginalJson(result.source,Buffer.byteLength(sourceWire))),sourceWire);
    assert.equal(checked(p.notionDatabaseReadDeclarationOriginalJson(result.declaration,Buffer.byteLength(declarationWire))),declarationWire);
    assert.equal(p.notionReadDatabaseDeclarationSourceCid(result.declaration),
      'sha256:'+createHash('sha256').update(declarationWire).digest('hex'));
    assert.equal(p.notionReadSourceSelectionMatches(result.selection,result.declaration,result.database),true);
    assert.equal(p.notionDataSourceMatchesDatabase(result.source,result.database),true);
    assert.equal(p.notionDataSourceReadMatches(result.readContracts,result.declaration,result.source),true);
    assert.deepEqual(result.responseCharges,f.state.charges);
    assert.equal(f.state.charges[0].originalBody.toString('utf8'),databaseWire);
    assert.equal(f.state.charges[1].originalBody.toString('utf8'),sourceWire);
    assert.deepEqual(f.state.requests.map(r=>r.path),['/v1/databases/db','/v1/data_sources/s']);
    assert.equal(reader.observe().cleanupConfirmed,false);
  });
});

test('actual metadata originals survive output exhaustion and caller-copy mutation without replacing the selected pair',async t=>{
  const f=await metadataDiscoveryFixture(t);exactResponses(f);
  await f.run(async x=>{
    const reader=x.reader(),result=await reader.read(),p=x.provider;
    for(const [fn,original,wire] of [[p.notionDatabaseOriginalJson,result.database,databaseWire],
      [p.notionDataSourceOriginalJson,result.source,sourceWire],
      [p.notionDatabaseReadDeclarationOriginalJson,result.declaration,declarationWire]]){
      for(const bound of [-1,Buffer.byteLength(wire)-1])assert.throws(()=>checked(fn(original,bound)));
      assert.equal(checked(fn(original,Buffer.byteLength(wire))),wire);
    }
    // Mutate only this new caller-owned copy, never the transport original or
    // its observation/charge aliases, which remain held by the physical reader.
    const copy=Buffer.from(f.state.charges[0].originalBody);
    const equalDatabase=checked(p.notionProjectDatabase(copy,...limits));copy.fill(0);
    assert.equal(checked(p.notionDatabaseOriginalJson(equalDatabase,Buffer.byteLength(databaseWire))),databaseWire);
    assert.equal(p.notionDataSourceMatchesDatabase(result.source,equalDatabase),false);
    assert.equal(p.notionReadSourceSelectionMatches(result.selection,result.declaration,equalDatabase),false);
    assert.equal(f.state.charges[0].originalBody.toString('utf8'),databaseWire);
    assert.equal(f.state.charges[1].originalBody.toString('utf8'),sourceWire);
    assert.deepEqual(result.responseCharges,f.state.charges);assert.equal(f.state.requests.length,2);
    assert.equal(reader.observe().cleanupConfirmed,false);
  });
});
