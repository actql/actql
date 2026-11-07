import assert from 'node:assert/strict';
import test from 'node:test';
import * as sdk from '../../packages/sdk/index.mjs';
import {fixture, cid, requestId} from './client-cancel-response-loss.fixture.mjs';

for (const transport of ['in-process', 'http']) {
  for (const phase of ['before-dispatch', 'after-commit']) {
    test(`${transport} cancel loss ${phase} preserves same-Run observation`,
      async t => {
        const f = await fixture(t, transport, phase);
        const ref = {...f.execution.ref};
        await assert.rejects(f.execution.cancel(f.cancelOptions()), {code: 'CancellationUnknown'});
        assert.deepEqual(f.execution.ref, ref);
        assert.deepEqual(f.operations, ['connect', 'attach', 'cancel']);
        const committed = phase === 'after-commit';
        const expected = [{...f.before[0],
          cancellation_requested: committed ? 1 : 0,
          revision: f.before[0].revision + (committed ? 1 : 0)}];
        assert.deepEqual(f.stored(), expected);
        assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});

        // A retained handle or request ID cannot bypass current authorization.
        f.authorize(false);
        for (const operation of [() => f.execution.status(),
          () => f.client.attach(ref), () => f.client.lookupRequest(requestId),
          ]) {
          await assert.rejects(operation(), {code: 'ClientConnectionDenied'});
        }
        await assert.rejects(f.execution.cancel(f.cancelOptions()), {code: 'CancellationUnknown'});
        assert.deepEqual(f.stored(), expected);
        assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});
        f.authorize(true);
        const found = await f.client.lookupRequest(requestId);
        assert.equal(found.kind, 'found');
        assert.equal(found.requestId, requestId);
        assert.deepEqual(found.ref, ref);
        const attached = await f.client.attach(found.ref);
        assert.deepEqual(attached.ref, ref);
        for (const handle of [f.execution, attached]) {
          const state = await handle.status();
          assert.equal(state.run_id, 'saved-run');
          assert.equal(state.status, committed ? 'cancelled' : 'running');
          assert.deepEqual(state.control, {
            revision: expected[0].revision,
            cancellation_requested: committed,
            physical_stop: committed ? 'confirmed' : 'unknown'});
        }
        // Read-only recovery changes neither the journal nor the write count.
        assert.deepEqual(f.stored(), expected);
        assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});
        assert.equal(f.operations.filter(op => op === 'cancel').length, 2);
        assert.equal(f.operations.includes('submit'), false);
        assert.equal(f.operations.includes('reconcile'), false);
      });
  }
  test(`${transport} cancel refusal stays definitive and does not commit`,
    async t => {
      const f = await fixture(t, transport);
      f.authorizeCancel(false);
      const refused = await f.execution.cancel(f.cancelOptions());
      assert.deepEqual(refused, {kind: 'refused', reason: 'authorization',
        guarantee: 'attempt_uncommitted_unconsumed',
        attemptRef: {operation: 'cancel', attemptId: 'fixture-attempt-1'}});
      assert.deepEqual(f.stored(), f.before);
      assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
      assert.deepEqual(f.operations, ['connect', 'attach', 'cancel']);
      assert.equal((await f.execution.status()).control.cancellation_requested,
        false);
      assert.deepEqual(f.stored(), f.before);
    });
}


// Selected DTO faults target the actual response capture. A separate unused
// clone trap proves that response admission does not consult a global copier.
for (const [scenario, alterCopy] of [
  ['clone erases fields', copy => { delete copy.revision; return copy; }],
  ['clone throws', () => { throw new Error('private-clone-failure'); }],
  ...['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].map(field =>
    [`clone changes ${field}`, copy => {
      copy.ref[field] = field === 'namespaceId' ? 'foreign-namespace' : cid('f');
      copy.cancelRef[field] = copy.ref[field];
      return copy;
    }]),
]) {
  test(`in-process: cancellation ${scenario} retains original Run uncertainty`, async t => {
    const privateCause = new Error('private-response-capture-failure');
    let captures = 0;
    const f = await fixture(t, 'in-process', undefined, {physicalStart: true,
      transformCancelReply(value) {
        captures++;
        const copy = {...value, ref: {...value.ref}, cancelRef: {...value.cancelRef}};
        if (scenario === 'clone throws') return Object.defineProperty(copy, 'revision', {
          enumerable: true, get() { throw privateCause; }});
        return alterCopy(copy);
      }});
    const ref = {...f.execution.ref};
    const result = await f.execution.cancel(f.cancelOptions()).then(value => ({value}), error => ({error}));
    assert.equal(captures, 1);
    assert.equal(result.error?.code, 'CancellationUnknown', '[check-mutation:cancel-clone-invalid]');
    assert.equal(result.error.cause.code, 'InvalidHostCancellation');
    const expected = {observation: 'outcome_unknown',
      summary: 'The Run cancellation outcome is unknown. The request may have been recorded.',
      next: {operation: 'lookupCancellation', cancelRef: f.cancellationRef()}};
    assert.deepEqual(sdk.explainCancellation(result.error), expected, '[check-mutation:cancel-clone-uncertainty]');
    assert.equal(sdk.explainCancellation({...result.error}), undefined);
    assert.deepEqual(f.execution.ref, ref);
    assert.deepEqual(f.operations, ['connect', 'attach', 'cancel']);
    const committed = [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}];
    assert.deepEqual(f.stored(), committed);
    const state = await f.execution.status();
    assert.equal(state.status, 'running');
    assert.equal(state.control.physical_stop, 'unknown');
    assert.equal(state.control.cancellation_requested, true);
    assert.deepEqual(sdk.explainCancellation(result.error), expected);
    assert.deepEqual(f.stored(), committed);
    assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
    assert.deepEqual(f.operations, ['connect', 'attach', 'cancel', 'status']);
  });
}

