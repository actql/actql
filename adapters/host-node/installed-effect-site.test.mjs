import assert from 'node:assert/strict';
import test from 'node:test';
import './effect-cleanup-composition.test.mjs';
import './effect-authorization-cleanup.test.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
import {acquisitionFailure} from '../host-common/acquisition-outcome.mjs';
import {checkedEffectPreparation as checked} from
  '../host-common/effect-preparation-result.mjs';
import {checked as checkedRuntime} from '../host-common/runtime-result.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

for (const kind of ['checked', 'unclassified-checked', 'transport', 'lookalike']) {
  test(`Preview preparation ${kind} keeps its outcome and cleanup distinct`,
    async () => {
      const ref = {runDefinitionCid: cid('b')};
      const observations = [];
      let computes = 0;
      let cleanups = 0;
      let pending = true;
      let failure;
      const execution = {async close() {}, async cleanup() {
        if (++cleanups === 1) return false;
        pending = false;
        return true;
      }, cleanupPending: () => pending};
      const site = createInstalledEffectSite({environmentWire: '{}',
        prepareCaptured() {
          try {
            if (kind === 'checked') checked({$tag: 0, _0: 'InvalidTarget'});
            if (kind === 'unclassified-checked') {
              checkedRuntime({$tag: 0, _0: 'IncompleteObservation'});
            }
            throw Object.assign(new Error('ObservationUnavailable'), {
              code: kind === 'lookalike' ? 'MoonBitHostFailure' : 'EIO'});
          } catch (error) { failure = error; throw error; }
        },
        prepareRecovered() { assert.fail('No automatic recovery'); }});
      const dispatch = installNodeClientDispatchOwner({});
      await assert.rejects(dispatch.track(ref, {
        observeStopped: value => observations.push(value),
        run: context => site.execute({...context,
          openComputation() { computes++; return {execution, checkedHost: {}}; },
        }),
      }), error => error === failure);
      assert.deepEqual(observations, []);
      assert.notEqual(dispatch.operation(ref), undefined);
      await dispatch.drain();
      assert.deepEqual(observations, [kind === 'checked' ? 'failed' : null]);
      assert.equal(dispatch.operation(ref), undefined);
      assert.equal(computes, 1);
      assert.equal(cleanups, 2);
    });
}

for (const outcome of ['not_started', 'stopped', 'unknown']) {
  test(`Effect acquisition ${outcome} failure observes outcome after cleanup`,
    async () => {
      const ref = {runDefinitionCid: cid('b')};
      const observations = [];
      let opens = 0;
      let cleanups = 0;
      let pending = true;
      const primary = new Error('SourceReadUnavailable');
      const recovery = {async close() {}, async cleanup() {
        cleanups++;
        if (cleanups === 1) return false;
        pending = false;
        return true;
      }, cleanupPending: () => pending};
      const site = createInstalledEffectSite({environmentWire: '{}',
        prepareCaptured() { assert.fail('No Preview or Effect may begin'); },
        prepareRecovered() { assert.fail('No automatic reexecution'); }});
      const dispatch = installNodeClientDispatchOwner({});
      await assert.rejects(dispatch.track(ref, {
        observeStopped: value => observations.push(value),
        run: context => site.execute({...context,
          openComputation: ({retainComputationOwner}) =>
            openAcquiredEffectComputation({acquired: {prepared: {}},
              moon: {clientProgramEffectAcquisitionCount: () => 1},
              now: () => '2026-09-29T00:00:00.000Z',
              retainComputationOwner,
              sourceProfile: {prepare() { return {}; }, open() {
                opens++;
                throw acquisitionFailure(primary, outcome,
                  outcome === 'unknown' ? recovery : undefined);
              }}}),
        }),
      }), error => error.cause === primary);
      assert.deepEqual(observations, outcome === 'unknown' ? [] : ['failed']);
      if (outcome === 'unknown') assert.notEqual(dispatch.operation(ref), undefined);
      await dispatch.drain();
      assert.deepEqual(observations, ['failed']);
      assert.equal(dispatch.operation(ref), undefined);
      assert.equal(opens, 1);
      assert.equal(cleanups, outcome === 'unknown' ? 2 : 0);
    });
}

