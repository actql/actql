// Common Host orchestration for one complete Run publication.
// MoonBit owns every contract body, identity, chain verdict and state
// transition. This module sequences Store effects and reports uncertain I/O;
// it never manufactures a semantic body or treats a write as publication.

import {issuedEffectSetReceiptWires} from './effect-receipt-custody.mjs';

export class RunPublicationError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const fail = (code, cause) => { throw new RunPublicationError(code, cause); };
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};
const contractShape = value => exactKeys(value,
  ['name', 'identityField', 'identity', 'wire']) &&
  typeof value.name === 'string' && value.name.length !== 0 &&
  typeof value.identityField === 'string' && value.identityField.length !== 0 &&
  cidPattern.test(value.identity) && typeof value.wire === 'string';

function validateControl(control) {
  if (control === null || typeof control !== 'object' ||
      !['issuePublicationRequest', 'issuePublicationAttempt',
        'issuePublicIndexEntry', 'issuePublicationRecord',
        'publicationAttemptAction', 'publicationCancellationAction',
        'publicationSetupAction',
        'committedPublicationFinalizationAction',
        'supersededPublicationFinalizationAction',
        'publicationCommitFailureAction', 'publicationUnknownRetryAction',
        'effectFreeChainValid', 'effectFreeCommitValid', 'admit']
        .every(name => typeof control[name] === 'function')) {
    fail('InvalidRunPublicationControl');
  }
}

function validateStore(store) {
  if (store === null || typeof store !== 'object' ||
      !['putPublicationContract', 'createAttempt', 'latestRecordContract',
        'appendRecord', 'commitIndex',
        'inspectCommittedIndex', 'confirmCommittedIndex',
        'readPublicationContract',
        'validateCommittedEvidence', 'retireUncommittedPublication']
        .every(name => typeof store[name] === 'function') ||
      store.putPublicationContracts !== undefined &&
        typeof store.putPublicationContracts !== 'function' ||
      store.putOriginalPublicationContracts !== undefined &&
        typeof store.putOriginalPublicationContracts !== 'function' ||
      store.beginPublicationAttempt !== undefined &&
        typeof store.beginPublicationAttempt !== 'function' ||
      store.beginPublicationAttemptWithRecords !== undefined &&
        typeof store.beginPublicationAttemptWithRecords !== 'function' ||
      store.appendInitialPublicationRecords !== undefined &&
        typeof store.appendInitialPublicationRecords !== 'function') {
    fail('InvalidRunPublicationStore');
  }
}

function validateLimits(limits) {
  if (!exactKeys(limits, ['maxWireBytes', 'maxNodes', 'maxDepth']) ||
      !Object.values(limits).every(value =>
        Number.isSafeInteger(value) && value > 0)) {
    fail('InvalidRunPublicationLimits');
  }
}

function validateEvidence(evidence, effectful) {
  const keys = ['runDefinition', 'invocation', 'definitions', 'artifacts',
    'derivations', 'orderings', 'retentions', 'durableBindings', 'manifest',
    'receipt', 'capturedRun'];
  if (!exactKeys(evidence, keys) ||
      !['definitions', 'artifacts', 'derivations', 'orderings', 'retentions',
        'durableBindings']
        .every(name => Array.isArray(evidence[name])) ||
      (effectful === undefined &&
        (evidence.definitions.length === 0 || evidence.artifacts.length === 0))) {
    fail('InvalidRunPublicationEvidence');
  }
  const contracts = [evidence.runDefinition, evidence.invocation,
    ...evidence.definitions, ...evidence.artifacts, ...evidence.derivations,
    ...evidence.orderings, ...evidence.retentions,
    ...evidence.durableBindings, evidence.manifest, evidence.receipt,
    evidence.capturedRun];
  if (!contracts.every(contractShape)) fail('InvalidRunPublicationEvidence');
  return contracts;
}

function validateRequest(request) {
  if (!exactKeys(request, ['namespaceId', 'authorityScopeCid',
    'publicationPolicyCid', 'publicationTargetCid', 'requestedAt']) ||
      typeof request.namespaceId !== 'string' || request.namespaceId.length === 0 ||
      !['authorityScopeCid', 'publicationPolicyCid', 'publicationTargetCid']
        .every(name => cidPattern.test(request[name])) ||
      typeof request.requestedAt !== 'string' ||
      request.requestedAt.length === 0) {
    fail('InvalidRunPublicationRequest');
  }
}

