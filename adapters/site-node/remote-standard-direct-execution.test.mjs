import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createRemoteStandardDirectExecution,
  createRemoteStandardSourceSessionControl,
  prepareInstalledRemoteStandardDirectRegistration,
} from
  './remote-standard-direct-execution.mjs';

function fixture({rejectFrame = false, cleanupResults = [true]} = {}) {
  const dispatch = Object.freeze({kind: 'dispatch'});
  const inputBinding = Object.freeze({kind: 'binding'});
  const claim = Object.freeze({
    destinationReceiptCid: 'receipt-a',
    materialGeneration: 'generation-a',
  });
  const frames = [Buffer.from('one'), Buffer.from('two')];
  const events = [];
  let cleanupIndex = 0;
  const receiver = Object.freeze({
    claim(requestCid) {
      assert.equal(requestCid, 'request-a');
      events.push('claim');
      return claim;
    },
    async consume(requestCid, authorize, accept) {
      assert.equal(requestCid, 'request-a');
      assert.equal(await authorize(claim), true);
      events.push('authorized-before');
      for (let index = 0; index < frames.length; index++) {
        await accept(index, frames[index]);
      }
      assert.equal(await authorize(claim), true);
      events.push('authorized-after');
      return claim;
    },
  });
  const session = Object.freeze({kind: 'session'});
  const failure = Object.freeze({kind: 'failure'});
  const output = Object.freeze({kind: 'output'});
  let failureCleanupPending = true;
  let physicalAvailable;
  let releasePhysical;
  const control = Object.freeze({
    requestCid(value, binding) {
      assert.equal(value, dispatch);
      assert.equal(binding, inputBinding);
      events.push('request');
      return 'request-a';
    },
    prepare(value, binding, retained, available, release) {
      assert.equal(value, dispatch);
      assert.equal(binding, inputBinding);
      assert.equal(retained, claim);
      physicalAvailable = available;
      releasePhysical = release;
      assert.equal(available(), true);
      events.push('prepare');
      return session;
    },
    authorize(value, retained) {
      assert.equal(value, session);
      assert.equal(retained, claim);
      assert.equal(physicalAvailable(), true);
      return true;
    },
    feed(value, index, frame) {
      assert.equal(value, session);
      assert.equal(frame, frames[index]);
      events.push(`feed-${index}`);
      return !(rejectFrame && index === 1);
    },
    async finish(value) {
      assert.equal(value, session);
      await Promise.resolve();
      assert.equal(releasePhysical(), true);
      assert.equal(physicalAvailable(), false);
      events.push('finish');
      return output;
    },
    cancel(value) {
      assert.equal(value, session);
      events.push('cancel');
      return failure;
    },
    failureCode(value) {
      assert.equal(value, failure);
      return 'standard-input-failed';
    },
    failureCleanupPending(value) {
      assert.equal(value, failure);
      return failureCleanupPending;
    },
    retryFailureCleanup(value) {
      assert.equal(value, failure);
      events.push('retry-cleanup');
      const result = cleanupResults[Math.min(
        cleanupIndex++,
        cleanupResults.length - 1,
      )];
      if (result) failureCleanupPending = false;
      return result;
    },
  });
  return {
    control,
    dispatch,
    events,
    inputBinding,
    output,
    receiver,
  };
}

test('direct input streams exact frames through the opaque task session',
  async () => {
    const setup = fixture();
    const execute = createRemoteStandardDirectExecution(setup);
    assert.equal(await execute({
      dispatch: setup.dispatch,
      inputBinding: setup.inputBinding,
    }), setup.output);
    assert.deepEqual(setup.events, [
      'request',
      'claim',
      'prepare',
      'authorized-before',
      'feed-0',
      'feed-1',
      'authorized-after',
      'finish',
    ]);
  });

test('MoonBit-owned failed input cleanup remains retryable', async () => {
  const setup = fixture({rejectFrame: true, cleanupResults: [false, true]});
  const execute = createRemoteStandardDirectExecution(setup);
  const failure = await execute({
    dispatch: setup.dispatch,
    inputBinding: setup.inputBinding,
  }).catch(error => error);
  assert.equal(failure.code, 'standard-input-failed');
  assert.equal(failure.cleanupPending, true);
  assert.deepEqual(failure.cleanupHandle.status(), {
    pending: true,
    errors: [],
  });
  assert.deepEqual(await failure.cleanupHandle.retry(), {
    pending: false,
    errors: [],
  });
  assert.deepEqual(setup.events, [
    'request',
    'claim',
    'prepare',
    'authorized-before',
    'feed-0',
    'feed-1',
    'cancel',
    'retry-cleanup',
    'retry-cleanup',
  ]);
});

