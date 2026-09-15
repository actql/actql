import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {buildConformance} from './build.mjs';
import {createTestRuntime} from './runtime.mjs';
import {runCase, cancellationCase} from './conformance.mjs';

test('immediate and pending-preparation cancellation cannot start Local work on Node or workerd', async () => {
  const {source} = await buildConformance();
  const runtime = createTestRuntime(source);
  try {
    for (const waiting of [false,true]) {
      const node = JSON.parse(JSON.stringify(await cancellationCase(waiting),(_,v) => typeof v === 'bigint' ? String(v) : v));
      const response = await runtime.dispatchFetch('http://worker.test/', {
        method:'POST',body:JSON.stringify({action:'cancel-before-dispatch',waiting}),
      });
      const worker = await response.json();
      assert.deepEqual(worker,node);
      assert.equal(worker.failed,true);
      assert.equal(worker.consumed,0);
      assert.equal(worker.after[1],'0');
      assert.equal(worker.after[2],'0');
      assert.deepEqual(worker.after.slice(4),['0','0','0','0']);
      assert.equal(worker.cleanupPending,false);
      assert.equal(worker.prepared,waiting ? 1 : 0);
      assert.equal(worker.finished,waiting ? 2 : 0);
    }
  } finally { await runtime.dispose(); }
});

const cid = rows => 'sha256:' + createHash('sha256').update(JSON.stringify(rows)).digest('hex');
const cases = [
  {input:{rows:[{id:3},{id:1},{id:2}]}, outputs:[[{id:3}], [{id:3},{id:2}], [{id:3}]]},
  {input:{rows:[{id:4},{id:3},{id:4},{id:2}]}, outputs:[[{id:4},{id:3},{id:4}], [{id:4},{id:3},{id:4},{id:2}], [{id:4},{id:3},{id:4}]]},
  {input:{rows:[]}, outputs:[[],[],[]]},
  {input:{rows:[{id:null},{id:3},{id:null},{id:2}], nullable:true}, outputs:[[{id:3}],[{id:3},{id:2}],[{id:3}]]},
];

test('product checker through Local selection execution consumer and recovery agrees on Node and workerd', async t => {
  const bundle = await buildConformance();
  t.diagnostic(`bundled bytes: ${bundle.bytes}; resolved modules: ${Object.keys(bundle.metafile.inputs).length}`);
  let outgoing = 0;
  const runtime = createTestRuntime(bundle.source, {onOutbound: () => outgoing++});
  try {
    for (const {input,outputs} of cases) {
      const node = await runCase(input);
      const response = await runtime.dispatchFetch('http://worker.test/', {method:'POST', body:JSON.stringify(input)});
      assert.equal(response.status,200,await response.clone().text());
      const worker = await response.json();
      assert.equal(worker.status, 'completed');
      assert.deepEqual(worker.outputs, outputs.map((rows,i) => ({task:i+1,rows:rows.length,cid:cid(rows)})));
      assert.deepEqual(worker.outputs,node.outputs);
      assert.equal(worker.released,true);
      assert.deepEqual(worker.finalUsage.slice(4),['0','0','0','0']);
    }
    assert.equal(outgoing,0);
  } finally { await runtime.dispose(); }
});

test('physical hash seeds do not change logical output identity order or ledger accounting', async () => {
  const {source} = await buildConformance();
  const runtime = createTestRuntime(source);
  try {
    const input = {rows:[{id:4},{id:3},{id:4},{id:2}]};
    let baseline;
    for (const hashSeed of [0, 1, -2147483648, 2147483647]) {
      const response = await runtime.dispatchFetch('http://worker.test/', {
        method:'POST',body:JSON.stringify({...input,hashSeed}),
      });
      const worker = await response.json();
      assert.equal(worker.status,'completed');
      const observation = {outputs:worker.outputs, usage:worker.usage, finalUsage:worker.finalUsage};
      if (baseline) assert.deepEqual(observation,baseline);
      else baseline = observation;
      assert.deepEqual(worker.outputs, cases[1].outputs.map((rows,i) => ({task:i+1,rows:rows.length,cid:cid(rows)})));
    }
  } finally { await runtime.dispose(); }
});

test('same-isolate Runs retain independent outputs budgets and cancellation', async () => {
  const {source} = await buildConformance();
  const runtime = createTestRuntime(source);
  try {
    for (const failure of [{maxRows:0},{cancel:true},{consumeFailure:true}]) {
      const inputs = [{rows:[{id:3}],...failure},{rows:[{id:4}]}];
      const response = await runtime.dispatchFetch('http://worker.test/',{method:'POST',body:JSON.stringify(inputs)});
      const [failed,success] = await response.json();
      assert.equal(failed.status,'failed');
      assert.equal(failed.cleanupPending,false);
      assert.equal(failed.released,true);
      assert.equal(success.status,'completed');
      assert.equal(success.outputs[2].cid,cid([{id:4}]));
      assert.deepEqual(failed.finalUsage.slice(4),['0','0','0','0']);
      assert.deepEqual(success.finalUsage.slice(4),['0','0','0','0']);
    }
  } finally { await runtime.dispose(); }
});

test('same-runtime foreign Run dispatch is refused without consuming the rightful task', async () => {
  const {source} = await buildConformance();
  const runtime = createTestRuntime(source);
  try {
    const response = await runtime.dispatchFetch('http://worker.test/', {
      method:'POST',body:JSON.stringify({action:'foreign-dispatch'}),
    });
    assert.equal(response.status,200,await response.clone().text());
    assert.deepEqual(await response.json(),[true,true,true,true]);
  } finally { await runtime.dispose(); }
});

test('public checker rejects an undeclared field before Host installation or I/O', async () => {
  const {source} = await buildConformance();
  let outgoing = 0;
  const runtime = createTestRuntime(source, {onOutbound: () => outgoing++});
  try {
    const response = await runtime.dispatchFetch('http://worker.test/', {
      method:'POST',body:JSON.stringify({action:'invalid-program'}),
    });
    assert.equal(response.status,200,await response.clone().text());
    assert.equal(await response.json(),true);
    assert.equal(outgoing,0);
  } finally { await runtime.dispose(); }
});

test('semantic arithmetic failure row slot and expression span survive the Workers boundary', async () => {
  const {source} = await buildConformance();
  const runtime = createTestRuntime(source);
  try {
    for (const [rows,row] of [[[{id:3},{id:4}],0],[[{id:4},{id:3}],1]]) {
      for (const hashSeed of [0,73]) {
        const input = {rows,computeFilter:'10 / (id - 3) > 1',hashSeed};
        const node = await runCase(input);
        const response = await runtime.dispatchFetch('http://worker.test/',{
          method:'POST',body:JSON.stringify(input),
        });
        const worker = await response.json();
        assert.equal(worker.status,'failed');
        // Task A, step 0, earliest failing input row, scalar slot 0, division
        // expression byte range [0,13). This expectation is source-authored.
        assert.deepEqual(worker.arithmetic,[1,0,row,0,0,13]);
        assert.deepEqual(worker.arithmetic,node.arithmetic);
        assert.equal(worker.diagnostic,node.diagnostic);
        assert.equal(worker.cleanupPending,false);
        assert.deepEqual(worker.finalUsage.slice(4),['0','0','0','0']);
      }
    }
    const response = await runtime.dispatchFetch('http://worker.test/',{
      method:'POST',body:JSON.stringify({rows:[{id:3}],maxRows:0}),
    });
    const failed = await response.json();
    assert.equal(failed.diagnostic,'common-input-rows');
    assert.equal(failed.finalUsage[1],'0');
  } finally { await runtime.dispose(); }
});