function validateAttempt(attempt) {
  if (!exactKeys(attempt, ['attemptId', 'fenceCid',
    'externalIdempotencyKey', 'startedAt']) ||
      typeof attempt.attemptId !== 'string' || attempt.attemptId.length === 0 ||
      !cidPattern.test(attempt.fenceCid) ||
      attempt.externalIdempotencyKey !== undefined &&
        (typeof attempt.externalIdempotencyKey !== 'string' ||
          attempt.externalIdempotencyKey.length === 0) ||
      typeof attempt.startedAt !== 'string' || attempt.startedAt.length === 0) {
    fail('InvalidRunPublicationAttempt');
  }
}

function validateClock(now) {
  if (typeof now !== 'function') fail('InvalidRunPublicationClock');
  return () => {
    const value = now();
    if (typeof value !== 'string' || value.length === 0) {
      fail('InvalidRunPublicationClock');
    }
    return value;
  };
}

function commitEvidence(evidence) {
  return Object.freeze({
    runDefinition: evidence.runDefinition,
    invocation: evidence.invocation,
    definitions: Object.freeze([...evidence.definitions]),
    artifacts: Object.freeze([...evidence.artifacts]),
    derivations: Object.freeze([...evidence.derivations]),
    orderings: Object.freeze([...evidence.orderings]),
    retentions: Object.freeze([...evidence.retentions]),
    durableBindings: Object.freeze([...evidence.durableBindings]),
    manifest: evidence.manifest,
    receipt: evidence.receipt,
    capturedRun: evidence.capturedRun,
  });
}

async function persistContracts(store, contracts, attempt, initialRecords) {
  const persisted = new Set();
  const selected = [];
  for (const contract of contracts) {
    if (persisted.has(contract.identity)) continue;
    selected.push(contract);
    persisted.add(contract.identity);
  }
  const begin = initialRecords === undefined ? store.beginPublicationAttempt : store.beginPublicationAttemptWithRecords;
  if (attempt !== undefined && begin !== undefined) {
    try {
      await Reflect.apply(begin, store, initialRecords === undefined
        ? [Object.freeze(selected), attempt] : [Object.freeze(selected), attempt, initialRecords]);
    } catch (primary) {
      // Continue only after this original setup's native outcome is confirmed.
      // Never invoke setup again, issue another attempt, or repeat Effect work.
      if (member(primary, 'code') !== 'PublicationMetadataCommitOutcomeUnknown' ||
          member(primary, 'outcome') !== 'unknown') throw primary;
      const cleanup = member(primary, 'cleanupHandle');
      const retry = member(cleanup, 'retry'), status = member(cleanup, 'status');
      const read = member(store, 'readPublicationContract');
      const latest = member(store, 'latestRecordContract');
      // An existing Store may preserve prior progress or a legacy file
      // attempt instead of installing a fresh initial pair. This describes
      // the actual retained mutation; it is not a COMMIT acknowledgement.
      const includesInitial = member(primary,'publicationStartKind') !== 'setup';
      if ([retry, status, read, latest].some(value => typeof value !== 'function')) throw primary;
      try {
        await Reflect.apply(retry, cleanup, []);
        if (member(Reflect.apply(status, cleanup, []), 'pending') !== false) throw primary;
        for (const original of [...selected, attempt, ...(includesInitial ? initialRecords ?? [] : [])]) {
          const confirmed = await Reflect.apply(read, store, [original.identity, original.name]);
          if (confirmed?.name !== original.name || confirmed.identity !== original.identity ||
              confirmed.identityField !== original.identityField || confirmed.wire !== original.wire) throw primary;
        }
        // A body alone is not the installed attempt/progress locator. The same
        // Store must successfully select that locator, even with no record yet.
        const retained = await Reflect.apply(latest, store, [attempt.identity]);
        if (initialRecords !== undefined && includesInitial) {
          const next = initialRecords[initialRecords.length - 1];
          if (retained?.name !== next.name || retained.identity !== next.identity ||
              retained.identityField !== next.identityField || retained.wire !== next.wire) throw primary;
        }
      } catch { throw primary; }
    }
    return true;
  }
  if (selected.length === 0) return false;
  const originals = store.putOriginalPublicationContracts;
  if (originals !== undefined) {
    await Reflect.apply(originals, store, [Object.freeze(selected)]);
    return false;
  }
  const batch = store.putPublicationContracts;
  if (batch !== undefined) {
    // One setup step has no protected action between these immutable bodies.
    // Its existing Store returns only after the group's real durable ACKs.
    await Reflect.apply(batch, store, [Object.freeze(selected.map(contract =>
      Object.freeze({name: contract.name, wire: contract.wire})))]);
    return false;
  }
  for (const contract of selected) {
    await store.putPublicationContract(contract.name, contract.wire);
  }
  return false;
}