test('Effect opening transfers physical custody before it can fail',
  async () => {
    let retained;
    let opens = 0;
    let cleanups = 0;
    let pending = true;
    const physical = {async close() {}, async cleanup() {
      cleanups++;
      if (cleanups === 1) return false;
      pending = false;
      return true;
    }, cleanupPending: () => pending};
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured() { assert.fail('No completed computation'); },
      prepareRecovered() { assert.fail('No automatic recovery'); }});
    await assert.rejects(site.execute({
      retainExecution(value) { retained = value; },
      async openComputation({retainComputationOwner}) {
        opens++;
        assert.equal(retained.cleanupPending(), true);
        retainComputationOwner(physical);
        throw new Error('SourceEvidenceUnavailable');
      },
    }), {message: 'SourceEvidenceUnavailable'});
    await retained.close();
    assert.equal(await retained.cleanup(), false);
    assert.equal(retained.cleanupPending(), true);
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    assert.equal(opens, 1);
  });

test('Effect opening without a physical owner cannot claim cleanup completed',
  async () => {
    let retained;
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured() { assert.fail('No completed computation'); },
      prepareRecovered() { assert.fail('No automatic recovery'); }});
    await assert.rejects(site.execute({
      retainExecution(value) { retained = value; },
      async openComputation() { throw new Error('UnobservedPhysicalStop'); },
    }), {message: 'UnobservedPhysicalStop'});
    await retained.close();
    assert.equal(await retained.cleanup(), false);
    assert.equal(retained.cleanupPending(), true);
  });

test('installed Effect retains Compute before provider capture can fail',
  async () => {
    const execution = {async close() {}, async cleanup() { return true; },
      cleanupPending: () => false};
    let opened = 0;
    let retained;
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured() {
        assert.equal(typeof retained?.cleanup, 'function');
        throw new Error('CaptureFailed');
      }, prepareRecovered() {
        assert.fail('Recovery cannot run during first capture');
      }});
    await assert.rejects(site.execute({signal: undefined,
      openComputation: async () => { opened++; return {execution,
        checkedHost: {}}; },
      retainExecution: owner => { retained = owner; }}),
    {message: 'CaptureFailed'});
    assert.equal(opened, 1);
    assert.equal(await retained.cleanup(), true);
  });

test('installed Effect custody retries provider cleanup without Compute',
  async () => {
    let opened = 0;
    let disposeCalls = 0;
    let retained;
    const execution = {async close() {}, async cleanup() { return true; },
      cleanupPending: () => false};
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured() {
        return {dispose() {
          disposeCalls++;
          if (disposeCalls === 1) throw new Error('DisposeUnavailable');
        }};
      }, prepareRecovered() {
        assert.fail('No recovery in a failed first capture');
      }});
    await assert.rejects(site.execute({openComputation: async () => {
      opened++;
      return {execution, checkedHost: {}};
    }, retainExecution: owner => { retained = owner; }}),
    {code: 'InvalidInstalledEffectCapture'});
    await assert.rejects(retained.cleanup(), {message: 'DisposeUnavailable'});
    assert.equal(retained.cleanupPending(), true);
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    assert.equal(opened, 1);
    assert.equal(disposeCalls, 2);
  });

test('installed Effect releases its consumer pins before Compute reclamation', async () => {
  const order = [];
  let retained, released = false;
  const execution = {async close() {
    order.push('compute-close');
    assert.equal(released, true, 'the stopped Effect no longer borrows Compute');
  }, async cleanup() { order.push('compute-cleanup'); return released; },
  cleanupPending: () => !released};
  const site = createInstalledEffectSite({environmentWire: '{}',
    prepareCaptured() { return {
      releaseInputs() { order.push('pins-release'); released = true; },
      dispose() { order.push('stage-dispose'); },
    }; }, prepareRecovered() { assert.fail('No new capture or Compute'); }});
  await assert.rejects(site.execute({openComputation: () => ({execution, checkedHost: {}}),
    retainExecution: value => { retained = value; }}),
  {code: 'InvalidInstalledEffectCapture'});
  await retained.close();
  assert.equal(await retained.cleanup(), true);
  assert.equal(await retained.cleanup(), true);
  assert.deepEqual(order, ['pins-release', 'compute-close', 'compute-cleanup',
    'stage-dispose']);
});

