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
    let outputCloses = 0;
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
      executeCaptured: async () => Object.freeze({
        kind: 'output',
        async close() { outputCloses++; },
      }),
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
    assert.equal(outputCloses, 1);
  });

test('execution cleanup stops before the input owner is released',
  async () => {
    const session = Object.freeze({kind: 'session'});
    const source = Object.freeze({kind: 'source'});
    const failure = Object.freeze({kind: 'input-failure'});
    let executionPending = true;
    let executionRetries = 0;
    let inputPending = true;
    let inputRetries = 0;
    let cancels = 0;
    const executionHandle = Object.freeze({
      status: () => Object.freeze({
        pending: executionPending,
        errors: Object.freeze([]),
      }),
      async retry() {
        executionRetries++;
        if (executionRetries === 3) executionPending = false;
        return this.status();
      },
    });
    const primary = Object.freeze(Object.assign(
      new Error('native still running'),
      {
        code: 'NativeStopPending',
        cleanupPending: true,
        cleanupHandle: executionHandle,
      },
    ));
    const control = createRemoteStandardSourceSessionControl({
      factory: Object.freeze({kind: 'factory'}),
      portable: Object.freeze({
        requestCid: () => 'request-a',
        start: () => session,
        authorize: () => true,
        feed: () => true,
        finish: () => source,
        captured: () => Object.freeze({kind: 'captured'}),
        release: () => { throw new Error('release must use cancellation'); },
        cancel(value) {
          assert.equal(value, session);
          cancels++;
          return failure;
        },
        failureCode: () => 'standard-source-release',
        failureCleanupPending: () => inputPending,
        retryFailureCleanup() {
          inputRetries++;
          if (inputRetries === 2) inputPending = false;
          return !inputPending;
        },
      }),
      executeCaptured: async () => { throw primary; },
    });
    const receiver = Object.freeze({
      claim: () => Object.freeze({kind: 'claim'}),
      async consume(_requestCid, authorize, accept) {
        const claim = Object.freeze({kind: 'claim'});
        assert.equal(authorize(claim), true);
        await accept(0, Buffer.from('row'));
      },
    });
    const execute = createRemoteStandardDirectExecution({receiver, control});
    const result = await execute({
      dispatch: Object.freeze({kind: 'dispatch'}),
      inputBinding: Object.freeze({kind: 'binding'}),
    }).catch(error => error);
    assert.equal(result.code, 'NativeStopPending');
    assert.equal(result.cause, primary);
    assert.equal(result.cleanupPending, true);
    assert.equal(executionRetries, 1);
    assert.equal(cancels, 0);
    assert.equal((await result.cleanupHandle.retry()).pending, true);
    assert.equal(executionRetries, 2);
    assert.equal(cancels, 0);
    assert.equal((await result.cleanupHandle.retry()).pending, true);
    assert.equal(executionRetries, 3);
    assert.equal(cancels, 1);
    assert.equal(inputRetries, 1);
    assert.equal((await result.cleanupHandle.retry()).pending, false);
    assert.equal(inputRetries, 2);
    assert.equal(cancels, 1);
    assert.equal((await result.cleanupHandle.retry()).pending, false);
    assert.equal(inputRetries, 2);
    assert.equal(cancels, 1);
  });

test('unhanded output cleanup and input cancellation remain retryable',
  async () => {
    const session = Object.freeze({kind: 'session'});
    const source = Object.freeze({kind: 'source'});
    const failure = Object.freeze({kind: 'input-failure'});
    let outputCloseAttempts = 0;
    let inputPending = true;
    let inputRetries = 0;
    let cancelAttempts = 0;
    const output = Object.freeze({
      kind: 'output',
      async close() {
        outputCloseAttempts++;
        if (outputCloseAttempts === 1) throw new Error('output close pending');
      },
    });
    const control = createRemoteStandardSourceSessionControl({
      factory: Object.freeze({kind: 'factory'}),
      portable: Object.freeze({
        requestCid: () => 'request-a',
        start: () => session,
        authorize: () => true,
        feed: () => true,
        finish: () => source,
        captured: () => Object.freeze({kind: 'captured'}),
        release: () => false,
        cancel(value) {
          assert.equal(value, session);
          cancelAttempts++;
          if (cancelAttempts === 1) throw new Error('cancel pending');
          return failure;
        },
        failureCode: () => 'standard-source-release',
        failureCleanupPending: () => inputPending,
        retryFailureCleanup() {
          inputRetries++;
          inputPending = false;
          return true;
        },
      }),
      executeCaptured: async () => output,
    });
    const receiver = Object.freeze({
      claim: () => Object.freeze({kind: 'claim'}),
      async consume(_requestCid, authorize, accept) {
        const claim = Object.freeze({kind: 'claim'});
        assert.equal(authorize(claim), true);
        await accept(0, Buffer.from('row'));
      },
    });
    const execute = createRemoteStandardDirectExecution({receiver, control});
    const result = await execute({
      dispatch: Object.freeze({kind: 'dispatch'}),
      inputBinding: Object.freeze({kind: 'binding'}),
    }).catch(error => error);
    assert.equal(result.code, 'RemoteStandardInputReleasePending');
    assert.equal(result.cleanupPending, true);
    assert.equal(outputCloseAttempts, 1);
    assert.equal(cancelAttempts, 0);
    assert.equal((await result.cleanupHandle.retry()).pending, true);
    assert.equal(outputCloseAttempts, 2);
    assert.equal(cancelAttempts, 1);
    assert.equal(inputRetries, 0);
    assert.equal((await result.cleanupHandle.retry()).pending, false);
    assert.equal(outputCloseAttempts, 2);
    assert.equal(cancelAttempts, 2);
    assert.equal(inputRetries, 1);
  });

