// Coordinator-owned orchestration for explicit in-process Site Transfer. The
// concrete copier is an adopted representation provider; common completion and
// physical accounting remain in the existing runtime Core.
import {ExecutionAuthorizationError, missingAuthorizationGate} from
  './authorization-gate.mjs';
import {executionSiteDescription, executionSiteTransferProvider,
  executionSiteTransferOperationAvailable,
  releaseExecutionSiteCleanup,
  releaseExecutionSiteHolding,
  retainExecutionSiteTransferHolding,
  retainExecutionSiteCleanup,
  settleExecutionSiteTransferDestination,
  settleExecutionSiteTransferSource,
  startExecutionSiteTransferOperation} from
  './execution-sites.mjs';

const fail = code => Object.assign(new Error(code), {code});
const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};
const pending = handle => {
  if (!handle || typeof member(handle, 'status') !== 'function') return true;
  try { return handle.status()?.pending !== false; } catch { return true; }
};
const validDestinationShape = destination =>
  destination !== null && typeof destination === 'object' &&
  destination.material !== null &&
  typeof destination.material === 'object' &&
  destination.generation !== null &&
  typeof destination.generation === 'object' &&
  Number.isSafeInteger(destination.rows) && destination.rows >= 0 &&
  Number.isSafeInteger(destination.batches) && destination.batches >= 0 &&
  Number.isSafeInteger(destination.maxBatchRows) &&
  destination.maxBatchRows > 0 &&
  Number.isSafeInteger(destination.maxBatchBytes) &&
  destination.maxBatchBytes > 0 &&
  typeof destination.bytes === 'bigint' && destination.bytes >= 0n &&
  typeof destination.retainedBytes === 'bigint' &&
  destination.retainedBytes >= 0n &&
  typeof destination.close === 'function' &&
  typeof destination.status === 'function';
const TRANSFER_AWAIT_SOURCE_STOP = 0;
const TRANSFER_MARK_CLEANUP_PENDING = 1;
const TRANSFER_SETTLE_SOURCE_SITE = 2;
const TRANSFER_SETTLE_RUN = 3;
const TRANSFER_RETAIN_DESTINATION_SITE = 4;
const TRANSFER_SETTLE_DESTINATION_SITE = 5;
const TRANSFER_RELEASE_DESTINATION_CLEANUP = 6;
const TRANSFER_COMPLETE_RUN = 7;
const TRANSFER_RECLAIM_DESTINATION = 8;
const TRANSFER_ABORT_RUN = 9;
const TRANSFER_RELEASE_RUN = 10;
const TRANSFER_RELEASE_SITE_HOLDING = 11;
const TRANSFER_FINISHED = 12;
const ownedTransferFailure = reason => {
  const reasonCode = member(reason, 'code');
  const failure = Object.assign(new Error(
    typeof reasonCode === 'string'
      ? reasonCode : 'ManagedSiteTransferFailed',
    {cause: reason},
  ), {
    code: typeof reasonCode === 'string'
      ? reasonCode : 'ManagedSiteTransferFailed',
    primaryFailure: reason,
  });
  const prior = member(reason, 'cleanupErrors');
  failure.cleanupErrors = Object.freeze(
    Array.isArray(prior) ? [...prior] : [],
  );
  return failure;
};

const transferState = ({
  core,
  setup,
  transfer,
  destination,
  siteOperation,
  receipt,
  holding,
  siteCleanup,
  reason,
}) => {
  const upstreamRequired = member(reason, 'cleanupPending') === true;
  const upstream = upstreamRequired
    ? member(reason, 'cleanupHandle') : undefined;
  return {
    core,
    setup,
    transfer,
    destination,
    siteOperation,
    receipt,
    holding,
    siteCleanup,
    upstreamRequired,
    upstream,
    progress: core.transferProgressBegin(transfer),
    destinationCloseAttempted: destination == null,
    destinationFailure: undefined,
    destinationCleanup: undefined,
    errors: [],
  };
};

const recordTransferFact = (accepted, code) => {
  if (!accepted) throw fail(code);
};