function requiredInventory(contracts, request, attempt) {
  return [...new Set([
    ...contracts.map(contract => contract.identity),
    request.identity,
    attempt.identity,
  ])];
}

function indexKey(request, evidence) {
  return Object.freeze({
    namespaceId: request.namespaceId,
    authorityScopeCid: request.authorityScopeCid,
    runDefinitionCid: evidence.runDefinition.identity,
  });
}

async function admittedCommittedIndex(store, control, key) {
  const value = await store.confirmCommittedIndex(key);
  if (value === undefined) return undefined;
  if (!cidPattern.test(value.public_index_entry_cid)) {
    fail('InvalidCommittedPublicationIndex');
  }
  return store.readPublicationContract(
    value.public_index_entry_cid, 'public_index_entry',
  );
}

async function validateExistingCommit(
  store, control, evidence, request, key, limits, effectful,
) {
  const index = await admittedCommittedIndex(store, control, key);
  if (index === undefined) return undefined;
  const value = JSON.parse(index.wire);
  const storedRequest = await store.readPublicationContract(
    value.publication_request_cid, 'publication_request',
  );
  const storedAttempt = await store.readPublicationContract(
    value.publication_attempt_cid, 'publication_attempt',
  );
  if (storedRequest.identity !== request.identity) {
    fail('RunPublicationCommitConflict');
  }
  const valid = await (effectful === undefined
    ? control.effectFreeCommitValid(
        evidence.runDefinition,
        evidence.invocation,
        evidence.definitions,
        evidence.artifacts,
        evidence.derivations,
        evidence.orderings,
        evidence.retentions,
        evidence.durableBindings,
        evidence.manifest,
        evidence.receipt,
        evidence.capturedRun,
        storedRequest,
        storedAttempt,
        index,
        limits,
      )
    : control.effectfulCommitValid(
      effectful.chain, effectful.preview, effectful.receipts,
      storedRequest, storedAttempt, index, limits,
    ));
  if (valid !== true) {
    fail('RunPublicationCommitConflict');
  }
  return Object.freeze({index, attempt: storedAttempt});
}

async function appendState(
  store, control, attempt, previous, state, observedAt, limits,
  index, uncommittedConfirmed = false,
) {
  const record = control.issuePublicationRecord(attempt, previous, {
    state,
    observedAt,
    publicIndexEntry: index,
    failureCid: undefined,
    cleanupOwnerCids: [],
    uncommittedConfirmed,
  }, limits);
  try {
    await store.appendRecord(record.wire, {uncommittedConfirmed});
  } catch (primary) {
    // Confirm only this native progress mutation, never repeat apply or issue
    // another Receipt. Cleanup retirement alone does not prove record storage:
    // the same Store must also admit the exact selected original afterward.
    if (member(primary, 'code') !== 'PublicationMetadataCommitOutcomeUnknown' ||
        member(primary, 'outcome') !== 'unknown') throw primary;
    const cleanup = member(primary, 'cleanupHandle');
    const retry = member(cleanup, 'retry'), status = member(cleanup, 'status');
    const observe = member(store, 'latestRecordContract');
    if (typeof retry !== 'function' || typeof status !== 'function' ||
        typeof observe !== 'function') throw primary;
    try {
      await Reflect.apply(retry, cleanup, []);
      if (member(Reflect.apply(status, cleanup, []), 'pending') !== false) throw primary;
      const confirmed = await Reflect.apply(observe, store, [attempt.identity]);
      if (confirmed?.name !== record.name || confirmed.identity !== record.identity ||
          confirmed.identityField !== record.identityField || confirmed.wire !== record.wire) throw primary;
    } catch { throw primary; }
  }
  return record;
}

function initialPublicationStates(control, attempt, signal, now, limits) {
  const preparing = control.issuePublicationRecord(attempt, undefined, {
    state:'preparing', observedAt:now(), publicIndexEntry:undefined,
    failureCid:undefined, cleanupOwnerCids:[], uncommittedConfirmed:false,
  }, limits);
  if (control.publicationAttemptAction(preparing, false, false) !== 'check_active') {
    fail('InvalidRunPublicationSetupProgress');
  }
  let cancellation, cancelled = false;
  try { signal?.throwIfAborted(); }
  catch (reason) { cancellation = reason; cancelled = true; }
  if (cancelled ? control.publicationCancellationAction(preparing) !== 'cancel_preparing' :
      control.publicationAttemptAction(preparing, true, false) !== 'append_committing') {
    fail('InvalidRunPublicationSetupProgress');
  }
  const next = control.issuePublicationRecord(attempt, preparing, {
    state:cancelled ? 'cancelled' : 'committing', observedAt:now(), publicIndexEntry:undefined,
    failureCid:undefined, cleanupOwnerCids:[], uncommittedConfirmed:false,
  }, limits);
  const records = Object.freeze([preparing, next]);
  return Object.freeze({records, next, cancelled, cancellation});
}

