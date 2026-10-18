import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {checkNotionReadDeclarationSchema,notionReadDeclarationSchema,notionReadDeclarationsSchema} from './notion-read-contracts-schema.mjs';
import {project,structuralValidatorSource} from './generate-client-publication-wire.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
import {createHash} from 'node:crypto';

const protocol=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
const declaration={id:'db',data_source_id:'source',read_contracts:{'n%3Ax':[
  {column:'amount',projection:'value',contract:{type:'decimal',nullable:false,precision:20,scale:2}},
]}};

test('public database map reuses complete declaration grammar and rejects an invalid unused alias',async()=>{
  const schema=notionReadDeclarationsSchema(protocol);
  const {$schema,$defs,...declarationSchema}=notionReadDeclarationSchema(protocol);
  assert.deepEqual(schema.additionalProperties,declarationSchema);
  assert.deepEqual(schema.$defs,$defs);
  assert.deepEqual(schema.propertyNames,{type:'string',minLength:1});
  const { $defs:mapDefinitions, ...mapBody }=schema;
  assert.deepEqual(mapDefinitions,$defs);
  const projected={aliases:project(mapBody),value_contract:project($defs.value_contract)};
  const source='const schemas='+JSON.stringify(projected)+';\n'+
    structuralValidatorSource({extended:true})+'export const check=value=>valid(value,schemas.aliases);';
  const reader=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  for(const value of [{},{tasks:'db',accounts:declaration},{'é':'db','é':'db2'}])assert.equal(reader.check(value),true);
  for(const value of [null,[], 'db',{'':'db'},{tasks:'db',unused:null},
    {tasks:'db',unused:{id:'db2',read_contracts:{p:[{column:'x',projection:'value',contract:{type:'bad',nullable:false}}]}}}]){
    assert.equal(reader.check(value),false);
  }
  for(const change of [p=>delete p.schemas.notion_database_read_declarations.additionalProperties,
    p=>p.schemas.notion_database_read_declarations.propertyNames.minLength=0,
    p=>p.schema_cids.notion_database_read_declarations='sha256:'+'0'.repeat(64)]){
    const changed=structuredClone(protocol);change(changed);assert.throws(()=>checkNotionReadDeclarationSchema(changed));
  }
});

test('independent alias source vectors keep every original value span and spelling',()=>{
  const vectors=JSON.parse(readFileSync('spec/contracts/fixtures/notion-read-declarations-vectors.json','utf8')).vectors;
  const hash=text=>'sha256:'+createHash('sha256').update(text,'utf8').digest('hex');
  for(const vector of vectors){
    assert.equal(hash(vector.source),vector.sourceCid);
    const map=JSON.parse(vector.source);
    assert.deepEqual(Object.keys(map),vector.entries.map(x=>x.alias));
    for(const entry of vector.entries){
      assert.equal(hash(entry.source),entry.sourceCid);
      assert.deepEqual(JSON.parse(entry.source),map[entry.alias]);
      assert(vector.source.includes(entry.source));
      assert.notEqual(hash(entry.source+' '),entry.sourceCid);
    }
  }
  assert.notEqual(vectors[2].entries[0].alias,vectors[2].entries[1].alias);
  assert.notEqual(vectors[1].sourceCid,hash(JSON.stringify(JSON.parse(vectors[1].source))));
});

test('Notion structural declaration reuses the complete checked owner and registered pin',()=>{
  checkNotionReadDeclarationSchema(protocol);
  const schema=notionReadDeclarationSchema(protocol);
  assert.deepEqual(schema.$defs,protocol.schemas.canonical_value_contract.$defs);
  assert.deepEqual(schema.oneOf[1].properties.read_contracts.additionalProperties.items.properties.contract,
    {$ref:'#/$defs/value_contract'});
  for(const change of [p=>delete p.schemas.notion_database_read_declaration.oneOf[1].properties.read_contracts,
    p=>p.schemas.notion_database_read_declaration.oneOf[1].additionalProperties=true,
    p=>p.schemas.notion_database_read_declaration.$defs.value_contract.oneOf.pop(),
    p=>p.schema_cids.notion_database_read_declaration='sha256:'+'0'.repeat(64)]){
    const changed=structuredClone(protocol);change(changed);
    assert.throws(()=>checkNotionReadDeclarationSchema(changed));
  }
});

