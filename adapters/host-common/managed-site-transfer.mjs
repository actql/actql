// Coordinator-owned orchestration for explicit in-process Site Transfer. The
// concrete copier is an adopted representation provider; common completion and
// physical accounting remain in the existing runtime Core.
import {executionSiteDescription, executionSiteTransferProvider,
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
const exactInteger = (value, expected) => value === expected ||
  (typeof value === 'bigint' && typeof expected === 'number' &&
    Number.isSafeInteger(expected) && value === BigInt(expected)) ||
  (typeof value === 'number' && Number.isSafeInteger(value) &&
    typeof expected === 'bigint' && BigInt(value) === expected);
const validDestination = (destination, estimate, source) =>
  destination !== null && typeof destination === 'object' &&
  destination.material !== null &&
  typeof destination.material === 'object' &&
  destination.material !== source.siteMaterial &&
  destination.material !== source.material &&
  destination.generation !== null &&
  typeof destination.generation === 'object' &&
  destination.generation !== source.materialGeneration &&
  Number.isSafeInteger(destination.rows) && destination.rows >= 0 &&
  Number.isSafeInteger(destination.batches) && destination.batches >= 0 &&
  Number.isSafeInteger(destination.maxBatchRows) &&
  destination.maxBatchRows > 0 &&
  Number.isSafeInteger(destination.maxBatchBytes) &&
  destination.maxBatchBytes > 0 &&
  typeof destination.bytes === 'bigint' && destination.bytes >= 0n &&
  destination.bytes <= estimate.transferBytes &&
  typeof destination.retainedBytes === 'bigint' &&
  destination.retainedBytes >= 0n &&
  destination.retainedBytes <= estimate.retainedBytes &&
  typeof destination.close === 'function' &&
  typeof destination.status === 'function';
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

function transferFailure(
  reason, core, setup, transfer, destination, siteOperation, receipt, holding,
  siteCleanup,
) {
  const upstreamRequired = member(reason, 'cleanupPending') === true;
  const upstream = upstreamRequired
    ? member(reason, 'cleanupHandle') : undefined;
  const upstreamPending = () => upstreamRequired && pending(upstream);
  let finalized = false, destinationClosed = destination === undefined;
  let holdingReleased = holding === undefined;
  let siteCleanupReleased = siteCleanup === undefined;
  let destinationCloseAttempted = destinationClosed;
  let destinationCleanup;
  const failure = ownedTransferFailure(reason);
  const errors = [...failure.cleanupErrors];
  const releaseDestinationCleanup = () => {
    if (!destinationClosed || siteCleanupReleased) return;
    try {
      releaseExecutionSiteCleanup(siteCleanup);
      siteCleanupReleased = true;
    } catch (error) { errors.push(error); }
  };
  const closeDestination = async retry => {
    if (destinationClosed) return;
    if (destinationCleanup !== undefined) {
      if (retry && pending(destinationCleanup) &&
          typeof member(destinationCleanup, 'retry') === 'function') {
        try { await destinationCleanup.retry(); }
        catch (error) { errors.push(error); }
      }
      if (!pending(destinationCleanup)) {
        destinationClosed = true;
        settleExecutionSiteTransferDestination(siteOperation);
        releaseDestinationCleanup();
        return;
      }
      return;
    }
    if (destinationCloseAttempted) return;
    destinationCloseAttempted = true;
    try {
      await destination.close();
      destinationClosed = true;
      settleExecutionSiteTransferDestination(siteOperation);
      releaseDestinationCleanup();
    }
    catch (error) {
      errors.push(error);
      if (member(error, 'cleanupPending') === true &&
          typeof member(member(error, 'cleanupHandle'), 'status') ===
            'function') {
        destinationCleanup = member(error, 'cleanupHandle');
      }
    }
  };
  const finalize = () => {
    if (finalized || upstreamPending() || !destinationClosed) return;
    try {
      if (receipt === undefined) {
        core.transferAbort(setup, transfer, true);
      } else {
        core.transferRelease(setup, receipt);
      }
      finalized = true;
    }
    catch (error) { errors.push(error); }
    if (finalized && !holdingReleased) {
      try {
        releaseExecutionSiteHolding(holding);
        holdingReleased = true;
      } catch (error) { errors.push(error); }
    }
  };
  if (receipt === undefined && upstreamPending()) {
    try { core.transferSettle(setup, transfer, false); }
    catch (error) { errors.push(error); }
  }
  if (!upstreamPending()) {
    settleExecutionSiteTransferSource(siteOperation);
  }
  if (destinationClosed) {
    settleExecutionSiteTransferDestination(siteOperation);
    releaseDestinationCleanup();
  }
  if (destinationClosed && !upstreamPending()) finalize();
  const status = () => Object.freeze({
    pending: !finalized || !holdingReleased || !siteCleanupReleased ||
      !destinationClosed ||
      upstreamPending(),
    errors: Object.freeze([...errors]),
  });
  failure.cleanupPending = status().pending;
  failure.cleanupErrors = status().errors;
  if (failure.cleanupPending) {
    failure.cleanupHandle = Object.freeze({
      status,
      async retry() {
        if (upstreamPending() &&
            typeof member(upstream, 'retry') === 'function') {
          try { await upstream.retry(); } catch (error) { errors.push(error); }
        }
        if (!upstreamPending()) {
          settleExecutionSiteTransferSource(siteOperation);
        }
        await closeDestination(true);
        finalize();
        failure.cleanupPending = status().pending;
        failure.cleanupErrors = status().errors;
        return status();
      },
    });
  }
  return failure;
}

export function createManagedSiteTransferCoordinator(
  setup, core, installation,
) {
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
    if (!entry.destinationClosed) {
      if (entry.destinationCleanup !== undefined) {
        if (entry.retryDestination && pending(entry.destinationCleanup) &&
            typeof member(entry.destinationCleanup, 'retry') === 'function') {
          await entry.destinationCleanup.retry();
        }
        if (pending(entry.destinationCleanup)) throw entry.destinationFailure;
        entry.destinationClosed = true;
      } else if (!entry.destinationCloseAttempted) {
        entry.destinationCloseAttempted = true;
        try {
          await entry.destination.close();
          entry.destinationClosed = true;
        } catch (error) {
          entry.destinationFailure = error;
          if (member(error, 'cleanupPending') === true &&
              typeof member(member(error, 'cleanupHandle'), 'status') ===
                'function') {
            entry.destinationCleanup = member(error, 'cleanupHandle');
          }
          throw error;
        }
      } else {
        throw entry.destinationFailure;
      }
    }
    if (!entry.receiptReleased) {
      core.transferRelease(setup, entry.receipt);
      entry.receiptReleased = true;
    }
    if (!entry.holdingReleased) {
      releaseExecutionSiteHolding(entry.holding);
      entry.holdingReleased = true;
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
    let destination, transfer, receipt, holding;
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
      destination = await provider.copy({
        sourceMaterial: occurrence.siteMaterial,
        input,
        authorize: value =>
          core.managedInputMatches(value, occurrence.material) === true,
        charge: bytes => core.transferCharge(setup, transfer, bytes),
        signal,
        estimate,
      });
      if (!validDestination(destination, estimate, occurrence)) {
        throw fail('InvalidTransferDestination');
      }
      // Source access has returned and the provider's commit boundary has
      // established the destination generation. Settle before retaining it.
      settleExecutionSiteTransferSource(siteOperation);
      core.transferSettle(setup, transfer, true);
      holding = retainExecutionSiteTransferHolding(
        siteOperation,
        destination,
        destination.retainedBytes,
      );
      settleExecutionSiteTransferDestination(siteOperation);
      releaseExecutionSiteCleanup(siteCleanup);
      receipt = core.transferComplete(
        setup, transfer, destination.retainedBytes,
      );
      const receiptFields = core.transferReceipt(receipt);
      if (!Array.isArray(receiptFields) || receiptFields.length !== 5 ||
          !exactInteger(receiptFields[0], occurrence.task) ||
          !(typeof receiptFields[1] === 'bigint' && receiptFields[1] > 0n ||
            Number.isSafeInteger(receiptFields[1]) && receiptFields[1] > 0) ||
          !exactInteger(receiptFields[2], destination.bytes) ||
          !exactInteger(receiptFields[3], destination.retainedBytes) ||
          !exactInteger(receiptFields[4], 1)) {
        throw fail('InvalidTransferReceipt');
      }
      const entry = {
        source: occurrence,
        site: candidate.site,
        material: destination.material,
        generation: destination.generation,
        destination,
        receipt,
        holding,
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
        destinationClosed: false,
        destinationCloseAttempted: false,
        destinationFailure: undefined,
        destinationCleanup: undefined,
        retryDestination: false,
        receiptReleased: false,
        holdingReleased: false,
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
      throw transferFailure(
        reason, core, setup, transfer, destination, siteOperation,
        receipt, holding, siteCleanup,
      );
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