async function appendInitialStates(store, control, attempt, signal, now, limits, prepared) {
  const append = member(store, 'appendInitialPublicationRecords');
  const {records, next, cancelled, cancellation} = prepared ?? initialPublicationStates(control, attempt, signal, now, limits);
  try { await Reflect.apply(append, store, [records]); }
  catch (primary) {
    if (member(primary, 'code') !== 'PublicationMetadataCommitOutcomeUnknown' ||
        member(primary, 'outcome') !== 'unknown') throw primary;
    const cleanup = member(primary, 'cleanupHandle');
    const retry = member(cleanup, 'retry'), status = member(cleanup, 'status');
    const read = member(store, 'readPublicationContract'), latest = member(store, 'latestRecordContract');
    if (typeof retry !== 'function' || typeof status !== 'function' ||
        typeof read !== 'function' || typeof latest !== 'function') throw primary;
    try {
      await Reflect.apply(retry, cleanup, []);
      if (member(Reflect.apply(status, cleanup, []), 'pending') !== false) throw primary;
      for (const original of records) {
        const confirmed = await Reflect.apply(read, store, [original.identity, original.name]);
        if (confirmed?.name !== original.name || confirmed.identity !== original.identity ||
            confirmed.identityField !== original.identityField || confirmed.wire !== original.wire) throw primary;
      }
      const confirmed = await Reflect.apply(latest, store, [attempt.identity]);
      if (confirmed?.name !== next.name || confirmed.identity !== next.identity ||
          confirmed.identityField !== next.identityField || confirmed.wire !== next.wire) throw primary;
    } catch { throw primary; }
  }
  if (cancelled) throw cancellation;
  return next;
}

async function finishCommittedAttempt(
  store, control, attempt, index, now, limits,
) {
  const previous = await store.latestRecordContract(attempt.identity);
  const action = control.committedPublicationFinalizationAction(previous);
  if (action === 'finished') return;
  if (action !== 'append_succeeded') {
    fail('InvalidCommittedPublicationAttempt');
  }
  try {
    await appendState(
      store, control, attempt, previous, 'succeeded', now(), limits, index,
    );
  } catch (error) {
    const current = await store.latestRecordContract(attempt.identity);
    // A competing append can win before the Store checks the transition,
    // rather than at its final link/CAS. Adopt only the same durable success.
    if (!['PublicationRecordConflict', 'InvalidPublicationRecordTransition']
      .includes(error?.code) ||
        control.committedPublicationFinalizationAction(current) !==
          'finished' ||
        JSON.parse(current.wire).public_index_entry_cid !== index.identity) {
      throw error;
    }
  }
}

async function finishSupersededAttempt(
  store, control, attempt, now, limits,
) {
  const previous = await store.latestRecordContract(attempt.identity);
  const action = control.supersededPublicationFinalizationAction(previous);
  if (action === 'finished' || action === 'superseded_confirmed') return;
  if (action !== 'append_superseded') {
    fail('InvalidSupersededPublicationAttempt');
  }
  try {
    await appendState(
      store,
      control,
      attempt,
      previous,
      'cancelled',
      now(),
      limits,
      undefined,
      true,
    );
  } catch (error) {
    const current = await store.latestRecordContract(attempt.identity);
    if (error?.code !== 'PublicationRecordConflict' ||
        control.supersededPublicationFinalizationAction(current) !==
          'superseded_confirmed') {
      throw error;
    }
  }
}

async function finishResolvedCommit(
  store, control, currentAttempt, candidateIndex, index, now, limits,
) {
  const value = JSON.parse(index.wire);
  const winner = await store.readPublicationContract(
    value.publication_attempt_cid, 'publication_attempt',
  );
  await finishCommittedAttempt(store, control, winner, index, now, limits);
  if (winner.identity !== currentAttempt.identity) {
    await finishSupersededAttempt(
      store, control, currentAttempt, now, limits,
    );
    const retired = await store.retireUncommittedPublication(
      candidateIndex.identity,
    );
    return Object.freeze({winner, cleanup: retired.cleanup});
  }
  return Object.freeze({winner, cleanup: undefined});
}

function withPublicationCleanup(value, cleanup) {
  if (cleanup?.status().pending !== true) return Object.freeze(value);
  return Object.freeze({
    ...value,
    cleanupPending: true,
    cleanupHandle: cleanup,
  });
}