const observeSourceStop = async (state, retry) => {
  if (!state.upstreamRequired) {
    recordTransferFact(
      state.core.transferRecordSourceStop(state.progress),
      'InvalidManagedTransferSourceStop',
    );
    return;
  }
  if (retry && pending(state.upstream) &&
      typeof member(state.upstream, 'retry') === 'function') {
    try { await state.upstream.retry(); }
    catch (error) { state.errors.push(error); }
  }
  if (!pending(state.upstream)) {
    recordTransferFact(
      state.core.transferRecordSourceStop(state.progress),
      'InvalidManagedTransferSourceStop',
    );
  }
};

const reclaimDestination = async (state, retry) => {
  if (state.destination == null) {
    recordTransferFact(
      state.core.transferRecordDestinationReclaimed(state.progress),
      'InvalidManagedTransferDestinationReclaim',
    );
    return true;
  }
  if (state.destinationCleanup !== undefined) {
    if (retry && pending(state.destinationCleanup) &&
        typeof member(state.destinationCleanup, 'retry') === 'function') {
      try { await state.destinationCleanup.retry(); }
      catch (error) { state.errors.push(error); }
    }
    if (!pending(state.destinationCleanup)) {
      recordTransferFact(
        state.core.transferRecordDestinationReclaimed(state.progress),
        'InvalidManagedTransferDestinationReclaim',
      );
      return true;
    }
    return false;
  }
  if (state.destinationCloseAttempted) return false;
  state.destinationCloseAttempted = true;
  try {
    await state.destination.close();
    recordTransferFact(
      state.core.transferRecordDestinationReclaimed(state.progress),
      'InvalidManagedTransferDestinationReclaim',
    );
    return true;
  } catch (error) {
    state.errors.push(error);
    state.destinationFailure = error;
    if (member(error, 'cleanupPending') === true &&
        typeof member(member(error, 'cleanupHandle'), 'status') ===
          'function') {
      state.destinationCleanup = member(error, 'cleanupHandle');
    }
  }
  return false;
};

const driveTransferCommit = state => {
  for (let step = 0; step < 16; step++) {
    const action = state.core.transferCommitAction(state.progress);
    if (action === TRANSFER_AWAIT_SOURCE_STOP) {
      throw fail('ManagedSiteTransferStopUnconfirmed');
    }
    if (action === TRANSFER_SETTLE_SOURCE_SITE) {
      settleExecutionSiteTransferSource(state.siteOperation);
      recordTransferFact(
        state.core.transferRecordSourceSiteSettlement(state.progress),
        'InvalidManagedTransferSourceSiteSettlement',
      );
      continue;
    }
    if (action === TRANSFER_SETTLE_RUN) {
      state.core.transferSettle(state.setup, state.transfer, true);
      continue;
    }
    if (action === TRANSFER_RETAIN_DESTINATION_SITE) {
      state.holding = retainExecutionSiteTransferHolding(
        state.siteOperation,
        state.destination,
        state.destination.retainedBytes,
      );
      recordTransferFact(
        state.core.transferRecordDestinationHolding(state.progress),
        'InvalidManagedTransferDestinationHolding',
      );
      continue;
    }
    if (action === TRANSFER_SETTLE_DESTINATION_SITE) {
      settleExecutionSiteTransferDestination(state.siteOperation);
      recordTransferFact(
        state.core.transferRecordDestinationSiteSettlement(state.progress),
        'InvalidManagedTransferDestinationSiteSettlement',
      );
      continue;
    }
    if (action === TRANSFER_RELEASE_DESTINATION_CLEANUP) {
      releaseExecutionSiteCleanup(state.siteCleanup);
      recordTransferFact(
        state.core.transferRecordDestinationCleanupRelease(state.progress),
        'InvalidManagedTransferDestinationCleanupRelease',
      );
      continue;
    }
    if (action === TRANSFER_COMPLETE_RUN) {
      state.receipt = state.core.transferComplete(
        state.setup,
        state.transfer,
        state.destination.retainedBytes,
      );
      continue;
    }
    if (action === TRANSFER_FINISHED) return state.receipt;
    throw fail('InvalidManagedTransferCommitAction');
  }
  throw fail('ManagedTransferCommitDidNotConverge');
};

