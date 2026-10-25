import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {open} from '../../packages/node/index.mjs';

// Expected rows are independent scalar/bag calculations, not engine snapshots.
test('source-free scalar compositions use checked value capacity without changing semantics', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'actql-relational-composition-'));
  const db = await open({stateDir});
  try {
    assert.deepEqual(await db.sql('SELECT x FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) ORDER BY x LIMIT 1 OFFSET 1').all(), [{x: 2}]);
    assert.deepEqual(await db.sql('SELECT x, COUNT(*) AS n FROM (SELECT 1 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) GROUP BY x HAVING COUNT(*) > 1').all(), [{x: 1, n: 2}]);
    assert.deepEqual(await db.aql('FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) AS t |> WHERE x > 1 |> EXTEND x * 2 AS y |> ORDER BY y DESC |> LIMIT 1 |> SELECT y').all(), [{y: 6}]);
    assert.deepEqual(await db.sql('SELECT x, b FROM (SELECT CAST(NULL AS NUMBER) AS x, TRUE AS b UNION ALL SELECT 2 AS x, CAST(NULL AS BOOLEAN) AS b UNION ALL SELECT 1 AS x, FALSE AS b) ORDER BY x NULLS LAST').all(), [{x: 1, b: false}, {x: 2, b: null}, {x: null, b: true}]);
    assert.deepEqual(await db.sql("SELECT 'wide fallback' AS s").all(), [{s: 'wide fallback'}]);
    assert.deepEqual(await db.sql('SELECT 1 AS healthy').all(), [{healthy: 1}]);
  } finally {
    await db.close();
    await rm(stateDir, {recursive: true, force: true});
  }
});

test('scalar capacity counts row containers, both join ports, repeated ports and cumulative steps', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'actql-relational-capacity-'));
  const db = await open({stateDir});
  const type = {type: 'number', nullable: false};
  async function execute(steps, expected) {
    const program = {version: 'actql/0.1', id: 'scalar-capacity', stages: [{id: 'main', inputs: {}, steps,
      results: {rows: {from: steps.at(-1).as, fields: ['k']}}}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
    const run = await db.start(program);
    const state = await run.wait({signal: AbortSignal.timeout(20000)});
    assert.equal(state.status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), expected);
  }
  try {
    for (const n of [50, 51, 100]) {
      const rows = Array.from({length: n}, (_, k) => ({k}));
      const values = {as: 'l', values: {schema: {k: type}, rows}};
      await execute([values], rows);
      await execute([values, {as: 'f', from: 'l', filter: 'k >= 0'},
        {as: 'd', from: 'f', derive: {m: 'k + 1'}},
        {as: 's', from: 'd', select: ['k']}], rows);
    }
    for (const n of [25, 26, 49, 50]) {
      const rows = Array.from({length: n}, (_, k) => ({k}));
      const left = {as: 'l', values: {schema: {k: type}, rows}};
      const right = {as: 'r', values: {schema: {k: type}, rows}};
      const joinStep = withName => ({as: 'j', from: 'l', join: {with: withName, kind: 'inner',
        on: [{left: 'k', right: 'k'}], max_output_rows: 100, select: {k: 'left.k'}}});
      await execute([left, right, joinStep('r')], rows);
      await execute([left, joinStep('l')], rows);
    }
  } finally {
    await db.close();
    await rm(stateDir, {recursive: true, force: true});
  }
});

const type={type:'number',nullable:false};
function cleanupJoinFixture(n,duplicate=false,composed=false){
 const left=Array.from({length:n},(_,i)=>({k:duplicate?Math.floor(i/2):i,v:i+1}));
 const right=Array.from({length:n},(_,i)=>({k:duplicate?Math.floor(i/2):i,v:i*2+3}));
 const steps=[{as:'l',values:{schema:{k:type,v:type},rows:left}}, {as:'r',values:{schema:{k:type,v:type},rows:right}},
  {as:'j',from:'l',join:{with:'r',kind:'inner',on:[{left:'k',right:'k'}],max_output_rows:duplicate?2*n:n,select:{k:'left.k',lv:'left.v',rv:'right.v'}}}];
 const index=new Map();for(const r of right){const bucket=index.get(r.k)??[];bucket.push(r);index.set(r.k,bucket);}
 let expected=[];for(const l of left)for(const r of index.get(l.k)??[])expected.push({k:l.k,lv:l.v,rv:r.v});
 if(composed){steps.push({as:'f',from:'j',filter:'k % 3 = 0'},{as:'d',from:'f',derive:{g:'k % 7',total:'lv + rv'}},{as:'a',from:'d',group:{by:['g'],aggregates:{n:{fn:'count'},s:{fn:'sum',field:'total'}}}},{as:'o',from:'a',sort:[{field:'s',dir:'desc',nulls:'last'},{field:'g',dir:'asc',nulls:'last'}]});
 const groups=new Map();for(const row of expected)if(row.k%3===0){const g=row.k%7;const a=groups.get(g)??{g,n:0,s:0};a.n++;a.s+=row.lv+row.rv;groups.set(g,a);}expected=[...groups.values()].sort((a,b)=>b.s-a.s||a.g-b.g);
 } else {steps.push({as:'o',from:'j',sort:[{field:'k',dir:'asc',nulls:'last'},{field:'lv',dir:'asc',nulls:'last'},{field:'rv',dir:'asc',nulls:'last'}]});expected.sort((a,b)=>a.k-b.k||a.lv-b.lv||a.rv-b.rv);}
 return {expected,program:{version:'actql/0.1',id:'join-scale',stages:[{id:'main',inputs:{},steps,results:{rows:{from:'o',fields:Object.keys(expected[0]??{k:0,lv:0,rv:0})}}}],results:{answer:{from:{stage:'main',result:'rows'}}}}};
}

// Regression: the 32-row duplicate join produces 64 rows, crossing the
// original completed-output scratch retirement quantum before grouping.
for (const n of [31,32,50]) test(`completed JOIN scratch retirement preserves composed result: ${n}`, async () => {
  const stateDir=await mkdtemp(join(tmpdir(),'actql-join-retirement-'));
  let db=await open({stateDir});
  const {program,expected}=cleanupJoinFixture(n,true,true);
  try {
    const run=await db.start(program);
    const status=await run.wait({signal:AbortSignal.timeout(20000)});
    assert.equal(status.status,'succeeded');
    assert.deepEqual(await run.result('answer').all(),expected);
    assert.equal((await run.status()).control.physical_stop,'confirmed');
    const ref=run.ref;
    await db.close();db=await open({stateDir});
    const attached=await db.attach(ref);
    assert.deepEqual(await attached.result('answer').all(),expected);
  } finally {await db.close();await rm(stateDir,{recursive:true,force:true});}
});
