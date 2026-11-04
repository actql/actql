// Result readers and their local progress, validation and cleanup custody.
// Opening or stopping a reader neither cancels nor resubmits its Run.
import {projectDeliveryExplanation, projectDeliveryLookupFailure, projectReadExplanation,
  localizeOperation} from '../operation-presentation.mjs';
import {canonicalJson, contentCid} from '../checkpoints.mjs';
import {resultSerializationContractCids} from '../json-value-wire.generated.mjs';
import {awaitValidation, captureReadOptions, captureResultRead, validationOutcome} from '../result-schema.mjs';
import {captureResponse, freezeInput, positive} from './data.mjs';
import {ClientError, fail, ownedClientFailure, markOwnedFailure, ownedFailureCode,
  requestCancellationCause} from './errors.mjs';
import {resultDescriptionLimits, validDeliveryAttemptLookup, validResultDescription} from '@actql/client-wire';

const readExplanations = new WeakMap();

const deliveryExplanations = new WeakMap();

const readerContexts = new WeakMap();

export function explainReadFailure(result, options) {
  return localizeOperation(readExplanations.get(result), 'read', options);
}

// Only this call's admitted Owner lookup supplies Delivery facts. No row count,
// Run outcome or application persistence is inferred from a release receipt.
export function explainDeliveryAttempt(result, options) {
  return localizeOperation(deliveryExplanations.get(result), 'delivery', options);
}

const retainDeliveryLookupFailure = (cause, next, observation) => {
  const error = requestCancellationCause(cause);
  deliveryExplanations.set(error, projectDeliveryLookupFailure(next, observation));
  return error;
};

const retainDeliveryExplanation = (answer, next) => {
  deliveryExplanations.set(answer, projectDeliveryExplanation(answer, next));
  return answer;
};

const retainReadExplanation = (result, context, rowsYielded, observation, cleanupUnknown = false) => {
  readExplanations.set(result, projectReadExplanation(result, context, rowsYielded, observation, cleanupUnknown));
  return result;
};

const appendCleanupFailure = (error, cause, redact = false) => {
  const failure = redact ? new Error('ResultReadCleanupUnknown') : cause;
  error.cleanupError = error.cleanupError === undefined ? failure :
    new AggregateError([error.cleanupError, failure], 'Multiple reader cleanup failures');
};
// Only SDK validation failures carry these diagnostics through reader wrappers.
const validationFailures = new WeakMap();

const validationFailure = (kind, context, rowIndex, detail) => {
  const error = ownedClientFailure('ResultValidationFailed');
  const metadata = Object.freeze({validationKind: kind, rowIndex,
    resultRef: Object.freeze({run: context.ref, resultName: context.resultName})});
  validationFailures.set(error, {...metadata, detail});
  Object.assign(error, metadata);
  if (kind === 'issues') Object.defineProperty(error, 'issues', {value: detail});
  if (kind === 'exception') Object.defineProperty(error, 'cause', {value: detail});
  return error;
};

const readFailure = (cause, context, rowsYielded, prior) => {
  // Borrowed stream exceptions may have throwing getters as well as private
  // messages. DSN mode reads only our private original classification/custody.
  const safe = context.redactErrors === true;
  const code = safe ? ownedFailureCode(cause) ?? 'ResultReadUnknown'
    : typeof cause?.code === 'string' ? cause.code : 'ResultReadUnknown';
  const cleanupUnknown = prior?.cleanup === 'unknown' ||
    readExplanations.get(cause)?.cleanup === 'unknown';
  const error = new ClientError(code, {attemptId: context.attemptId, rowsYielded,
    ...(safe ? {} : {cause}),
    ...(safe ? cleanupUnknown ? {cleanupError: new Error('ResultReadCleanupUnknown')} : {}
      : cause?.cleanupError === undefined ? {} : {cleanupError: cause.cleanupError})});
  if (safe) markOwnedFailure(error, code);
  const validation = validationFailures.get(cause);
  if (validation) {
    const {detail, ...metadata} = validation;
    Object.assign(error, metadata);
    if (validation.validationKind === 'issues') {
      Object.defineProperty(error, 'issues', {value: detail});
    }
    validationFailures.set(error, validation);
  }
  return retainReadExplanation(error, context, rowsYielded,
    prior?.observation ?? 'read_incomplete', cleanupUnknown);
};