const driveTransferCleanup = async (
  state,
  {retryPhysical = false, reclaim = true} = {},
) => {
  await observeSourceStop(state, retryPhysical);
  for (let step = 0; step < 20; step++) {
    const action = state.core.transferCleanupAction(state.progress);
    if (action === TRANSFER_MARK_CLEANUP_PENDING) {
      state.core.transferSettle(state.setup, state.transfer, false);
      continue;
    }
    if (action === TRANSFER_AWAIT_SOURCE_STOP) return false;
    if (action === TRANSFER_SETTLE_SOURCE_SITE) {
      settleExecutionSiteTransferSource(state.siteOperation);
      recordTransferFact(
        state.core.transferRecordSourceSiteSettlement(state.progress),
        'InvalidManagedTransferSourceSiteSettlement',
      );
      continue;
    }
    if (action === TRANSFER_RECLAIM_DESTINATION) {
      if (!reclaim || !await reclaimDestination(state, retryPhysical)) {
        return false;
      }
      continue;
    }
    if (action === TRANSFER_SETTLE_DESTINATION_SITE) {
      settleExecutionSiteTransferDestination(state.siteOperation);
      recordTransferFact(
        state.core.transferRecordDestinationSiteSettlement(state.progress),
        'InvalidManagedTransferDestinationSiteSettlement',
      );
      continue;
    }
    if (action === TRANSFER_RELEASE_DESTINATION_CLEANUP) {
      releaseExecutionSiteCleanup(state.siteCleanup);
      recordTransferFact(
        state.core.transferRecordDestinationCleanupRelease(state.progress),
        'InvalidManagedTransferDestinationCleanupRelease',
      );
      continue;
    }
    if (action === TRANSFER_ABORT_RUN) {
      state.core.transferAbort(state.setup, state.transfer, true);
      continue;
    }
    if (action === TRANSFER_RELEASE_RUN) {
      if (state.receipt === undefined) {
        throw fail('MissingManagedTransferReceipt');
      }
      state.core.transferRelease(state.setup, state.receipt);
      continue;
    }
    if (action === TRANSFER_RELEASE_SITE_HOLDING) {
      releaseExecutionSiteHolding(state.holding);
      recordTransferFact(
        state.core.transferRecordSiteHoldingRelease(state.progress),
        'InvalidManagedTransferSiteHoldingRelease',
      );
      continue;
    }
    if (action === TRANSFER_FINISHED) {
      return true;
    }
    throw fail('InvalidManagedTransferCleanupAction');
  }
  throw fail('ManagedTransferCleanupDidNotConverge');
};

const transferFailure = async (reason, state) => {
  const failure = ownedTransferFailure(reason);
  state.errors.push(...failure.cleanupErrors);
  try {
    await driveTransferCleanup(state, {reclaim: false});
  } catch (error) {
    state.errors.push(error);
  }
  const status = () => Object.freeze({
    pending: state.core.transferCleanupAction(state.progress) !==
      TRANSFER_FINISHED,
    errors: Object.freeze([...state.errors]),
  });
  const refresh = () => {
    const current = status();
    failure.cleanupPending = current.pending;
    failure.cleanupErrors = current.errors;
    return current;
  };
  if (refresh().pending) {
    failure.cleanupHandle = Object.freeze({
      status,
      async retry() {
        try {
          await driveTransferCleanup(state, {
            retryPhysical: true,
            reclaim: true,
          });
        } catch (error) {
          state.errors.push(error);
        }
        return refresh();
      },
    });
  }
  return failure;
};

