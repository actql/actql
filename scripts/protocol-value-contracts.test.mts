import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {valueBodyContract,generateValueKinds,commandInputPresenceBody,commandInputPresenceSchemas,textEnumerationBody,signed64Body} from './protocol-value-contracts.mjs';
import {byteValuesBody} from './byte-values-contract.mjs';
type Protocol = Parameters<typeof valueBodyContract>[0] & Parameters<typeof commandInputPresenceSchemas>[0] & {
  artifact_schemas: Record<string, unknown>;
};
type Arm = Protocol['schemas']['canonical_value_contract']['$defs']['value_contract']['oneOf'][number];
type TraversedNode = {type?: string; required?: string[];
  properties?: {type?: {const?: string; enum?: string[]}; nullable?: unknown; enum?: unknown}};
type ValuesBody = {params_schema: {$defs: {value_contract: {oneOf: unknown[]}}};
  semantics: {byte_values?: string; text_enumeration: string};
  dependencies: {canonical_value_contract: {cid: string}}};
type ValuesPreimage = {body: ValuesBody; cid: string; canonicalPreimage: string};
type TextCorpus = {checkedTextContracts: {contract: unknown; proposedContractCid: string; canonicalPreimage: string}[];
  valuesExecution: ValuesPreimage};
type Generated = {check(value: unknown): boolean};

