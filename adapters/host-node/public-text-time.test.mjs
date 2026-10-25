import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {open} from '../../packages/node/index.mjs';

async function session(body) {
  const stateDir = await mkdtemp(join(tmpdir(), 'actql-public-text-time-'));
  let db = await open({stateDir});
  try { await body(db, async () => {
    await db.close(); db = await open({stateDir}); return db;
  }); } finally { await db.close(); await rm(stateDir, {recursive:true,force:true}); }
}
const scalar = (db, sql, parameters, options) => db.sql(sql, parameters, options).all();
const stringOptions = {parameterDeclarations: {s: {type:'string',nullable:false}}};

test('public Local String TRY_NUMBER executes all original fifteen conversion boundaries', async () => {
  await session(async db => {
    for (const [s, expected] of [['0',0],['12',12],['-12',-12],['1.5',1.5],['1e3',1000],
      ['01',null],['+1',null],[' 1',null],['1 ',null],['',null],['NaN',null],
      ['Infinity',null],['1e309',null],['-0',0],['0x10',null]]) {
      assert.deepEqual(await scalar(db,'SELECT TRY_NUMBER(@s) AS v',{s},stringOptions),
        [{v:expected}], JSON.stringify(s));
    }
  });
});

test('public Local pinned Unicode normalization executes all original twelve examples', async () => {
  await session(async db => {
    for (const [operation, examples] of [['NFKC', [['ＡＢＣ','ABC'],['ﬁ','fi'],['①','1'],
      ['é','é'],['Å','Å'],['😀','😀']]], ['CASE_FOLD', [['Straße','strasse'],['Σςσ','σσσ'],
      ['İ','i̇'],['K','k'],['é','é'],['😀','😀']]]]) {
      for (const [s, expected] of examples) {
        assert.deepEqual(await scalar(db,`SELECT ACTQL.${operation}(@s) AS v`,{s},stringOptions),
          [{v:expected}], operation+':'+s);
      }
    }
  });
});

test('text-time defaults preserve NULL, lazy demand, child failure and a usable Client', async () => {
  await session(async db => {
    for (const fn of ['TRY_NUMBER','ACTQL.NFKC','ACTQL.CASE_FOLD']) {
      assert.deepEqual(await scalar(db,`SELECT ${fn}(CAST(NULL AS STRING)) AS v`),[{v:null}]);
    }
    assert.deepEqual(await scalar(db,"SELECT IF(FALSE, TRY_NUMBER(CAST(1 / 0 AS STRING)), 7) AS v"),[{v:7}]);
    await assert.rejects(scalar(db,"SELECT TRY_NUMBER(CAST(1 / 0 AS STRING)) AS v"));
    await assert.rejects(scalar(db,'SELECT TRY_NUMBER(TRUE) AS v'));
    assert.deepEqual(await scalar(db,"SELECT TRY_NUMBER('9') AS v"),[{v:9}]);
  });
});

test('text-time installed bounds refuse excess input and persisted defaults reopen unchanged', async () => {
  await session(async (db,reopen) => {
    await assert.rejects(scalar(db,'SELECT TRY_NUMBER(@s) AS v',{s:'1'.repeat(4097)},
      {parameterDeclarations:{s:{type:'string',nullable:false}}}));
    assert.deepEqual(await scalar(db,"SELECT ACTQL.NFKC('Ａ') AS v"),[{v:'A'}]);
    db = await reopen();
    assert.deepEqual(await scalar(db,"SELECT TRY_NUMBER('2') AS v"),[{v:2}]);
    assert.deepEqual(await scalar(db,"SELECT ACTQL.CASE_FOLD('Straße') AS v"),[{v:'strasse'}]);
  });
});
