// Common sequencing for one authorized Result delivery. MoonBit owns grant,
// attempt, receipt, serialization, and transition semantics. Store and sink
// adapters own durable effects and exact byte-exposure observations.

export class ResultDeliveryError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail = (code, cause) => { throw new ResultDeliveryError(code, cause); };
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const digestPattern = /^[0-9a-f]{64}$/u;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const contractShape = value => exactKeys(value,
  ['name', 'identityField', 'identity', 'wire']) &&
  typeof value.name === 'string' && value.name.length !== 0 &&
  typeof value.identityField === 'string' &&
  cidPattern.test(value.identity) && typeof value.wire === 'string';

function validateStore(store) {
  if (store === null || typeof store !== 'object' ||
      !['confirmCommittedIndex', 'readPublicationContract',
        'createDeliveryAttempt', 'latestDeliveryRecord',
        'latestDeliveryRecordContract', 'confirmDeliveryRecord',
        'appendDeliveryRecord',
        'putPublicationContract', 'withCommittedResultRows']
        .every(name => typeof store[name] === 'function')) {
    fail('InvalidResultDeliveryStore');
  }
}

function validateControl(control) {
  if (control === null || typeof control !== 'object' ||
      !['admit', 'issueDeliveryAttempt', 'deliveryResultDefinitionCid',
        'resultReadGrantAllowsBytes', 'resultReadGrantValidAt',
        'issueDeliveryRecord', 'issueResultDeliveryReceipt',
        'prepareResultDeliverySerializer', 'beginResultDelivery',
        'nextResultDeliveryRow', 'finishResultDelivery',
        'existingDeliveryAttemptAction', 'deliveryFailureTerminalAction',
        'deliveryRecordRetryAction']
        .every(name => typeof control[name] === 'function')) {
    fail('InvalidResultDeliveryControl');
  }
}

function selectDeliveryAttempt(control, admitted, proposed, index, manifest,
  grant, request, limits) {
  try {
    if (typeof admitted?.created !== 'boolean' || admitted.attempt === null ||
        typeof admitted.attempt !== 'object' || Array.isArray(admitted.attempt)) {
      fail('InvalidResultDeliveryAttemptState');
    }
    // Store selects the canonical birth time for a logical attempt. Admit its
    // complete contract, then check every binding through the existing issuer.
    const selected = control.admit('delivery_attempt',
      JSON.stringify(admitted.attempt), limits);
    const expected = control.issueDeliveryAttempt(index, manifest, grant, {
      ...request, requestedAt: JSON.parse(selected.wire).requested_at,
    }, limits);
    if (selected.identity !== expected.identity || selected.wire !== expected.wire ||
        admitted.created && selected.wire !== proposed.wire) {
      fail('InvalidResultDeliveryAttemptState');
    }
    return selected;
  } catch (cause) {
    if (cause instanceof ResultDeliveryError) throw cause;
    fail('InvalidResultDeliveryAttemptState', cause);
  }
}

function validateRequest(options) {
  if (!exactKeys(options, [
    'store', 'control', 'indexKey', 'grant', 'resultName', 'format',
    'attemptId', 'limits', 'frameLimits', 'now', 'sink', 'createDigest',
    'authorize', 'signal',
  ]) || !exactKeys(options.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof options.indexKey.namespaceId !== 'string' ||
      options.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(options.indexKey.authorityScopeCid) ||
      !cidPattern.test(options.indexKey.runDefinitionCid) ||
      !contractShape(options.grant) ||
      typeof options.resultName !== 'string' ||
      options.resultName.length === 0 ||
      !['json', 'jsonl', 'csv'].includes(options.format) ||
      typeof options.attemptId !== 'string' ||
      options.attemptId.length === 0 ||
      !exactKeys(options.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(options.limits).every(value =>
        Number.isSafeInteger(value) && value > 0) ||
      !exactKeys(options.frameLimits, [
        'maxRowBytes', 'maxDepth', 'maxFrameBytes',
      ]) || !Object.values(options.frameLimits).every(value =>
        Number.isSafeInteger(value) && value > 0) ||
      typeof options.now !== 'function' ||
      typeof options.sink?.write !== 'function' ||
      typeof options.sink?.finish !== 'function' ||
      typeof options.createDigest !== 'function' ||
      typeof options.authorize !== 'function' ||
      options.signal !== undefined &&
        (options.signal === null ||
          typeof options.signal.throwIfAborted !== 'function')) {
    fail('InvalidResultDeliveryRequest');
  }
}

async function requireCurrentAuthorization(authorize, facts) {
  if (await authorize(Object.freeze(facts)) !== true) {
    fail('ResultDeliveryDenied');
  }
}

function trustedNow(now) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidResultDeliveryClock');
  }
  return value;
}