for (const mismatch of ['Preview', 'Unit', 'missing Unit']) {
test(`installed Effect continuation rejects ${mismatch} before claim`,
  async () => {
    const moon = {};
    const store = {};
    const control = {effectComputationPreviewSemanticCid: () => cid('a')};
    const preview = {wire: '{}'};
    const computation = {};
    const storedResults = {};
    const recovered = {computation: {computation, storedResults, preview}};
    let prepared = 0;
    let claims = 0;
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured() {
        assert.fail('Compute cannot run during continuation recovery');
      }, prepareRecovered({recovered: actual}) {
        prepared++;
        assert.equal(actual, recovered);
        return {preview, computation, storedResults, apply: {moon,
          computation, preview}, receipt: {commonMoon: moon},
        publication: {execution: null, store, control, computation,
          storedResults, preview}, scopes: [{}], reviewWire: '{}',
        continuationWire: '{"provider":"bound"}', unitId: 'values',
        declaredResults: ['answer']};
      }});
    await assert.rejects(site.resume({moon, store, control,
      retainExecution() {},
      ref: {runDefinitionCid: cid('b')},
      view: {runId: 'run-a', subject: {kind: 'run_unit', unit_id: 'compute_a'}},
      continuation: {version: 'actql-installed-effect-continuation/0.1',
        ...(mismatch === 'missing Unit' ? {} : {
          unit_id: mismatch === 'Unit' ? 'other' : 'compute_a'}),
        run_definition_cid: cid('b'),
        preview_cid: mismatch === 'Preview' ? cid('c') : cid('a'),
        provider: {provider: 'bound'}},
      recoverCapture: async () => recovered,
      checkpointJournal: {claimResume() { claims++; }},
    }), {code: 'InstalledEffectContinuationMismatch'});
    assert.equal(prepared, 0);
    assert.equal(claims, 0);
  });
}

test('missing durable Effect capture never claims an approved resume',
  async () => {
    let claims = 0;
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured() {
        assert.fail('Unexpected Compute');
      }, prepareRecovered() {
        assert.fail('No recovered capture can be prepared');
      }});
    await assert.rejects(site.resume({signal: undefined,
      retainExecution() {},
      recoverCapture: async () => {
        throw Object.assign(new Error('CompletedEffectfulCaptureUnavailable'),
          {code: 'CompletedEffectfulCaptureUnavailable'});
      }, checkpointJournal: {claimResume() { claims++; }}}),
    {code: 'CompletedEffectfulCaptureUnavailable'});
    assert.equal(claims, 0);
  });

test('a failed capture read leaves no unobserved physical continuation',
  async () => {
    const ref = {runDefinitionCid: cid('b')};
    let reads = 0;
    let stopped = 0;
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured() { assert.fail('Compute must not restart'); },
      prepareRecovered() { assert.fail('A busy claim cannot prepare'); }});
    const owner = installNodeClientDispatchOwner({});
    const run = ({signal, retainExecution, beginPhysicalWork}) =>
      site.resume({signal, retainExecution, beginPhysicalWork, ref,
        recoverCapture: async () => {
          reads++;
          throw new Error('TemporaryStoreFailure');
        }});
    const first = owner.track(ref, {run,
      observeStopped: () => { stopped++; }});
    await assert.rejects(first, {message: 'TemporaryStoreFailure'});
    await owner.drain();
    assert.equal(owner.operation(ref), undefined);
    assert.equal(reads, 1);
    assert.equal(stopped, 1);
  });

// A write driver is checked when the installed row Effect is created: a
// composition whose recovery would need a hook it lacks is refused then, as
// InvalidInstalledRowEffectDriver, never later as a TypeError.
{
  const hook = () => {};
  const createWithRecovery = {kinds: ['create'], prepareRequest: hook,
    requestFacts: hook, writeOperation: hook, send: hook, project: hook,
    footprint: hook, recoveryEntry: hook, recoverRequests: hook,
    requestCid: hook};
  const update = {...createWithRecovery, kinds: ['update'],
    targetRead: {operation: 'read'}, observeTargets: hook};
  const drivers = {'a create driver with its own recovery':
    createWithRecovery, 'an update driver': update};
  const refusedCode = async driver => createInstalledRowEffect({driver})
    .then(() => 'created', error => error?.code ?? String(error));
  for (const [label, complete] of Object.entries(drivers)) {
    test(`${label} missing any required hook is refused at registration`,
      async () => {
        // The complete driver passes the driver check; creation then fails
        // only on the other (absent) arguments.
        assert.notEqual(await refusedCode(complete),
          'InvalidInstalledRowEffectDriver');
        const required = ['prepareRequest', 'requestFacts', 'writeOperation',
          'send', 'project', 'footprint', 'recoveryEntry', 'recoverRequests',
          'requestCid',
          ...(complete === update ? ['targetRead', 'observeTargets'] : [])];
        for (const name of required) {
          const {[name]: _omitted, ...driver} = complete;
          assert.equal(await refusedCode(driver),
            'InvalidInstalledRowEffectDriver', `without ${name}`);
        }
      });
  }
}

