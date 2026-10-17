import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const bounds=[8192,512,16,8,8,64,64];
const databaseWire='{"object":"database","id":"db","data_sources":[{"id":"s1","name":"same"},{"id":"s2","name":"same"}]}';
const sourceWire='{"object":"data_source","id":"s2","parent":{"type":"database_id","database_id":"db"},"properties":{"é":{"id":"title","name":"é","type":"title","title":{}},"é":{"id":"text","name":"é","type":"rich_text","rich_text":{}}}}';
const database=(body=databaseWire,limits=bounds)=>checked(provider.notionProjectDatabase(Buffer.from(body),...limits));
const source=(original,index=1,body=sourceWire,limits=bounds)=>checked(
  provider.notionProjectDataSource(original,index,Buffer.from(body),...limits));
const metadata=value=>checked(provider.notionDataSourceMetadataJson(value,4096,100,8));

test('Notion actual database inventory and explicitly selected schema preserve original Unicode names',()=>{
  const original=database(),selected=source(original);
  assert.equal(checked(provider.notionDatabaseMetadataJson(original,4096,100,8)),
    '{"databaseId":"db","dataSources":[{"id":"s1","name":"same"},{"id":"s2","name":"same"}]}');
  assert.equal(metadata(selected),
    '{"databaseId":"db","dataSourceId":"s2","properties":[{"id":"title","name":"é","type":"title"},{"id":"text","name":"é","type":"rich_text"}]}');
  assert.equal(provider.notionDataSourceMatchesDatabase(selected,original),true);
  assert.equal(provider.notionDataSourceMatchesDatabase(selected,database()),false);
});

test('Notion actual foreign schema selection malformed responses and unselected definitions refuse',()=>{
  const original=database();
  for(const index of [-1,0,2]) assert.throws(()=>source(original,index),{code:'MoonBitHostFailure'});
  for(const body of [sourceWire.replace('"database_id":"db"','"database_id":"foreign"'),
    sourceWire.replace('"name":"é"','"name":"renamed"'),
    sourceWire.replace('"id":"text"','"id":"title"'),
    sourceWire.replace('"rich_text":{}','"rich_text":null'),
    '{"object":"error","status":403}',sourceWire+'{}']){
    assert.throws(()=>source(original,1,body),{code:'MoonBitHostFailure'});
  }
  assert.throws(()=>checked(provider.notionProjectDatabase(Buffer.from([0xff]),...bounds)),{code:'MoonBitHostFailure'});
});

test('Notion actual metadata input and writer boundaries are exact without partial output',()=>{
  const original=database(),selected=source(original),wire=metadata(selected);
  assert.equal(checked(provider.notionDataSourceMetadataJson(selected,Buffer.byteLength(wire),100,8)),wire);
  for(const [bytes,nodes,depth] of [[Buffer.byteLength(wire)-1,100,8],[4096,1,8],[4096,100,1]]){
    assert.throws(()=>checked(provider.notionDataSourceMetadataJson(selected,bytes,nodes,depth)),{code:'MoonBitHostFailure'});
  }
  for(const [index,value] of [[0,Buffer.byteLength(databaseWire)-1],[1,1],[2,1],[3,1],[5,1],[6,3]]){
    const limits=[...bounds];limits[index]=value;
    assert.throws(()=>database(databaseWire,limits),{code:'MoonBitHostFailure'});
  }
  const limits=[...bounds];limits[4]=1;
  assert.throws(()=>source(original,1,sourceWire,limits),{code:'MoonBitHostFailure'});
});