class SinkWriteFailure extends Error {
  constructor(cause, confirmedBytes, exposure, possibleUnconfirmedMaxBytes) {
    super('ResultDeliverySinkWriteFailed', {cause});
    this.cause = cause;
    this.confirmedBytes = confirmedBytes;
    this.exposure = exposure;
    this.possibleUnconfirmedMaxBytes = possibleUnconfirmedMaxBytes;
  }
}

function sinkFailure(reason, length) {
  const progress = reason !== null && typeof reason === 'object'
    ? reason.deliveryProgress : undefined;
  if (progress !== null && typeof progress === 'object' &&
      Number.isSafeInteger(progress.confirmedBytes) &&
      progress.confirmedBytes >= 0 && progress.confirmedBytes <= length &&
      ['exact', 'unknown_additional'].includes(progress.exposure) &&
      (progress.exposure === 'exact' &&
        progress.possibleUnconfirmedMaxBytes === undefined ||
        progress.exposure === 'unknown_additional' &&
        Number.isSafeInteger(progress.possibleUnconfirmedMaxBytes) &&
        progress.possibleUnconfirmedMaxBytes >= 0 &&
        progress.possibleUnconfirmedMaxBytes <=
          length - progress.confirmedBytes)) {
    return new SinkWriteFailure(
      reason,
      progress.confirmedBytes,
      progress.exposure,
      progress.possibleUnconfirmedMaxBytes,
    );
  }
  return new SinkWriteFailure(reason, 0, 'unknown_additional', length);
}

async function appendExactRecord(store, record) {
  return store.appendDeliveryRecord(record.wire);
}

class DeliveryRecordDurabilityFailure extends ResultDeliveryError {}

function pendingRecordFailure(
  code,
  reason,
  store,
  control,
  records,
  recordFailure,
) {
  const failure = new DeliveryRecordDurabilityFailure(code, reason);
  const errors = [recordFailure];
  let pending = true;
  let nextRecord = 0;
  let retrying;
  const status = () => Object.freeze({
    pending,
    errors: Object.freeze([...errors]),
  });
  const update = () => {
    const current = status();
    failure.cleanupPending = current.pending;
    failure.cleanupErrors = current.errors;
    return current;
  };
  failure.cleanupHandle = Object.freeze({
    status,
    retry() {
      if (retrying !== undefined) return retrying;
      // Install the shared flight before invoking either port. Only this loop
      // may advance the retained cursor; a later flight resumes after failure.
      retrying = Promise.resolve().then(async () => {
        while (true) {
          const action = control.deliveryRecordRetryAction(
            nextRecord, records.length,
          );
          if (action === 'finished') {
            pending = false;
            break;
          }
          if (action !== 'append_next_record') {
            fail('InvalidResultDeliveryRecordRetry');
          }
          try {
            await appendExactRecord(store, records[nextRecord]);
            nextRecord++;
          } catch (error) {
            errors.push(error);
            break;
          }
        }
        pending = nextRecord < records.length;
        return update();
      }).finally(() => { retrying = undefined; });
      return retrying;
    },
  });
  update();
  return failure;
}

function pendingTerminalFailure(
  reason, store, control, terminal, recordFailure,
) {
  return pendingRecordFailure(
    'ResultDeliveryFailed', reason, store, control, [terminal], recordFailure,
  );
}

async function finishSink(sink, signal) {
  let result;
  try { result = await sink.finish(signal); }
  catch (cause) {
    fail('ResultDeliverySinkCompletionFailed', cause);
  }
  if (!exactKeys(result, ['confirmed']) || result.confirmed !== true) {
    fail('ResultDeliverySinkCompletionUnknown');
  }
}