for (const scenario of ['erase', 'throw', 'namespaceId', 'authorityScopeCid', 'runDefinitionCid']) {
  test(`in-process: unused cancellation clone trap ${scenario} cannot replace original data`, async t => {
    const f = await fixture(t, 'in-process', undefined, {physicalStart: true});
    let copies = 0;
    const clone = globalThis.structuredClone;
    t.mock.method(globalThis, 'structuredClone', value => {
      const copy = clone(value);
      if (value?.kind === 'accepted' && value?.cancellation !== undefined) {
        copies++;
        if (scenario === 'throw') throw new Error('private-clone-failure');
        if (scenario === 'erase') delete copy.cancellation.revision;
        else copy.cancellation.ref[scenario] = scenario === 'namespaceId'
          ? 'foreign-namespace' : cid('f');
      }
      return copy;
    });
    const answer = await f.execution.cancel(f.cancelOptions());
    assert.equal(copies, 0, 'Response capture must not consult the request copier');
    assert.equal(answer.kind, 'accepted');
    assert.deepEqual(answer.cancellation.ref, f.execution.ref);
    assert.equal(answer.cancellation.revision, f.before[0].revision + 1);
    assert.equal(sdk.explainCancellation(answer).observation, 'accepted');
    assert.deepEqual(f.stored(), [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}]);
    assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
    assert.deepEqual(f.operations, ['connect', 'attach', 'cancel']);
  });
}

for (const representation of ['Date', 'Proxy', 'namespaceId', 'authorityScopeCid', 'runDefinitionCid']) {
  test(`in-process: cancellation captures the original ${representation} response data`, async t => {
    let reads = 0, raw;
    const f = await fixture(t, 'in-process', undefined, {physicalStart: true,
      transformCancelReply(value) {
        // The installed Owner freezes its DTO; the Local response container
        // is independently owned by this transport fixture.
        value = {...value, ref: {...value.ref}};
        raw = value;
        if (representation === 'Date') {
          raw = Object.assign(new Date(0), value);
          Object.defineProperty(raw, 'toJSON', {value() { assert.fail('response toJSON must not run'); }});
          return raw;
        }
        if (representation === 'Proxy') return new Proxy(value, {
          get(target, key) { if (key === 'ref') reads++; return Reflect.get(target, key); },
        });
        const original = value.ref[representation];
        Object.defineProperty(value.ref, representation, {enumerable: true,
          get() { return ++reads === 1 ? original
            : representation === 'namespaceId' ? 'foreign-namespace' : cid('f'); }});
        return value;
      }});
    const answer = await f.execution.cancel(f.cancelOptions());
    assert.equal(answer.kind, 'accepted');
    assert.deepEqual(answer.cancellation.ref, f.execution.ref);
    assert.equal(reads, representation === 'Date' ? 0 : 1);
    assert.equal(sdk.explainCancellation(answer).observation, 'accepted');
    raw.kind = 'already_terminal';
    assert.equal(answer.kind, 'accepted');
    assert.equal(sdk.explainCancellation(answer).observation, 'accepted');
    assert.deepEqual(f.stored(), [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}]);
    assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
    assert.deepEqual(f.operations, ['connect', 'attach', 'cancel']);
  });
}