function continuationFixture() {
  const original = 'e\u0301\r\nline\rreturn\n' + JSON.stringify({nested: 'e\u0301'});
  const binding = {version: 'actql-effect-target-read-binding/0.1',
    submission: {input: {format: 'json', text: original}, parameters: {text: original}},
    inventory_cid: cid('c'), targets: [{physicalBindings: [{text: original}]}]};
  const data = {'é': 'composed', 'e\u0301': 'decomposed',
    '\r\n': 'CRLF', '\n': 'LF'};
  binding.submission.input.data = {$json: data};
  binding.targets[0].physicalBindings[0].data = data;
  const provider = {wire: original, data};
  const stop = new Error('StopBeforeEffectDispatch');
  const moon = {clientProgramEffectCompilationUnitId: () => 'effect',
    clientProgramEffectCompilationResultNames: () => ['answer']};
  const control = {effectComputationPreviewSemanticCid: () => cid('a'),
    effectComputationPreviewWire: () => '{}', runDefinitionRunId: () => 'run-a'};
  const store = {}, computation = {}, storedResults = {}, preview = {};
  const physical = {close() {}, cleanup: async () => true, cleanupPending: () => false};
  const targetReads = {prepare: async () => ({status: 'ready'}),
    enterComputation() {}, close() {}, captureBinding: () => structuredClone(binding)};
  const stage = execution => ({preview, computation, storedResults,
    apply: {moon, computation, preview}, receipt: {commonMoon: moon},
    publication: {execution, store, control, computation, storedResults, preview},
    scopes: [{}], continuationWire: JSON.stringify(provider), cleanupOwner: physical});
  const site = createInstalledEffectSite({environmentWire: '{}',
    prepareCaptured: () => stage(physical), prepareRecovered: () => stage(null)});
  const facts = {moon, control, store, compilation: {}, ref: {runDefinitionCid: cid('b')},
    targetReads, retainExecution() {}, openComputation: () => ({execution: physical, checkedHost: {}})};
  return {site, facts, stop, provider, binding, stage,
    recovered: {computation: {computation, storedResults, preview}}};
}

test('outer Effect commit continuation preserves target and provider data', async () => {
  const f = continuationFixture();
  let saved;
  await assert.rejects(f.site.execute({...f.facts, effectAuthorization(options) {
    saved = JSON.parse(options.continuationWire); throw f.stop;
  }}), error => error === f.stop);
  assert.deepEqual(saved.target_read_binding, f.binding);
  assert.deepEqual(saved.provider, f.provider);
});

for (const changed of ['target binding', 'provider']) {
  test(`outer Effect resume refuses normalization-distinct ${changed} before authorization`, async () => {
    const f = continuationFixture();
    const saved = {version: 'actql-installed-effect-continuation/0.1',
      unit_id: 'effect', run_definition_cid: cid('b'), preview_cid: cid('a'),
      target_read_binding: structuredClone(f.binding), provider: {...f.provider}};
    if (changed === 'target binding') {
      saved.target_read_binding.submission.parameters.text =
        saved.target_read_binding.submission.parameters.text.normalize('NFC');
    } else saved.provider.wire = saved.provider.wire.normalize('NFC');
    let authorizations = 0, dispatchStarts = 0;
    await assert.rejects(f.site.resume({...f.facts, compilation: undefined,
      view: {runId: 'run-a', subject: {kind: 'run_unit', unit_id: 'effect'}},
      retained: {resultNames: ['answer']}, continuation: saved, recoverCapture: async () => f.recovered,
      checkpointJournal: {claimResume: () => ({action: 'claimed'})},
      effectAuthorization() { authorizations++; throw f.stop; },
      beginPhysicalWork() { dispatchStarts++; },
    }), {code: 'InstalledEffectContinuationMismatch'});
    assert.equal(authorizations, 0); assert.equal(dispatchStarts, 0);
  });
}
