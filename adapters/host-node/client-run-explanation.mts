// Retained compiler-original structural facts only. The existing read Request
// owns admission, construction and output consumption. No historical read can
// compile, acquire, execute or repair absent Facts.
import {validClientBody, validWireRunExplanationViewShape,
  validWireRunExplanationContextViewShape, withinResultDescriptionLimits} from '../../packages/client-wire/index.mjs';
import type {WireClientBodyByOperation, WireRunExplanationView, WireRunExplanationContextView, WireRunRef} from
  '../../packages/client-wire/index.js';

type ExplanationRequest = WireClientBodyByOperation['run-explanation'] & Readonly<{
  principalId: string;
  signal?: AbortSignal;
}>;
type ExplanationOriginal = Readonly<{
  definitionWire: string;
  admissionEvidenceWire?: string;
  programDefinitionCid: string;
  parameterValuesCid: string;
  factsWire?: string;
  compiledPlanWire?: string;
  planViewWire?: string;
  contextWire?: string;
  invocationTemplateWire?: string;
}>;
type ExplanationInstallation<Operation, Extent extends Readonly<{storedBytes: number}>, Context extends boolean> = Readonly<{
  context?: Context;
  authorizeCurrent?(request: ExplanationRequest, operation: Operation): unknown;
  authorize(request: ExplanationRequest, operation: Operation): boolean | PromiseLike<boolean>;
  authorizeEgress(request: ExplanationRequest, operation: Operation): boolean | PromiseLike<boolean>;
  probeOriginal(ref: WireRunRef): Extent | undefined;
  lookupOriginal(ref: WireRunRef, extent: Extent): ExplanationOriginal | undefined;
  readWorkspace: Readonly<{
    beginExplanation?(request: ExplanationRequest): Operation;
    beginExplanationContext?(request: ExplanationRequest): Operation;
    explanationRequest(request: ExplanationRequest): ExplanationRequest;
    prepareExplanation(request: ExplanationRequest, original: Context extends true ? Extent : number): undefined;
    renderExplanation(request: ExplanationRequest, original: ExplanationOriginal): string;
    close(request: ExplanationRequest, primary: unknown): undefined;
  }>;
}>;
type ExplanationView<Context extends boolean> = Context extends true
  ? WireRunExplanationContextView : WireRunExplanationView;
type Consume<Value, Context extends boolean> = (view: ExplanationView<Context>) => Value | PromiseLike<Value>;

const failure = (code: string) => Object.assign(new Error(code), {code});