export function createManagedSiteTransferCoordinator(
  setup, core, installation, {
    authorization = missingAuthorizationGate(),
    subjectCid,
  } = {},
) {
  if (authorization === null || typeof authorization !== 'object' ||
      typeof authorization.authorize !== 'function' ||
      typeof authorization.cover !== 'function' ||
      typeof authorization.isProtectedSite !== 'function') {
    throw fail('InvalidAuthorizationGate');
  }
  // Transfer boundary: the recipient Site, the source Site and the scope are
  // authorized before any copy, reservation or Site transfer operation. An
  // in-process transfer between unprotected Sites carries already captured
  // data inside the Host and is covered without evaluation.
  const authorizeTransfer = async (destination, source, signal) => {
    const destinationKey = executionSiteDescription(destination).key;
    const sourceKey = executionSiteDescription(source).key;
    const scope = Object.freeze({
      connection: destinationKey,
      resource: sourceKey,
      operation: 'transfer',
    });
    if (!authorization.isProtectedSite(destinationKey) &&
        !authorization.isProtectedSite(sourceKey)) {
      authorization.cover('transfer', scope);
      return;
    }
    const decision = await authorization.authorize('transfer', scope, {
      subjectCid,
      signal,
    });
    if (decision.action !== 'dispatch') {
      throw new ExecutionAuthorizationError(decision);
    }
  };
  const provider = executionSiteTransferProvider(installation);
  const contract = provider?.contract;
  const bySource = new WeakMap();
  const entries = new Set();
  let closing;

  const sameOccurrence = (left, right) =>
    left.task === right.task &&
    left.material === right.material &&
    left.site === right.site &&
    left.siteMaterial === right.siteMaterial &&
    left.materialGeneration === right.materialGeneration;
  const cached = (occurrence, destinationSite) => {
    const destinations = bySource.get(occurrence.siteMaterial);
    if (!destinations) return undefined;
    for (const entry of destinations.get(destinationSite) ?? []) {
      if (!entry.closed && sameOccurrence(entry.source, occurrence)) {
        return entry;
      }
    }
    return undefined;
  };
  const remember = (source, destinationSite, entry) => {
    let destinations = bySource.get(source);
    if (!destinations) {
      destinations = new Map();
      bySource.set(source, destinations);
    }
    let retained = destinations.get(destinationSite);
    if (!retained) {
      retained = new Set();
      destinations.set(destinationSite, retained);
    }
    retained.add(entry);
    entries.add(entry);
  };
  const forget = entry => {
    const destinations = bySource.get(entry.source.siteMaterial);
    const retained = destinations?.get(entry.site);
    retained?.delete(entry);
    if (retained?.size === 0) destinations.delete(entry.site);
    if (destinations?.size === 0) {
      bySource.delete(entry.source.siteMaterial);
    }
    entries.delete(entry);
  };
  const releaseEntry = async entry => {
    if (entry.closed) return;
    const complete = await driveTransferCleanup(entry.state, {
      retryPhysical: entry.retryDestination,
      reclaim: true,
    });
    if (!complete) {
      throw entry.state.destinationFailure ??
        fail('ManagedSiteTransferCleanupPending');
    }
    entry.closed = true;
    forget(entry);
  };

  const retryEntry = async entry => {
    entry.retryDestination = true;
    try { await releaseEntry(entry); }
    finally { entry.retryDestination = false; }
  };

  async function create(candidate, occurrence, input, signal) {
    if (!provider) throw fail('MissingTransferProvider');
    const transferPlan = candidate.transfers.find(value =>
      value.input === occurrence);
    if (!transferPlan) throw fail('MissingTransferPlan');
    const estimate = transferPlan.estimate;
    let destination, transfer, state;
    const siteOperation = startExecutionSiteTransferOperation(
      occurrence.site,
      candidate.site,
      Object.freeze({
        retainedBytes: estimate.retainedBytes,
        executionBytes: estimate.executionBytes,
      }),
    );
    const siteCleanup = retainExecutionSiteCleanup(
      candidate.site,
      siteOperation,
    );
    try {
      transfer = core.transferBegin(
        setup,
        occurrence.task,
        estimate.transferBytes,
        estimate.retainedBytes,
        estimate.executionBytes,
      );
      state = transferState({
        core,
        setup,
        transfer,
        destination: undefined,
        siteOperation,
        receipt: undefined,
        holding: undefined,
        siteCleanup,
        reason: undefined,
      });
      destination = await provider.copy({
        sourceMaterial: occurrence.siteMaterial,
        input,
        authorize: value =>
          core.managedInputMatches(value, occurrence.material) === true &&
          executionSiteTransferOperationAvailable(siteOperation),
        destinationAuthorize: value =>
          core.managedInputMatches(value, occurrence.material) === true,
        charge: bytes => core.transferCharge(setup, transfer, bytes),
        signal,
        estimate,
      });
      state.destination = destination;
      state.destinationCloseAttempted = destination == null;
      recordTransferFact(
        state.core.transferRecordSourceStop(state.progress),
        'InvalidManagedTransferSourceStop',
      );
      if (destination != null) {
        recordTransferFact(
          state.core.transferRecordDestinationCreated(state.progress),
          'InvalidManagedTransferDestinationCreation',
        );
      }
      if (!validDestinationShape(destination) ||
          !core.transferRecordDestinationAdmission(
            state.progress,
            Object.freeze({
              distinctMaterial:
                destination.material !== occurrence.siteMaterial &&
                destination.material !== occurrence.material,
              distinctGeneration:
                destination.generation !== occurrence.materialGeneration,
              rows: destination.rows,
              batches: destination.batches,
              maxBatchRows: destination.maxBatchRows,
              maxBatchBytes: destination.maxBatchBytes,
              transferredBytes: destination.bytes,
              retainedBytes: destination.retainedBytes,
              transferLimit: estimate.transferBytes,
              retentionLimit: estimate.retainedBytes,
            }),
          )) {
        throw fail('InvalidTransferDestination');
      }
      if (!executionSiteTransferOperationAvailable(siteOperation)) {
        throw fail('ExecutionSiteTransferCommitRejected');
      }
      const receipt = driveTransferCommit(state);
      const receiptFields = core.transferReceipt(receipt);
      if (!core.transferReceiptMatches(
        receipt,
        transfer,
        occurrence.task,
        destination.bytes,
        destination.retainedBytes,
      ) || !Array.isArray(receiptFields) || receiptFields.length !== 5 ||
          !(typeof receiptFields[1] === 'bigint' && receiptFields[1] > 0n ||
            Number.isSafeInteger(receiptFields[1]) && receiptFields[1] > 0)) {
        throw fail('InvalidTransferReceipt');
      }
      const entry = {
        source: occurrence,
        site: candidate.site,
        material: destination.material,
        generation: destination.generation,
        destination,
        receipt,
        holding: state.holding,
        state,
        record: Object.freeze({
          version: 'actql-managed-site-transfer/0.1',
          transferAttempt: receiptFields[1],
          sourceTask: occurrence.task,
          sourceSite: executionSiteDescription(occurrence.site),
          destinationSite: executionSiteDescription(candidate.site),
          sourceMaterialGeneration: occurrence.materialGeneration,
          destinationMaterialGeneration: destination.generation,
          sourceLogicalView: Object.freeze({
            producerTask: occurrence.task,
            port: 'selected-managed-output',
          }),
          destinationLogicalView: Object.freeze({
            producerTask: occurrence.task,
            port: 'selected-managed-output',
          }),
          codec: contract.codec,
          preservationRule: contract.preservationRule,
          trustBoundary: contract.trustBoundary,
          integrityModel: contract.integrityModel,
          physicalContentDigest: contract.contentDigest,
          logicalIdentity: contract.logicalIdentity,
          rows: destination.rows,
          batches: destination.batches,
          maxBatchRows: destination.maxBatchRows,
          maxBatchBytes: destination.maxBatchBytes,
          transferredBytes: destination.bytes,
          retainedBytes: destination.retainedBytes,
          destinationRetention: 'retained',
          integrity: Object.freeze([
            'source-use-authorized',
            'source-generation-pinned',
            'trusted-typed-values-copied-in-order',
            'destination-generation-retained',
          ]),
        }),
        closed: false,
        retryDestination: false,
      };
      remember(occurrence.siteMaterial, candidate.site, entry);
      return entry;
    } catch (reason) {
      if (transfer === undefined) {
        settleExecutionSiteTransferSource(siteOperation);
        settleExecutionSiteTransferDestination(siteOperation);
        releaseExecutionSiteCleanup(siteCleanup);
        throw reason;
      }
      state ??= transferState({
        core,
        setup,
        transfer,
        destination,
        siteOperation,
        receipt: undefined,
        holding: undefined,
        siteCleanup,
        reason,
      });
      state.upstreamRequired = member(reason, 'cleanupPending') === true;
      state.upstream = state.upstreamRequired
        ? member(reason, 'cleanupHandle') : undefined;
      if (!state.upstreamRequired || !pending(state.upstream)) {
        recordTransferFact(
          state.core.transferRecordSourceStop(state.progress),
          'InvalidManagedTransferSourceStop',
        );
      }
      throw await transferFailure(reason, state);
    }
  }

  let api;
  api = Object.freeze({
    async resolve(candidate, inputs, signal) {
      if (!Array.isArray(inputs) || inputs.length !== candidate.inputs.length) {
        throw fail('InvalidTransferInputCount');
      }
      const physical = [];
      const records = [];
      // Authorize every transfer this activation needs before the first
      // copy, so a later refusal cannot follow a partially started transfer.
      for (let index = 0; index < inputs.length; index++) {
        const occurrence = candidate.inputs[index];
        if (occurrence.site === candidate.site &&
            !candidate.transfers.some(value => value.input === occurrence)) {
          continue;
        }
        const reusable = cached(occurrence, candidate.site);
        if (reusable && !reusable.closed) continue;
        await authorizeTransfer(candidate.site, occurrence.site, signal);
      }
      for (let index = 0; index < inputs.length; index++) {
        const occurrence = candidate.inputs[index];
        if (occurrence.site === candidate.site &&
            !candidate.transfers.some(value => value.input === occurrence)) {
          physical.push(occurrence.siteMaterial);
          continue;
        }
        let entry = cached(occurrence, candidate.site);
        if (!entry || entry.closed) {
          entry = await create(candidate, occurrence, inputs[index], signal);
        } else if (!core.managedInputMatches(
          inputs[index], occurrence.material,
        )) {
          throw fail('ForeignTransferInput');
        }
        physical.push(entry.material);
        records.push(entry.record);
      }
      return Object.freeze({
        materials: Object.freeze(physical),
        records: Object.freeze(records),
      });
    },

    async releaseSource(occurrence) {
      if (!occurrence || typeof occurrence !== 'object' ||
          occurrence.siteMaterial == null) {
        throw fail('InvalidTransferSourceOccurrence');
      }
      const destinations = bySource.get(occurrence.siteMaterial);
      if (!destinations) return;
      const failures = [];
      const retained = [...destinations.values()].flatMap(value => [...value])
        .filter(entry => sameOccurrence(entry.source, occurrence));
      for (const entry of retained) {
        try { await releaseEntry(entry); }
        catch (error) { failures.push(error); }
      }
      if (failures.length) {
        const failure = new AggregateError(
          failures, 'ManagedSiteTransferCleanupFailed',
        );
        const status = () => Object.freeze({
          pending: retained.some(entry => !entry.closed),
          errors: Object.freeze([...failures]),
        });
        failure.cleanupPending = true;
        failure.cleanupHandle = Object.freeze({
          status,
          async retry() {
            const retryFailures = [];
            for (const entry of retained) {
              try { await retryEntry(entry); }
              catch (error) { retryFailures.push(error); }
            }
            failures.push(...retryFailures);
            return status();
          },
        });
        throw failure;
      }
    },

    close() {
      if (closing) return closing;
      if (entries.size === 0) return undefined;
      closing = (async () => {
        const failures = [];
        for (const entry of [...entries].reverse()) {
          try { await releaseEntry(entry); }
          catch (error) { failures.push(error); }
        }
        if (failures.length) {
          const failure = new AggregateError(
            failures, 'ManagedSiteTransferCleanupFailed',
          );
          const status = () => Object.freeze({
            pending: entries.size !== 0,
            errors: Object.freeze([...failures]),
          });
          failure.cleanupPending = true;
          failure.cleanupHandle = Object.freeze({
            status,
            async retry() {
              for (const entry of [...entries].reverse()) {
                try { await retryEntry(entry); }
                catch (error) { failures.push(error); }
              }
              return status();
            },
          });
          throw failure;
        }
      })().finally(() => { closing = undefined; });
      return closing;
    },

    status: () => Object.freeze({retainedTransfers: entries.size}),
  });
  return api;
}