test('dispatch abort reaches captured Compute before input release',
  async () => {
    const session = Object.freeze({kind: 'session'});
    const source = Object.freeze({kind: 'source'});
    const failure = Object.freeze({kind: 'input-failure'});
    const controller = new AbortController();
    let computeStarted;
    const started = new Promise(resolve => { computeStarted = resolve; });
    let stopRequests = 0;
    let inputCancels = 0;
    const control = createRemoteStandardSourceSessionControl({
      factory: Object.freeze({kind: 'factory'}),
      portable: Object.freeze({
        requestCid: () => 'request-a',
        start: () => session,
        authorize: () => true,
        feed: () => true,
        finish: () => source,
        captured: () => Object.freeze({kind: 'captured'}),
        release: () => { throw new Error('cancel must release the input'); },
        cancel(value) {
          assert.equal(value, session);
          inputCancels++;
          return failure;
        },
        failureCode: () => 'dispatch-aborted',
        failureCleanupPending: () => false,
        retryFailureCleanup: () => true,
      }),
      executeCaptured: async (_captured, options) => {
        assert.equal(options.signal, controller.signal);
        computeStarted();
        await new Promise((resolve, reject) => {
          const stop = () => {
            stopRequests++;
            reject(options.signal.reason);
          };
          options.signal.addEventListener('abort', stop, {once: true});
        });
      },
    });
    const receiver = Object.freeze({
      claim: () => Object.freeze({kind: 'claim'}),
      async consume(_requestCid, authorize, accept) {
        const claim = Object.freeze({kind: 'claim'});
        assert.equal(authorize(claim), true);
        await accept(0, Buffer.from('row'));
      },
    });
    const executing = createRemoteStandardDirectExecution({receiver, control})(
      {
        dispatch: Object.freeze({kind: 'dispatch'}),
        inputBinding: Object.freeze({kind: 'binding'}),
        signal: controller.signal,
      },
    );
    await started;
    controller.abort('cancel-compute');
    const result = await executing.catch(error => error);
    assert.equal(result.code, 'dispatch-aborted');
    assert.equal(result.primaryFailure, 'cancel-compute');
    assert.equal(stopRequests, 1);
    assert.equal(inputCancels, 1);
    assert.equal(result.cleanupPending, false);
  });

test('abort racing with Compute output reclaims output before input',
  async () => {
    const session = Object.freeze({kind: 'session'});
    const source = Object.freeze({kind: 'source'});
    const failure = Object.freeze({kind: 'input-failure'});
    const controller = new AbortController();
    let resolveCompute;
    let inputCancels = 0;
    const events = [];
    const output = Object.freeze({
      async close() { events.push('output-closed'); },
    });
    const control = createRemoteStandardSourceSessionControl({
      factory: Object.freeze({kind: 'factory'}),
      portable: Object.freeze({
        requestCid: () => 'request-a',
        start: () => session,
        authorize: () => true,
        feed: () => true,
        finish: () => source,
        captured: () => Object.freeze({kind: 'captured'}),
        release: () => { throw new Error('cancel must release the input'); },
        cancel() {
          events.push('input-cancelled');
          inputCancels++;
          return failure;
        },
        failureCode: () => 'dispatch-aborted',
        failureCleanupPending: () => false,
        retryFailureCleanup: () => true,
      }),
      executeCaptured: async (_captured, {signal}) => {
        assert.equal(signal, controller.signal);
        return await new Promise(resolve => { resolveCompute = resolve; });
      },
    });
    const receiver = Object.freeze({
      claim: () => Object.freeze({kind: 'claim'}),
      async consume(_requestCid, authorize, accept) {
        const claim = Object.freeze({kind: 'claim'});
        assert.equal(authorize(claim), true);
        await accept(0, Buffer.from('row'));
      },
    });
    const executing = createRemoteStandardDirectExecution({receiver, control})(
      {
        dispatch: Object.freeze({kind: 'dispatch'}),
        inputBinding: Object.freeze({kind: 'binding'}),
        signal: controller.signal,
      },
    );
    while (resolveCompute === undefined) await Promise.resolve();
    controller.abort('cancel-race');
    resolveCompute(output);
    const result = await executing.catch(error => error);
    assert.equal(result.code, 'dispatch-aborted');
    assert.equal(result.primaryFailure, 'cancel-race');
    assert.equal(inputCancels, 1);
    assert.deepEqual(events, ['output-closed', 'input-cancelled']);
    assert.equal(result.cleanupPending, false);
  });