test('existing generated structural reader checks closed configuration without minting original evidence',async()=>{
  const {$defs,...body}=protocol.schemas.notion_database_read_declaration;
  const schemas={notion:project(body),value_contract:project($defs.value_contract)};
  const source='const schemas='+JSON.stringify(schemas)+';\n'+
    structuralValidatorSource({extended:true})+'export const check=value=>valid(value,schemas.notion);';
  const generated=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  for(const original of ['db',{id:'db'},{id:'db',unique:'key',marker:'marker'},declaration,
    {id:'db',read_contracts:{}},
    {id:'db',read_contracts:{date:[{column:'start',projection:'start',contract:{type:'date',nullable:false}},
      {column:'end',projection:'end',contract:{type:'date',nullable:true}}]}},
    {id:'db',read_contracts:{state:[{column:'state',projection:'value',contract:{type:'string',nullable:false,enum:[]}}]}}]){
    assert.equal(generated.check(original),true);
  }
  for(const original of ['',null,{}, {id:'db',data_source_id:null},{id:'db',extra:true},
    {id:'db',read_contracts:null}, {id:'db',read_contracts:{'':[]}},
    {id:'db',read_contracts:{n:[]}},
    {id:'db',read_contracts:{n:[...declaration.read_contracts['n%3Ax'],...declaration.read_contracts['n%3Ax'],...declaration.read_contracts['n%3Ax']]}},
    {id:'db',read_contracts:{n:[{column:'x',projection:'first',contract:{type:'string',nullable:false}}]}},
    {id:'db',read_contracts:{n:[{column:'x',projection:'value',contract:{type:'decimal',nullable:false,precision:0,scale:0}}]}},
    {id:'db',read_contracts:{n:[{column:'x',projection:'value',contract:{type:'string',nullable:false,enum:null}}]}},
    {id:'db',read_contracts:{n:[{column:'x',projection:'value',contract:{type:'string',nullable:false},grant:true}]}}]){
    assert.equal(generated.check(original),false,JSON.stringify(original));
  }
  // Matching role, property kind, complete schema, selected occurrence and
  // actual installation/configuration originals are Common/Host obligations.
});

test('independent declaration preimages preserve old absence and exact checked-contract vector identity',()=>{
  const vectors=JSON.parse(readFileSync('portability/corpus/notion-read-declaration-identities.json','utf8'));
  for(const item of vectors.values)verifyIdentity(item.declaration,item.bodyCid,item.canonicalPreimage);
  assert.equal(vectors.values[0].canonicalPreimage,'"db"');
  assert.equal(vectors.values[1].canonicalPreimage,'{"id":"db","marker":"marker","unique":"key"}');
  const original=vectors.values.find(x=>x.name==='ordered-text-constraints');
  for(const enumeration of [['low','medium'],['medium','low','low'],[]]){
    const changed=structuredClone(original.declaration);
    changed.read_contracts.s[0].contract.enum=enumeration;
    assert.throws(()=>verifyIdentity(changed,original.bodyCid,original.canonicalPreimage));
  }
});

test('saved Notion read snapshot pins a closed representation without admitting its embedded originals',async()=>{
  checkNotionReadDeclarationSchema(protocol);
  const schema=protocol.schemas.notion_database_read_snapshot;
  assert.deepEqual(schema.required,['database_response','declaration_source','schema_cid','schema_wire',
    'selected_data_source_response','system_columns','version']);
  assert.equal(schema.additionalProperties,false);
  const source='const schemas={snapshot:'+JSON.stringify(project(schema))+'};\n'+
    structuralValidatorSource({extended:true})+'export const check=value=>valid(value,schemas.snapshot);';
  const reader=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  const vectors=JSON.parse(readFileSync('spec/contracts/fixtures/notion-read-snapshot-vectors.json','utf8')).vectors;
  for(const original of vectors){
    assert.equal(reader.check(original.body),true);
    for(const changed of [{...original.body,extra:true},{...original.body,system_columns:null},
      {...original.body,version:'other'},{...original.body,schema_cid:'sha256:'+'A'.repeat(64)}]){
      assert.equal(reader.check(changed),false);
    }
    for(const key of schema.required){const changed={...original.body};delete changed[key];assert.equal(reader.check(changed),false);}
  }
  for(const alter of [p=>delete p.schemas.notion_database_read_snapshot.properties.system_columns,
    p=>p.schemas.notion_database_read_snapshot.additionalProperties=true,
    p=>p.schema_cids.notion_database_read_snapshot='sha256:'+'0'.repeat(64)]){
    const changed=structuredClone(protocol);alter(changed);assert.throws(()=>checkNotionReadDeclarationSchema(changed));
  }
});

test('independent saved snapshot vectors preserve exact original text and complete checked schema facts',()=>{
  const vectors=JSON.parse(readFileSync('spec/contracts/fixtures/notion-read-snapshot-vectors.json','utf8')).vectors;
  const canonical=value=>value&&typeof value==='object'?(Array.isArray(value)?'['+value.map(canonical).join(',')+']':
    '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}'):JSON.stringify(value);
  const hash=text=>'sha256:'+createHash('sha256').update(text,'utf8').digest('hex');
  for(const item of vectors){
    assert.equal(canonical(item.body),item.wire);assert.equal(hash(item.wire),item.source_cid);
    assert.equal(hash(item.body.schema_wire),item.body.schema_cid);
    const checked=JSON.parse(item.body.schema_wire);assert.equal(checked.additional_properties,false);
    assert.equal(Object.keys(checked.fields).length,item.body.system_columns?8:0);
    assert(item.body.database_response.includes('9007199254740993.25'));
    assert(item.body.database_response.includes('e\u0301😀'));assert(item.body.declaration_source.includes('\r\n'));
    for(const key of ['declaration_source','database_response','selected_data_source_response']){
      assert.notEqual(hash(canonical({...item.body,[key]:item.body[key]+' '})),item.source_cid);
    }
    assert.notEqual(hash(canonical({...item.body,system_columns:!item.body.system_columns})),item.source_cid);
  }
});
