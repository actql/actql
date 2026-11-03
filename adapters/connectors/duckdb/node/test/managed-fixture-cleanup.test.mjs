import assert from 'node:assert/strict';
import test from 'node:test';
import {closeManagedFixtureExecution, managedFixtureCleanupDiagnostic} from './managed-fixture-cleanup.mjs';

function fixture(reason = new Error('LocalManagedOutputCleanupPending')) {
  let released = false, closes = 0, cleanups = 0;
  const handle = {status: () => ({pending: !released}),
    retry() { assert.fail('The fixture consumer must use the execution recovery owner'); }};
  const inner = Object.assign(new Error('ManagedExecutionFailed', {cause: reason}),
    {code: 'ManagedExecutionFailed', primaryFailure: reason,
      cleanupErrors: [], cleanupPending: true, cleanupHandle: handle});
  const failure = Object.assign(new Error('ManagedInputReleaseFailed', {cause: inner}),
    {code: 'ManagedInputReleaseFailed', primaryFailure: inner,
      cleanupErrors: [inner], cleanupPending: true, cleanupHandle: handle});
  const execution = {completed: [{task: 1}],
    usage: () => ({attempts: 4n, reservedExecutionBytes: released ? 0n : 128n}),
    async close() { closes++; throw failure; },
    async cleanup() {
      cleanups++;
      if (cleanups === 4) { released = true; inner.cleanupPending = false; }
      return released;
    }, cleanupPending: () => !released};
  return {execution, failure, counts: () => ({closes, cleanups})};
}

test('fixture cleanup retains its first bounded-pending error and uses only explicit recovery', async () => {
  const f = fixture();
  const result = await closeManagedFixtureExecution(f.execution, 60000);
  assert.equal(result.firstCloseFailure, f.failure);
  assert.equal(result.cleanupAttempts, 4);
  assert.deepEqual(f.counts(), {closes: 1, cleanups: 4});
  assert.equal(f.failure.cause.primaryFailure.message, 'LocalManagedOutputCleanupPending');
});

test('fixture cleanup rejects a physical exception hidden under the same outer classification', async () => {
  const f = fixture(new Error('PhysicalReleaseUnavailable'));
  await assert.rejects(closeManagedFixtureExecution(f.execution, 60000), error => {
    assert.equal(error.errors[0], f.failure);
    assert.equal(error.errors[1].code, 'ERR_ASSERTION');
    return true;
  });
  assert.deepEqual(f.counts(), {closes: 1, cleanups: 0});
});

test('fixture cleanup retains the original pending failure when explicit recovery rejects', async () => {
  const f = fixture(), recoveryFailure = new Error('RecoveryUnavailable');
  f.execution.cleanup = async () => { throw recoveryFailure; };
  await assert.rejects(closeManagedFixtureExecution(f.execution, 60000), error => {
    assert.deepEqual(error.errors, [f.failure, recoveryFailure]);
    return true;
  });
  assert.equal(f.execution.cleanupPending(), true);
  assert.equal(f.counts().closes, 1);
});

import {readFileSync} from 'node:fs';
import {retainFirstAndLatestCleanupError} from '../../../../host-common/managed-failure.mjs';
// The actual retained-chain caller body, not a second cleanup implementation.
// Only explicit original-child ports are supplied to this Source-bound unit.
function retainedChainCloseStep() {
  const source=readFileSync(new URL('./retained-values-chain.test.mjs',import.meta.url),'utf8');
  const start='      const child = ';
  assert.equal(source.split(start).length,2);
  const body=source.slice(source.indexOf(start),source.indexOf('    }, async () => {',source.indexOf(start)));
  const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
  return new AsyncFunction('owner','execution','assert','closeManagedFixtureExecution','retainFirstAndLatestCleanupError','state',
    `let executionCloseStarted=state.started;const cleanupErrors=state.errors??=[];try{${body}}finally{state.started=executionCloseStarted;}`);
}
test('retained chain connects its original child to the existing bounded cleanup consumer',async()=>{
  const f=fixture(),state={started:false};
  await retainedChainCloseStep()(undefined,f.execution,assert,closeManagedFixtureExecution,retainFirstAndLatestCleanupError,state);
  assert.equal(state.started,true);
  assert.deepEqual(f.counts(),{closes:1,cleanups:4});
  assert.equal(f.failure.cleanupHandle.status().pending,false);
  assert.deepEqual(state.errors,[f.failure]);
});

test('retained chain refuses a physical release exception without retiring or replacing its child',async()=>{
  const f=fixture(new Error('PhysicalReleaseUnavailable')),state={started:false};
  await assert.rejects(retainedChainCloseStep()(undefined,f.execution,assert,closeManagedFixtureExecution,retainFirstAndLatestCleanupError,state),error=>{
    assert.equal(error.errors[0],f.failure);assert.equal(error.errors[1].code,'ERR_ASSERTION');return true;
  });
  assert.equal(f.execution.cleanupPending(),true);assert.equal(state.started,true);
  assert.deepEqual(f.counts(),{closes:1,cleanups:0});
});
test('retained chain continuation never repeats failed close or treats pending cleanup as ACK',async()=>{
  const f=fixture(),state={started:false},failure=new Error('RecoveryUnavailable');
  const cleanup=f.execution.cleanup;let allow=false;
  f.execution.cleanup=async()=>{if(!allow)throw failure;return cleanup();};
  const step=()=>retainedChainCloseStep()(undefined,f.execution,assert,closeManagedFixtureExecution,retainFirstAndLatestCleanupError,state);
  await assert.rejects(step(),error=>{assert.deepEqual(error.errors,[f.failure,failure]);return true;});
  assert.equal(state.started,true);assert.deepEqual(f.counts(),{closes:1,cleanups:0});
  allow=true;
  for(let attempt=0;attempt<3;attempt++){await assert.rejects(step(),{code:'ERR_ASSERTION'});assert.equal(f.execution.cleanupPending(),true);}
  await step();assert.equal(f.execution.cleanupPending(),false);
  assert.deepEqual(f.counts(),{closes:1,cleanups:4});
});

test('fixture pending diagnostics retain closed codes without exposing primary values or invoking getters',()=>{
  const primary=Object.assign(new Error('raw rows must not print'),{code:'private-value',actual:'private-key'});
  const classified=Object.assign(new Error('arbitrary message'),{code:'ERR_ASSERTION'});
  assert.equal(managedFixtureCleanupDiagnostic(new AggregateError([primary,classified])), 'AggregateError/Error/ERR_ASSERTION');
  assert.equal(managedFixtureCleanupDiagnostic(undefined),'undefined/none/none');
  let reads=0;const accessor={get code(){reads++;throw Error('must not run');},get errors(){reads++;throw Error('must not run');}};
  assert.equal(managedFixtureCleanupDiagnostic(accessor),'opaque/none/none');assert.equal(reads,0);
  const proxy=new Proxy({}, {getOwnPropertyDescriptor(){throw undefined;}});
  assert.equal(managedFixtureCleanupDiagnostic(proxy),'opaque');
});
