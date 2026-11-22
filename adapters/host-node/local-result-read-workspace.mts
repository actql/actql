import {openRequestPreparation, cleanupRequestInput} from '../local-node/request-preparation-adapter.mjs';
import {physicalContentReadWindowBytes} from '../store-local/publication-store.mjs';
import {runtimeField, runtimeIsError} from '../host-common/compiler-binding.generated.mjs';
import {ResultDeliveryError} from '../host-common/result-delivery.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {setImmediate as yieldRead} from 'node:timers/promises';
import {types as nodeTypes} from 'node:util';

import type {RequestPreparationState} from '../local-node/request-preparation-adapter.mjs';
import type {installResultAccessService} from '../host-common/result-access.mjs';
import type {installClientRunExplanation} from './client-run-explanation.mjs';

type ResultWorkspace = NonNullable<Parameters<typeof installResultAccessService>[0]['readWorkspace']>;
type ResultRequest = Parameters<ResultWorkspace['begin']>[0];
type ExplanationRequest = Parameters<Parameters<typeof installClientRunExplanation>[0]['authorize']>[0];
type Request = ResultRequest | ExplanationRequest;
type ExplanationKind = 'run-explanation' | 'run-explanation-context';
type ExplanationExtent = Readonly<{storedBytes: number; contextBytes: number; invocationTemplateBytes: number}>;
type Control = Parameters<ResultWorkspace['begin']>[1];
type RowAdmission = Awaited<ReturnType<ResultWorkspace['row']>>;
type RowResult<Value extends number | string> = Value extends number ? RowAdmission : Promise<RowAdmission>;
type Limits = Parameters<ResultWorkspace['prepare']>[2];
type FrameLimits = Parameters<ResultWorkspace['prepare']>[3];
type Metadata = Parameters<ResultWorkspace['prepare']>[1];
type RequestMemory = RequestPreparationState['context']['requestMemory'];

// Parent and raw Common Results stay opaque at this boundary.
type ReadBinding<Args extends unknown[] = []> =
  (parent: unknown, request: Request, ...args: Args) => unknown;
type Runtime = Readonly<{
  clientProgramReserveRequestResultRead:
    ReadBinding<[maxRow: number, frame: number, schemaUnits: number, maxNodes: number, desiredWindow: number]>;
  clientProgramGrowRequestResultReadFrame: ReadBinding<[units: number]>;
  clientProgramBeginRequestResultReadWire: ReadBinding<[payloadBytes: bigint, rowCount: number]>;
  clientProgramBeginRequestResultReadWireRow: ReadBinding<[wire: string]>;
  clientProgramAdvanceRequestResultReadWireRow: ReadBinding<[quantum: number]>;
  clientProgramReserveRequestResultMetadata: ReadBinding<[bytes: number]>;
  clientProgramRetainRequestResultMetadataData: ReadBinding<[slot: number, nodes: number, textUnits: number]>;
  clientProgramReleaseRequestResultMetadata: ReadBinding<[slot: number]>;
  clientProgramFinishRequestResultMetadata: ReadBinding;
  clientProgramReconcileRequestResultReadSerializer: ReadBinding<[serializer: unknown]>;
  clientProgramBeginRequestExplanationRead: ReadBinding;
  clientProgramReserveRequestExplanationRead:
    ReadBinding<[storedBytes: number, maxWireBytes: number, maxNodes: number, maxDepth: number]>;
  clientProgramReadRequestExplanation: ReadBinding<[
    definition: string, compiledPlan: string | undefined, planView: string | undefined, facts: string | undefined,
    program: string, parameters: string, namespaceId: string, authorityScopeCid: string, runDefinitionCid: string,
    storedBytes: number, maxWireBytes: number, maxNodes: number, maxDepth: number
  ]>;
  clientProgramBeginRequestExplanationContextRead: ReadBinding;
  clientProgramReserveRequestExplanationContextRead:
    ReadBinding<[storedBytes: number, contextBytes: number, invocationTemplateBytes: number,
      maxWireBytes: number, maxNodes: number, maxDepth: number]>;
  clientProgramReadRequestExplanationContext: ReadBinding<[
    definition: string, compiledPlan: string | undefined, planView: string | undefined, facts: string | undefined,
    context: string | undefined, template: string | undefined, program: string, parameters: string,
    namespaceId: string, authorityScopeCid: string, runDefinitionCid: string,
    storedBytes: number, maxWireBytes: number, maxNodes: number, maxDepth: number
  ]>;
  clientProgramRequestExplanationReadIssueCode(issue: unknown): string;
}>;
type Configuration = Readonly<{
  runtime: Runtime & RequestPreparationState['context']['runtime'];
  requestMemory?: RequestMemory;
  assertCurrent(): undefined;
}>;
type ExplanationOperation = Readonly<{
  principalId: string;
  purpose: ExplanationKind;
  indexKey: ExplanationRequest['ref'];
}>;
type Entry = {
  request: Request;
  state: RequestPreparationState;
  control?: Control;
  retained: unknown;
  active: boolean;
  rowUnits: number;
  window?: number;
  prepared: boolean | 'scanning';
  metadataActive: boolean;
  physical: {
    receiver: unknown;
    status(): Readonly<{pending?: unknown}>;
    retry(): unknown;
  }[];
  unknownPhysical: boolean;
  explanation?: {
    operation: ExplanationOperation;
    selected: ExplanationRequest;
    prepared: boolean;
    storedBytes?: number;
    rendered?: boolean;
  };
};