test('portable source session executes only after verified capture',
  async () => {
    const events = [];
    const factory = Object.freeze({kind: 'factory'});
    const session = Object.freeze({kind: 'session'});
    const source = Object.freeze({kind: 'source'});
    const captured = Object.freeze({kind: 'captured'});
    const output = Object.freeze({kind: 'output'});
    const failure = Object.freeze({kind: 'failure'});
    const portable = Object.freeze({
      requestCid(value, binding) {
        assert.equal(value, factory);
        assert.equal(binding.kind, 'binding');
        events.push('request');
        return 'request-a';
      },
      start(value, dispatch, binding, claim, available, release) {
        assert.equal(value, factory);
        assert.equal(dispatch.kind, 'dispatch');
        assert.equal(binding.kind, 'binding');
        assert.equal(claim.kind, 'claim');
        assert.equal(available(), true);
        assert.equal(typeof release, 'function');
        events.push('start');
        return session;
      },
      authorize(value, claim) {
        assert.equal(value, session);
        assert.equal(claim.kind, 'claim');
        return true;
      },
      feed(value, index, bytes) {
        assert.equal(value, session);
        assert.equal(index, 0);
        assert.equal(bytes.toString(), 'row');
        events.push('feed');
        return true;
      },
      finish(value) {
        assert.equal(value, session);
        events.push('verify');
        return source;
      },
      captured(value) {
        assert.equal(value, source);
        events.push('capture');
        return captured;
      },
      release(value) {
        assert.equal(value, source);
        events.push('release');
        return true;
      },
      cancel: () => failure,
      failureCode: () => 'standard-source-release',
      failureCleanupPending: () => false,
      retryFailureCleanup: () => true,
    });
    const control = createRemoteStandardSourceSessionControl({
      portable,
      factory,
      async executeCaptured(value) {
        assert.equal(value, captured);
        events.push('execute');
        return output;
      },
    });
    assert.equal(control.requestCid(
      Object.freeze({kind: 'dispatch'}),
      Object.freeze({kind: 'binding'}),
    ), 'request-a');
    const value = control.prepare(
      Object.freeze({kind: 'dispatch'}),
      Object.freeze({kind: 'binding'}),
      Object.freeze({kind: 'claim'}),
      () => true,
      () => true,
    );
    assert.equal(control.authorize(value, Object.freeze({kind: 'claim'})), true);
    assert.equal(control.feed(value, 0, Buffer.from('row')), true);
    assert.equal(await control.finish(value), output);
    assert.deepEqual(events, [
      'request',
      'start',
      'feed',
      'verify',
      'capture',
      'execute',
      'release',
    ]);
  });

test('failed asynchronous execution retains the MoonBit source owner',
  async () => {
    const source = Object.freeze({kind: 'source'});
    const session = Object.freeze({kind: 'session'});
    const failure = Object.freeze({kind: 'failure'});
    let pending = true;
    let releases = 0;
    const control = createRemoteStandardSourceSessionControl({
      factory: Object.freeze({kind: 'factory'}),
      portable: Object.freeze({
        requestCid: () => 'request-a',
        start: () => session,
        authorize: () => true,
        feed: () => true,
        finish: () => source,
        captured: () => Object.freeze({kind: 'captured'}),
        release() {
          releases++;
          if (releases === 1) return false;
          pending = false;
          return true;
        },
        cancel(value) {
          assert.equal(value, session);
          return failure;
        },
        failureCode: () => 'standard-source-release',
        failureCleanupPending: () => pending,
        retryFailureCleanup() {
          releases++;
          pending = false;
          return true;
        },
      }),
      executeCaptured: async () => Object.freeze({kind: 'output'}),
    });
    const receiver = Object.freeze({
      claim: () => Object.freeze({kind: 'claim'}),
      async consume(requestCid, authorize, accept) {
        const claim = Object.freeze({kind: 'claim'});
        assert.equal(requestCid, 'request-a');
        assert.equal(await authorize(claim), true);
        await accept(0, Buffer.from('row'));
      },
    });
    const execute = createRemoteStandardDirectExecution({receiver, control});
    const result = await execute({
      dispatch: Object.freeze({kind: 'dispatch'}),
      inputBinding: Object.freeze({kind: 'binding'}),
    }).catch(error => error);
    assert.equal(result.code, 'standard-source-release');
    assert.equal(result.cleanupPending, false);
    assert.equal(releases, 2);
  });

test('verified active bundle supplies the exact session factory', async () => {
  const setup = fixture();
  const bundle = Object.freeze({component: 'verified-component'});
  const manifest = Object.freeze({runtimeBundleCid: 'bundle-a'});
  let loads = 0;
  const registration = await prepareInstalledRemoteStandardDirectRegistration({
    receiver: setup.receiver,
    loadSessionControl(value) {
      assert.equal(value, bundle);
      loads++;
      return setup.control;
    },
    bundleStore: Object.freeze({
      active: () => Object.freeze({manifest}),
      async verify(runtimeBundleCid) {
        assert.equal(runtimeBundleCid, 'bundle-a');
        return bundle;
      },
    }),
    bundleControl: Object.freeze({
      identity: value => value.runtimeBundleCid,
    }),
    control: Object.freeze({
      managedOutputEvidenceKind: 'managed-output',
      registerExecutionCapability: value => Object.freeze({value}),
      registerEvidenceIssuer: value => Object.freeze({value}),
      managedRuntimeRegistrationScope: () => Object.freeze([
        'site-a',
        '1',
        'bundle-a',
        'local',
        'local/1',
        'strategy/1',
        'operation-a',
        'issuer-a',
      ]),
    }),
    site: Object.freeze({kind: 'site'}),
    runtimeBundleCid: 'bundle-a',
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    operationCapabilityCid: 'operation-a',
    evidenceKind: 'managed-output',
    issuerCapabilityCid: 'issuer-a',
  });
  assert.equal(loads, 1);
  assert.equal(await registration.execute({
    dispatch: setup.dispatch,
    inputBinding: setup.inputBinding,
  }), setup.output);
});