const protocol: Protocol=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8'));
test('all eight legacy value roles use the checked grammar, never the carrier grammar',()=>{
  const body=valueBodyContract(protocol);
  assert.deepEqual(body.kinds,['request_schema','command_input','command_output','idempotency_key','checkpoint',
    'lookup_request_key','lookup_batch_request','lookup_response_key']);
  assert.equal(body.schema.pointer,'/schemas/canonical_value_contract');
  assert.ok(!body.kinds.includes('carrier_schema'));
  assert.equal((generateValueKinds(protocol).match(/"/g)??[]).length,18);
  assert.ok(generateValueKinds(protocol).includes(JSON.stringify(body.schema.cid)));
});
test('added, missing and repeated envelope kinds cannot bypass grammar routing',()=>{
  for(const mutate of [xs=>xs.push('new_role'),xs=>xs.pop(),xs=>xs.push(xs[0])] satisfies ((xs: string[]) => unknown)[]){
    const changed=structuredClone(protocol);mutate(changed.schemas.contract_envelope.properties.kind.enum);
    assert.throws(()=>valueBodyContract(changed));
  }
});
test('Command presence has one closed domain-specific record and unchanged child grammar',()=>{
  const presence=commandInputPresenceBody(protocol);
  const schema=presence.schema;
  assert.equal(schema.additionalProperties,false);
  assert.deepEqual(schema.required,['additional_properties','fields','required_fields']);
  assert.deepEqual(Object.keys(schema.properties),schema.required);
  assert.deepEqual(schema.properties.additional_properties,{const:false});
  assert.deepEqual(schema.properties.fields.additionalProperties,{$ref:'#/$defs/value_contract'});
  assert.deepEqual(schema.$defs,protocol.schemas.canonical_value_contract.$defs);
  assert.equal(schema.properties.required_fields.uniqueItems,true);
  assert.equal((schema.properties.required_fields as typeof schema.properties.required_fields & {minItems?: number}).minItems,
    undefined,'empty required subset remains legal');
  assert.match(presence.correspondence,/same_original_command_catalog_environment/);
  assert.match(presence.required_fields,/preserve_exact_array_order/);
  assert.deepEqual(valueBodyContract(protocol).command_input_presence,presence);
  commandInputPresenceSchemas(protocol);
  for(const mutate of [p=>delete p.schemas.command_contract.properties.input_contract.properties.required_fields,
    p=>p.schemas.connector_catalog.$defs.command_contract.properties.input_contract.properties.required_fields={type:'array'},
  ] satisfies ((p: Protocol) => unknown)[]){
    const drift=structuredClone(protocol);mutate(drift);assert.throws(()=>commandInputPresenceSchemas(drift));
  }
  assert.equal((protocol.schemas.canonical_value_contract.$defs.value_contract.oneOf.find(
    value=>value.properties?.type?.const==='object')!.properties as Arm['properties'] & {required_fields?: unknown}).required_fields,
    undefined);
});

test('Text enum retains empty and repeated vectors in every current registered type entrance',()=>{
  const body=textEnumerationBody(protocol);
  assert.deepEqual(body.grammar,{type:'array',items:{type:'string'}});
  assert.match(body.join_qualification,/conservative_common_supertype/);
  let count=0;
  const visit=(value: unknown): void=>{
    if(!value||typeof value!=='object')return;
    const kind=(value as TraversedNode).properties?.type;
    if((value as TraversedNode).type==='object'&&(value as TraversedNode).properties?.nullable&&
      (kind?.const==='string'||kind?.enum?.includes('string'))){
      assert.deepEqual((value as TraversedNode).properties!.enum,body.grammar,'current Text entrance must retain constraint grammar');
      assert.equal((value as TraversedNode).required!.includes('enum'),false);
      count++;
    }
    for(const child of Object.values(value))visit(child);
  };
  visit(protocol.schemas);visit(protocol.artifact_schemas);
  assert.ok(count>0,'actual registered entrances inspected');
  for(const name of ['author_value_contract','canonical_value_contract'] as const){
    for(const change of [branch=>delete branch.properties.enum,
      branch=>(branch.properties.enum as {uniqueItems?: boolean}).uniqueItems=true,
      branch=>(branch.properties.enum as {minItems?: number}).minItems=1,
      branch=>branch.required.push('enum')] satisfies ((branch: Arm) => unknown)[]){
      const changed=structuredClone(protocol);
      change(changed.schemas[name].$defs.value_contract.oneOf.find(branch=>branch.properties?.type?.const==='string')!);
      assert.throws(()=>textEnumerationBody(changed));
    }
  }
});

test('actual generated structural type validator keeps enum shape without claiming value membership',async()=>{
  const {project,structuralValidatorSource}=await import('./generate-client-publication-wire.mjs');
  const schema=project(protocol.schemas.canonical_value_contract.$defs.value_contract);
  const source='const schemas={value_contract:'+JSON.stringify(schema)+'};\n'+
    structuralValidatorSource({extended:true})+'export const check=value=>valid(value,schemas.value_contract);';
  const generated: Generated=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  for(const enumeration of [[],['low','medium','high'],['high','low','high']]){
    const original={type:'string',nullable:false,enum:enumeration};
    assert.equal(generated.check(original),true);
    assert.deepEqual(original.enum,enumeration,'no source normalization');
  }
  assert.equal(generated.check({type:'string',nullable:false}),true,'old absence');
  for(const original of [
    {type:'string',nullable:false,enum:null},
    {type:'string',nullable:false,enum:['low',null]},
    {type:'string',nullable:false,enum:[1]},
    {type:'string',nullable:false,enum:['low'],default:'low'},
    {type:'number',nullable:false,enum:['1']},
  ])assert.equal(generated.check(original),false);
  // This checks the shipped structural declaration route only. Common must
  // still check Unicode, actual membership, extents and original value custody.
});

test('original Text enum vectors and the Values dependency retain independently authored preimages',async()=>{
  const {verifyIdentity}=await import('./check-canonical-json.mjs');
  const vectors: TextCorpus=JSON.parse(readFileSync('portability/corpus/text-enumeration-identities.json','utf8'));
  const ids=[];
  for(const value of vectors.checkedTextContracts){
    verifyIdentity(value.contract,value.proposedContractCid,value.canonicalPreimage);
    ids.push(value.proposedContractCid);
  }
  assert.equal(new Set(ids).size,ids.length,'absence/order/repetitions/empty preserve distinct originals');
  const aoa: {execution_contracts: {'REL.values': ValuesBody}}=JSON.parse(readFileSync('spec/contracts/actql-aoa.json','utf8'));
  const previous=vectors.valuesExecution;
  verifyIdentity(previous.body,previous.cid,previous.canonicalPreimage);
  const expected=(JSON.parse(readFileSync('portability/corpus/signed64-identities.json','utf8')) as
    {valuesExecution: ValuesPreimage}).valuesExecution;
  verifyIdentity(expected.body,expected.cid,expected.canonicalPreimage);
  const current = structuredClone(expected.body);
  const bytes = byteValuesBody(protocol);
  current.params_schema.$defs.value_contract.oneOf.push(bytes.grammar);
  current.semantics.byte_values = bytes.wire.pattern;
  current.dependencies.canonical_value_contract.cid = valueBodyContract(protocol).schema.cid;
  assert.deepEqual(aoa.execution_contracts['REL.values'],current);
  assert.equal(expected.body.semantics.text_enumeration,previous.body.semantics.text_enumeration);
  assert.deepEqual(expected.body.params_schema.$defs.value_contract.oneOf.slice(0,-1),
    previous.body.params_schema.$defs.value_contract.oneOf);
});


test('signed64 has one closed distinct initial contract without Decimal or Number constraints',()=>{
  const body=signed64Body(protocol);
  assert.deepEqual(body.domain,{minimum:'-9223372036854775808',maximum:'9223372036854775807'});
  assert.match(body.identity,/distinct_complete_checked_int64/);
  assert.match(body.operations,/no_implicit_arithmetic_overload/);
  assert.deepEqual(valueBodyContract(protocol).signed64,body);
  for(const name of ['author_value_contract','canonical_value_contract'] as const){
    for(const mutate of [
      branches=>branches.pop(),
      branches=>branches.push(structuredClone(branches.at(-1)!)),
      branches=>branches.at(-1)!.properties.type!.const='decimal',
      branches=>(branches.at(-1)!.properties as {precision?: {const: number}}).precision={const:19},
      branches=>(branches.at(-1)!.properties as {minimum?: {const: number}}).minimum={const:0},
      branches=>(branches.at(-1)!.properties as {nullable?: {const: boolean}}).nullable={const:false},
    ] satisfies ((branches: Arm[]) => unknown)[]){
      const changed=structuredClone(protocol);
      const definition=changed.schemas[name].$defs.value_contract;
      const signed64=definition.oneOf.filter(branch=>branch.properties.type!.const==='int64');
      assert.equal(signed64.length,1);
      mutate(signed64);
      definition.oneOf=definition.oneOf.filter(branch=>branch.properties.type!.const!=='int64').concat(signed64);
      assert.throws(()=>signed64Body(changed));
    }
  }
});

test('generated structural type validation preserves signed64 schema without claiming value admission',async()=>{
  const {project,structuralValidatorSource}=await import('./generate-client-publication-wire.mjs');
  const schema=project(protocol.schemas.canonical_value_contract.$defs.value_contract);
  const source='const schemas={value_contract:'+JSON.stringify(schema)+'};\n'+
    structuralValidatorSource({extended:true})+'export const check=value=>valid(value,schemas.value_contract);';
  const generated: Generated=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  for(const nullable of [false,true]){
    const contract={type:'int64',nullable};assert.equal(generated.check(contract),true);
    assert.equal(generated.check({type:'array',nullable:false,items:contract}),true);
    for(const extra of [{precision:19,scale:0},{minimum:0},{enum:['1']},{max_utf8_bytes:20},{default:'1'}])
      assert.equal(generated.check({...contract,...extra}),false);
  }
  for(const input of [{type:'int64'},{type:'Int64',nullable:false},{type:'int64',nullable:null}])
    assert.equal(generated.check(input),false);
});

test('BYTES wire admits only canonical padded Base64 with zero unused bits', () => {
  const body = byteValuesBody(protocol);
  assert.deepEqual(valueBodyContract(protocol).bytes, body);
  const validWire = new RegExp(body.wire.pattern, 'u');
  for (const accepted of ['', 'Zg==', 'Zm8=', 'AP+A', '/w==', 'AP8=']) {
    assert.equal(validWire.test(accepted), true, accepted);
  }
  for (const refused of ['Zh==', 'Zm9=', 'Zg', 'Zg=', 'Zg===', 'Zg==Zg==', '_w==', 'Zg==\n']) {
    assert.equal(validWire.test(refused), false, refused);
  }
});