export function installClientRunExplanation<Operation, Extent extends Readonly<{storedBytes: number}>, Context extends boolean = false>({authorize, authorizeEgress,
  probeOriginal, lookupOriginal, readWorkspace, context = false as Context, authorizeCurrent}: ExplanationInstallation<Operation, Extent, Context>) {
  const kind = context ? 'run-explanation-context' : 'run-explanation';
  const begin = context ? readWorkspace?.beginExplanationContext : readWorkspace?.beginExplanation;
  const selectedRequest = readWorkspace?.explanationRequest,
    prepare = readWorkspace?.prepareExplanation, render = readWorkspace?.renderExplanation,
    close = readWorkspace?.close;
  if (![authorize, authorizeEgress, probeOriginal, lookupOriginal,
    begin, selectedRequest, prepare, render, close].every(value => typeof value === 'function') ||
      context && typeof authorizeCurrent !== 'function') {
    throw new TypeError('InvalidClientRunExplanationInstallation');
  }
  const authorized = async (request: ExplanationRequest, selected: ExplanationRequest, operation: Operation) => {
    if (Reflect.apply(selectedRequest, readWorkspace, [request]) !== selected) throw failure('RunExplanationReadUnavailable');
    selected.signal?.throwIfAborted();
    // Account metadata egress precedes even a Journal extent probe. This same
    // owned operation memo is reobserved after callbacks, never another read.
    if (await authorizeEgress(selected, operation) !== true ||
        await authorize(selected, operation) !== true) throw failure('RunObservationAccessDenied');
    if (Reflect.apply(selectedRequest, readWorkspace, [request]) !== selected) throw failure('RunExplanationReadUnavailable');
    selected.signal?.throwIfAborted();
  };
  function assertCurrentAccess(request: ExplanationRequest, selected: ExplanationRequest, operation: Operation) {
    if (!context) return;
    if (Reflect.apply(selectedRequest, readWorkspace, [request]) !== selected) throw failure('RunExplanationReadUnavailable');
    selected.signal?.throwIfAborted();
    const decision = authorizeCurrent!(selected, operation);
    if (decision !== true) {
      if (typeof (decision as {then?: unknown} | null | undefined)?.then === 'function') Promise.resolve(decision).catch(() => {});
      throw failure('RunObservationAccessDenied');
    }
    selected.signal?.throwIfAborted();
  }
  // Keep all new semantic/wire/view aliases in this inner frame. It unwinds
  // completely before the outer owner may return/refund the read admission.
  async function readOwned<Value>(request: ExplanationRequest, operation: Operation, consume: Consume<Value, Context>) {
    const selected = Reflect.apply(selectedRequest, readWorkspace, [request]);
    const {connection, ref, maxWireBytes, maxNodes, maxDepth} = selected;
    if (!Object.isFrozen(connection) ||
        !validClientBody(kind, {connection, ref, maxWireBytes, maxNodes, maxDepth})) {
      throw new TypeError('InvalidRunExplanationRequest');
    }
    await authorized(request, selected, operation);
    assertCurrentAccess(request, selected, operation);
    const extent = probeOriginal(ref);
    assertCurrentAccess(request, selected, operation);
    if (extent === undefined) throw failure('RunObservationAccessDenied');
    Reflect.apply(prepare, readWorkspace, [request, context ? extent : extent.storedBytes]);
    assertCurrentAccess(request, selected, operation);
    const original = lookupOriginal(ref, extent);
    assertCurrentAccess(request, selected, operation);
    if (original === undefined) throw failure('RunObservationAccessDenied');
    const {definitionWire, admissionEvidenceWire, programDefinitionCid,
      parameterValuesCid, factsWire, compiledPlanWire, planViewWire} = original;
    const contextWire = context ? original.contextWire : undefined;
    const templateWire = context ? original.invocationTemplateWire : undefined;
    const wire = Reflect.apply(render, readWorkspace, [request, original]);
    if (typeof wire !== 'string') throw failure('RunExplanationEncodingRejected');
    if (wire.length > maxWireBytes || Buffer.byteLength(wire) > maxWireBytes) {
      throw failure('RunExplanationReadLimit');
    }
    let view: unknown;
    try {view = JSON.parse(wire);}
    catch {throw failure('RunExplanationEncodingRejected');}
    if (!withinResultDescriptionLimits(view, selected)) throw failure('RunExplanationReadLimit');
    const validate = context ? validWireRunExplanationContextViewShape : validWireRunExplanationViewShape;
    if (!validate(view) ||
        view.run_ref.namespaceId !== ref.namespaceId ||
        view.run_ref.authorityScopeCid !== ref.authorityScopeCid ||
        view.run_ref.runDefinitionCid !== ref.runDefinitionCid ||
        ((context ? contextWire : factsWire) === undefined) !== (view.explanation.state === 'not_projected') ||
        context && (contextWire === undefined) !== (templateWire === undefined)) {
      throw failure('RunExplanationEncodingRejected');
    }
    await authorized(request, selected, operation);
    assertCurrentAccess(request, selected, operation);
    // The second native projection uses the SAME admitted bounds. Compare
    // the complete immutable originals, not wrapper equality as permission.
    const current = lookupOriginal(ref, extent);
    if (current === undefined ||
        current.definitionWire !== definitionWire ||
        current.admissionEvidenceWire !== admissionEvidenceWire ||
        current.programDefinitionCid !== programDefinitionCid ||
        current.parameterValuesCid !== parameterValuesCid ||
        current.factsWire !== factsWire ||
        current.compiledPlanWire !== compiledPlanWire || current.planViewWire !== planViewWire ||
        context && (current.contextWire !== contextWire ||
          current.invocationTemplateWire !== templateWire)) throw failure('RunExplanationEncodingRejected');
    // No await can separate synchronous installed Account observation from
    // entering the consumer. The same Request remains owned during output.
    assertCurrentAccess(request, selected, operation);
    selected.signal?.throwIfAborted();
    // A private existing-handler sink owns transport completion. It is never
    // serialized or offered as an application callback/public operation field.
    return await consume(view as ExplanationView<Context>);
  }
  return async <Value,>(request: ExplanationRequest, consume: Consume<Value, Context>) => {
    if (typeof consume !== 'function') throw new TypeError('InvalidRunExplanationConsumer');
    request.signal?.throwIfAborted();
    let operation: Operation | undefined, opened = false, primary: unknown;
    try {
      operation = Reflect.apply(begin!, readWorkspace, [request]);
      opened = true;
      return await readOwned(request, operation, consume);
    } catch (cause) {primary = cause; throw cause;}
    finally {
      // Only the existing original Request/cleanup duty remains here. No
      // original row, codec, memo, selected snapshot or view survives this cut.
      operation = undefined;
      if (opened) Reflect.apply(close, readWorkspace, [request, primary]);
    }
  };
}
