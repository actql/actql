import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledEffectSite} from './installed-effect-site.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

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

test('installed Effect continuation rejects a foreign Preview before claim',
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
      ref: {runDefinitionCid: cid('b')},
      view: {runId: 'run-a'},
      continuation: {version: 'actql-installed-effect-continuation/0.1',
        run_definition_cid: cid('b'), preview_cid: cid('c'),
        provider: {provider: 'bound'}},
      recoverCapture: async () => recovered,
      checkpointJournal: {claimResume() { claims++; }},
    }), {code: 'InstalledEffectContinuationMismatch'});
    assert.equal(prepared, 0);
    assert.equal(claims, 0);
  });

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
      recoverCapture: async () => {
        throw Object.assign(new Error('CompletedEffectfulCaptureUnavailable'),
          {code: 'CompletedEffectfulCaptureUnavailable'});
      }, checkpointJournal: {claimResume() { claims++; }}}),
    {code: 'CompletedEffectfulCaptureUnavailable'});
    assert.equal(claims, 0);
  });