for (const transport of ['in-process', 'https']) {
  test(`${transport}: reused cancellation replies preserve each original Run observation`, async t => {
    // Reuse a Local port's response object, or its HTTPS serializer input,
    // while both cancellations still pass through the actual journal owner.
    const cancelResponseCache = {};
    const a = await fixture(t, transport, undefined, {
      physicalStart: true, runId: 'cache-run-a', cancelResponseCache});
    const b = await fixture(t, transport, undefined, {
      physicalStart: true, runId: 'cache-run-b', cancelResponseCache});
    assert.notDeepEqual(a.execution.ref, b.execution.ref);
    const expected = f => ({observation: 'accepted',
      revision: f.before[0].revision + 1,
      summary: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.',
      next: {operation: 'status', ref: {...f.execution.ref}}});
    const first = await a.execution.cancel(a.cancelOptions());
    const second = await b.execution.cancel(b.cancelOptions());
    assert.deepEqual(sdk.explainCancellation(first), expected(a), '[check-mutation:cancel-custody]');
    assert.deepEqual(sdk.explainCancellation(second), expected(b), '[check-mutation:cancel-custody]');
    assert.notEqual(first, second);
    assert.deepEqual(first, {kind: 'accepted',
      attemptRef: {operation: 'cancel', attemptId: 'fixture-attempt-1'},
      cancellation: {kind: 'accepted', ref: a.execution.ref, cancelRef: a.cancellationRef(),
        revision: a.before[0].revision + 1}});
    assert.deepEqual(second, {kind: 'accepted',
      attemptRef: {operation: 'cancel', attemptId: 'fixture-attempt-1'},
      cancellation: {kind: 'accepted', ref: b.execution.ref, cancelRef: b.cancellationRef(),
        revision: b.before[0].revision + 1}});
    const repeated = await a.execution.cancel(a.cancelOptions());
    assert.deepEqual(sdk.explainCancellation(repeated), {...expected(a),
      observation: 'already_requested',
      summary: 'The Host reports an existing Run cancellation request. Refresh Run state for physical stop, Effects and release.'});
    assert.deepEqual(sdk.explainCancellation(first), expected(a), '[check-mutation:cancel-custody]');
    assert.deepEqual(sdk.explainCancellation(second), expected(b), '[check-mutation:cancel-custody]');
    assert.equal(sdk.explainCancellation({...first}), undefined);
    for (const f of [a, b]) {
      assert.deepEqual(f.stored(), [{...f.before[0], cancellation_requested: 1,
        revision: f.before[0].revision + 1}]);
      const state = await f.execution.status();
      assert.equal(state.status, 'running');
      assert.equal(state.control.physical_stop, 'unknown');
      assert.equal(state.control.cancellation_requested, true);
    }
    assert.deepEqual(a.counts(), {cancelCalls: 2, submits: 0});
    assert.deepEqual(b.counts(), {cancelCalls: 1, submits: 0});
  });

  test(`${transport}: Run cancellation explanations retain recorded control facts`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true});
    const accepted = await f.execution.cancel(f.cancelOptions());
    assert.equal(typeof sdk.explainCancellation, 'function', '[check-mutation:cancel-explanation-api]');
    const next = {operation: 'status', ref: {...f.execution.ref}};
    const expected = {observation: 'accepted', revision: f.before[0].revision + 1,
      summary: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.', next};
    assert.deepEqual(sdk.explainCancellation(accepted), expected, '[check-mutation:cancel-explanation]');
    const beforeLocale = f.counts();
    for (const format of ['text', 'html', 'json']) {
      const output = sdk.formatCancellation(accepted, {format});
      assert.ok(output);
      if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, expected,
        '[check-mutation:operation-cancel-public-format]');
    }
    assert.deepEqual(sdk.explainCancellation(accepted, {locale: 'ja'}), {...expected,
      summary: 'HostはRunの取消し要求を記録しました。物理停止・Effect・解放はRunの現在状態で確認してください。'},
    '[check-mutation:operation-cancel-public-locale]');
    assert.deepEqual(f.counts(), beforeLocale, '[check-mutation:operation-cancel-public-passive]');

    assert.equal(f.stored()[0].physical_close_confirmed, 0);
    const state = await f.execution.status();
    assert.equal(state.status, 'running');
    assert.equal(state.control.cancellation_requested, true);
    assert.equal(state.control.physical_stop, 'unknown');
    const already = await f.execution.cancel(f.cancelOptions());
    assert.deepEqual(sdk.explainCancellation(already), {...expected,
      observation: 'already_requested',
      summary: 'The Host reports an existing Run cancellation request. Refresh Run state for physical stop, Effects and release.'},
    '[check-mutation:cancel-explanation]');
    assert.deepEqual(sdk.explainCancellation(JSON.parse(JSON.stringify(accepted))), undefined);
    assert.deepEqual(sdk.explainCancellation({kind: 'accepted', ref: f.execution.ref, revision: 999}), undefined);
    assert.equal(Object.isFrozen(sdk.explainCancellation(accepted).next.ref), true);
    if (!Object.isFrozen(accepted)) accepted.kind = 'already_terminal';
    assert.deepEqual(sdk.explainCancellation(accepted), expected, '[check-mutation:cancel-explanation]');
    assert.deepEqual(f.counts(), {cancelCalls: 2, submits: 0});
    f.authorize(false);
    await assert.rejects(f.execution.status(), {code: 'ClientConnectionDenied'});
    await assert.rejects(f.execution.cancel(f.cancelOptions()), error => {
      assert.equal(sdk.explainCancellation(error)?.observation, 'outcome_unknown');
      return error.code === 'CancellationUnknown';
    });
    assert.deepEqual(f.counts(), {cancelCalls: 2, submits: 0});
    assert.deepEqual(sdk.explainCancellation(accepted), expected);
    const terminal = await fixture(t, transport, undefined, {physicalStart: true, terminal: true});
    const reply = await terminal.execution.cancel(terminal.cancelOptions());
    assert.deepEqual(sdk.explainCancellation(reply), {
      observation: 'already_terminal', revision: terminal.before[0].revision,
      summary: 'The Host reports the Run is already terminal for cancellation. Refresh Run state for Effect and release details.',
      next: {operation: 'status', ref: {...terminal.execution.ref}},
    }, '[check-mutation:cancel-explanation]');
    assert.equal(sdk.explainCancellation(reply, {locale: 'ja'}).summary,
      'Hostは取消しについてRunが既に終端状態にあると報告しました。Effect・解放の詳細はRunの現在状態で確認してください。');
    assert.equal(terminal.stored()[0].cancellation_requested, 0);
  });

  test(`${transport}: Run cancellation uncertainty retains read-only observation advice`, async t => {
    assert.equal(typeof sdk.explainCancellation, 'function', '[check-mutation:cancel-explanation-api]');
    for (const scenario of [
      {phase: 'before-dispatch', committed: false},
      {phase: 'after-commit', committed: true},
      {reply: 'foreign_ref', committed: true},
      {reply: 'malformed', committed: true},
      ...(transport === 'in-process' ? [{reply: 'response_object', committed: true}] : []),
    ]) {
      const f = await fixture(t, transport, scenario.phase, {reply: scenario.reply ?? null, physicalStart: true});
      let error;
      await assert.rejects(f.execution.cancel(f.cancelOptions()), cause => {error = cause; return true;});
      if (scenario.reply === 'response_object') {
        assert.equal(error.code, 'CancellationUnknown', '[check-mutation:cancel-format-uncertainty]');
        assert.equal(error.cause.code, 'InvalidLocalHostPortResponse');
      }
      const before = f.stored();
      assert.equal(before[0].cancellation_requested, scenario.committed ? 1 : 0);
      assert.equal(before[0].physical_close_confirmed, 0);
      assert.deepEqual(f.counts(), {cancelCalls: scenario.committed ? 1 : 0, submits: 0});
      const expected = {observation: 'outcome_unknown',
        summary: 'The Run cancellation outcome is unknown. The request may have been recorded.',
        next: {operation: 'lookupCancellation', cancelRef: f.cancellationRef()}};
      assert.deepEqual(sdk.explainCancellation(error), expected, '[check-mutation:cancel-unknown-explanation]');
      assert.deepEqual(sdk.explainCancellation(error, {locale: 'ja'}), {...expected,
        summary: 'Run取消しの結果を確認できません。要求は記録されている可能性があります。'},
      '[check-mutation:operation-cancel-unknown-public-locale]');

      error.code = 'Accepted'; error.message = 'stopped';
      assert.deepEqual(sdk.explainCancellation(error), expected, '[check-mutation:cancel-unknown-explanation]');
      assert.equal(sdk.explainCancellation(Object.assign(new Error(error.message), error)), undefined);
      await f.execution.status();
      assert.deepEqual(f.stored(), before);
      assert.deepEqual(f.counts(), {cancelCalls: scenario.committed ? 1 : 0, submits: 0});
      assert.deepEqual(sdk.explainCancellation(error), expected);
    }
    if (transport === 'https') {
      const credentials = await fixture(t, transport);
      const failed = new Error('private credential failure');
      credentials.rejectCredentials(failed);
      await assert.rejects(credentials.execution.cancel(credentials.cancelOptions()), error => {
        assert.equal(error, failed);
        assert.equal(sdk.explainCancellation(error), undefined);
        return true;
      });
      assert.deepEqual(credentials.counts(), {cancelCalls: 0, submits: 0});
    }
    const closed = await fixture(t, transport);
    closed.client.close();
    await assert.rejects(closed.execution.cancel(closed.cancelOptions()), error => {
      assert.equal(sdk.explainCancellation(error), undefined);
      return error.code === 'ClientClosed';
    });
    assert.deepEqual(closed.counts(), {cancelCalls: 0, submits: 0});
  });
}


