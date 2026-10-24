import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {open} from '../../packages/node/index.mjs';

function program(expr) {
  return {version:'actql/0.1',id:'null-context',stages:[{id:'main',inputs:{},steps:[
    {as:'seed',values:{schema:{n:{type:'number',nullable:false}},rows:[{n:1}]}},
    {from:'seed',derive:{v:expr},as:'computed'}],results:{rows:{from:'computed',fields:['v']}}}],
  results:{answer:{from:{stage:'main',result:'rows'}}}};
}
test('immediate NULL comparisons and predicates and signed source zero execute through Local', async () => {
  const directory=await mkdtemp(join(tmpdir(),'actql-null-context-'));
  const client=await open({stateDir:directory});
  try {
    for (const [expression,value] of [
      ['NULL = 1',null],['NULL < 1',null],['NULL IS NULL',true],['NULL IS NOT NULL',false],
      ['-0.0',0],['1 = NULL',null],['NULL <> 1',null],['NULL >= 1',null],
      ['0e10',0],['0e-10',0],['-0e10',0],['+0E0',0],['0e99999',0],
      ['-(+0)',0],['-(-0.0)',0],['NULL IS DISTINCT FROM 1',true],
    ]) assert.deepEqual(await client.sql(`SELECT ${expression} AS v`).all(),[{v:value}],expression);
    for(const operation of ['eq','lt']) {
      const run=await client.start(program({[operation]:[{literal:null},{literal:1}]}));
      assert.equal((await run.wait()).status,'succeeded');
      assert.deepEqual(await run.result('answer').all(),[{v:null}]);
    }
    // NULL must not suppress demanded failures or resolve an unknown name/domain.
    await assert.rejects(client.sql('SELECT NULL = 1 / 0 AS v').all());
    await assert.rejects(client.sql('SELECT NULL = missing AS v').all());
    for (const token of ['0e','0e+','0e--1','1e999']) {
      await assert.rejects(client.sql(`SELECT ${token} AS v`).all());
    }
    await assert.rejects(client.sql('SELECT NULL = NULL AS v').all());
    assert.deepEqual(await client.sql('SELECT 7 AS v').all(),[{v:7}]);
  } finally {await client.close();await rm(directory,{recursive:true,force:true});}
});