function tighter(requested, maximum) {
  if (requested === undefined) return maximum;
  if (!positive(requested) || requested > maximum) fail('InvalidReadLimit');
  return requested;
}

// A decoded-value accounting bound, not an operating-system RSS measurement.
function retainedValueBytes(value, raw = false) {
  let nodes = 0;
  const active = new Set();
  const visit = item => {
    nodes++;
    if (raw && (item === null || typeof item !== 'object')) {
      // The existing canonical codec owns scalar number and text validity.
      canonicalJson(item, {dataKeys: true});
      return;
    }
    if (raw && active.has(item)) throw new TypeError('CyclicResultValue');
    if (raw) active.add(item);
    if (Array.isArray(item)) {
      for (const child of item) visit(child);
    } else if (item !== null && typeof item === 'object') {
      if (raw && Object.getPrototypeOf(item) !== Object.prototype) throw new TypeError('InvalidResultValue');
      for (const [key, entry] of Object.entries(item)) {
        nodes++; visit(key); visit(entry);
      }
    }
    if (raw) active.delete(item);
  };
  try { visit(value); }
  catch (error) {
    if (raw) fail('InvalidResultFrame');
    throw error;
  }
  return new TextEncoder().encode(JSON.stringify(value)).byteLength + nodes * 64;
}

// JSON.parse has already checked the grammar. Check the original text's decoded
// object keys per nesting level; last-key-wins parsing would hide duplicates.
function rejectDuplicateRowKeys(text) {
  const scopes = [];
  for (const [token] of text.matchAll(/"(?:\\[\s\S]|[^"\\])*"|[{}\[\],:]/gu)) {
    if (token === '{') scopes.push({keys: new Set(), key: true});
    else if (token === '[') scopes.push(null);
    else if (token === '}' || token === ']') scopes.pop();
    else {
      const scope = scopes.at(-1);
      if (scope == null) continue;
      if (token === ',') scope.key = true;
      else if (token === ':') scope.key = false;
      else if (scope.key) {
        const key = JSON.parse(token);
        if (scope.keys.has(key)) fail('InvalidResultFrame');
        scope.keys.add(key);
      }
    }
  }
}

// Only this module's original Result owns these continuations. The association
// preserves an eager query's captured options; it issues no resource admission.
const capturedResultReads = new WeakMap();
const capturedQueryReads = new WeakMap();
export function captureQueryResultRead(before, current, kind, schemaOrOptions, options) {
  before?.(schemaOrOptions, options);
  const captured = kind === 'all' ? captureResultRead(ClientError, schemaOrOptions, options)
    : captureReadOptions(schemaOrOptions);
  const token = Object.freeze({});
  capturedQueryReads.set(token, {before, current, kind, captured});
  return token;
}
export function collectCapturedResult(result, token) {
  const target = capturedResultReads.get(result), original = capturedQueryReads.get(token);
  if (target === undefined || original === undefined || target.before !== original.before ||
      target.current !== original.current) fail('InvalidResult');
  capturedQueryReads.delete(token);
  original.current?.();
  return target.read(original.kind, original.captured);
}