async function requireActiveAttempt(
  signal, store, control, attempt, now, limits,
) {
  try { signal?.throwIfAborted(); }
  catch (reason) {
    const previous = await store.latestRecordContract(attempt.identity);
    const action = control.publicationCancellationAction(previous);
    if (action === 'cancel_preparing' || action === 'cancel_committing') {
      await appendState(
        store,
        control,
        attempt,
        previous,
        'cancelled',
        now(),
        limits,
        undefined,
        action === 'cancel_committing',
      );
    }
    throw reason;
  }
}

function cleanupState(handle, required) {
  if (!handle || typeof member(handle, 'status') !== 'function') {
    return {pending: required, errors: []};
  }
  try {
    const value = handle.status();
    return value && typeof value.pending === 'boolean'
      ? {pending: value.pending,
        errors: Array.isArray(value.errors) ? [...value.errors] : []}
      : {pending: true, errors: []};
  } catch (error) { return {pending: true, errors: [error]}; }
}

function capturedComputationLifetime(control, capturedRun) {
  const original = member(control, 'retireCapturedComputation');
  if (original !== undefined && typeof original !== 'function') {
    fail('InvalidCapturedComputationRetirement');
  }
  let retired = false;
  return {
    transferred: false,
    retire() {
      if (retired) return;
      retired = true;
      if (original !== undefined) Reflect.apply(original, control, [capturedRun]);
    },
  };
}

function uncertainFailure(
  primary, reconciliation, recordFailure, control, reconcile, retireComputation,
) {
  const failure = new RunPublicationError('RunPublicationUnknown', primary);
  failure.publicationState = 'publication_unknown';
  failure.reconciliationFailure = reconciliation;
  failure.recordFailure = recordFailure;
  const upstreamRequired = member(primary, 'cleanupPending') === true;
  const upstream = upstreamRequired
    ? member(primary, 'cleanupHandle') : undefined;
  const errors = [];
  let resolved = false;
  let result, flight, computationRetired = false;
  const status = () => {
    const cleanup = cleanupState(upstream, upstreamRequired);
    return Object.freeze({
      pending: !resolved || cleanup.pending,
      outcome: result?.outcome,
      errors: Object.freeze([...cleanup.errors, ...errors]),
    });
  };
  const handle = Object.freeze({
    status,
    retry() {
      if (flight !== undefined) return flight;
      // Install the same flight before any original callback can reenter.
      flight = Promise.resolve().then(async () => {
        let upstreamRetryAttempted = false;
        while (true) {
          const cleanup = cleanupState(upstream, upstreamRequired);
          const action = control.publicationUnknownRetryAction(
            resolved,
            cleanup.pending,
            typeof member(upstream, 'retry') === 'function',
            upstreamRetryAttempted,
          );
          if (action === 'reconcile') {
            try {
              result = await reconcile(upstream);
              resolved = true;
              failure.publicationResult = result.publication;
            } catch (error) {
              errors.push(error);
              throw error;
            }
            continue;
          }
          if (action === 'retry_upstream_cleanup') {
            upstreamRetryAttempted = true;
            try { await upstream.retry(); }
            catch (error) { errors.push(error); }
            continue;
          }
          if (action === 'finished') {
            // Common may finish this retry while its upstream remains pending.
            // Neither that action nor a status observation retires the facts.
            if (resolved && !cleanup.pending && !computationRetired) {
              computationRetired = true;
              retireComputation?.();
            }
            break;
          }
          fail('InvalidRunPublicationUnknownRetry');
        }
        failure.cleanupPending = status().pending;
        failure.cleanupErrors = status().errors;
        return status();
      }).finally(() => {flight = undefined;});
      return flight;
    },
  });
  failure.cleanupPending = true;
  failure.cleanupHandle = handle;
  failure.cleanupErrors = status().errors;
  return failure;
}

