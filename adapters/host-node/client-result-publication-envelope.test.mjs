import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {open} from '../../packages/node/index.mjs';

// Boundaries formerly split between the common reservation owner and Node's
// independent 10-field/100-workspace publication defaults.
for (const [width,count,terms,aliases] of [
  [1,49,1,1],[1,50,1,1],[1,46,8,1],[1,47,8,1],
  [1,99,1,1],[1,100,1,1],[32,1,0,1],[1,1,0,10],
  [100,0,0,1],[100,1,0,1],[100,25,0,1],
]) {
  test(`checked publication envelope: ${width} fields, ${count} rows, ${terms} order terms, ${aliases} roots`,async()=>{
    const directory=await mkdtemp(join(tmpdir(),'actql-publication-envelope-'));
    const db=await open({stateDir:directory});
    try {
      const fields=Array.from({length:width},(_,i)=>`v${i}`);
      const rows=Array.from({length:count},(_,row)=>Object.fromEntries(fields.map((name,i)=>[name,row+i])));
      const program={version:'actql/0.1',id:'publication-envelope',stages:[{id:'main',inputs:{},
        steps:[{as:'v',values:{schema:Object.fromEntries(fields.map(name=>[name,{type:'number',nullable:false}])),rows}}],
        results:{rows:{from:'v',fields,...(terms?{order_by:Array.from({length:terms},()=>({v0:'asc'}))}:{})}}}],
        results:Object.fromEntries(Array.from({length:aliases},(_,i)=>[`answer${i}`,{from:{stage:'main',result:'rows'}}]))};
      const run=await db.start(program);
      assert.equal((await run.wait({signal:AbortSignal.timeout(20000)})).status,'succeeded');
      for(let i=0;i<aliases;i++)assert.deepEqual(await run.result(`answer${i}`).all(),rows);
    } finally {await db.close();await rm(directory,{recursive:true,force:true});}
  });
}

// These small programs formerly exhausted the shared metadata/wire reservation.
test('scalar capacity plan admits composed UNION and redundant Pipe stages', async()=>{
  const directory=await mkdtemp(join(tmpdir(),'actql-composition-envelope-'));
  const db=await open({stateDir:directory});
  try {
    for (const count of [4,5,6,7]) {
      const query=`SELECT x FROM (${Array.from({length:count},(_,i)=>`SELECT ${i+1} AS x`).join(' UNION ALL ')}) ORDER BY x`;
      assert.deepEqual(await db.sql(query).all(),Array.from({length:count},(_,i)=>({x:i+1})));
    }
    const prefix='FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) AS t |> WHERE x > 1 |> EXTEND x * 2 AS y';
    for (const count of [0,1,2,4]) {
      const query=prefix+Array(count).fill(' |> WHERE y >= 0').join('')+' |> ORDER BY y DESC |> LIMIT 1 |> SELECT y';
      assert.deepEqual(await db.aql(query).all(),[{y:6}]);
    }
  } finally {await db.close();await rm(directory,{recursive:true,force:true});}
});
