import test from 'node:test';
import assert from 'node:assert/strict';
import {clientSourceFormats, validClientBody, snapshotClientRequest} from './index.mjs';
const connection = {mode:'remote', owner:'remote', consentRefs:[], runners:[]};
test('public aql format preserves the authored check and submit source', () => {
  assert.ok(clientSourceFormats.includes('aql'));
  const input={text:'SELECT @p AS id',format:'aql',parameterDeclarations:{p:{type:'number',nullable:false}}};
  const submit={connection,kind:'aql',requestId:'original-aql',input,parameters:{p:1}};
  assert.equal(validClientBody('submit',submit),true);
  assert.equal(validClientBody('check',{connection,kind:'text',scope:'bound_input',input,parameters:{p:1}}),true);
  assert.deepEqual(snapshotClientRequest(submit),submit);
  // The new spelling is neither autodetection nor a rewrite of saved sources.
  const legacy={...submit,input:{...input,format:'aql-text'}};
  assert.equal(validClientBody('submit',legacy),true);
  assert.equal(snapshotClientRequest(legacy).input.format,'aql-text');
  assert.equal(validClientBody('submit',{...submit,input:{...input,format:'aql2'}}),false);
  assert.equal(validClientBody('submit',{...submit,input:{...input,parameterDeclarations:[]}}),false);
});
