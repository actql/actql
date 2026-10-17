import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {metadataDiscoveryFixture} from './installation-metadata-discovery.fixture.mjs';

const readLimits=[16384,1024,20,8,8,128,128,256,16,4096,16,100000];
const snapshotLimits=[65536,8192,32];
const hash=bytes=>'sha256:'+createHash('sha256').update(bytes).digest('hex');
const restore=(p,bytes,cid)=>checked(p.notionReadDatabaseReadSnapshot(bytes,cid,...readLimits,...snapshotLimits));

// Explicit private fixture persistence, not a normal installed publication or
// an authenticated Run material issuer. The production codec has no file I/O.
test('actual observed Notion schema snapshot survives bounded cold data admission without metadata rediscovery',async t=>{
  const f=await metadataDiscoveryFixture(t);
  const saved=await f.run(async x=>{
    const reader=x.reader({systemColumns:true}),original=await reader.read(),p=x.provider;
    const snapshot=checked(p.notionCaptureDatabaseReadSnapshot(original.selection,original.source,original.readContracts,...snapshotLimits));
    assert.equal(p.notionDatabaseReadSnapshotMatches(snapshot,original.selection,original.source,original.readContracts),true);
    const wire=checked(p.notionDatabaseReadSnapshotWire(snapshot)),cid=checked(p.notionDatabaseReadSnapshotSourceCid(snapshot));
    assert.equal(hash(wire),cid);assert.equal(JSON.parse(wire).system_columns,true);
    const path=join(f.root,'saved-read-snapshot.json');await writeFile(path,wire,{mode:0o600});
    const restored=restore(p,await readFile(path),cid);
    assert.equal(checked(p.notionDatabaseReadSnapshotWire(restored)),wire);
    assert.equal(p.notionDatabaseReadSnapshotMatches(restored,original.selection,original.source,original.readContracts),false);
    const declaration=checked(p.notionDatabaseReadSnapshotDeclaration(restored));
    const source=checked(p.notionDatabaseReadSnapshotSource(restored));
    const contracts=checked(p.notionDatabaseReadSnapshotContracts(restored));
    assert.equal(p.notionDataSourceReadMatches(contracts,declaration,source),true);
    assert.equal(checked(p.notionDataSourceReadSchemaJson(contracts,...snapshotLimits)),original.schemaWire);
    assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(f.state.requests.length,2);
    return{path,cid,wire,schemaWire:original.schemaWire};
  });
  f.state.reply=()=>assert.fail('Saved DATA admission cannot discover current metadata');
  const provider=new URL('../../../../_build/js/release/build/connectors/notion/host_node/host_node.js',import.meta.url).href;
  const shim=new URL('../../../host-common/runtime-result.mjs',import.meta.url).href;
  const code=`import * as p from ${JSON.stringify(provider)};import{checked}from ${JSON.stringify(shim)};
    import{readFileSync}from'node:fs';const s=checked(p.notionReadDatabaseReadSnapshot(readFileSync(process.argv[1]),process.argv[2],...${JSON.stringify(readLimits)},...${JSON.stringify(snapshotLimits)}));
    const c=checked(p.notionDatabaseReadSnapshotContracts(s));console.log(JSON.stringify({wire:checked(p.notionDatabaseReadSnapshotWire(s)),schema:checked(p.notionDataSourceReadSchemaJson(c,...${JSON.stringify(snapshotLimits)}))}));`;
  const cold=JSON.parse(execFileSync(process.execPath,['--input-type=module','-e',code,saved.path,saved.cid],
    {encoding:'utf8',timeout:10000,maxBuffer:1024*1024}));
  assert.equal(cold.wire,saved.wire);assert.equal(cold.schema,saved.schemaWire);assert.equal(f.state.requests.length,2);
});

test('actual Notion saved material refuses substituted identity schema and flags while original custody remains',async t=>{
  const f=await metadataDiscoveryFixture(t);
  await f.run(async x=>{
    const reader=x.reader(),original=await reader.read(),p=x.provider;
    const snapshot=checked(p.notionCaptureDatabaseReadSnapshot(original.selection,original.source,original.readContracts,...snapshotLimits));
    const wire=checked(p.notionDatabaseReadSnapshotWire(snapshot)),cid=checked(p.notionDatabaseReadSnapshotSourceCid(snapshot));
    assert.throws(()=>restore(p,Buffer.from(' '+wire),cid));
    const body=JSON.parse(wire);
    for(const change of [{schema_wire:'{}'},{schema_cid:'sha256:'+'0'.repeat(64)},
      {system_columns:true},{system_columns:null},{version:'other'},{extra:true}]){
      const changed=Buffer.from(JSON.stringify({...body,...change}));
      assert.throws(()=>restore(p,changed,hash(changed)));
    }
    const copy=Buffer.from(wire),restored=restore(p,copy,cid);copy.fill(0);
    assert.equal(checked(p.notionDatabaseReadSnapshotWire(restored)),wire);
    assert.equal(checked(p.notionDatabaseReadSnapshotWire(snapshot)),wire);
    assert.equal(p.notionDataSourceReadMatches(original.readContracts,original.declaration,original.source),true);
    assert.deepEqual(original.responseCharges,f.state.charges);
    assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(f.state.requests.length,2);
  });
});
