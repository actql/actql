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
  const previous = await store.latestRecordContract(attempt.identity);
  const action = control.committedPublicationFinalizationAction(previous);
  if (action === 0) return;
  if (action !== 1) {
    fail('InvalidCommittedPublicationAttempt');
  }
  try {
    await appendState(
      store, control, attempt, previous, 'succeeded', now(), limits, index,
    );
  } catch (error) {
    const current = await store.latestRecordContract(attempt.identity);
    if (error?.code !== 'PublicationRecordConflict' ||
        control.committedPublicationFinalizationAction(current) !== 0) {
      throw error;
    }
  }
}

async function finishSupersededAttempt(
  store, control, attempt, now, limits,
) {
  const previous = await store.latestRecordContract(attempt.identity);
  const action = control.supersededPublicationFinalizationAction(previous);
  if (action === 0 || action === 3) return;
  if (action !== 2) {
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
        control.supersededPublicationFinalizationAction(current) !== 3) {
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
    if (action === 1 || action === 2) {
      await appendState(
        store,
        control,
        attempt,
        previous,
        'cancelled',
        now(),
        limits,
        undefined,
        action === 2,
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

function uncertainFailure(
  primary, reconciliation, recordFailure, control, reconcile,
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
  let result;
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
    async retry() {
      let upstreamRetryAttempted = false;
      while (true) {
        const cleanup = cleanupState(upstream, upstreamRequired);
        const action = control.publicationUnknownRetryAction(
          resolved,
          cleanup.pending,
          typeof member(upstream, 'retry') === 'function',
          upstreamRetryAttempted,
        );
        if (action === 0) {
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
        if (action === 1) {
          upstreamRetryAttempted = true;
          try { await upstream.retry(); }
          catch (error) { errors.push(error); }
          continue;
        }
        if (action === 2) break;
        fail('InvalidRunPublicationUnknownRetry');
      }
      failure.cleanupPending = status().pending;
      failure.cleanupErrors = status().errors;
      return status();
    },
  });
  failure.cleanupPending = true;
  failure.cleanupHandle = handle;
  failure.cleanupErrors = status().errors;
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
  let existingChecked = false;
  let existing;
  let existingEvidenceValidated = false;
  let existingFinalized = false;
  let initialActiveChecked = false;
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
    if (action === 0) {
      existing = await validateExistingCommit(
        store, control, evidence, publicationRequest, key, limits,
      );
      existingChecked = true;
      continue;
    }
    if (action === 1) {
      await store.validateCommittedEvidence(existing.index, evidence);
      existingEvidenceValidated = true;
      continue;
    }
    if (action === 2) {
      await finishCommittedAttempt(
        store, control, existing.attempt, existing.index, now, limits,
      );
      existingFinalized = true;
      continue;
    }
    if (action === 3) {
      return Object.freeze({
        state: 'succeeded',
        committed: false,
        idempotent: true,
        request: publicationRequest,
        attempt: existing.attempt,
        index: existing.index,
      });
    }
    if (action === 4) {
      signal?.throwIfAborted();
      initialActiveChecked = true;
      continue;
    }
    if (action === 5) {
      await persistContracts(store, [...contracts, publicationRequest]);
      contractsPersisted = true;
      continue;
    }
    if (action === 6) {
      await store.createAttempt(publicationAttempt.wire);
      attemptCreated = true;
      continue;
    }
    if (action === 7) break;
    fail('InvalidRunPublicationSetupProgress');
  }
  let record = await store.latestRecordContract(publicationAttempt.identity);
  let activeChecked = false;
  let index;
  while (true) {
    const action = control.publicationAttemptAction(
      record, activeChecked, index !== undefined,
    );
    if (action === 0) {
      record = await appendState(
        store, control, publicationAttempt, undefined, 'preparing', now(),
        limits,
      );
      activeChecked = false;
      continue;
    }
    if (action === 1) {
      await requireActiveAttempt(
        signal, store, control, publicationAttempt, now, limits,
      );
      activeChecked = true;
      continue;
    }
    if (action === 2) {
      record = await appendState(
        store, control, publicationAttempt, record, 'committing', now(),
        limits,
      );
      activeChecked = false;
      continue;
    }
    if (action === 3) {
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
    if (action === 4) break;
    if (action === 5) fail('RunPublicationReconciliationRequired');
    if (action === 6) fail('CommittedPublicationIndexMissing');
    if (action === 7) fail('RunPublicationAttemptTerminal');
    fail('InvalidRunPublicationProgress');
  }
  let committed;
  try {
    committed = await store.commitIndex(
      index.wire,
      requiredInventory(contracts, publicationRequest, publicationAttempt),
      commitEvidence(evidence),
    );
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
      if (action === 0) {
        reconciliationAttempted = true;
        try {
          reconciled = await validateExistingCommit(
            store, control, evidence, publicationRequest, key, limits,
          );
        } catch (error) {
          reconciliationFailed = true;
          reconciliationFailure = error;
        }
        continue;
      }
      if (action === 1) {
        unknownAppendAttempted = true;
        try {
          await appendState(
            store, control, publicationAttempt, record,
            'publication_unknown', now(), limits,
          );
        } catch (error) { recordFailure = error; }
        continue;
      }
      if (action === 2) {
        const reconcile = async upstream => {
          const resolved = await validateExistingCommit(
            store, control, evidence, publicationRequest, key, limits,
          );
          if (resolved === undefined) {
            if (typeof member(upstream, 'resolveConfirmed') === 'function') {
              upstream.resolveConfirmed(undefined);
            }
            return Object.freeze({outcome: 'uncommitted'});
          }
          await store.validateCommittedEvidence(resolved.index, evidence);
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
        throw uncertainFailure(
          primary,
          reconciliationFailure,
          recordFailure,
          control,
          reconcile,
        );
      }
      if (action === 3) {
        const cleanup = member(primary, 'cleanupHandle');
        if (member(primary, 'cleanupPending') === true &&
            typeof member(cleanup, 'resolveConfirmed') === 'function') {
          cleanup.resolveConfirmed(undefined);
        }
        throw primary;
      }
      if (action !== 4) fail('InvalidRunPublicationCommitFailure');
      await store.validateCommittedEvidence(reconciled.index, evidence);
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
