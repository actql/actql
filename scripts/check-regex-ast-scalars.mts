import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {canonicalText,verifyIdentity} from './check-canonical-json.mjs';
import {checkRegexAstContract,schemaPath,contractPath} from './regex-ast-contract.mjs';
import {isDeepStrictEqual} from 'node:util';

type Schema = boolean | { $ref?: string; type?: string; const?: unknown; enum?: unknown[];
  oneOf?: Schema[]; not?: Schema; minimum?: number; maximum?: number; minLength?: number;
  pattern?: string; minItems?: number; items?: Schema; required?: string[];
  properties?: Record<string, Schema>; additionalProperties?: Schema };
type ContractInput = Parameters<typeof checkRegexAstContract>;
type ContractFixture = ReturnType<typeof import('./regex-ast-contract.mjs').regexAstContract>;
type Fixture = {id: string; ast: {root: unknown}; schema_valid: boolean} & (
  {semantic_valid: false; expected_cid?: never} |
  {semantic_valid: true; expected_preimage: string; expected_cid: string; expected_ast: string});
const read = <Value,>(path: string): Value => JSON.parse(readFileSync(path,'utf8'));
const schema=read<ContractInput[0] & Exclude<Schema, boolean> & {properties: Record<string, Schema>}>(schemaPath);
const contract=read<ContractFixture>(contractPath), expression=read<ContractInput[2]>('spec/contracts/actql-expressions.json');
checkRegexAstContract(schema,contract,expression);
const file='portability/corpus/regex-ast-scalars.json';
const corpus=read<{version: string; cases: Fixture[]}>(file);
assert.equal(corpus.version,'actql-regex-ast-scalar-vectors/0.1');
// Test-only interpreter for this schema's explicit keyword subset. This is not
// a general validator or a replacement for regex semantic admission.
const keywords=new Set(['$schema','$id','$defs','$ref','title','description','type','properties','additionalProperties','required','enum','const','oneOf','not','minimum','maximum','minLength','minItems','items']);
function valid(s: Schema,v: unknown): boolean {
  if(typeof s==='boolean') return s;
  for(const key of Object.keys(s)) assert.ok(keywords.has(key),'unsupported keyword '+key);
  if(s.$ref) {
    assert.ok(s.$ref.startsWith('#/'));
    const target=s.$ref.slice(2).split('/').reduce<unknown>((node,key)=>
      (node as Record<string, unknown>)[key],schema);
    if(!valid(target as Schema,v))return false;
  }
  const object=v!==null&&typeof v==='object'&&!Array.isArray(v);
  if(s.type) {
    const matches=s.type==='object'?object:s.type==='array'?Array.isArray(v):s.type==='integer'?Number.isInteger(v):s.type==='null'?v===null:typeof v===s.type;
    if(!matches)return false;
  }
  if(Object.hasOwn(s,'const')&&!isDeepStrictEqual(s.const,v))return false;
  if(s.enum&&!s.enum.some(x=>isDeepStrictEqual(x,v)))return false;
  if(s.oneOf&&s.oneOf.filter(x=>valid(x,v)).length!==1)return false;
  if(s.not&&valid(s.not,v))return false;
  if(typeof v==='number'&&(v<(s.minimum??-Infinity)||v>(s.maximum??Infinity)))return false;
  if(typeof v==='string'&&[...v].length<(s.minLength??0))return false;
  if(typeof v==='string'&&s.pattern&&!new RegExp(s.pattern,'u').test(v))return false;
  const items=s.items;
  if(Array.isArray(v)&&(v.length<(s.minItems??0)||(items&&!v.every(x=>valid(items,x)))))return false;
  if(object) {
    if(s.required?.some(k=>!Object.hasOwn(v,k)))return false;
    for(const [k,x] of Object.entries(v)) {
      const child=s.properties&&Object.hasOwn(s.properties,k)?s.properties[k]:s.additionalProperties??true;
      assert.ok(child !== undefined, `missing schema for ${k}`);
      if(!valid(child,x))return false;
    }
  }
  return true;
}
// Keep the identity field's grammar fixed as well as validating its pattern.
keywords.add('pattern');
assert.deepEqual(schema.properties.ast_cid,{type:'string',pattern:'^sha256:[a-f0-9]{64}$'});
const ids=new Set<string>();
for(const c of corpus.cases) {
  assert.ok(!ids.has(c.id));ids.add(c.id);
  assert.equal(valid(schema,{...c.ast,ast_cid:'sha256:'+'0'.repeat(64)}),c.schema_valid,c.id);
  if(!c.semantic_valid)continue;
  if(process.argv.includes('--write-identities')) {
    c.expected_preimage=canonicalText(c.ast);
    c.expected_cid='sha256:'+createHash('sha256').update(c.expected_preimage).digest('hex');
    c.expected_ast=canonicalText({...c.ast,ast_cid:c.expected_cid});
  }
  verifyIdentity(c.ast,c.expected_cid,c.expected_preimage);
  assert.equal(c.expected_ast,canonicalText({...c.ast,ast_cid:c.expected_cid}));
}
if(process.argv.includes('--write-identities'))writeFileSync(file,JSON.stringify(corpus,null,2)+'\n');
const byId=new Map(corpus.cases.map(c=>[c.id,c]));
function fixture(id: string) {
  const value=byId.get(id);
  assert.ok(value,id);
  return value;
}
assert.notEqual(fixture('cr').expected_cid,fixture('lf').expected_cid);
assert.notEqual(fixture('cr-range').expected_cid,fixture('lf-range').expected_cid);
assert.notEqual(fixture('sequence-crlf').expected_cid,fixture('sequence-lfcr').expected_cid);
assert.notEqual(fixture('cr').expected_cid,fixture('repeated-cr').expected_cid);
// Legacy string-valued ASTs remain rejected. The current String value law
// preserves CR/LF; demonstrate the historical collision with its old LF
// conversion explicitly, rather than requiring it from the current encoder.
const legacyCr=fixture('legacy-cr').ast as {root: {value: string}}, legacyLf=fixture('legacy-lf').ast;
assert.notEqual(canonicalText(legacyCr),canonicalText(legacyLf));
const formerlyNormalized=structuredClone(legacyCr);
formerlyNormalized.root.value=formerlyNormalized.root.value.replace(/\r\n?/gu,'\n');
assert.equal(canonicalText(formerlyNormalized),canonicalText(legacyLf));
const reversed=fixture('reversed-range').ast;
assert.equal(valid(schema,{...reversed,ast_cid:'sha256:'+'0'.repeat(64)}),true);
const [range]=(reversed.root as {items: {start: number; end: number}[]}).items;
assert.ok(range && range.start>range.end);
const changes: ((value: ContractFixture) => void)[]=[c=>{c.schema.cid='stale'},c=>{c.semantics.escapes.r=10}];
for(const change of changes) {
  const altered=structuredClone(contract);change(altered);
  assert.throws(()=>checkRegexAstContract(schema,altered,expression));
}
const stale=structuredClone(expression);stale.regex_ast_contract.cid='stale';
assert.throws(()=>checkRegexAstContract(schema,contract,stale));
const literal=(text: string)=>JSON.stringify(text);
const lines=['// Generated by scripts/check-regex-ast-scalars.mjs --write. Do not edit.'];
for(const c of corpus.cases) {
  if(!c.semantic_valid)continue;
  lines.push('', '///|', `test ${literal('regex scalar AST identity: '+c.id)} {`,
    `  let json = @json.parse(${literal(JSON.stringify(c.ast))})`,
    '  let value = @canonical_json.from_json(json, 10000, 100, 100000)',
    `  assert_eq(@canonical_json.stringify_value(value, 100000, 10000, 100), ${literal(c.expected_preimage)})`,
    `  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), ${literal(c.expected_cid)})`, '}');
}
const path='src/canonical_json/regex_ast_scalars.generated_test.mbt',text=lines.join('\n')+'\n';
if(process.argv.includes('--write'))writeFileSync(path,text);
else assert.equal(readFileSync(path,'utf8'),text,'stale scalar identity tests');
console.log(`${ids.size} regex AST scalar fixtures verified; identities do not certify parser or executor conformance.`);