for (const transport of ['in-process', 'https']) {
  test(`${transport}: uninterpretable Run observations retain only the original authorized lookup`, async t => {
    let alter = value => value;
    const setup = await fixture(t, transport, undefined, {transformRunReply: value => alter(value)});
    const {execution} = setup;
    const original = await execution.status();
    assert.equal(original.status, 'running');
    const before = setup.stored();
    for (const [mutation, kind, problem] of [
      [value => ({...value, status: 'private-future-state', next_action: {kind: 'submit'}}), 'uninterpretable', 'unknown_state'],
      [value => ({...value, result_available: 'true'}), 'protocol_failure', 'malformed_response'],
      [value => ({...value, version: 'actql-private-future-state/0.1'}), 'protocol_failure', 'contract_mismatch'],
    ]) {
      alter = mutation;
      const previous = setup.operations.length;
      let error;
      try { await execution.status(); } catch (failure) { error = failure; }
      assert.equal(error?.code, 'InvalidHostRunState', '[check-mutation:run-protocol-public-rejection]');
      const view = sdk.explainRunObservationFailure(error);
      assert.deepEqual({kind: view?.kind, problem: view?.problem, operation: view?.operation},
        {kind, problem, operation: 'status'}, '[check-mutation:run-protocol-public-kind]');
      assert.deepEqual(view.next, {operation: 'status', ref: execution.ref}, '[check-mutation:run-protocol-public-ref]');
      assert.equal(sdk.explainRunObservationFailure({...error}), undefined);
      assert.equal(sdk.explainRunObservationFailure(error, {locale: 'ja'}).kind, kind);
      assert.equal(sdk.explainEffectUncertainty(error), undefined);
      assert.doesNotMatch(JSON.stringify({error, view}), /private-future-state|actql-private/);
      assert.deepEqual(setup.operations.slice(previous), ['status'], '[check-mutation:run-protocol-public-passive]');
      assert.deepEqual(setup.stored(), before);
    }
    alter = value => value;
    assert.deepEqual(await execution.status(), original);
    setup.authorize(false);
    let denied;
    try { await execution.status(); } catch (error) { denied = error; }
    assert.ok(denied);
    const unavailable = sdk.explainRunObservationFailure(denied);
    assert.deepEqual({kind: unavailable.kind, problem: unavailable.problem, operation: unavailable.operation},
      {kind: 'unavailable', problem: 'observation_unavailable', operation: 'status'});
    assert.deepEqual(unavailable.next, {operation: 'status', ref: execution.ref});
    assert.equal(sdk.explainRunObservationFailure({...denied}), undefined);
    assert.equal(sdk.explainEffectUncertainty(denied), undefined);
    assert.deepEqual(setup.counts(), {cancelCalls: 0, submits: 0});
    assert.deepEqual(setup.stored(), before);
  });
}

