import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {publicWireLanguageVectors, wireConnection} from './fixtures/public-wire-language-vectors.mjs';

// Mutate real generated code, not the independent expected answers. Exact
// mutation sites identify compiler implementation changes, not facade syntax.
const source=await readFile(new URL('../packages/client-wire/client-host.generated.js',import.meta.url),'utf8');
const vector=name=>{const entry=publicWireLanguageVectors.find(entry=>entry.name===name);assert.ok(entry,name);return entry;};
const change=(source,before,after)=>{assert.ok(source.includes(before),'mutation site exists');return source.replaceAll(before,after);};
const mutations=[
 ['negative zero',' && !Object.is(value, -0)','', 'admission revision negative zero','validAdmissionContract'],
 ['integer range','Number.isSafeInteger(value)',"(typeof value === 'number')",'admission revision unsafe integer','validAdmissionContract'],
 ['integer type','Number.isSafeInteger(value)',"(typeof value === 'number')",'admission revision fraction','validAdmissionContract'],
 ['Unicode validity','!value.isWellFormed()','false','profile scope lone high surrogate','validProfileContract'],
 ['UTF-16 maximum','value.length > schema.maxLength','[...value].length > schema.maxLength','profile scope astral258','validProfileContract'],
 ['bool/int',"return typeof value === 'boolean'","return typeof value === 'boolean' || value === 0",'report boolean nullable rejects numeric zero','validCheckOutcomeContract'],
 ['NULL/omission',"return typeof value === 'string'","return value === null || typeof value === 'string'",'held optional field null','validHeldContract'],
 ['unknown variant','schema.oneOf && schema.oneOf.filter(rule => valid(value, rule)).length !== 1','false','report unknown variant','validCheckOutcomeContract'],
 ['correlation','value.requestId === expected','true','held wrong identity','validHeldContract'],
 ['old revision','value.outcome_schema_cid === checkOutcomeSchemaCid','true','report old outcome CID','validCheckOutcomeContract'],
 ['input revision','input.revision !== location.revision','false','report foreign input revision','validCheckOutcomeContract'],
];
for(const [name,before,after,probe,entryPoint] of mutations) test('JS vector kills '+name+' mutation',async()=>{
 const mutant=change(source,before,after);
 const wire=await import('data:text/javascript;base64,'+Buffer.from(mutant).toString('base64'));
 const entry=vector(probe);
 const actual=wire[entryPoint](JSON.parse(entry.valueJSON),entry.requestId ?? wireConnection);
 assert.equal(entry.expected,false);
 assert.equal(actual,true,'the mutant must expose the precise prohibited acceptance');
});
test('Python vectors kill codec, correlation, revision and Unicode mutations',()=>{
 const root=fileURLToPath(new URL('../',import.meta.url));
 const output=JSON.parse(execFileSync(process.env.ACTQL_PYTHON ?? 'python3',
  ['-I','scripts/fixtures/python-public-wire-mutations.py',root],{
   cwd:root,encoding:'utf8',timeout:10000,
   input:JSON.stringify(publicWireLanguageVectors),
  }));
 assert.equal(output.killed,10);
 assert.equal(output.survived,0);
});
