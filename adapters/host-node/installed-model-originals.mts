// Original Run admission bytes for fixed Model custody and cancellation.
// This packaging is not admission: the common Model original-Run reader
// re-admits every leaf and their exact linkage before the journal uses it.
import type {WireRunRef} from '../../packages/client-wire/index.js';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {retainInstalledHostRuntimeFailure} from './installed-host-cleanup.mjs';
import {sourceAliasDataGeometry} from './source-alias-construction.mjs';

type UncheckedWire = {readonly wire?: unknown};
type UncheckedCompiled = {readonly template?: UncheckedWire; readonly preparedEvidence?: UncheckedWire; readonly authorization?: UncheckedWire; readonly compiledPlan?: UncheckedWire};

export function originalModelRunWire(compiled: unknown, runDefinition: unknown, maxBytes?: number) {
  const originals = {
    boundInvocationTemplateWire: (compiled as UncheckedCompiled | null | undefined)?.template?.wire,
    preparedInvocationWire: (compiled as UncheckedCompiled | null | undefined)?.preparedEvidence?.wire,
    runAuthorizationWire: (compiled as UncheckedCompiled | null | undefined)?.authorization?.wire,
    compiledPlanWire: (compiled as UncheckedCompiled | null | undefined)?.compiledPlan?.wire,
    runDefinitionWire: (runDefinition as UncheckedWire | null | undefined)?.wire,
  };
  if (Object.values(originals).some(wire => typeof wire !== 'string' || wire === '')) {
    throw new TypeError('InstalledModelOriginalRunUnavailable');
  }
  // All keys here are fixed ASCII and canonicalJson preserves data strings,
  // so its sorted key order leaves the measured UTF-8 size unchanged.
  if (maxBytes !== undefined &&
      sourceAliasDataGeometry(Object.freeze(originals)).jsonBytes > BigInt(maxBytes)) return undefined;
  return canonicalJson(originals);
}

export type ModelPlanBinding = Readonly<{
  task: number; stage: number; step: number; taskCid: string; providerBindingCid: string;
}>;
export type ModelPlanBindings = Readonly<{
  runDefinitionCid: string; compiledPlanCid: string; bindings: readonly ModelPlanBinding[];
}>;

type ModelReplayIssue = 'model_provider_selection' | 'model_provider_selection_unavailable';
const replayRefusals = new WeakMap<object, Readonly<{ref: WireRunRef; issue: ModelReplayIssue}>>();

export function rejectModelPlanReplay(ref: WireRunRef, issue: ModelReplayIssue): never {
  const code = issue === 'model_provider_selection' ? 'ClientModelProviderSelectionChanged' :
    'ClientModelProviderSelectionUnavailable';
  const error = Object.assign(new Error(code), {code});
  replayRefusals.set(error, {ref, issue});
  throw error;
}

export function originalModelPlanReplayRefusal(error: unknown, ref: WireRunRef): ModelReplayIssue | undefined {
  const original = error !== null && typeof error === 'object' ? replayRefusals.get(error) : undefined;
  if (original?.ref.runDefinitionCid === ref.runDefinitionCid &&
      original.ref.authorityScopeCid === ref.authorityScopeCid && original.ref.namespaceId === ref.namespaceId) {
    return original.issue;
  }
}

type ModelReplayMember = Readonly<{
  occurrence?: unknown;
  providerBinding?: Readonly<{identity: string}>;
  structuredPreflightRefusal?: Error;
  assertTrustedRuntime?(): void;
  currentProvider(): boolean;
}>;
type ModelReplaySelection = (ModelReplayMember & Readonly<{components?: never}>) |
  Readonly<{components: readonly ModelReplayMember[]}>;
type ModelReplayRuntime = Readonly<{
  clientProgramInferOccurrenceCoordinates(occurrence: unknown): unknown;
  clientProgramInferOccurrenceModelTaskCid(occurrence: unknown): unknown;
}>;
type ModelReplayOriginal = Readonly<{
  ref: WireRunRef;
  runAdmissionEvidence?: Readonly<{modelOriginalRunWire?: string; modelPlanBindings?: ModelPlanBindings}>;
}>;

export function assertInstalledModelPreflight(selection: ModelReplaySelection | undefined): void {
  if (selection === undefined) return;
  for (const member of selection.components ?? [selection]) {
    if (member.structuredPreflightRefusal === undefined) continue;
    member.assertTrustedRuntime?.();
    if (!member.currentProvider()) throw new Error('InferTrustedRuntimeOriginalChanged');
    throw member.structuredPreflightRefusal;
  }
}

export function selectedModelPlanRows(moon: ModelReplayRuntime,
    selection: ModelReplaySelection | undefined): readonly ModelPlanBinding[] | undefined {
  if (selection === undefined) return undefined;
  const components = selection.components ?? [selection];
  if (components.length === 0 || components.length > 64) return undefined;
  const rows: ModelPlanBinding[] = [];
  for (const component of components) {
    if (component.occurrence === undefined || component.providerBinding === undefined ||
        !component.currentProvider()) return undefined;
    const coordinates = moon.clientProgramInferOccurrenceCoordinates(component.occurrence);
    const taskCid = moon.clientProgramInferOccurrenceModelTaskCid(component.occurrence);
    if (typeof taskCid !== 'string') return undefined;
    rows.push(Object.freeze({task: runtimeField(coordinates, 0) as number,
      stage: runtimeField(coordinates, 1) as number, step: runtimeField(coordinates, 2) as number,
      taskCid, providerBindingCid: component.providerBinding.identity}));
  }
  return Object.freeze(rows);
}