for (const [entrance, transport] of [['local', 'in-process'], ['https', 'https']]) {
  test(`${entrance}: captured Run getters preserve the first real owner observation`, async t => {
    let reads = 0;
    const f = await fixture(t, transport, undefined, {physicalStart: true,
      transformRunReply: reply => {
        const original = reply.run_id; let observed = false;
        return {...reply, get run_id() {
          reads++;
          if (observed) return 'replacement-run';
          observed = true;
          return original;
        }};
      }});
    const answer = await f.execution.status();
    // HTTPS serializes at the Host boundary; Local hands the accessor directly
    // to the SDK. Both keep the actual original owner fact exactly once.
    assert.equal(answer.run_id, 'saved-run');
    assert.equal(answer.status, 'running');
    assert.equal(answer.control.physical_stop, 'unknown');
    assert.equal(reads, 1);
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
    f.authorize(false);
    await assert.rejects(f.execution.status(), error => error.code === 'ClientConnectionDenied');
    assert.equal(reads, 1);
    assert.deepEqual(f.stored(), f.before);
  });
  test(`${entrance}: copied Run observations retain original owner facts`, async t => {
    let changed = 0, alter = false;
    const f = await fixture(t, transport, undefined, {physicalStart: true,
      transformRunReply(value) {
        if (!alter) return value;
        changed++;
        return {...value, run_id: 'foreign-run-copy',
          control: {...value.control, physical_stop: 'confirmed',
            revision: value.control.revision + 1}};
      }});
    const before = await f.execution.status();
    assert.equal(before.status, 'running');
    assert.equal(before.control.physical_stop, 'unknown');
    alter = true;
    let rejected;
    try { await f.execution.status(); } catch (error) { rejected = error; }
    assert.equal(rejected?.code, 'InvalidHostRunState', '[check-mutation:run-copy-public]');
    assert.ok(changed > 0, 'Fault must affect a Run observation copy');
    assert.deepEqual(sdk.explainRunObservationFailure(rejected), {
      kind: 'protocol_failure', problem: 'stale_observation', operation: 'status',
      summary: 'The Run reply has an older control revision or conflicts with previously observed control facts.',
      hint: 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.',
      next: {operation: 'status', ref: f.execution.ref},
    });
    assert.equal(sdk.explainEffectUncertainty(rejected), undefined);
    assert.equal(Object.hasOwn(rejected, 'cause'), false);
    assert.doesNotMatch(JSON.stringify(rejected), /foreign-run-copy/);
    assert.equal(before.control.physical_stop, 'unknown');
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
    assert.equal(f.operations.filter(operation => operation === 'status').length, 2);
    alter = false;
    const refreshed = await f.execution.status();
    assert.deepEqual(refreshed, before);
    assert.equal(f.operations.filter(operation => operation === 'status').length, 3);
    f.authorize(false);
    let denied;
    try { await f.execution.status(); } catch (error) { denied = error; }
    assert.equal(denied.code, 'ClientConnectionDenied');
    const unavailable = sdk.explainRunObservationFailure(denied);
    assert.deepEqual({kind: unavailable.kind, problem: unavailable.problem, operation: unavailable.operation},
      {kind: 'unavailable', problem: 'observation_unavailable', operation: 'status'});
    assert.deepEqual(unavailable.next, {operation: 'status', ref: f.execution.ref});
    assert.equal(sdk.explainRunObservationFailure({...denied}), undefined);
    assert.equal(sdk.explainEffectUncertainty(denied), undefined);
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
  });
  test(`${entrance}: malformed Run DTO retains the original owner lookup`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true,
      transformRunReply(value) {
        const copy = {...value};
        delete copy.run_id;
        return copy;
      }});
    let rejected;
    try { await f.execution.status(); } catch (error) { rejected = error; }
    assert.equal(rejected?.code, 'InvalidHostRunState');
    const explanation = sdk.explainRunObservationFailure(rejected);
    assert.equal(explanation.kind, 'protocol_failure');
    assert.equal(explanation.problem, 'malformed_response');
    assert.deepEqual(explanation.next, {operation: 'status', ref: f.execution.ref});
    assert.equal(Object.hasOwn(rejected, 'cause'), false);
    assert.equal(sdk.explainEffectUncertainty(rejected), undefined);
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
    assert.deepEqual(f.operations, ['connect', 'attach', 'status']);
  });
  test(`${entrance}: unused Run clone trap cannot replace original owner facts`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true});
    const before = await f.execution.status();
    const clone = globalThis.structuredClone;
    let copies = 0;
    t.mock.method(globalThis, 'structuredClone', value => {
      const copy = clone(value);
      if (value?.version === 'actql-run-state/0.1') {
        copies++;
        copy.run_id = 'foreign-run-copy';
        copy.control.physical_stop = 'confirmed';
      }
      return copy;
    });
    assert.deepEqual(await f.execution.status(), before);
    assert.equal(copies, 0);
    assert.equal(before.control.physical_stop, 'unknown');
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
  });
  test(`${entrance}: request cancellation acceptance retains an unconfirmed physical stop`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true, targetOperation: 'cancel-request'});
    const answer = await f.client.cancelRequest(requestId);
    assert.equal(answer.kind, 'accepted');
    const explanation = sdk.explainRequestCancellation(answer);
    assert.deepEqual({observation: explanation.observation, requestId: explanation.requestId,
      revision: explanation.revision, next: explanation.next}, {
      observation: 'accepted', requestId, revision: f.before[0].revision + 1,
      next: {operation: 'status', ref: {...f.execution.ref}},
    }, '[check-mutation:request-cancel-public]');
    for (const field of ['stopped', 'physicalStop', 'cleanupComplete', 'resourcesReleased', 'runStatus', 'effectOutcome', 'cancelRef', 'permission']) {
      assert.equal(Object.hasOwn(explanation, field), false, '[check-mutation:request-cancel-physical-claim]');
    }
    assert.deepEqual(f.stored(), [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}]);
    const current = await f.execution.status();
    assert.equal(current.control.cancellation_requested, true);
    assert.equal(current.control.physical_stop, 'unknown');
    const before = {...f.counts()};
    for (const locale of ['en', 'ja']) for (const format of ['text', 'html', 'json']) {
      assert.ok(sdk.formatRequestCancellation(answer, {locale, format}));
    }
    assert.deepEqual(f.counts(), before);
    assert.equal(sdk.explainRequestCancellation(structuredClone(answer)), undefined);
    assert.equal(sdk.getSubmissionInput(answer), undefined);
    f.authorize(false);
    await assert.rejects(f.client.lookupRequest(requestId), {code: 'ClientConnectionDenied'});
    assert.deepEqual(f.counts(), before);
  });
  for (const phase of ['before-dispatch', 'after-commit']) {
    test(`${entrance}: request cancellation loss ${phase} keeps the original lookup without inventing acceptance`, async t => {
      const f = await fixture(t, transport, phase, {physicalStart: true, targetOperation: 'cancel-request'});
      let failure;try {await f.client.cancelRequest(requestId);} catch (error) {failure = error;}
      assert.equal(failure.code, 'CancellationUnknown');
      assert.equal(failure.requestId, requestId);
      const explanation = sdk.explainRequestCancellation(failure);
      assert.deepEqual({observation: explanation.observation, problem: explanation.problem,
        requestId: explanation.requestId, operation: explanation.next.operation,
        nextRequestId: explanation.next.requestId, scopeRef: explanation.next.lookupContext.scopeRef}, {
        observation: 'outcome_unknown', problem: 'exchange_failed', requestId,
        operation: 'lookupRequest', nextRequestId: requestId, scopeRef: 'local-principal',
      }, '[check-mutation:request-cancel-loss]');
      const committed = phase === 'after-commit';
      const expected = [{...f.before[0], cancellation_requested: committed ? 1 : 0,
        revision: f.before[0].revision + (committed ? 1 : 0)}];
      assert.deepEqual(f.stored(), expected);
      assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});
      for (const locale of ['en', 'ja']) assert.ok(sdk.formatRequestCancellation(failure, {locale}));
      const found = await f.client.lookupRequest(requestId);
      assert.equal(found.kind, 'found');
      assert.deepEqual(found.ref, f.execution.ref);
      const current = await f.execution.status();
      assert.equal(current.control.cancellation_requested, committed);
      assert.equal(current.control.physical_stop, 'unknown');
      assert.deepEqual(f.stored(), expected);
      assert.equal(f.operations.filter(op => op === 'cancel-request').length, 1);
      assert.equal(f.operations.includes('submit'), false);
      assert.equal(f.operations.includes('reconcile'), false);
    });
  }
  test(`${entrance}: request cancellation already-terminal observation does not invent its Run outcome`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true, terminal: true, targetOperation: 'cancel-request'});
    const answer = await f.client.cancelRequest(requestId);
    assert.equal(answer.kind, 'already_terminal');
    const explanation = sdk.explainRequestCancellation(answer);
    assert.equal(explanation.observation, 'already_terminal');
    assert.equal(explanation.summary, 'The Host reports that this request is already terminal. This response does not establish its execution outcome, physical stop or resource release.');
    assert.deepEqual(explanation.next.ref, f.execution.ref);
    assert.equal(Object.hasOwn(explanation, 'runStatus'), false);
    assert.equal((await f.execution.status()).status, 'failed');
    assert.deepEqual(f.stored(), f.before);
  });
}

