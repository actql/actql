import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';
import * as wire from '../packages/client-wire/index.mjs';
import {publicWireLanguageVectors, wireConnection} from './fixtures/public-wire-language-vectors.mjs';

export function jsWireVector(entry) {
  const value=JSON.parse(entry.valueJSON);
  switch(entry.operation) {
    case 'profile': return wire.validClientProfile(value,wireConnection);
    case 'admission': return wire.validClientAdmission(value,wireConnection);
    case 'run_ref': return wire.validRunRef(value);
    case 'lookup': return wire.validRequestLookup(value,entry.requestId);
    case 'held': return wire.validHeldRequest(value,entry.requestId);
    case 'cancellation': return wire.validCancellation(value,JSON.parse(entry.expectedJSON));
    case 'check_outcome': return wire.validCheckOutcome(value);
    default: throw Error('UnknownIndependentVector');
  }
}
for(const entry of publicWireLanguageVectors) test('JS public wire: '+entry.name,()=>{
  assert.equal(jsWireVector(entry),entry.expected);
});
let pythonResults;
function pythonVectorResults() {
 if(pythonResults) return pythonResults;
 const root=fileURLToPath(new URL('../',import.meta.url));
 pythonResults=JSON.parse(execFileSync(process.env.ACTQL_PYTHON ?? 'python3',
  ['-I','scripts/fixtures/python-public-wire-vectors.py',root],{
    cwd:root,encoding:'utf8',timeout:10000,
    input:JSON.stringify(publicWireLanguageVectors.map(entry=>({...entry,selected:wireConnection}))),
 }));
 assert.equal(pythonResults.length,publicWireLanguageVectors.length);
 return pythonResults;
}
for(const [index,entry] of publicWireLanguageVectors.entries()) test('Python Remote wire: '+entry.name,()=>{
 const result=pythonVectorResults()[index];
 assert.equal(result.name,entry.name);
 assert.equal(result.error,undefined,entry.name);
 assert.equal(result.actual,entry.expected,entry.name);
});
