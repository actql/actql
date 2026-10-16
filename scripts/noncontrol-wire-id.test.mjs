import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';
import {wireNonControlIdPattern} from './client-wire-scalar-rules.mjs';
import {publicWireLanguageVectors} from './fixtures/public-wire-language-vectors.mjs';

const registry=JSON.parse(await readFile(new URL('../spec/contracts/actql-client-host.json',import.meta.url)));
const vectors=publicWireLanguageVectors.filter(entry=>entry.name.startsWith('Run non-control '))
 .map(entry=>({value:JSON.parse(entry.valueJSON).namespaceId,expected:entry.expected}));
const selected=[];
function collect(value,path='') {
 if(value===null || typeof value!=='object')return;
 if(typeof value.pattern==='string' && value.pattern.startsWith('^[^\\u0000-\\u001f\\u007f]+'))selected.push({path,pattern:value.pattern});
 for(const [key,child] of Object.entries(value))collect(child,path+'/'+key);
}
collect(registry);
test('registered source schemas express absolute whole-string identifiers',()=>{
 assert.ok(selected.length>0);
 assert.ok(vectors.length>100);
 for(const {path,pattern} of selected) {
  assert.equal(pattern,wireNonControlIdPattern,path);
  for(const {value,expected} of vectors)assert.equal(new RegExp(pattern,'u').test(value),expected,path+': '+JSON.stringify(value));
 }
});
test('generic Python schema-pattern search obeys the same absolute end',()=>{
 // Exercise the source pattern itself, not a product-only exception or fullmatch.
 const output=JSON.parse(execFileSync(process.env.ACTQL_PYTHON ?? 'python3',['-B','-c',
  'import json,re,sys\np=json.load(sys.stdin)\nprint(json.dumps([re.search(p["pattern"],v["value"]) is not None for v in p["vectors"]]))'],
 {input:JSON.stringify({pattern:wireNonControlIdPattern,vectors}),encoding:'utf8',timeout:10000}));
 assert.deepEqual(output,vectors.map(entry=>entry.expected));
});