test('falsy execution failures retain their exact primary cause', async () => {
  for (const primary of [null, undefined, false, 0, '']) {
    const session = Object.freeze({kind: 'session'});
    const source = Object.freeze({kind: 'source'});
    const failure = Object.freeze({kind: 'input-failure'});
    let cancels = 0;
    const control = createRemoteStandardSourceSessionControl({
      factory: Object.freeze({kind: 'factory'}),
      portable: Object.freeze({
        requestCid: () => 'request-a',
        start: () => session,
        authorize: () => true,
        feed: () => true,
        finish: () => source,
        captured: () => Object.freeze({kind: 'captured'}),
        release: () => { throw new Error('release must use cancellation'); },
        cancel() { cancels++; return failure; },
        failureCode: () => 'standard-source-release',
        failureCleanupPending: () => false,
        retryFailureCleanup: () => true,
      }),
      executeCaptured: async () => { throw primary; },
    });
    const receiver = Object.freeze({
      claim: () => Object.freeze({kind: 'claim'}),
      async consume(_requestCid, authorize, accept) {
        const claim = Object.freeze({kind: 'claim'});
        assert.equal(authorize(claim), true);
        await accept(0, Buffer.from('row'));
      },
    });
    const result = await createRemoteStandardDirectExecution({receiver, control})(
      {
        dispatch: Object.freeze({kind: 'dispatch'}),
        inputBinding: Object.freeze({kind: 'binding'}),
      },
    ).catch(error => error);
    assert.equal(result.code, 'standard-source-release');
    assert.equal(result.cause, primary);
    assert.equal(result.primaryFailure, primary);
    assert.equal(result.cleanupPending, false);
    assert.equal(cancels, 1);
  }
});

test('verified active bundle supplies the exact session factory', async () => {
  const bundle = Object.freeze({component: 'verified-component'});
  const manifest = Object.freeze({runtimeBundleCid: 'bundle-a'});
  const factory = Object.freeze({kind: 'factory'});
  const session = Object.freeze({kind: 'session'});
  const source = Object.freeze({kind: 'source'});
  const captured = Object.freeze({kind: 'captured'});
  const output = Object.freeze({kind: 'output'});
  const claim = Object.freeze({kind: 'claim'});
  const receiver = Object.freeze({
    claim: () => claim,
    async consume(requestCid, authorize, accept) {
      assert.equal(requestCid, 'request-a');
      assert.equal(authorize(claim), true);
      await accept(0, Buffer.from('row'));
    },
  });
  const portable = Object.freeze({
    requestCid(value) {
      assert.equal(value, factory);
      return 'request-a';
    },
    start(value, dispatch, binding, current) {
      assert.equal(value, factory);
      assert.equal(dispatch.kind, 'dispatch');
      assert.equal(binding.kind, 'binding');
      assert.equal(current, claim);
      return session;
    },
    authorize: (value, current) => value === session && current === claim,
    feed(value, index, frame) {
      assert.equal(value, session);
      assert.equal(index, 0);
      assert.equal(frame.toString(), 'row');
      return true;
    },
    finish: value => value === session ? source : undefined,
    captured(value) {
      assert.equal(value, source);
      return captured;
    },
    release: value => value === source,
    cancel: () => Object.freeze({kind: 'failure'}),
    failureCode: () => 'unexpected-source-failure',
    failureCleanupPending: () => false,
    retryFailureCleanup: () => true,
  });
  let loads = 0;
  const registration = await prepareInstalledRemoteStandardDirectRegistration({
    receiver,
    portable,
    loadSourceExecution(value) {
      assert.equal(value, bundle);
      loads++;
      return Object.freeze({
        factory,
        async executeCaptured(value) {
          assert.equal(value, captured);
          return output;
        },
      });
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
    dispatch: Object.freeze({kind: 'dispatch'}),
    inputBinding: Object.freeze({kind: 'binding'}),
  }), output);
});