// Both Run kinds share one publication progression. Only their exact chain
// admission and Store commit differ; retry and unknown handling do not.
async function publishRun(options, effectful, computationLifetime) {
  const keys = ['store', 'control', 'evidence', 'request', 'attempt', 'limits',
    'now', 'signal'];
  if (!exactKeys(options, keys)) fail('InvalidRunPublicationOptions');
  const {store, control, evidence, request, attempt, limits, signal} = options;
  validateStore(store);
  validateControl(control);
  if (effectful !== undefined &&
      (typeof store.commitEffectfulIndex !== 'function' ||
        typeof store.validateCommittedEffectfulEvidence !== 'function' ||
        typeof control.effectfulCommitValid !== 'function')) {
    fail('InvalidEffectfulRunPublicationBoundary');
  }
  validateLimits(limits);
  const contracts = validateEvidence(evidence, effectful);
  validateRequest(request);
  validateAttempt(attempt);
  const now = validateClock(options.now);
  const publicationRequest = control.issuePublicationRequest(
    evidence.runDefinition, evidence.definitions, request, limits,
  );
  const publicationAttempt = control.issuePublicationAttempt(
    publicationRequest, evidence.runDefinition, attempt, limits,
  );
  const key = indexKey(request, evidence);
  const validateCommit = index => effectful === undefined
    ? store.validateCommittedEvidence(index, evidence)
    : store.validateCommittedEffectfulEvidence({
      ...effectful.preparation, index,
    });
  const lookupCommit = () => validateExistingCommit(
    store, control, evidence, publicationRequest, key, limits, effectful,
  );
  let existingChecked = false;
  let existing;
  let existingEvidenceValidated = false;
  let existingFinalized = false;
  let initialActiveChecked = false;
  let initialPublication;
  let contractsPersisted = false;
  let attemptCreated = false;
  while (true) {
    const action = control.publicationSetupAction(
      existingChecked,
      existing !== undefined,
      existingEvidenceValidated,
      existingFinalized,
      initialActiveChecked,
      contractsPersisted,
      attemptCreated,
    );
    if (action === 'check_existing_commit') {
      existing = await lookupCommit();
      existingChecked = true;
      continue;
    }
    if (action === 'validate_existing_evidence') {
      await validateCommit(existing.index);
      existingEvidenceValidated = true;
      continue;
    }
    if (action === 'finalize_existing_commit') {
      await finishCommittedAttempt(
        store, control, existing.attempt, existing.index, now, limits,
      );
      existingFinalized = true;
      continue;
    }
    if (action === 'return_existing_commit') {
      return Object.freeze({
        state: 'succeeded',
        committed: false,
        idempotent: true,
        request: publicationRequest,
        attempt: existing.attempt,
        index: existing.index,
      });
    }
    if (action === 'check_initial_active') {
      signal?.throwIfAborted();
      if (effectful === undefined && await control.effectFreeChainValid(
        evidence.runDefinition,
        evidence.invocation,
        evidence.definitions,
        evidence.artifacts,
        evidence.manifest,
        evidence.receipt,
        evidence.capturedRun,
        limits,
        signal,
      ) !== true) {
        fail('InvalidEffectFreeRunPublicationChain');
      }
      signal?.throwIfAborted();
      initialActiveChecked = true;
      continue;
    }
    if (action === 'persist_contracts') {
      // Issuing immutable initial records performs no protected action. The
      // selected Store can acknowledge their bodies, attempt and progress in
      // one transaction; later cancellation/current dispatch checks remain.
      initialPublication = typeof store.beginPublicationAttemptWithRecords === 'function'
        ? initialPublicationStates(control, publicationAttempt, signal, now, limits) : undefined;
      attemptCreated = await persistContracts(store, [
        ...contracts, ...(effectful?.contracts ?? []), publicationRequest,
      ], publicationAttempt, initialPublication?.records);
      contractsPersisted = true;
      continue;
    }
    if (action === 'create_attempt') {
      await store.createAttempt(publicationAttempt.wire);
      attemptCreated = true;
      continue;
    }
    if (action === 'enter_attempt_progress') break;
    fail('InvalidRunPublicationSetupProgress');
  }
  let record = await store.latestRecordContract(publicationAttempt.identity);
  if (record !== undefined) {
    if (initialPublication?.cancelled && record.name === initialPublication.next.name &&
        record.identity === initialPublication.next.identity && record.wire === initialPublication.next.wire) {
      throw initialPublication.cancellation;
    }
    initialPublication = undefined;
  }
  let activeChecked = false;
  let index;
  while (true) {
    const action = control.publicationAttemptAction(
      record, activeChecked, index !== undefined,
    );
    if (action === 'append_preparing') {
      const prepared = initialPublication;
      initialPublication = undefined;
      record = typeof store.appendInitialPublicationRecords === 'function'
        ? await appendInitialStates(store, control, publicationAttempt, signal, now, limits, prepared)
        : await appendState(
        store, control, publicationAttempt, undefined, 'preparing', now(),
        limits,
      );
      activeChecked = false;
      continue;
    }
    if (action === 'check_active') {
      await requireActiveAttempt(
        signal, store, control, publicationAttempt, now, limits,
      );
      activeChecked = true;
      continue;
    }
    if (action === 'append_committing') {
      record = await appendState(
        store, control, publicationAttempt, record, 'committing', now(),
        limits,
      );
      activeChecked = false;
      continue;
    }
    if (action === 'issue_index') {
      index = control.issuePublicIndexEntry({
        runDefinition: evidence.runDefinition,
        invocation: evidence.invocation,
        manifest: evidence.manifest,
        receipt: evidence.receipt,
        capturedRun: evidence.capturedRun,
        durableBindings: evidence.durableBindings,
        request: publicationRequest,
        attempt: publicationAttempt,
      }, now(), limits);
      continue;
    }
    if (action === 'commit_index') break;
    if (action === 'require_reconciliation') {
      fail('RunPublicationReconciliationRequired');
    }
    if (action === 'reject_missing_index') {
      fail('CommittedPublicationIndexMissing');
    }
    if (action === 'reject_terminal') fail('RunPublicationAttemptTerminal');
    fail('InvalidRunPublicationProgress');
  }
  let committed;
  try {
    const inventory = requiredInventory([
      ...contracts, ...(effectful?.contracts ?? []),
    ], publicationRequest, publicationAttempt);
    committed = effectful === undefined
      ? await store.commitIndex(
        index.wire, inventory, commitEvidence(evidence),
      )
      : await store.commitEffectfulIndex({
        ...effectful.preparation, index,
      }, [...new Set([...inventory, ...effectful.sourceSchemaCids])]);
  } catch (primary) {
    let reconciliationAttempted = false;
    let reconciliationFailed = false;
    let reconciled;
    let reconciliationFailure;
    let unknownAppendAttempted = false;
    let recordFailure;
    while (true) {
      const action = control.publicationCommitFailureAction(
        reconciliationAttempted,
        reconciliationFailed,
        reconciled !== undefined,
        unknownAppendAttempted,
      );
      if (action === 'reconcile_commit') {
        reconciliationAttempted = true;
        try {
          reconciled = await lookupCommit();
        } catch (error) {
          reconciliationFailed = true;
          reconciliationFailure = error;
        }
        continue;
      }
      if (action === 'append_unknown') {
        unknownAppendAttempted = true;
        try {
          await appendState(
            store, control, publicationAttempt, record,
            'publication_unknown', now(), limits,
          );
        } catch (error) { recordFailure = error; }
        continue;
      }
      if (action === 'return_unknown') {
        const reconcile = async upstream => {
          const resolved = await lookupCommit();
          if (resolved === undefined) {
            if (typeof member(upstream, 'resolveConfirmed') === 'function') {
              upstream.resolveConfirmed(undefined);
            }
            return Object.freeze({outcome: 'uncommitted'});
          }
          await validateCommit(resolved.index);
          const resolution = await finishResolvedCommit(
            store,
            control,
            publicationAttempt,
            index,
            resolved.index,
            now,
            limits,
          );
          return Object.freeze({
            outcome: 'committed',
            publication: withPublicationCleanup({
              state: 'succeeded',
              committed: false,
              idempotent: true,
              request: publicationRequest,
              attempt: resolution.winner,
              index: resolved.index,
            }, resolution.cleanup),
          });
        };
        const failure = uncertainFailure(
          primary,
          reconciliationFailure,
          recordFailure,
          control,
          reconcile,
          computationLifetime?.retire,
        );
        if (computationLifetime !== undefined) computationLifetime.transferred = true;
        throw failure;
      }
      if (action === 'confirm_uncommitted_failure') {
        const cleanup = member(primary, 'cleanupHandle');
        if (member(primary, 'cleanupPending') === true &&
            typeof member(cleanup, 'resolveConfirmed') === 'function') {
          cleanup.resolveConfirmed(undefined);
        }
        throw primary;
      }
      if (action !== 'adopt_committed_index') {
        fail('InvalidRunPublicationCommitFailure');
      }
      await validateCommit(reconciled.index);
      committed = Object.freeze({
        entry: JSON.parse(reconciled.index.wire),
        committed: false,
        idempotent: true,
      });
      break;
    }
  }
  const committedIndex = await store.readPublicationContract(
    committed.entry.public_index_entry_cid, 'public_index_entry',
  );
  const resolution = await finishResolvedCommit(
    store,
    control,
    publicationAttempt,
    index,
    committedIndex,
    now,
    limits,
  );
  return withPublicationCleanup({
    state: 'succeeded',
    committed: committed.committed,
    idempotent: committed.idempotent,
    request: publicationRequest,
    attempt: resolution.winner,
    index: committedIndex,
  }, resolution.cleanup);
}