export async function deliverPublishedResult(options) {
  validateRequest(options);
  validateStore(options.store);
  validateControl(options.control);
  const {store, control, indexKey, grant, resultName, format, attemptId,
    limits, frameLimits, now, sink, createDigest, authorize, signal} = options;
  signal?.throwIfAborted();

  const entry = await store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('ResultDeliveryDenied');
  const index = await store.readPublicationContract(
    entry.public_index_entry_cid, 'public_index_entry',
  );
  const manifest = await store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const requestedAt = trustedNow(now);
  const authorizationFacts = Object.freeze({
    index,
    manifest,
    grant,
    resultName,
    format,
    attemptId,
  });
  await requireCurrentAuthorization(authorize, {
    ...authorizationFacts,
    stage: 'attempt',
    observedAt: requestedAt,
  });
  const proposed = control.issueDeliveryAttempt(
    index,
    manifest,
    grant,
    {resultName, format, attemptId, requestedAt},
    limits,
  );
  const admitted = await store.createDeliveryAttempt(
    proposed.wire, grant.wire,
  );
  const attempt = selectDeliveryAttempt(control, admitted, proposed, index,
    manifest, grant, {resultName, format, attemptId}, limits);
  if (!admitted.created) {
    const existing = await store.latestDeliveryRecordContract(
      attempt.identity,
    );
    // Another caller may own the first record commit. Absence is not authority
    // to start a second stream or consume another grant use.
    if (existing === undefined) fail('ResultDeliveryAttemptUnresolved');
    if (existing !== undefined) {
      const action = control.existingDeliveryAttemptAction(existing);
      const value = JSON.parse(existing.wire);
      if (action === 'confirm_succeeded_record') {
        try { await store.confirmDeliveryRecord(existing.wire); }
        catch (recordFailure) {
          throw pendingRecordFailure(
            'ResultDeliveryDurabilityPending',
            recordFailure,
            store,
            control,
            [existing],
            recordFailure,
          );
        }
        await requireCurrentAuthorization(authorize, {
          ...authorizationFacts,
          attempt,
          stage: 'receipt',
          observedAt: trustedNow(now),
        });
        const receipt = await store.readPublicationContract(
          value.result_delivery_receipt_cid,
          'result_delivery_receipt',
        );
        return Object.freeze({
          attempt,
          record: existing,
          receipt,
          byteCount: value.confirmed_byte_count,
          sha256: value.delivered_sha256,
          idempotent: true,
        });
      }
      if (action === 'reject_unresolved_attempt') {
        fail('ResultDeliveryAttemptUnresolved');
      }
      if (action === 'reject_terminal_attempt') {
        fail('ResultDeliveryAttemptTerminal');
      }
      fail('InvalidResultDeliveryAttemptState');
    }
  }

  let streaming;
  let ownsStreaming = false;
  let confirmedByteCount = 0;
  let writeFailure;
  try {
    streaming = control.issueDeliveryRecord(attempt, undefined, {
      state: 'streaming',
      confirmedByteCount: 0,
      exposure: 'exact',
      possibleUnconfirmedMaxBytes: undefined,
      deliveredSha256: undefined,
      receipt: undefined,
      failureCid: undefined,
      observedAt: trustedNow(now),
      cleanupOwnerCids: [],
    }, limits);
    try { await store.appendDeliveryRecord(streaming.wire); }
    catch (recordFailure) {
      const terminal = control.issueDeliveryRecord(attempt, streaming, {
        state: 'failed',
        confirmedByteCount: 0,
        exposure: 'exact',
        possibleUnconfirmedMaxBytes: undefined,
        deliveredSha256: undefined,
        receipt: undefined,
        failureCid: undefined,
        observedAt: trustedNow(now),
        cleanupOwnerCids: [],
      }, limits);
      throw pendingRecordFailure(
        'ResultDeliveryFailed',
        recordFailure,
        store,
        control,
        [streaming, terminal],
        recordFailure,
      );
    }
    ownsStreaming = true;

    const resultDefinitionCid = control.deliveryResultDefinitionCid(
      manifest, attempt,
    );
    const digest = createDigest();
    if (digest === null || typeof digest !== 'object' ||
        typeof digest.update !== 'function' ||
        typeof digest.finish !== 'function') {
      fail('InvalidResultDeliveryDigest');
    }
    const encoder = new TextEncoder();
    const write = async text => {
      if (typeof text !== 'string') fail('InvalidResultDeliveryChunk');
      const bytes = encoder.encode(text);
      if (bytes.byteLength === 0) return;
      const observedAt = trustedNow(now);
      if (!control.resultReadGrantValidAt(grant, observedAt)) {
        fail('ResultDeliveryGrantExpired');
      }
      if (!control.resultReadGrantAllowsBytes(
        grant, confirmedByteCount + bytes.byteLength,
      )) {
        fail('ResultDeliveryByteLimit');
      }
      await requireCurrentAuthorization(authorize, {
        ...authorizationFacts,
        attempt,
        stage: 'write',
        observedAt,
        confirmedByteCount,
        nextByteCount: confirmedByteCount + bytes.byteLength,
      });
      const dispatchAt = trustedNow(now);
      if (!control.resultReadGrantValidAt(grant, dispatchAt)) {
        fail('ResultDeliveryGrantExpired');
      }
      signal?.throwIfAborted();
      let result;
      try { result = await sink.write(bytes, signal); }
      catch (reason) {
        writeFailure = sinkFailure(reason, bytes.byteLength);
        confirmedByteCount += writeFailure.confirmedBytes;
        throw writeFailure;
      }
      if (!exactKeys(result, ['confirmedBytes']) ||
          result.confirmedBytes !== bytes.byteLength) {
        writeFailure = new SinkWriteFailure(
          new ResultDeliveryError('InvalidResultDeliverySinkResult'),
          Number.isSafeInteger(result?.confirmedBytes) &&
            result.confirmedBytes >= 0 &&
            result.confirmedBytes <= bytes.byteLength
            ? result.confirmedBytes : 0,
          'unknown_additional',
          bytes.byteLength -
            (Number.isSafeInteger(result?.confirmedBytes) &&
              result.confirmedBytes >= 0 &&
              result.confirmedBytes <= bytes.byteLength
              ? result.confirmedBytes : 0),
        );
        confirmedByteCount += writeFailure.confirmedBytes;
        throw writeFailure;
      }
      digest.update(bytes);
      confirmedByteCount += bytes.byteLength;
    };

    await store.withCommittedResultRows(
      indexKey,
      resultDefinitionCid,
      authorization =>
        authorization.resultDefinitionCid === resultDefinitionCid,
      frameLimits,
      async (metadata, readRows) => {
        await requireCurrentAuthorization(authorize, {
          ...authorizationFacts,
          attempt,
          stage: 'read',
          observedAt: trustedNow(now),
          durableResultBindingCid: metadata.durableResultBindingCid,
          logicalResultCid: metadata.logicalResultCid,
          resultSchemaCid: metadata.resultSchemaCid,
          rowCount: metadata.rowCount,
          payloadBytes: metadata.payloadBytes,
        });
        const serializer = control.prepareResultDeliverySerializer(
          format,
          metadata.resultSchemaWire,
          metadata.resultFields,
          limits,
        );
        await write(control.beginResultDelivery(serializer));
        await readRows(row =>
          write(control.nextResultDeliveryRow(serializer, row)));
        await write(control.finishResultDelivery(serializer));
      },
      control,
      attempt.identity,
    );
    const finishedAt = trustedNow(now);
    await requireCurrentAuthorization(authorize, {
      ...authorizationFacts,
      attempt,
      stage: 'finish',
      observedAt: finishedAt,
      confirmedByteCount,
    });
    signal?.throwIfAborted();
    await finishSink(sink, signal);
    const committedAt = trustedNow(now);
    if (!control.resultReadGrantValidAt(grant, committedAt)) {
      fail('ResultDeliveryGrantExpired');
    }
    await requireCurrentAuthorization(authorize, {
      ...authorizationFacts,
      attempt,
      stage: 'receipt',
      observedAt: committedAt,
      confirmedByteCount,
    });
    const deliveredSha256 = await digest.finish();
    if (!digestPattern.test(deliveredSha256)) {
      fail('InvalidResultDeliveryDigest');
    }
    const receipt = control.issueResultDeliveryReceipt(
      index,
      manifest,
      grant,
      attempt,
      {byteCount: confirmedByteCount, sha256: deliveredSha256},
      limits,
    );
    await store.putPublicationContract(receipt.name, receipt.wire);
    const succeeded = control.issueDeliveryRecord(attempt, streaming, {
      state: 'succeeded',
      confirmedByteCount,
      exposure: 'exact',
      possibleUnconfirmedMaxBytes: undefined,
      deliveredSha256,
      receipt,
      failureCid: undefined,
      observedAt: committedAt,
      cleanupOwnerCids: [],
    }, limits);
    try { await appendExactRecord(store, succeeded); }
    catch (recordFailure) {
      throw pendingRecordFailure(
        'ResultDeliveryDurabilityPending',
        recordFailure,
        store,
        control,
        [succeeded],
        recordFailure,
      );
    }
    return Object.freeze({
      attempt,
      record: succeeded,
      receipt,
      byteCount: confirmedByteCount,
      sha256: deliveredSha256,
      idempotent: false,
    });
  } catch (reason) {
    if (reason instanceof DeliveryRecordDurabilityFailure) throw reason;
    if (!ownsStreaming) throw reason;
    const terminalAction = control.deliveryFailureTerminalAction(
      signal?.aborted === true,
    );
    if (terminalAction !== 'failed' && terminalAction !== 'cancelled') {
      fail('InvalidResultDeliveryTerminalAction');
    }
    const terminal = control.issueDeliveryRecord(attempt, streaming, {
      state: terminalAction,
      confirmedByteCount,
      exposure: writeFailure?.exposure ?? 'exact',
      possibleUnconfirmedMaxBytes:
        writeFailure?.possibleUnconfirmedMaxBytes,
      deliveredSha256: undefined,
      receipt: undefined,
      failureCid: undefined,
      observedAt: trustedNow(now),
      cleanupOwnerCids: [],
    }, limits);
    try { await appendExactRecord(store, terminal); }
    catch (recordFailure) {
      throw pendingTerminalFailure(
        reason, store, control, terminal, recordFailure,
      );
    }
    throw reason;
  }
}