const nonnegativeInt32 = (value: number) => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;

function checkedExplanation(
  result: unknown, runtime: Runtime, explanationIssueCode: Runtime['clientProgramRequestExplanationReadIssueCode'],
) {
    if (runtimeIsError(result)) {
      const issue = runtimeField(result, 0);
      const code = Reflect.apply(explanationIssueCode, runtime, [issue]);
      if (typeof code !== 'string' || code.length < 1 || code.length > 128) {
        throw Object.assign(new Error('InvalidHostRuntimeResult'), {code: 'InvalidHostRuntimeResult'});
      }
      throw Object.assign(new Error(code, {cause: issue}), {code});
    }
    return checked(result);
}

// The installed Result owner supplies the original runtime/policy. A READ is
// one existing Request admission, independent of its retired producing Run.
// These instance-local limits are not a separately reserved Host RAM pool.
export function createLocalResultReadWorkspace({runtime, requestMemory, assertCurrent}: Configuration) {
  const reserve = runtime.clientProgramReserveRequestResultRead;
  const grow = runtime.clientProgramGrowRequestResultReadFrame;
  const beginWire = runtime.clientProgramBeginRequestResultReadWire;
  const beginRow = runtime.clientProgramBeginRequestResultReadWireRow;
  const advanceRow = runtime.clientProgramAdvanceRequestResultReadWireRow;
  const metadata = runtime.clientProgramReserveRequestResultMetadata;
  const retainData = runtime.clientProgramRetainRequestResultMetadataData;
  const releaseMetadata = runtime.clientProgramReleaseRequestResultMetadata;
  const finishMetadata = runtime.clientProgramFinishRequestResultMetadata;
  const reconcileSerializer = runtime.clientProgramReconcileRequestResultReadSerializer;
  const beginExplanation = runtime.clientProgramBeginRequestExplanationRead;
  const reserveExplanation = runtime.clientProgramReserveRequestExplanationRead;
  const renderExplanation = runtime.clientProgramReadRequestExplanation;
  const beginExplanationContext = runtime.clientProgramBeginRequestExplanationContextRead;
  const reserveExplanationContext = runtime.clientProgramReserveRequestExplanationContextRead;
  const renderExplanationContext = runtime.clientProgramReadRequestExplanationContext;
  const explanationIssueCode = runtime.clientProgramRequestExplanationReadIssueCode;
  if (typeof assertCurrent !== 'function') {
    throw Object.assign(new Error('ResultReadCapacityUnavailable'), {code: 'ResultReadCapacityUnavailable'});
  }
  const context = Object.freeze({runtime, requestMemory});

  const reads = new Map<Request, Entry>();
  let closing = false;
  const unavailable: () => never = () => {throw Object.assign(new Error('ForeignResultReadWorkspace'),
    {code: 'ForeignResultReadWorkspace'});};
  const original = (request: Request) => reads.get(request) ?? unavailable();
  const pending = (entry: Entry) => {
    if (entry.active || entry.prepared === 'scanning') return true;
    if (entry.unknownPhysical) return true;
    return entry.physical.some(child => {
      try {return Reflect.apply(child.status, child.receiver, []).pending !== false;}
      catch {return true;}
    });
  };
  function retire(entry: Entry) {
    if (pending(entry)) return false;
    // These semantic aliases must disappear before the existing Request can
    // settle. Physical cleanup responsibility remains on this SAME entry.
    if (entry.explanation !== undefined) entry.explanation = undefined;
    cleanupRequestInput(entry.state);
    reads.delete(entry.request);
    return true;
  }
  async function retry(entry: Entry) {
    if (entry.active) return Object.freeze({pending: true});
    for (const child of entry.physical) {
      let stopped = false;
      try {stopped = Reflect.apply(child.status, child.receiver, []).pending === false;} catch {}
      if (!stopped) await Reflect.apply(child.retry, child.receiver, []);
    }
    return Object.freeze({pending: !retire(entry)});
  }
  function cleanupFailure(entry: Entry, cause: unknown) {
    const error = Object.assign(new Error('ResultReadCleanupPending', {cause}), {
      code: 'ResultReadCleanupPending', cleanupPending: true, primaryFailure: cause,
      cleanupHandle: Object.freeze({status: () => Object.freeze({pending: reads.has(entry.request)}),
        retry: () => retry(entry)}),
    });
    return error;
  }
  function beginEntry(request: ResultRequest, control: Control, explanation: false): undefined;
  function beginEntry(request: ExplanationRequest, control: undefined, explanation: ExplanationKind): ExplanationOperation;
  function beginEntry(request: Request, control: Control | undefined, explanation: false | ExplanationKind) {
    if (closing || reads.has(request)) unavailable();
    assertCurrent();
    const retained = control === undefined ? undefined : Object.getOwnPropertyDescriptor(control, 'retainResultReadMetadata')?.value;
    const entry: Entry = {request, state: {context}, control, retained, active: true, rowUnits: 0,
      prepared: false, metadataActive: false, physical: [], unknownPhysical: false};
    reads.set(request, entry);
    try {
      openRequestPreparation(entry.state, request, assertCurrent, () => pending(entry));
      if (explanation) {
        const begin = explanation === 'run-explanation-context' ? beginExplanationContext : beginExplanation;
        checkedExplanation(Reflect.apply(begin, runtime, [entry.state.parent, request]), runtime, explanationIssueCode);
        // Only after the structural entry reservation: one public read owns
        // this memo across its before/after Account checks, never another read.
        const operation = Object.freeze({principalId: request.principalId,
          purpose: explanation, indexKey: Object.freeze({...(request as ExplanationRequest).ref})});
        // The ingress already owns the immutable connection. Capture only
        // this bounded read's scalars/ref here, after its fixed entry admits
        // the snapshot. No second serialization of connection/Source input.
        const selected = Object.freeze({principalId: operation.principalId,
          connection: (request as ExplanationRequest).connection, ref: operation.indexKey,
          maxWireBytes: (request as ExplanationRequest).maxWireBytes, maxNodes: (request as ExplanationRequest).maxNodes,
          maxDepth: (request as ExplanationRequest).maxDepth, signal: (request as ExplanationRequest).signal});
        entry.explanation = {operation, selected, prepared: false};
        return operation;
      }
    } catch (cause) {
      entry.active = false;
      try {retire(entry);} catch {throw cleanupFailure(entry, cause);}
      throw cause;
    }
  }
  return Object.freeze({
    begin(request: ResultRequest, control: Control) {
      if (closing || reads.has(request)) unavailable();
      if ([reserve, grow, beginWire, beginRow, advanceRow, metadata, retainData, releaseMetadata, finishMetadata, reconcileSerializer].some(method => typeof method !== 'function')) {
        throw Object.assign(new Error('ResultReadCapacityUnavailable'), {code: 'ResultReadCapacityUnavailable'});
      }
      // Retain the original before any fallible platform/Core constructor.
      beginEntry(request, control, false);
    },
    beginExplanation(request: ExplanationRequest) {
      if (typeof beginExplanation !== 'function' || typeof reserveExplanation !== 'function' ||
          typeof renderExplanation !== 'function' || typeof explanationIssueCode !== 'function') {
        throw Object.assign(new Error('RunExplanationReadCapacityUnavailable'),
          {code: 'RunExplanationReadCapacityUnavailable'});
      }
      return beginEntry(request, undefined, 'run-explanation');
    },
    beginExplanationContext(request: ExplanationRequest) {
      if (typeof beginExplanationContext !== 'function' || typeof reserveExplanationContext !== 'function' ||
          typeof renderExplanationContext !== 'function' || typeof explanationIssueCode !== 'function') {
        throw Object.assign(new Error('RunExplanationReadCapacityUnavailable'),
          {code: 'RunExplanationReadCapacityUnavailable'});
      }
      return beginEntry(request, undefined, 'run-explanation-context');
    },
    explanationRequest(request: ExplanationRequest) {
      const entry = original(request);
      if (!entry.active || entry.explanation === undefined) unavailable();
      assertCurrent();
      return entry.explanation.selected;
    },
    prepareExplanation(request: ExplanationRequest, extent: number | ExplanationExtent): undefined {
      const entry = original(request);
      const companion = entry.explanation?.operation.purpose === 'run-explanation-context';
      const storedBytes = companion ? (extent as ExplanationExtent)?.storedBytes : extent as number;
      if (companion && (!nonnegativeInt32((extent as ExplanationExtent)?.contextBytes) ||
          !nonnegativeInt32((extent as ExplanationExtent)?.invocationTemplateBytes))) unavailable();
      if (!entry.active || entry.explanation === undefined || entry.explanation.prepared ||
          !Number.isSafeInteger(storedBytes) || storedBytes < 1 || storedBytes > 2147483647) unavailable();
      assertCurrent();
      const selected = entry.explanation.selected;
      const result = companion
        ? Reflect.apply(reserveExplanationContext, runtime, [entry.state.parent, request, storedBytes,
            (extent as ExplanationExtent).contextBytes, (extent as ExplanationExtent).invocationTemplateBytes, selected.maxWireBytes, selected.maxNodes, selected.maxDepth])
        : Reflect.apply(reserveExplanation, runtime, [entry.state.parent, request, storedBytes,
            selected.maxWireBytes, selected.maxNodes, selected.maxDepth]);
      checkedExplanation(result, runtime, explanationIssueCode);
      entry.explanation.prepared = true;
      entry.explanation.storedBytes = storedBytes;
    },
    renderExplanation(request: ExplanationRequest, stored: unknown): string {
      const entry = original(request);
      if (!entry.active || entry.explanation?.prepared !== true || entry.explanation.rendered) unavailable();
      assertCurrent();
      // The native Journal already bounds every selected original. Parsing
      // this retained Host-private wrapper is physical codec work under the
      // SAME read admission; Common alone interprets the Plan/Facts binding.
      const rejected = (cause?: unknown) => Object.assign(new Error('RunExplanationEncodingRejected', {cause}),
        {code: 'RunExplanationEncodingRejected'});
      if (stored === null || typeof stored !== 'object' || nodeTypes.isProxy(stored)) throw rejected();
      const own = (name: string): unknown => {
        const field = Object.getOwnPropertyDescriptor(stored, name);
        if (field === undefined || !Object.hasOwn(field, 'value')) throw rejected();
        return field.value;
      };
      const definition = own('definitionWire'), evidence = own('admissionEvidenceWire'),
        facts = own('factsWire'), program = own('programDefinitionCid'), parameters = own('parameterValuesCid');
      if (typeof definition !== 'string' || typeof program !== 'string' || typeof parameters !== 'string' ||
          evidence !== undefined && typeof evidence !== 'string' || facts !== undefined && typeof facts !== 'string') throw rejected();
      entry.explanation.rendered = true;
      const {selected, operation} = entry.explanation;
      const companion = operation.purpose === 'run-explanation-context';
      const contextWire = companion ? own('contextWire') : undefined;
      const templateWire = companion ? own('invocationTemplateWire') : undefined;
      if (contextWire !== undefined && typeof contextWire !== 'string' ||
          templateWire !== undefined && typeof templateWire !== 'string') throw rejected();
      let plan;
      if (facts !== undefined && (!companion || contextWire !== undefined)) {
        try {plan = JSON.parse(evidence!)?.logicalPlanOriginal;}
        catch (cause) {throw Object.assign(new Error('RunExplanationEncodingRejected', {cause}),
          {code: 'RunExplanationEncodingRejected'});}
        if (plan === null || typeof plan !== 'object' || Array.isArray(plan) ||
            Object.keys(plan).length !== 2 || typeof plan.compiledPlanWire !== 'string' ||
            typeof plan.planViewWire !== 'string') throw rejected();
      }
      const result = companion
        ? Reflect.apply(renderExplanationContext, runtime, [entry.state.parent, request,
            definition, plan?.compiledPlanWire, plan?.planViewWire, facts, contextWire, templateWire,
            program, parameters, selected.ref.namespaceId, selected.ref.authorityScopeCid, selected.ref.runDefinitionCid,
            entry.explanation.storedBytes, selected.maxWireBytes, selected.maxNodes, selected.maxDepth])
        : Reflect.apply(renderExplanation, runtime, [entry.state.parent, request,
            definition, plan?.compiledPlanWire, plan?.planViewWire, facts,
            program, parameters, selected.ref.namespaceId, selected.ref.authorityScopeCid, selected.ref.runDefinitionCid,
            entry.explanation.storedBytes, selected.maxWireBytes, selected.maxNodes, selected.maxDepth]);
      return checkedExplanation(result, runtime, explanationIssueCode) as string;
    },
    metadata(request: ResultRequest, bytes: number): undefined {
      const entry = original(request);
      if (!entry.active || !Number.isSafeInteger(bytes) || bytes < 0 || bytes > 2147483647) unavailable();
      assertCurrent();
      checked(Reflect.apply(metadata, runtime,
        [entry.state.parent, request, bytes]));
      entry.metadataActive = true;
    },
    metadataRetain(request: ResultRequest, slot: number, originalContract: Parameters<ResultWorkspace['metadataRetain']>[2], mode: number) {
      const entry = original(request);
      if (!entry.active || typeof entry.retained !== 'function') unavailable();
      Reflect.apply(entry.retained, entry.control, [entry.state.parent, request, slot, originalContract, mode]);
    },
    metadataData(request: ResultRequest, slot: number, nodes: number, textUnits: number) {
      const entry = original(request);
      if (!entry.active) unavailable();
      checked(Reflect.apply(retainData, runtime,
        [entry.state.parent, request, slot, nodes, textUnits]));
    },
    metadataRelease(request: ResultRequest, slot: number) {
      const entry = original(request);
      if (!entry.active) unavailable();
      checked(Reflect.apply(releaseMetadata, runtime,
        [entry.state.parent, request, slot]));
    },
    metadataFinish(request: ResultRequest) {
      const entry = original(request);
      if (!entry.active) unavailable();
      if (!entry.metadataActive) return;
      checked(Reflect.apply(finishMetadata, runtime, [entry.state.parent, request]));
      entry.metadataActive = false;
    },
    prepare(request: ResultRequest, metadata: Metadata, limits: Limits, frames: FrameLimits) {
      const entry = original(request);
      if (!entry.active || entry.prepared) unavailable();
      assertCurrent();
      const payload = metadata.payloadBytes;
      const rows = metadata.rowCount;
      if (!Number.isSafeInteger(payload) || payload < 0 ||
          !Number.isSafeInteger(rows) || rows < 0 || rows > 2147483647) unavailable();
      const maxRow = Math.max(1, Math.min(frames.maxRowBytes, payload));
      const frame = Math.max(1, Math.min(frames.maxFrameBytes, payload));
      let schemaUnits = metadata.resultSchemaWire.length;
      for (const field of metadata.resultFields) schemaUnits += field.length;
      if (!Number.isSafeInteger(schemaUnits) || schemaUnits > 2147483647) unavailable();
      const desired = Math.max(1, Math.min(physicalContentReadWindowBytes,
        frames.maxFrameBytes, limits.maxWireBytes, payload));
      const window = checked(Reflect.apply(reserve, runtime,
        [entry.state.parent, request, maxRow, frame, schemaUnits, limits.maxNodes, desired])) as number;
      if (!Number.isSafeInteger(window) || window < 1 || window > desired) unavailable();
      checked(Reflect.apply(beginWire, runtime, [entry.state.parent, request, BigInt(payload), rows]));
      entry.prepared = true;
      entry.window = window;
      return window;
    },
    serializer(request: ResultRequest, value: unknown) {
      const entry = original(request);
      if (!entry.active || entry.prepared !== true) unavailable();
      checked(Reflect.apply(reconcileSerializer, runtime, [entry.state.parent, request, value]));
    },
    row<Value extends number | string>(request: ResultRequest, value: Value): RowResult<Value> {
      const entry = original(request);
      if (!entry.active || entry.prepared !== true) unavailable();
      if (typeof value === 'string') return prepareWireRow(entry, value) as RowResult<Value>;
      const units = value as number;
      if (!Number.isSafeInteger(units) || units < 0) unavailable();
      // Pure local counters consume an already acquired window. Core/current
      // is crossed only at a new geometric high-water constructor boundary.
      if (units <= entry.rowUnits) return {units: entry.rowUnits, window: entry.window!} as RowResult<Value>;
      assertCurrent();
      const admitted = checked(Reflect.apply(grow, runtime,
        [entry.state.parent, request, units]));
      const high = runtimeField(admitted, 0) as number, window = runtimeField(admitted, 1) as number;
      if (!Number.isSafeInteger(high) || high < units || !Number.isSafeInteger(window) ||
          window < 1 || window > entry.window!) unavailable();
      entry.rowUnits = high;
      entry.window = window;
      return {units: high, window} as RowResult<Value>;
    },
    close(request: Request, failure?: unknown): undefined {
      const entry = original(request);
      entry.active = false;
      // The canonical delivery failure can join a failed terminal-record
      // write with its SAME original reader failure. Both duties survive;
      // record completion alone cannot release an outstanding physical FD.
      const primary = failure instanceof ResultDeliveryError
        ? Object.getOwnPropertyDescriptor(failure, 'primaryFailure')?.value : undefined;
      for (const original of [failure, primary]) {
        if (original === null || typeof original !== 'object') continue;
        try {
          const pending = Object.getOwnPropertyDescriptor(original, 'cleanupPending');
          const handle = Object.getOwnPropertyDescriptor(original, 'cleanupHandle');
          if (handle === undefined) {
            if (pending?.value === true) entry.unknownPhysical = true;
            continue;
          }
          if (!Object.hasOwn(handle, 'value')) {entry.unknownPhysical = true;continue;}
          const receiver = handle.value;
          if (entry.physical.some(child => child.receiver === receiver)) continue;
          const status = Object.getOwnPropertyDescriptor(receiver, 'status')?.value;
          const retry = Object.getOwnPropertyDescriptor(receiver, 'retry')?.value;
          if (typeof status !== 'function' || typeof retry !== 'function') {
            entry.unknownPhysical = true;
          } else entry.physical.push({receiver, status, retry});
        } catch {entry.unknownPhysical = true;}
      }
      try {retire(entry);} catch (cause) {throw cleanupFailure(entry, failure ?? cause);}
    },
    async closeAll() {
      closing = true;
      for (const entry of reads.values()) await retry(entry);
      return Object.freeze({pending: reads.size !== 0});
    },
  });

  async function prepareWireRow(entry: Entry, wire: string): Promise<RowAdmission> {
    if (wire.length > entry.rowUnits) unavailable();
    entry.prepared = 'scanning';
    try {
      assertCurrent();
      checked(Reflect.apply(beginRow, runtime, [entry.state.parent, entry.request, wire]));
      while (true) {
        if (!entry.active) unavailable();
        assertCurrent();
        const result = checked(Reflect.apply(advanceRow, runtime,
          [entry.state.parent, entry.request, 4096]));
        const ready = runtimeField(result, 0);
        if (ready !== true && ready !== false) unavailable();
        if (ready) {
          const high = runtimeField(result, 1) as number, window = runtimeField(result, 2) as number;
          if (!Number.isSafeInteger(high) || high < wire.length || high !== entry.rowUnits ||
              !Number.isSafeInteger(window) || window < 1 || window > entry.window!) unavailable();
          entry.window = window;
          return {units: high, window};
        }
        // The same cursor/work receipt survives this yield. A new complete raw
        // row cannot replace it; cancellation/current is checked before polling.
        await yieldRead();
      }
    } finally { entry.prepared = true; }
  }
}
