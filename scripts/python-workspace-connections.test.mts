// Cross-language checks use independent literal vectors, not generated answers.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {parseConnectionString,connectionStringCredential} from '../packages/sdk/connection-string.mjs';
const python=process.env.ACTQL_PYTHON??'python3';
const code="import sys,json;sys.path[:0]=['packages/python-sdk/src','packages/python-sdk/tests'];from test_connection_string import VALID,INVALID;print(json.dumps({'valid':VALID,'invalid':INVALID}))";
const vectors=JSON.parse(execFileSync(python,['-I','-B','-c',code],{encoding:'utf8',timeout:10000}));

test('independent Python/JS Workspace targets and credential spelling agree',async t=>{
  for(const [index,[input,endpoint,workspaceId,credential]] of vectors.valid.entries())
    await t.test(`accepted original vector ${index}`,()=>{
      const parsed=parseConnectionString(input);
      assert.deepEqual(parsed,{endpoint,workspaceId});
      assert.equal(connectionStringCredential(parsed)??null,credential);
    });
});
test('independent closed URI refusals precede target and credential projection',async t=>{
  for(const [index,input] of vectors.invalid.entries())await t.test(`refused original vector ${index}`,()=>{
    assert.throws(()=>parseConnectionString(input),{message:'InvalidConnectionString'});
  });
});
