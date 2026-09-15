import test from 'node:test';
import assert from 'node:assert/strict';
import {phaseAudit} from './phase-audit.mjs';

test('all external-work ports are denied during pure phases even with a claimed grant', () => {
  for (const phase of ['checking','lowering','planning']) {
    for (const kind of ['acquire','store','transfer','provision','execute']) {
      const audit = phaseAudit();
      let actual = 0;
      assert.throws(() => audit.during(phase,() => audit.perform(kind,true,() => actual++)),
        /UnpermittedPhaseIO/);
      assert.equal(actual,0);
      assert.deepEqual(audit.calls,[]);
      assert.deepEqual(audit.violations,[{phase,kind,admitted:true}]);
    }
  }
});

test('per-Run spies track asynchronous admitted work without sharing phases', async () => {
  const a = phaseAudit(), b = phaseAudit();
  let actual = 0;
  await Promise.all([
    a.during('execution',async () => {
      await Promise.resolve();
      a.perform('execute',true,() => actual++);
      assert.throws(() => a.perform('transfer',false,() => actual++),/UnpermittedPhaseIO/);
    }),
    b.during('planning',async () => {
      await Promise.resolve();
      assert.throws(() => b.perform('acquire',true,() => actual++),/UnpermittedPhaseIO/);
    }),
  ]);
  assert.equal(actual,1);
  assert.deepEqual(a.calls,[{phase:'execution',kind:'execute'}]);
  assert.deepEqual(b.calls,[]);
  assert.throws(() => a.perform('execute',true,() => actual++),/UnpermittedPhaseIO/);
});