/// Persist and atomically publish one complete Effect-free Run chain.
/// A repeated immutable request reconciles the existing commit without
/// changing the internal Compute outcome.
export async function publishEffectFreeRun(options) {
  const lifetime = capturedComputationLifetime(options?.control, options?.evidence?.capturedRun);
  try { return await publishRun(options, undefined, lifetime); }
  finally {
    // A same-original Unknown owns its reconciliation closure beyond return.
    // Ordinary terminal paths no longer need the completed computation fact.
    if (!lifetime.transferred) lifetime.retire();
  }
}

// The caller must first establish each physical row outcome from the saved
// response and issue the complete set through the common MoonBit owner.
// This boundary only sequences final publication and never sends an Effect.
export async function publishEffectfulRun(options) {
  if (!exactKeys(options, [
    'store', 'control', 'chain', 'preview', 'ledger', 'issuedSet',
    'effectSources', 'sourceArtifacts', 'request', 'attempt', 'limits',
    'now', 'signal',
  ])) fail('InvalidEffectfulRunPublicationOptions');
  const {store, control, chain, preview, ledger, issuedSet, effectSources,
    sourceArtifacts, limits} = options;
  if (!chain || !Array.isArray(chain.definitions) ||
      !Array.isArray(chain.artifacts) ||
      !Array.isArray(chain.durableBindings) ||
      !Array.isArray(effectSources) ||
      !Array.isArray(sourceArtifacts) ||
      effectSources.length !== sourceArtifacts.length ||
      typeof control?.issueEffectfulFinalRunReceipt !== 'function' ||
      typeof control?.effectSetReceiptRunDisposition !== 'function' ||
      typeof control?.effectPrivateEvidenceBinding !== 'function' ||
      typeof control?.capturedEffectSourceArtifactCid !== 'function' ||
      !contractShape(chain.computationReceipt) ||
      typeof store?.storeAuthorityCid !== 'string') {
    fail('InvalidEffectfulRunPublicationEvidence');
  }
  validateLimits(limits);
  const issuedWires = issuedEffectSetReceiptWires(
    issuedSet, ledger, preview,
  );
  const disposition = control.effectSetReceiptRunDisposition(
    preview, issuedWires, limits,
  );
  if (disposition === 1) fail('EffectfulRunNeedsReconciliation');
  if (disposition === 2) fail('EffectfulRunFailed');
  if (disposition !== 0) fail('InvalidEffectSetRunDisposition');
  const issuedFinal = control.issueEffectfulFinalRunReceipt(
    chain, preview, issuedWires, limits,
  );
  const receipts = Object.freeze({...issuedWires,
    finalWire: issuedFinal.wire});
  const setReceipt = control.admit(
    'effect_set_apply_receipt', receipts.setWire, limits,
  );
  const memberReceipts = receipts.memberWires.map(wire =>
    control.admit('effect_apply_receipt', wire, limits));
  const sourceSchemaCids = [];
  const admittedSourceArtifacts = [];
  for (let index = 0; index < effectSources.length; index++) {
    const artifact = sourceArtifacts[index];
    if (!contractShape(artifact) ||
        artifact.name !== 'effect_source_artifact' ||
        artifact.identity !==
          control.capturedEffectSourceArtifactCid(effectSources[index])) {
      fail('InvalidEffectfulSourceInventory');
    }
    const admitted = control.admit(
      'effect_source_artifact', artifact.wire, limits,
    );
    if (admitted.identity !== artifact.identity) {
      fail('InvalidEffectfulSourceInventory');
    }
    admittedSourceArtifacts.push(admitted);
    const body = JSON.parse(admitted.wire);
    if (!cidPattern.test(body.result_schema_cid)) {
      fail('InvalidEffectfulSourceInventory');
    }
    sourceSchemaCids.push(body.result_schema_cid);
  }
  const evidence = Object.freeze({
    runDefinition: chain.runDefinition,
    invocation: chain.invocation,
    definitions: chain.definitions,
    artifacts: chain.artifacts,
    derivations: chain.derivations,
    orderings: chain.orderings,
    retentions: chain.retentions,
    durableBindings: chain.durableBindings,
    manifest: chain.manifest,
    receipt: issuedFinal,
    capturedRun: chain.capturedRun,
  });
  const privateBinding = control.effectPrivateEvidenceBinding(
    preview, store.storeAuthorityCid,
  );
  const effectful = Object.freeze({
    chain, preview, receipts,
    contracts: Object.freeze([
      chain.computationReceipt, setReceipt, ...memberReceipts,
      ...admittedSourceArtifacts,
    ]),
    sourceSchemaCids: Object.freeze(sourceSchemaCids),
    preparation: Object.freeze({
      chain, preview, receipts, privateBinding, effectSources,
    }),
  });
  return publishRun({
    store, control, evidence, request: options.request,
    attempt: options.attempt, limits, now: options.now,
    signal: options.signal,
  }, effectful);
}