for (const field of ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']) {
  test(`in-process: cancellation captures the first getter-backed ${field} association`, async t => {
    let reads = 0;
    const f = await fixture(t, 'in-process', undefined, {physicalStart: true,
      transformCancelReply(value) {
        const original = value.ref[field];
        return {...value, ref: Object.defineProperty({...value.ref}, field, {
          enumerable: true,
          get: () => ++reads <= 2 ? original
            : field === 'namespaceId' ? 'foreign-namespace' : cid('f'),
        })};
      }});
    const ref = {...f.execution.ref};
    const result = await f.execution.cancel().then(value => ({value}), error => ({error}));
    assert.equal(result.error, undefined, '[check-mutation:cancel-reference-capture]');
    assert.deepEqual(result.value.cancellation.ref, ref);
    assert.deepEqual(sdk.explainCancellation(result.value).next, {operation: 'status', ref});
    assert.equal(reads, 1);
    assert.deepEqual(f.stored(), [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}]);
    assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
  });
}


for (const [entrance, transport] of [['local', 'in-process'], ['https', 'https']]) {
  test(`${entrance}: getter-backed Run reply preserves the first owner observation`, async t => {
    let reads = 0, issued;
    const f = await fixture(t, transport, undefined, {physicalStart: true,
      transformRunReply: value => {
        issued = {...value};
        return {...value, get run_id() { return ++reads === 1 ? value.run_id : 'replacement-run'; }};
      }});
    const answer = await f.execution.status();
    assert.equal(answer.run_id, 'saved-run', '[check-mutation:response-capture-public-run]');
    assert.deepEqual(answer, issued);
    assert.equal(reads, 1);
    assert.equal(answer.control.physical_stop, 'unknown');
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
    assert.deepEqual(f.operations, ['connect', 'attach', 'status']);
  });
  test(`${entrance}: getter-backed cancellation preserves issued kind and revision`, async t => {
    const reads = {kind: 0, revision: 0}; let issued;
    const f = await fixture(t, transport, undefined, {physicalStart: true,
      transformCancelReply: value => {
        issued = {...value};
        return {...value,
          get kind() { return ++reads.kind === 1 ? value.kind : 'already_terminal'; },
          get revision() { return ++reads.revision === 1 ? value.revision : 999; }};
      }});
    const answer = await f.execution.cancel();
    assert.deepEqual({kind: answer.cancellation.kind, revision: answer.cancellation.revision},
      {kind: 'accepted', revision: f.before[0].revision + 1}, '[check-mutation:response-capture-public-cancel]');
    assert.deepEqual(answer.cancellation, issued);
    assert.deepEqual(reads, {kind: 1, revision: 1});
    assert.deepEqual(sdk.explainCancellation(answer).next, {operation: 'status', ref: f.execution.ref});
    assert.equal(sdk.explainCancellation(answer).observation, 'accepted');
    assert.equal(sdk.explainCancellation(structuredClone(answer)), undefined);
    assert.deepEqual(f.stored(), [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}]);
    assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
    const current = await f.execution.status();
    assert.equal(current.control.physical_stop, 'unknown');
    assert.notEqual(current.status, 'cancelled');
    // The default cancellation first observes the revision; the later status
    // remains an independent observation of physical-stop uncertainty.
    assert.deepEqual(f.operations, ['connect', 'attach', 'status', 'cancel', 'status']);
  });

  test(`${entrance}: request lookup verification faults preserve original uncertainty and journal custody`, async t => {
    const privateCause = new Error('private-lookup-verification-getter');
    let copies = 0, reads = 0, failure;
    const f = await fixture(t, transport, undefined, {physicalStart: true,
      transformLookupReply(value) {
        copies++;
        const copy = {...value};
        if (transport === 'in-process') return Object.defineProperty(copy, 'ref', {
          enumerable: true, get() { reads++; throw privateCause; }});
        // An HTTP decoder receives DATA, not the server's getter or exception.
        return {...copy, ref: null};
      }});
    const ref = {...f.execution.ref};
    try { await f.client.lookupRequest(requestId); } catch (error) { failure = error; }
    assert.equal(copies, 1);
    assert.equal(reads, transport === 'in-process' ? 1 : 0);
    assert.deepEqual(f.execution.ref, ref);
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
    assert.deepEqual(f.operations, ['connect', 'attach', 'lookup-request']);
    assert.equal(failure?.code, 'InvalidHostRequestLookup', '[lookup-verification:public-classification]');
    assert.notEqual(failure, privateCause);
    const explanation = sdk.explainRequestLookup(failure);
    assert.equal(explanation.observation, 'lookup_uninterpretable');
    assert.equal(explanation.next.operation, 'lookupRequest');
    assert.equal(explanation.next.requestId, requestId);
    assert.equal(explanation.next.lookupContext.scopeRef, 'local-principal');
    assert.equal(sdk.explainRequestLookup({...failure}), undefined);
    const current = await f.execution.status();
    assert.equal(current.status, 'running');
    assert.equal(current.control.physical_stop, 'unknown');
    assert.equal(current.control.cancellation_requested, false);
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
  });
  test(`${entrance}: unused request lookup clone trap cannot replace original custody`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true});
    const clone = globalThis.structuredClone;
    let copies = 0;
    t.mock.method(globalThis, 'structuredClone', value => {
      const copy = clone(value);
      if (value?.kind === 'found' && value.requestId === requestId) {
        copies++;
        Object.defineProperty(copy, 'ref', {enumerable: true,
          get() { throw new Error('private-unused-lookup-getter'); }});
      }
      return copy;
    });
    const answer = await f.client.lookupRequest(requestId);
    assert.equal(copies, 0);
    assert.equal(answer.kind, 'found');
    assert.equal(answer.requestId, requestId);
    assert.deepEqual(answer.ref, f.execution.ref);
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
    assert.deepEqual(f.operations, ['connect', 'attach', 'lookup-request']);
  });

}
