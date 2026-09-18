// Common Host orchestration for one complete Effect-free Run publication.
// MoonBit owns every contract body, identity, chain verdict and state
// transition. This module sequences Store effects and reports uncertain I/O;
// it never manufactures a semantic body or treats a write as publication.

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
const contractShape = value => exactKeys(value,
  ['name', 'identityField', 'identity', 'wire']) &&
  typeof value.name === 'string' && value.name.length !== 0 &&
  typeof value.identityField === 'string' && value.identityField.length !== 0 &&
  cidPattern.test(value.identity) && typeof value.wire === 'string';

function validateControl(control) {
  if (control === null || typeof control !== 'object' ||
      !['issuePublicationRequest', 'issuePublicationAttempt',
        'issuePublicIndexEntry', 'issuePublicationRecord',
        'effectFreeChainValid', 'effectFreeCommitValid', 'admit']
        .every(name => typeof control[name] === 'function')) {
    fail('InvalidRunPublicationControl');
  }
}

function validateStore(store) {
  if (store === null || typeof store !== 'object' ||
      !['putPublicationContract', 'createAttempt', 'latestRecord',
        'latestRecordContract', 'appendRecord', 'commitIndex',
        'inspectCommittedIndex', 'readPublicationContract']
        .every(name => typeof store[name] === 'function')) {
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

function validateEvidence(evidence) {
  const keys = ['runDefinition', 'invocation', 'definitions', 'artifacts',
    'derivations', 'orderings', 'retentions', 'durableBindings', 'manifest',
    'receipt', 'capturedRun'];
  if (!exactKeys(evidence, keys) ||
      !['definitions', 'artifacts', 'derivations', 'orderings', 'retentions',
        'durableBindings']
        .every(name => Array.isArray(evidence[name])) ||
      evidence.definitions.length === 0 || evidence.artifacts.length === 0) {
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
  if (!exactKeys(request, ['tenantId', 'authorityScopeCid',
    'publicationPolicyCid', 'publicationTargetCid', 'requestedAt']) ||
      typeof request.tenantId !== 'string' || request.tenantId.length === 0 ||
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

async function persistContracts(store, contracts) {
  const persisted = new Set();
  for (const contract of contracts) {
    if (persisted.has(contract.identity)) continue;
    await store.putPublicationContract(contract.name, contract.wire);
    persisted.add(contract.identity);
  }
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
    tenantId: request.tenantId,
    authorityScopeCid: request.authorityScopeCid,
    runDefinitionCid: evidence.runDefinition.identity,
  });
}

async function admittedCommittedIndex(store, control, key) {
  const value = await store.inspectCommittedIndex(key);
  if (value === undefined) return undefined;
  if (!cidPattern.test(value.public_index_entry_cid)) {
    fail('InvalidCommittedPublicationIndex');
  }
  return store.readPublicationContract(
    value.public_index_entry_cid, 'public_index_entry',
  );
}

async function validateExistingCommit(
  store, control, evidence, request, key, limits,
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
  if (storedRequest.identity !== request.identity ||
      control.effectFreeCommitValid(
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
      ) !== true) {
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
  await store.appendRecord(record.wire, {uncommittedConfirmed});
  return record;
}

async function finishCommittedAttempt(
  store, control, attempt, index, now, limits,
) {
  const value = await store.latestRecord(attempt.identity);
  if (value?.state === 'succeeded') return;
  const previous = await store.latestRecordContract(attempt.identity);
  if (previous === undefined ||
      !['committing', 'publication_unknown'].includes(value?.state)) {
    fail('InvalidCommittedPublicationAttempt');
  }
  await appendState(
    store, control, attempt, previous, 'succeeded', now(), limits, index,
  );
}

async function requireActiveAttempt(
  signal, store, control, attempt, now, limits,
) {
  try { signal?.throwIfAborted(); }
  catch (reason) {
    const value = await store.latestRecord(attempt.identity);
    const previous = await store.latestRecordContract(attempt.identity);
    if (previous !== undefined &&
        ['preparing', 'committing'].includes(value?.state)) {
      await appendState(
        store,
        control,
        attempt,
        previous,
        'cancelled',
        now(),
        limits,
        undefined,
        value.state === 'committing',
      );
    }
    throw reason;
  }
}

function uncertainFailure(primary, reconciliation, recordFailure) {
  const failure = new RunPublicationError('RunPublicationUnknown', primary);
  failure.publicationState = 'publication_unknown';
  failure.reconciliationFailure = reconciliation;
  failure.recordFailure = recordFailure;
  return failure;
}

/// Persist and atomically publish one complete Effect-free Run chain.
/// A repeated call with the same immutable request reconciles an existing
/// commit before creating work. Internal Compute completion is never mutated.
export async function publishEffectFreeRun(options) {
  const keys = ['store', 'control', 'evidence', 'request', 'attempt', 'limits',
    'now', 'signal'];
  if (!exactKeys(options, keys)) fail('InvalidRunPublicationOptions');
  const {store, control, evidence, request, attempt, limits, signal} = options;
  validateStore(store);
  validateControl(control);
  validateLimits(limits);
  const contracts = validateEvidence(evidence);
  validateRequest(request);
  validateAttempt(attempt);
  const now = validateClock(options.now);
  if (control.effectFreeChainValid(
    evidence.runDefinition,
    evidence.invocation,
    evidence.definitions,
    evidence.artifacts,
    evidence.manifest,
    evidence.receipt,
    evidence.capturedRun,
    limits,
  ) !== true) {
    fail('InvalidEffectFreeRunPublicationChain');
  }
  const publicationRequest = control.issuePublicationRequest(
    evidence.runDefinition, evidence.definitions, request, limits,
  );
  const publicationAttempt = control.issuePublicationAttempt(
    publicationRequest, evidence.runDefinition, attempt, limits,
  );
  const key = indexKey(request, evidence);
  const existing = await validateExistingCommit(
    store, control, evidence, publicationRequest, key, limits,
  );
  if (existing !== undefined) {
    if (existing.attempt.identity === publicationAttempt.identity) {
      await finishCommittedAttempt(
        store, control, existing.attempt, existing.index, now, limits,
      );
    }
    return Object.freeze({
      state: 'succeeded',
      committed: false,
      idempotent: true,
      request: publicationRequest,
      attempt: existing.attempt,
      index: existing.index,
    });
  }

  signal?.throwIfAborted();
  await persistContracts(store, [...contracts, publicationRequest]);
  await store.createAttempt(publicationAttempt.wire);
  let recordValue = await store.latestRecord(publicationAttempt.identity);
  let record = await store.latestRecordContract(publicationAttempt.identity);
  if (record === undefined) {
    record = await appendState(
      store, control, publicationAttempt, undefined, 'preparing', now(), limits,
    );
    recordValue = JSON.parse(record.wire);
  }
  if (recordValue.state === 'preparing') {
    await requireActiveAttempt(
      signal, store, control, publicationAttempt, now, limits,
    );
    record = await appendState(
      store, control, publicationAttempt, record, 'committing', now(), limits,
    );
    recordValue = JSON.parse(record.wire);
  }
  if (recordValue.state === 'succeeded') {
    fail('CommittedPublicationIndexMissing');
  }
  if (recordValue.state !== 'committing') {
    fail(recordValue.state === 'publication_unknown'
      ? 'RunPublicationReconciliationRequired'
      : 'RunPublicationAttemptTerminal');
  }
  await requireActiveAttempt(
    signal, store, control, publicationAttempt, now, limits,
  );
  const index = control.issuePublicIndexEntry({
    runDefinition: evidence.runDefinition,
    invocation: evidence.invocation,
    manifest: evidence.manifest,
    receipt: evidence.receipt,
    capturedRun: evidence.capturedRun,
    durableBindings: evidence.durableBindings,
    request: publicationRequest,
    attempt: publicationAttempt,
  }, now(), limits);
  let committed;
  try {
    committed = await store.commitIndex(
      index.wire,
      requiredInventory(contracts, publicationRequest, publicationAttempt),
      commitEvidence(evidence),
    );
  } catch (primary) {
    let reconciled;
    try {
      reconciled = await validateExistingCommit(
        store, control, evidence, publicationRequest, key, limits,
      );
    } catch (reconciliation) {
      let recordFailure;
      try {
        await appendState(
          store, control, publicationAttempt, record, 'publication_unknown',
          now(), limits,
        );
      } catch (error) { recordFailure = error; }
      throw uncertainFailure(primary, reconciliation, recordFailure);
    }
    if (reconciled === undefined) throw primary;
    committed = Object.freeze({
      entry: JSON.parse(reconciled.index.wire),
      committed: false,
      idempotent: true,
    });
  }
  const committedIndex = await store.readPublicationContract(
    committed.entry.public_index_entry_cid, 'public_index_entry',
  );
  await finishCommittedAttempt(
    store, control, publicationAttempt, committedIndex, now, limits,
  );
  return Object.freeze({
    state: 'succeeded',
    committed: committed.committed,
    idempotent: committed.idempotent,
    request: publicationRequest,
    attempt: publicationAttempt,
    index: committedIndex,
  });
}