export function createResultFactory({ref, limits, lookupContext, redactErrors, typedRows,
  beforeResultRead, assertResultReadCurrent},
  {runRequest, responseValue}, {activeReaders, readerCleanups}, getExecution) {
  return name => {
    if (typeof name !== 'string' || !name) fail('InvalidResultName');
    const readRows = ({options, validate}, collection, retainSizes = false) => {
      const attemptId = crypto.randomUUID();
      const context = freezeInput({ref, resultName: name, attemptId,
        redactErrors: redactErrors,
        lookupContext: {...lookupContext}});
      const maxWireBytes = tighter(options.maxWireBytes,
        limits.maxReadWireBytes);
      const maxRowWireBytes = tighter(options.maxRowWireBytes,
        limits.maxRowWireBytes);
      const maxRowRetainedValueBytes = tighter(
        options.maxRowRetainedValueBytes,
        limits.maxRowRetainedValueBytes);
      let state = 'not_started';
      let rowsYielded = 0, rawRows = 0, retainedBytes = 0;
      const controller = new AbortController();
      const acceptRow = async (row, size = retainedValueBytes(row, true)) => {
        // Charge the untouched decoded row before invoking application code.
        // A mutating/shrinking transform cannot reduce its collection charge.
        if (size > maxRowRetainedValueBytes) fail('ResultRowRetainedLimit');
        if (collection && (rawRows >= collection.maxRows ||
            retainedBytes + size > collection.maxBytes)) {
          fail('ResultRetainedLimit');
        }
        retainedBytes += size;
        const rowIndex = rawRows++;
        controller.signal.throwIfAborted();
        if (validate === undefined) return retainSizes
          ? {value: row, retainedBytes: size} : {value: row};
        let response;
        try {
          response = await awaitValidation(validate(row), controller.signal);
        } catch (cause) {
          if (controller.signal.aborted) throw controller.signal.reason;
          throw validationFailure('exception', context, rowIndex, cause);
        }
        controller.signal.throwIfAborted();
        let outcome;
        try { outcome = validationOutcome(response); }
        catch (cause) { throw validationFailure('exception', context, rowIndex, cause); }
        if (outcome.kind !== undefined) {
          throw validationFailure(outcome.kind, context, rowIndex, outcome.issues);
        }
        return outcome;
      };
      const iterate = async function* (ownedReader) {
        if (state !== 'not_started') fail('ReadAttemptAlreadyStarted');
        assertResultReadCurrent?.();
        state = 'opening';
        const abort = () => controller.abort();
        options.signal?.addEventListener('abort', abort, {once: true});
        if (options.signal?.aborted) controller.abort();
        let wireBytes = 0, line = '';
        let stream, failure, localCleanup, frames;
        let framesComplete = false, cleanupUncertain = false;
        activeReaders.add(ownedReader);
        try {
          const response = await runRequest('read', {
            resultName: name, format: !typedRows ? 'jsonl' :
              'typed', attemptId,
          }, controller.signal);
          if (typedRows) {
            if (response?.kind !== 'rows' ||
                typeof response.frames?.[Symbol.asyncIterator] !==
                  'function') fail('InvalidResultStream');
            if (typeof response.close === 'function') {
              localCleanup = () => response.close();
              readerCleanups.add(localCleanup);
            }
            frames = response.frames[Symbol.asyncIterator]();
            const nextFrame = frames.next;
            while (true) {
              const next = await Reflect.apply(nextFrame, frames, []);
              if (next === null || !['object', 'function'].includes(typeof next)) {
                fail('InvalidResultStream');
              }
              if (next.done) { framesComplete = true; break; }
              const frame = next.value;
              controller.signal.throwIfAborted();
              if (frame === null || typeof frame !== 'object') fail('InvalidResultFrame');
              const byteLength = frame.byteLength;
              if (!Number.isSafeInteger(byteLength) || byteLength < 1) {
                fail('InvalidResultFrame');
              }
              const value = frame.value;
              if (value === null || typeof value !== 'object' ||
                  Array.isArray(value)) fail('InvalidResultFrame');
              if (byteLength > maxRowWireBytes) {
                fail('ResultRowWireLimit');
              }
              wireBytes += byteLength;
              if (wireBytes > maxWireBytes) fail('ResultWireLimit');
              // Capture borrowed row fields once. Accounting and application
              // validation consume that same owned value, not later getters.
              const row = structuredClone(value);
              const size = retainedValueBytes(row, true);
              if (size > maxRowRetainedValueBytes) fail('ResultRowRetainedLimit');
              state = 'prefix';
              const output = await acceptRow(row, size);
              controller.signal.throwIfAborted();
              rowsYielded++;
              yield output;
            }
            controller.signal.throwIfAborted();
            state = 'complete';
          } else {
            stream = response.body?.getReader();
            if (!stream) fail('InvalidResultStream');
            // The successful HTTP opening response was received. Local
            // frames open lazily, so their first accepted row is the ack.
            state = 'prefix';
            const decoder = new TextDecoder('utf-8', {fatal: true});
            const acceptText = function* (text) {
              line += text;
              let newline;
              while ((newline = line.indexOf('\n')) >= 0) {
                controller.signal.throwIfAborted();
                const item = line.slice(0, newline);
                line = line.slice(newline + 1);
                if (!item) fail('InvalidResultStream');
                if (new TextEncoder().encode(item).byteLength >
                    maxRowWireBytes) {
                  fail('ResultRowWireLimit');
                }
                let row;
                try { row = JSON.parse(item); }
                catch { fail('InvalidResultFrame'); }
                rejectDuplicateRowKeys(item);
                if (row === null || typeof row !== 'object' ||
                    Array.isArray(row)) fail('InvalidResultFrame');
                yield row;
              }
              if (new TextEncoder().encode(line).byteLength >
                  maxRowWireBytes) {
                fail('ResultRowWireLimit');
              }
            };
            while (true) {
              controller.signal.throwIfAborted();
              const {done, value} = await stream.read();
              controller.signal.throwIfAborted();
              if (done) break;
              wireBytes += value.byteLength;
              if (wireBytes > maxWireBytes) fail('ResultWireLimit');
              const sliceBytes = Math.min(8192, maxRowWireBytes);
              for (let offset = 0; offset < value.byteLength;
                offset += sliceBytes) {
                for (const row of acceptText(decoder.decode(
                  value.subarray(offset, offset + sliceBytes), {stream: true}))) {
                  const output = await acceptRow(row);
                  controller.signal.throwIfAborted();
                  rowsYielded++;
                  yield output;
                }
              }
            }
            for (const row of acceptText(decoder.decode())) {
              const output = await acceptRow(row);
              controller.signal.throwIfAborted();
              rowsYielded++;
              yield output;
            }
            if (line !== '\x1e') fail('IncompleteResultStream');
            state = 'complete';
          }
        } catch (cause) {
          failure = readFailure(cause, context, rowsYielded,
            state === 'opening' ? {observation: 'read_open_unknown'} : undefined);
        } finally {
          // A failed opening has no authoritative no-send proof. Keep the
          // original attempt for lookup, even when no row was received.
          if (state === 'opening') state = 'open_unknown';
          options.signal?.removeEventListener('abort', abort);
          if (frames !== undefined && !framesComplete) {
            // AsyncIteratorClose suppresses return() failures when a loop
            // body already threw. This owner must retain both validation
            // failure and frame cleanup uncertainty, even without close().
            try {
              const finish = frames.return;
              if (finish !== undefined && finish !== null) {
                const returned = await Reflect.apply(finish, frames, []);
                if (returned === null || !['object', 'function'].includes(typeof returned)) {
                  fail('InvalidResultStream');
                }
              }
            } catch (cause) {
              cleanupUncertain = true;
              if (failure) {
                appendCleanupFailure(failure, cause, context.redactErrors);
                retainReadExplanation(failure, context, rowsYielded,
                  readExplanations.get(failure)?.observation ?? 'read_incomplete', true);
              }
              else failure = retainReadExplanation(ownedClientFailure('ResultReadCleanupUnknown',
                {attemptId, rowsYielded,
                  ...(context.redactErrors ? {} : {cause})}), context, rowsYielded, 'cleanup_unknown');
            }
          }
          if (stream) {
            try {
              if (state !== 'complete') await stream.cancel();
            } catch (cause) {
              cleanupUncertain = true;
              // Remote delivery uncertainty stays on this read. Releasing
              // its local lock is not a remote cleanup acknowledgment, and
              // a closed stream supplies no Host cleanup retry witness.
              if (failure) {
                appendCleanupFailure(failure, cause, context.redactErrors);
                retainReadExplanation(failure, context, rowsYielded, 'read_incomplete', true);
              }
              else failure = retainReadExplanation(ownedClientFailure('ResultReadCleanupUnknown',
                {attemptId, rowsYielded,
                  ...(context.redactErrors ? {} : {cause})}), context, rowsYielded, 'cleanup_unknown');
            } finally {
              stream.releaseLock();
            }
          }
          // Cancel the reader before aborting its fetch: our own abort
          // must not turn successful early cleanup into an AbortError.
          if (state !== 'complete') controller.abort();
          if (localCleanup !== undefined) {
            try {
              await localCleanup();
              readerCleanups.delete(localCleanup);
            } catch (cause) {
              if (failure) {
                appendCleanupFailure(failure, cause, context.redactErrors);
                retainReadExplanation(failure, context, rowsYielded,
                  readExplanations.get(failure)?.observation ?? 'read_incomplete', true);
              }
              else failure = retainReadExplanation(ownedClientFailure('ResultReadCleanupUnknown',
                {attemptId, rowsYielded,
                  ...(context.redactErrors ? {} : {cause})}), context, rowsYielded, 'cleanup_unknown');
            }
          }
          activeReaders.delete(ownedReader);
          // A pending iterator.return() skips code after finally.
          if (failure) {
            if (cleanupUncertain) ownedReader.cleanupFailure = failure;
            throw failure;
          }
        }
      };
      const reader = Object.freeze({attemptId, state: () => state,
        rowsYielded: () => rowsYielded,
        [Symbol.asyncIterator]() {
          const owned = {abort: () => controller.abort(new ClientError('ClientClosed')),
            finish: () => iterator.return()};
          const iterator = iterate(owned);
          // Do not yield transformed values from an async generator: it
          // would assimilate thenable outputs. Only unwrap IteratorResult.
          const unwrap = item => item.done || retainSizes ? item
            : {done: false, value: item.value.value};
          return {
            next: value => iterator.next(value).then(unwrap),
            return: value => iterator.return(value).then(unwrap),
            throw: error => iterator.throw(error).then(unwrap),
            [Symbol.asyncIterator]() { return this; },
          };
        }});
      readerContexts.set(reader, context);
      return reader;
    };

    const rows = (schemaOrOptions, options) => {
      beforeResultRead?.(schemaOrOptions, options);
      return readRows(captureResultRead(ClientError, schemaOrOptions, options));
    };

    const batches = options => {
      beforeResultRead?.(options, undefined);
      if (options === undefined) options = {};
      const captured = captureResultRead(ClientError, options);
      const batchOptions = captured.validate === undefined ? captured.options
        : captureReadOptions(options);
      const reader = readRows(captured, undefined, true);
      let rowsYielded = 0;
      const maxRows = tighter(batchOptions.maxBatchRows,
        limits.maxBatchRows);
      const maxBytes = tighter(batchOptions.maxBatchRetainedValueBytes,
        limits.maxBatchRetainedValueBytes);
      const iterate = async function* (ownedReader) {
        activeReaders.add(ownedReader);
        let batch = [], bytes = 0;
        try {
          for await (const output of reader) {
            const row = output.value;
            // No application has received this row yet. Reuse its original
            // charge unless a validator produced or could have mutated it.
            const size = output.retainedBytes ?? retainedValueBytes(row);
            if (size > maxBytes) fail('ResultBatchLimit');
            if (batch.length === maxRows || bytes + size > maxBytes) {
              rowsYielded += batch.length;
              yield batch; batch = []; bytes = 0;
            }
            batch.push(row); bytes += size;
          }
          if (batch.length) {
            rowsYielded += batch.length;
            yield batch;
          }
        } catch (cause) {
          throw readFailure(cause, readerContexts.get(reader), rowsYielded, readExplanations.get(cause));
        } finally {
          // A yielded batch belongs to the application. Drop our retained
          // reference without mutating that already returned value.
          batch = [];
          activeReaders.delete(ownedReader);
        }
      };
      return Object.freeze({attemptId: reader.attemptId,
        state: reader.state, rowsYielded: () => rowsYielded,
        [Symbol.asyncIterator]() {
          // The underlying row reader owns abort. This outer scope also
          // owns a buffered next row/batch and must be returned on close.
          const owned = {abort() {}, finish: () => iterator.return()};
          const iterator = iterate(owned);
          return iterator;
        }});
    };

    const allCaptured = async captured => {
      const reader = readRows(captured, {
        maxRows: tighter(captured.options.maxRows, limits.maxRows),
        maxBytes: tighter(captured.options.maxRetainedValueBytes,
          limits.maxRetainedValueBytes),
      });
      const values = [];
      try {
        for await (const row of reader) values.push(row);
        return values;
      } catch (cause) {
        throw readFailure(cause, readerContexts.get(reader), 0, readExplanations.get(cause));
      }
    };
    const all = async (schemaOrOptions, options) => {
      beforeResultRead?.(schemaOrOptions, options);
      return allCaptured(captureResultRead(ClientError, schemaOrOptions, options));
    };
    const captureOneRead = options => captureResultRead(ClientError, {...options,
      maxRows: Math.min(2, limits.maxRows)});
    const oneCaptured = async captured => {
      const values = await allCaptured(captured);
      if (values.length !== 1) fail('ExpectedOneRow');
      return values[0];
    };
    const scalarCaptured = async captured => {
      const row = await oneCaptured(captured);
      if (row === null || typeof row !== 'object' ||
          Array.isArray(row) || Object.keys(row).length !== 1) fail('ExpectedOneColumn');
      return Object.values(row)[0];
    };
    const result = Object.freeze({
      ref: Object.freeze({run: ref, resultName: name}),
      execution: getExecution(), rows, batches, all,
      one: async options => {
        beforeResultRead?.(options, undefined);
        return oneCaptured(captureOneRead(options));
      },
      scalar: async options => {
        beforeResultRead?.(options, undefined);
        return scalarCaptured(captureOneRead(options));
      },
      describe: async ({signal, format = 'jsonl',
        ...requestedLimits} = {}) => {
        if (!['json', 'jsonl', 'csv'].includes(format)) {
          fail('UnsupportedResultDescriptionFormat');
        }
        if (Object.keys(requestedLimits).some(key =>
          !Object.hasOwn(resultDescriptionLimits, key))) {
          fail('InvalidResultDescriptionOptions');
        }
        const limits = Object.fromEntries(
          Object.entries(resultDescriptionLimits).map(([key, ceiling]) => {
            const value = requestedLimits[key] ?? ceiling;
            if (!positive(value) || value > ceiling) {
              fail('InvalidResultDescriptionOptions');
            }
            return [key, value];
          }));
        const response = await runRequest('result-describe', {
          resultName: name, format, attemptId: crypto.randomUUID(),
          ...limits,
        }, signal);
        let answer;
        try { answer = await responseValue(response, limits.maxWireBytes); }
        catch (cause) {
          throw new ClientError('InvalidHostResultDescription', {cause});
        }
        try { answer = captureResponse(answer); }
        catch { fail('InvalidHostResultDescription'); }
        if (!validResultDescription(answer, {ref, resultName: name, format},
          limits)) fail('InvalidHostResultDescription');
        const schema = Object.fromEntries(answer.columns.map(column =>
          [column.name, column.contract]));
        if (await contentCid(schema) !== answer.resultSchemaCid ||
            resultSerializationContractCids[answer.serialization.version] !==
              answer.serialization.contractCid ||
            await contentCid({version: 'actql-result-definition/0.1',
              program_definition_cid: answer.programDefinitionCid,
              result_name: name}) !== answer.resultDefinitionCid) {
          fail('InvalidHostResultDescription');
        }
        return freezeInput(answer);
      },
      deliveryAttempt: async (attemptId, {signal} = {}) => {
        if (typeof attemptId !== 'string' || !attemptId) {
          fail('InvalidReadAttempt');
        }
        const next = freezeInput({operation: 'deliveryAttempt', ref, resultName: name, attemptId,
          lookupContext: {...lookupContext}});
        let response;
        try {
          response = await runRequest('delivery-attempt', {resultName: name, attemptId}, signal);
        } catch (cause) {
          throw retainDeliveryLookupFailure(cause, next, 'lookup_unavailable');
        }
        let answer;
        try { answer = await responseValue(response); }
        catch {
          throw retainDeliveryLookupFailure(new ClientError('InvalidHostAttemptLookup'), next,
            'lookup_uninterpretable');
        }
        const expected = {
          attemptId, runDefinitionCid: ref.runDefinitionCid,
          resultName: name,
        };
        try {
          answer = captureResponse(answer);
          if (!validDeliveryAttemptLookup(answer, expected)) fail('InvalidHostAttemptLookup');
          return retainDeliveryExplanation(freezeInput(answer), {
            operation: 'deliveryAttempt', ref, resultName: name, attemptId,
            lookupContext: {...lookupContext},
          });
        } catch {
          throw retainDeliveryLookupFailure(new ClientError('InvalidHostAttemptLookup'), next,
            'lookup_uninterpretable');
        }
      },
    });
    capturedResultReads.set(result, {before: beforeResultRead, current: assertResultReadCurrent,
      read(kind, captured) {
        if (kind === 'all') return allCaptured(captured);
        if (kind === 'one' || kind === 'scalar') {
          const single = {options: {...captured, maxRows: Math.min(2, limits.maxRows)}};
          return kind === 'one' ? oneCaptured(single) : scalarCaptured(single);
        }
        fail('InvalidResult');
      }});
    return result;
  };
}
