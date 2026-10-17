import assert from 'node:assert/strict';
import test from 'node:test';
import * as provider from '../../../../_build/js/release/build/connectors/notion/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const bounds=[8192,512,16,8,8,64,64];
const databaseWire='{"object":"database","id":"db","data_sources":[{"id":"s","name":"tasks"}]}';
const sourceWire='{"object":"data_source","id":"s","parent":{"type":"database_id","database_id":"db"},"properties":{"amount":{"id":"num%3Ax","name":"amount","type":"number","number":{"format":"number"}},"é":{"id":"text","name":"é","type":"rich_text","rich_text":{}}}}';
const row='{"object":"page","id":"page","parent":{"type":"data_source_id","data_source_id":"s","database_id":"db"},"properties":{"amount":{"id":"num%3Ax","type":"number","number":9007199254740993.25},"é":{"id":"text","type":"rich_text","rich_text":[],"has_more":true}}}';
const page=(rows=row,cursor=null,more=false)=>'{"object":"list","type":"page_or_data_source","page_or_data_source":{},"results":['+rows+'],"has_more":'+more+',"next_cursor":'+JSON.stringify(cursor)+'}';
const source=()=>{
  const original=checked(provider.notionProjectDatabase(Buffer.from(databaseWire),...bounds));
  return checked(provider.notionProjectDataSource(original,0,Buffer.from(sourceWire),...bounds));
};
const project=(s,bytes,limits=bounds,rows=100,cursor=64)=>checked(provider.notionProjectQueryPage(s,bytes,...limits,rows,cursor));
const property=(p,row,index,max=128)=>checked(provider.notionQueryPropertyValueJson(p,row,index,max));

test('actual Notion query keeps the original schema and exact numeric bytes independently of external Buffer mutation',()=>{
  const original=source(),wire=page(),bytes=Buffer.from(wire),p=project(original,bytes);
  assert.equal(provider.notionQueryPageMatchesSource(p,original),true);
  assert.equal(provider.notionQueryPageMatchesSource(p,source()),false);
  assert.equal(property(p,0,0),'9007199254740993.25');
  assert.equal(property(p,0,1),'[]','inline data is retained, not promoted to complete rich text');
  assert.equal(checked(provider.notionQueryPageMetadataJson(p,128,10,4)),'{"ids":["page"],"nextCursor":null}');
  bytes.fill(0);
  assert.equal(property(p,0,0),'9007199254740993.25');
  assert.equal(checked(provider.notionQueryPageOriginalJson(p,Buffer.byteLength(wire))),wire);
  for(const [r,i] of [[-1,0],[1,0],[0,-1],[0,2]])assert.throws(()=>property(p,r,i),{code:'MoonBitHostFailure'});
  assert.throws(()=>property(p,0,0,18),{code:'MoonBitHostFailure'});
});

test('actual Notion query preserves null and cursors but refuses changed schemas foreign parents and nested sources',()=>{
  const original=source(),p=project(original,Buffer.from(page(row.replace('9007199254740993.25','null'),'next',true)));
  assert.equal(property(p,0,0),'null');
  assert.equal(checked(provider.notionQueryPageMetadataJson(p,128,10,4)),'{"ids":["page"],"nextCursor":"next"}');
  for(const wire of [page(row+','+row),page(row.replace('"data_source_id":"s"','"data_source_id":"foreign"')),
    page(row.replace('"id":"num%3Ax"','"id":"foreign"')),page(row.replace('"é":','"é":')),
    page(row.replace(',"number":9007199254740993.25','')),page(row,'',true),page(row,'next',false),
    page('{"object":"data_source","id":"nested"}'),'{"object":"error","status":403}']){
    assert.throws(()=>project(original,Buffer.from(wire)),{code:'MoonBitHostFailure'});
  }
});

test('actual Notion query input snapshot output and selection bounds fail without partial rows',()=>{
  const original=source(),bytes=Buffer.from(page()),p=project(original,bytes,[bytes.length,...bounds.slice(1)]);
  assert.throws(()=>project(original,bytes,[bytes.length-1,...bounds.slice(1)]),{code:'MoonBitHostFailure'});
  assert.throws(()=>project(original,bytes,bounds,0),{code:'MoonBitHostFailure'});
  assert.throws(()=>project(original,Buffer.from(page(row,'four',true)),bounds,100,3),{code:'MoonBitHostFailure'});
  for(const limits of [[128,1,4],[128,10,1],[1,10,4]]){
    assert.throws(()=>checked(provider.notionQueryPageMetadataJson(p,...limits)),{code:'MoonBitHostFailure'});
  }
  assert.throws(()=>checked(provider.notionQueryPageOriginalJson(p,bytes.length-1)),{code:'MoonBitHostFailure'});
  assert.throws(()=>project(original,Buffer.from([0xff,0x80])),{code:'MoonBitHostFailure'});
});
