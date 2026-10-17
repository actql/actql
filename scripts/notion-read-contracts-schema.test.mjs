import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {checkNotionReadDeclarationSchema,notionReadDeclarationSchema} from './notion-read-contracts-schema.mjs';
import {project,structuralValidatorSource} from './generate-client-publication-wire.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';

const protocol=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
const declaration={id:'db',data_source_id:'source',read_contracts:{'n%3Ax':[
  {column:'amount',projection:'value',contract:{type:'decimal',nullable:false,precision:20,scale:2}},
]}};

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
