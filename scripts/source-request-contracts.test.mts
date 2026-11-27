import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {generateRoutes} from './catalog-reference-roles.mjs';
const protocol=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
test('SourceView request correlation keeps the explicit complete enum and tuple shape',()=>{
  const acquisition=protocol.schemas.source_view.properties.acquisition;
  assert.deepEqual([...acquisition.properties.kind.enum].sort(),['fetch','follow','scan','search']);
  const c=acquisition.properties.correlation;
  assert.equal(c.additionalProperties,false);
  assert.deepEqual([...c.required].sort(),['cardinality','identity','request_fields','response_fields']);
  assert.deepEqual([...c.properties.cardinality.enum].sort(),['one','one_or_many','zero_or_many','zero_or_one']);
  for(const name of ['request_fields','response_fields','identity']){
    const field=c.properties[name];
    assert.equal(field.type,'array');assert.equal(field.minItems,1);assert.equal(field.uniqueItems,true);
    assert.deepEqual(field.items,{type:'string',minLength:1});
  }
});
test('request and Carrier schema indexes have exactly one SourceView owner route',()=>{
  const lines=generateRoutes(protocol.schemas).output.split('\n');
  for(const [kind,first,second] of [['request_schema','acquisition','request_schema'],['carrier_schema','output','schema']]){
    const selected=lines.filter(x=>x.endsWith(`, "${kind}"),`)).map(x=>x.trim());
    assert.deepEqual(selected,[`ReferenceRoute(true, [RefField("${first}", true), RefField("${second}", true)], "${kind}"),`]);
  }
});