export function assertOriginalModelPlanReplay(moon: ModelReplayRuntime, retained: ModelReplayOriginal | undefined,
    selected: ModelReplaySelection | undefined): void {
  if (retained?.runAdmissionEvidence?.modelOriginalRunWire === undefined) return;
  const original = retained.runAdmissionEvidence.modelPlanBindings;
  const current = selectedModelPlanRows(moon, selected);
  if (original === undefined || current === undefined) {
    rejectModelPlanReplay(retained.ref, 'model_provider_selection_unavailable');
  }
  if (original.bindings.length !== current.length ||
      original.bindings.some((prior, index) => {
        const next = current[index];
        return prior.task !== next.task || prior.stage !== next.stage || prior.step !== next.step ||
          prior.taskCid !== next.taskCid || prior.providerBindingCid !== next.providerBindingCid;
      })) {
    rejectModelPlanReplay(retained.ref, 'model_provider_selection');
  }
}

type OriginalRequestInput = Readonly<{finish(terminal: 'failed' | 'returned'): void}>;
type RetainOriginalRequestInput = (input: OriginalRequestInput) => void;

// The restored worker owns this one input until its original work returns.
// Failed child cleanup must settle before an attempt to return the parent.
export async function runWithRestoredModelInput<Result>(
    work: (retain: RetainOriginalRequestInput) => Promise<Result>): Promise<Result> {
  const held: {input?: OriginalRequestInput} = {};
  try {
    const result = await work(original => {held.input = original;});
    held.input?.finish('returned');
    return result;
  } catch (cause) {
    const original = held.input;
    if (original === undefined) throw cause;
    throw retainInstalledHostRuntimeFailure(cause, () => original.finish('failed'));
  }
}

// A read flight ends its renewal before its successful input return. A
// refused return retries the same returned disposition on the same input.
export async function runWithEffectReadInput<Result>(
    work: (retain: RetainOriginalRequestInput) => Promise<Result>,
    stopRenewal: () => void): Promise<Result> {
  const held: {input?: OriginalRequestInput} = {};
  let failed = false;
  try {
    return await work(original => {held.input = original;});
  } catch (cause) {
    failed = true;
    const original = held.input;
    if (original === undefined) throw cause;
    throw retainInstalledHostRuntimeFailure(cause, () => original.finish('failed'));
  } finally {
    stopRenewal();
    const original = held.input;
    if (!failed && original !== undefined) {
      try {original.finish('returned');}
      catch (cause) {
        throw retainInstalledHostRuntimeFailure(cause, () => original.finish('returned'));
      }
    }
  }
}

export async function prepareRestoredModelEffectRequest<Request extends {updateTargetPreparedOriginal?: unknown},
    Intent, Prepared>(request: Request,
    originalIntent: Readonly<{intent: Intent; assertCurrent(): void}> | undefined, materialWire: unknown,
    {retain, retainInput, prepare, assertIntent, attach}: Readonly<{
      retain(request: Request, intent: Intent, wire: string): OriginalRequestInput;
      retainInput: RetainOriginalRequestInput;
      prepare(request: Request): Promise<Prepared>;
      assertIntent(prepared: Prepared, intent: Intent): void;
      attach(request: Request, prepared: Prepared): void;
    }>): Promise<void> {
  if (originalIntent === undefined || typeof materialWire !== 'string') {
    throw new Error('ModelResumeOriginalMaterialsUnavailable');
  }
  originalIntent.assertCurrent();
  retainInput(retain(request, originalIntent.intent, materialWire));
  const prepared = await prepare(request);
  assertIntent(prepared, originalIntent.intent);
  attach(request, prepared);
  // A cold execution needs the fresh funded Prepared/compiler. The old
  // projection remains evidence and cannot replace that pair.
  delete request.updateTargetPreparedOriginal;
}

export function assertRestoredModelRunSelection(moon: ModelReplayRuntime, ref: WireRunRef,
    admitted: ModelReplayOriginal | undefined, selected: () => ModelReplaySelection | undefined): void {
  if (admitted?.ref.runDefinitionCid !== ref.runDefinitionCid) {
    throw new Error('ModelResumeRunDefinitionMismatch');
  }
  const selection = selected();
  assertOriginalModelPlanReplay(moon, admitted, selection);
  assertInstalledModelPreflight(selection);
}

export async function prepareOriginalEffectReadRequest<Request, Prepared>(
    request: Request, moon: ModelReplayRuntime, retained: ModelReplayOriginal | undefined,
    {retain, retainInput, prepare, attach, bind, check}: Readonly<{
      retain(request: Request): OriginalRequestInput;
      retainInput: RetainOriginalRequestInput;
      prepare(request: Request): Promise<Prepared>;
      attach(request: Request, prepared: Prepared): void;
      bind(request: Request): void;
      check(request: Request): ModelReplaySelection | undefined;
    }>): Promise<void> {
  retainInput(retain(request));
  attach(request, await prepare(request));
  bind(request);
  const selected = check(request);
  assertOriginalModelPlanReplay(moon, retained, selected);
  assertInstalledModelPreflight(selected);
}

export function retainOriginalEffectInput<Body, Receipt>(
    register: (pending: Promise<void>) => void,
    open: () => Readonly<{body: Body; receipt: Receipt}>,
    finish: (receipt: Receipt, terminal: 'failed' | 'returned') => void) {
  let settled!: () => void;
  const pending = new Promise<void>(resolve => {settled = resolve;});
  register(pending);
  let original, finished = false;
  try {original = open();}
  catch (cause) {settled(); throw cause;}
  return Object.freeze({body: original.body,
    finish(terminal: 'failed' | 'returned') {
      if (finished) return;
      try {
        finish(original.receipt, terminal);
        finished = true;
      } finally {
        // End the pending Host call. A refused physical cleanup stays with
        // the original producer and may require another retirement attempt.
        settled();
      }
    }});
}
