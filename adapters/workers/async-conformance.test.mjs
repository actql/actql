import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {buildConformance} from './build.mjs';
import {createTestRuntime} from './runtime.mjs';
import {runAsyncCase} from './async-conformance.mjs';
import {checkWorkersArtifact,conformanceModules} from './artifact.mjs';

test('real planning fetch bypassing phase spies fails the common runtime audit even if caught', async () => {
  const bundle = await buildConformance();
  const needle = 'const scenario = audit.during("checking-lowering-installation",';
  assert.ok(bundle.source.includes(needle),'injection anchor must identify the actual preparation path');
  const normal = createTestRuntime(bundle.source);
  const options = {method:'POST',body:JSON.stringify({action:'async-probe',mode:'planning-io'})};
  let expected;
  try { expected = await (await normal.dispatchFetch('http://worker.test/',options)).json(); }
  finally { await normal.dispose(); }
  for (const caught of [false,true]) {
    const fetch = 'await fetch("https://must-not-resolve.invalid/")';
    const operation = caught ? `try { const denied = ${fetch}; if (!denied.ok) throw new Error("denied"); } catch {}` : `${fetch};`;
    const injected = bundle.source.replace(needle,`if (mode === "planning-io") await audit.during("planning", async () => { ${operation} });\n${needle}`);
    // No import changed: the separate runtime audit must catch ambient I/O.
    checkWorkersArtifact(bundle.metafile,injected,conformanceModules);
    const runtime = createTestRuntime(injected);
    try {
      const actual = await (await runtime.dispatchFetch('http://worker.test/',options)).json();
      assert.deepEqual(actual,expected);
      assert.equal(runtime.outboundAttempts,1);
    } finally { await assert.rejects(runtime.dispose(),{code:'UnexpectedOutbound'}); }
  }
});

const jsonValue = value => JSON.parse(JSON.stringify(value, (_, item) =>
  typeof item === 'bigint' ? item.toString() : item));
const cid = rows => 'sha256:' + createHash('sha256').update(JSON.stringify(rows)).digest('hex');
const zeroRetained = usage => {
  for (const key of ['reservedTransferBytes','heldBytes','reservedRetentionBytes','reservedExecutionBytes']) {
    assert.equal(usage[key],'0',key);
  }
};

test('asynchronous independent Connector preserves reservation completion and recovery in workerd', async () => {
  const {source} = await buildConformance();
  let outgoing = 0;
  const runtime = createTestRuntime(source, {onOutbound: () => outgoing++});
  try {
    for (const mode of ['complete','cancel','cancel-computed','cleanup-failure']) {
      const node = jsonValue(await runAsyncCase({mode}));
      const response = await runtime.dispatchFetch('http://worker.test/', {
        method:'POST',body:JSON.stringify({action:'async-probe',mode}),
      });
      assert.equal(response.status,200,await response.clone().text());
      const worker = await response.json();
      assert.deepEqual(worker,node,mode);
      assert.deepEqual(worker.violations,[]);
      assert.ok(worker.calls.every(call => ['execution','cleanup'].includes(call.phase)));
      // The independent numeric connector's configured capacity: 64 * 100
      // output units; scratch adds 2 * 10000 bytes + 64 * 30000 value nodes.
      assert.equal(worker.samples[0].usage.reservedRetentionBytes,'6400');
      assert.equal(worker.samples[0].usage.reservedExecutionBytes,'1946400');
      assert.equal(worker.samples[0].completed,false);
      zeroRetained(worker.finalUsage);
      if (mode === 'complete') {
        assert.equal(worker.status,'completed');
        assert.equal(worker.published,true);
        assert.equal(worker.samples[1].phase,'computed');
        assert.equal(worker.samples[1].completed,false);
        assert.deepEqual(worker.outputs,[cid([{id:3}]),cid([{id:3},{id:2}]),cid([{id:3}])]);
        assert.equal(worker.waits,6);
        assert.equal(worker.stops,3);
        assert.equal(worker.finalUsage.attempts,'3');
        assert.equal(worker.finalUsage.holdings,'3');
      } else {
        assert.equal(worker.status,'failed');
        assert.equal(worker.published,false);
        assert.equal(worker.finalUsage.attempts,'1');
        assert.equal(worker.finalUsage.holdings,'0');
        assert.equal(worker.waits,mode === 'cancel-computed' ? 2 : 1);
        assert.equal(worker.stops,mode === 'cleanup-failure' ? 2 : 1);
        assert.equal(worker.recovered,true);
        assert.equal(worker.finalUsage.planningWork,worker.beforeRecovery.planningWork);
      }
      if (mode === 'cleanup-failure') {
        assert.equal(worker.pending,true);
        assert.equal(worker.beforeRecovery.reservedRetentionBytes,'6400');
        assert.equal(worker.beforeRecovery.reservedExecutionBytes,'1946400');
      }
    }
    assert.equal(outgoing,0);
  } finally { await runtime.dispose(); }
});

test('injected planning-time port use is rejected before any attempt or physical work', async () => {
  const {source} = await buildConformance();
  const runtime = createTestRuntime(source);
  try {
    const response = await runtime.dispatchFetch('http://worker.test/', {
      method:'POST',body:JSON.stringify({action:'async-probe',mode:'planning-io'}),
    });
    const value = await response.json();
    assert.equal(value.status,'failed');
    assert.equal(value.published,false);
    assert.deepEqual(value.calls,[]);
    assert.deepEqual(value.violations,[{phase:'planning',kind:'execute',admitted:false}]);
    assert.equal(value.finalUsage.attempts,'0');
    assert.equal(value.waits,0);
    assert.equal(value.stops,0);
    zeroRetained(value.finalUsage);
  } finally { await runtime.dispose(); }
});

test('one asynchronous Run awaiting recovery does not invalidate another completed Run', async () => {
  const {source} = await buildConformance();
  const runtime = createTestRuntime(source);
  try {
    const response = await runtime.dispatchFetch('http://worker.test/', {
      method:'POST',body:JSON.stringify([
        {action:'async-probe',mode:'cleanup-failure'},
        {action:'async-probe',mode:'complete'},
      ]),
    });
    const [failed,completed] = await response.json();
    assert.equal(failed.status,'failed');
    assert.equal(failed.pending,true);
    assert.equal(failed.recovered,true);
    assert.equal(completed.status,'completed');
    assert.equal(completed.outputs[2],cid([{id:3}]));
    assert.equal(failed.finalUsage.attempts,'1');
    assert.equal(completed.finalUsage.attempts,'3');
    zeroRetained(failed.finalUsage);
    zeroRetained(completed.finalUsage);
  } finally { await runtime.dispose(); }
});
