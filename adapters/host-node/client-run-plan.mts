// Read the original compiler evidence of an admitted Run. Authorization is
// current; the stored map never creates an inspection or control permission.
import {resumeControlOperationRef, validClientBody, snapshotClientRequest, validWireRunPlanViewShape, validWireRunSampleShape,
  validControlOperationLookup, withinResultDescriptionLimits} from
  '../../packages/client-wire/index.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import type {WireClientBodyByOperation, WireRunRef} from '../../packages/client-wire/index.js';
import type {WireControlOperationLookup, WireControlOperationRef, WireLogicalMap, WirePlanView,
  WireRunSample, WireSampleCapture, WireSampleSelector, WireSampleSource} from
  '../../packages/client-wire/interactive-control.generated.js';

type PlanRequest = WireClientBodyByOperation['run-plan'] & Readonly<{
  principalId: string;
  signal?: AbortSignal;
}>;
type PlanOriginal = Readonly<{compiledPlanWire: string; planViewWire: string}>;
type PlanInstallation<Definition> = Readonly<{
  authorize(request: PlanRequest): boolean | PromiseLike<boolean>;
  lookupOriginal(ref: WireRunRef): Readonly<{
    runDefinition: Definition;
    programDefinitionCid: string;
    runAdmissionEvidence?: Readonly<{logicalPlanOriginal?: PlanOriginal}>;
  }> | undefined;
  control: Readonly<{
    readStoredRunPlanOriginal(original: PlanOriginal, definition: Definition,
      programDefinitionCid: string, limits: PlanRequest): string;
  }>;
}>;

const failure = (code: string) => Object.assign(new Error(code), {code});
export function installClientRunPlan<Definition>({authorize, lookupOriginal, control}: PlanInstallation<Definition>) {
  if (typeof authorize !== 'function' || typeof lookupOriginal !== 'function' ||
      typeof control?.readStoredRunPlanOriginal !== 'function') {
    throw new TypeError('InvalidClientRunPlanInstallation');
  }
  return async (request: PlanRequest) => {
    const {signal, ...data} = request;
    const selected = Object.freeze({...snapshotClientRequest(data) as typeof data,
      ...(signal === undefined ? {} : {signal})});
    const {connection, ref, maxWireBytes, maxNodes, maxDepth} = selected;
    if (!validClientBody('run-plan', {connection, ref, maxWireBytes, maxNodes, maxDepth})) {
      throw new TypeError('InvalidRunPlanRequest');
    }
    if (await authorize(selected) !== true) throw failure('RunObservationAccessDenied');
    signal?.throwIfAborted();
    const original = lookupOriginal(ref);
    if (original === undefined) throw failure('RunObservationAccessDenied');
    const saved = original.runAdmissionEvidence?.logicalPlanOriginal;
    if (saved === undefined) throw failure('ClientOperationUnavailable');
    const wire = control.readStoredRunPlanOriginal(saved, original.runDefinition,
      original.programDefinitionCid, selected);
    if (wire !== saved.planViewWire) throw failure('InvalidClientHostRunPlanView');
    const view = {version: 'actql-run-plan-view/0.1', run_ref: {...ref},
      plan_view: JSON.parse(wire) as unknown};
    if (!validWireRunPlanViewShape(view) ||
        Buffer.byteLength(JSON.stringify(view)) > maxWireBytes) {
      throw failure('InvalidClientHostRunPlanView');
    }
    if (await authorize(selected) !== true) throw failure('RunObservationAccessDenied');
    signal?.throwIfAborted();
    // Recheck the exact original after the awaited current-authority callback.
    const current = lookupOriginal(ref)?.runAdmissionEvidence?.logicalPlanOriginal;
    if (current?.compiledPlanWire !== saved.compiledPlanWire ||
        current?.planViewWire !== saved.planViewWire) throw failure('InvalidClientHostRunPlanView');
    return view;
  };
}

// Use the canonical Stored Plan to match the requested Step and exact
// compiler port. An input can reuse an actual upstream output association.
type SampleStep = WireLogicalMap['steps'][number];
type SamplePort = SampleStep['ports'][number];
type SampleUnavailable = Extract<WireRunSample, {state: 'unavailable'}>['reason'];
type SamplePortSelection = {reason: SampleUnavailable} | {
  step: SampleStep; port: SamplePort; producerStep?: SampleStep; producerPort?: SamplePort;
};

function samplePortSelection(map: WireLogicalMap, selector: WireSampleSelector, next: boolean): SamplePortSelection {
  const target = selector.step;
  const steps = map.steps.filter(step => target.by === 'id' ? step.step_id === target.step_id
    : target.by === 'operator' ? step.operator === target.operator : step.names.includes(target.name));
  if (steps.length !== 1) return {reason: 'selection_required'};
  const [step] = steps;
  const ports = step.ports.filter(port => port.role === selector.role &&
    (selector.input_port_id === undefined || port.port_id === selector.input_port_id));
  if (ports.length !== 1) return {reason: 'selection_required'};
  const [port] = ports;
  if (port.carrier !== 'relation') return {reason: 'not_supported'};
  if (port.role === 'output') return {step, port, producerStep: step, producerPort: port};
  const source = port.source;
  if (source.kind !== 'logical_output') {
    return next && source.kind === 'stage_input' ? {step, port} : {reason: 'not_retained'};
  }
  const producerStep = map.steps.find(candidate => candidate.step_id === source.step_id);
  const producerPort = producerStep?.ports.find(candidate => candidate.role === 'output' &&
    candidate.port_id === source.output_port_id);
  if (producerPort?.carrier_contract_cid !== port.carrier_contract_cid ||
      producerPort?.carrier !== port.carrier) throw failure('ForeignClientRunSampleOutput');
  return {step, port, producerStep, producerPort};
}

type SampleRequest = WireClientBodyByOperation['run-sample'] & Readonly<{
  principalId: string; signal?: AbortSignal; nextRevision?: number;
}>;
type SampleOriginal = Readonly<{definitionWire: string; programDefinitionCid: string;
  admissionEvidenceWire?: string; compiledPlanWire?: string; planViewWire?: string}>;
type SampleObservable = Pick<WireSampleSource, 'run_ref' | 'compiled_plan_cid' | 'logical_map_cid' |
  'carrier' | 'carrier_contract_cid'>;
type SampleRetained = Readonly<{kind: 'expired' | 'unobserved' | 'ambiguous'}> | Readonly<{
  kind: 'available';
  source: SampleObservable & Readonly<{self_cid: string}>;
  capture: Pick<WireSampleCapture, 'strategy'> & Readonly<{self_cid: string}>;
  emission: Pick<WireSampleCapture, 'sampled_items' | 'total' | 'completeness' | 'truncation'> & Readonly<{self_cid: string}>;
  reference: Readonly<{self_cid: string}>;
  receipt: Readonly<{receiptCid: string}>;
  relation: unknown;
}>;
type SampleScope = Readonly<{compiledPlanCid: string; logicalMapCid: string; maxBytes: number}>;
type SampleProducer = Readonly<{stepId: string; outputPortId: string; carrierContractCid: string}>;
type SampleNextSelection = SampleScope & Readonly<{revision: number; nextStepId: string;
  inputOrdinal: number; maxWork: number}>;
type SampleReserve = (bytes: number) => undefined;
type SampleReadInstallation<Definition extends Readonly<{identity: string}>, Extent extends Readonly<{storedBytes: number}>> = Readonly<{
  authorize(request: SampleRequest): boolean | PromiseLike<boolean>;
  probeOriginal(ref: WireRunRef): Extent | undefined;
  lookupOriginal(ref: WireRunRef, extent: Extent): SampleOriginal | undefined;
  readRetained(ref: WireRunRef, selected: SampleScope & SampleProducer,
    custody: Readonly<{current: () => boolean; reserve: SampleReserve}>): SampleRetained;
  readNextRetained?(request: SampleRequest, selected: SampleNextSelection, current: () => boolean,
    reserve: SampleReserve, bindProducer: (producer: SampleProducer) => boolean): SampleRetained;
  observeNext?(request: SampleRequest, current: () => boolean): {revision: number; nextStepId?: string} | undefined;
  readWorkspace: Readonly<{
    begin(request: SampleRequest, control: SampleReadControl<Definition>): unknown;
    metadata(request: SampleRequest, bytes: number): unknown;
    close(request: SampleRequest, failure: unknown): unknown;
  }>;
  control: SampleReadControl<Definition>;
}>;
type SampleReadControl<Definition> = Readonly<{
  admit(kind: 'run_definition', wire: string, limits: SampleRequest): Definition;
  readStoredRunPlanOriginal(original: PlanOriginal, definition: Definition, programDefinitionCid: string,
    limits: SampleRequest): string;
}>;
type SampleSink<Value> = (view: WireRunSample) => Value | PromiseLike<Value>;

export function installClientRunSample<Definition extends Readonly<{identity: string}>,
  Extent extends Readonly<{storedBytes: number}>>({authorize, probeOriginal, lookupOriginal,
  readRetained, readNextRetained, observeNext, readWorkspace, control}: SampleReadInstallation<Definition, Extent>) {
  if (![authorize, probeOriginal, lookupOriginal, readRetained, readWorkspace?.begin,
    readWorkspace?.metadata, readWorkspace?.close, control?.admit, control?.readStoredRunPlanOriginal]
    .every(method => typeof method === 'function')) {
    throw new TypeError('InvalidClientRunSampleInstallation');
  }
  const forbidden = Object.freeze({state: 'forbidden'});
  const unavailable = (reason: SampleUnavailable) => Object.freeze({state: 'unavailable', reason});
  async function readOwned<Value>(request: SampleRequest, consume: SampleSink<Value>) {
    const {ref, selector, nextRevision} = request;
    const current = () => {
      request.signal?.throwIfAborted();
      const permission = authorize(request);
      if (permission !== true && permission !== false && typeof permission?.then === 'function') {
        void Promise.resolve(permission).catch(() => {});
      }
      return permission === true;
    };
    const reply = async (answer: WireRunSample) => await consume(current() ? answer : forbidden);
    if (!current()) return await consume(forbidden);
    const next = nextRevision !== undefined;
    if (next) {
      if (typeof readNextRetained !== 'function' || typeof observeNext !== 'function') {
        return await reply(unavailable('not_supported'));
      }
      if (!Number.isInteger(nextRevision) || nextRevision < 1 || nextRevision > 2147483647 ||
          selector.role !== 'input' || selector.step.by !== 'id' || selector.input_port_id === undefined) {
        throw failure('InvalidRunSampleRequest');
      }
    }
    // Scalar probe and fixed selection/reply controls on this same Read.
    // The Journal charges variable Sample material from its actual extent.
    readWorkspace.metadata(request, 1024);
    if (!current()) return await consume(forbidden);
    const extent = probeOriginal(ref);
    if (!current()) return await consume(forbidden);
    if (extent === undefined) return await reply(unavailable('not_retained'));
    readWorkspace.metadata(request, 2 * extent.storedBytes);
    if (!current()) return await consume(forbidden);
    const original = lookupOriginal(ref, extent);
    if (original === undefined) return await reply(unavailable('not_retained'));
    const inline = original.admissionEvidenceWire === undefined ? undefined :
      (JSON.parse(original.admissionEvidenceWire) as {logicalPlanOriginal?: PlanOriginal}).logicalPlanOriginal;
    const hasCompiledPlan = original.compiledPlanWire !== undefined;
    const hasPlanView = original.planViewWire !== undefined;
    if (hasCompiledPlan !== hasPlanView || hasCompiledPlan && inline !== undefined) {
      throw failure('ForeignClientRunSampleOutput');
    }
    const saved = original.compiledPlanWire !== undefined && original.planViewWire !== undefined ? {
      compiledPlanWire: original.compiledPlanWire, planViewWire: original.planViewWire,
    } : inline;
    if (saved === undefined) return await reply(unavailable('not_retained'));
    const definition = control.admit('run_definition', original.definitionWire, request);
    if (definition.identity !== ref.runDefinitionCid) throw failure('ForeignClientRunSampleOutput');
    const planWire = control.readStoredRunPlanOriginal(saved, definition, original.programDefinitionCid, request);
    if (planWire !== saved.planViewWire) throw failure('ForeignClientRunSampleOutput');
    const map = (JSON.parse(planWire) as WirePlanView).logical_map;
    const selected = samplePortSelection(map, selector, next);
    if ('reason' in selected) return await reply(unavailable(selected.reason));
    const {step, port} = selected;
    let {producerStep, producerPort} = selected;
    const reserve: SampleReserve = bytes => {readWorkspace.metadata(request, bytes);};
    const scope = {compiledPlanCid: map.compiled_plan_cid, logicalMapCid: map.self_cid, maxBytes: request.maxWireBytes};
    let stored: SampleRetained;
    try {
      if (next) {
        stored = readNextRetained!(request, Object.freeze({...scope, revision: nextRevision, nextStepId: step.step_id,
          inputOrdinal: port.port_ordinal, maxWork: request.maxNodes}), current, reserve, producer => {
          // A checked Stage input can have an upstream task even though its
          // public locator records only the receiving Stage/input. Validate
          // the live producer's output against this same retained Map.
          const originalStep = map.steps.find(item => item.step_id === producer.stepId);
          const originalPort = originalStep?.ports.find(item => item.role === 'output' && item.port_id === producer.outputPortId);
          if (originalPort?.carrier !== port.carrier ||
              originalPort.carrier_contract_cid !== producer.carrierContractCid ||
              producer.carrierContractCid !== port.carrier_contract_cid ||
              (producerPort !== undefined && (producerStep !== originalStep || producerPort !== originalPort))) return false;
          producerStep = originalStep;
          producerPort = originalPort;
          return true;
        });
      } else {
        if (producerStep === undefined || producerPort === undefined) throw failure('ForeignClientRunSampleOutput');
        stored = readRetained(ref, {...scope, stepId: producerStep.step_id, outputPortId: producerPort.port_id,
          carrierContractCid: producerPort.carrier_contract_cid}, {current, reserve});
      }
    } catch (issue) {
      const error = issue as {code?: string; outcome?: string} | undefined;
      if (error?.code === 'ClientRelationSampleDenied' ||
          next && error?.code === 'ClientRunDebugEntryDenied') return await consume(forbidden);
      if (error?.code === 'ClientRelationSampleCapacity') return await reply(unavailable('capacity'));
      if (error?.code === 'ClientRelationSampleReadUnknown' && error.outcome === 'unknown') {
        return await reply(Object.freeze({state: 'unknown', reason: 'sample_read_unknown'}));
      }
      throw issue;
    }
    if (!current()) return await consume(forbidden);
    // A final current read of the same bounded Plan owner joins egress. An
    // unrelated Run or same-sized metadata replacement cannot redirect it.
    const retained = lookupOriginal(ref, extent);
    if (retained?.definitionWire !== original.definitionWire ||
        retained.admissionEvidenceWire !== original.admissionEvidenceWire ||
        retained.programDefinitionCid !== original.programDefinitionCid ||
        retained.compiledPlanWire !== original.compiledPlanWire ||
        retained.planViewWire !== original.planViewWire) throw failure('ForeignClientRunSampleOutput');
    const disclose = !next ? reply : (answer: WireRunSample) => {
      if (!current()) return consume(forbidden);
      let pause;
      try {pause = observeNext!(request, current);}
      catch (error) {
        if ((error as {code?: string} | undefined)?.code === 'ClientRunDebugEntryDenied') return consume(forbidden);
        throw error;
      }
      if (pause?.revision !== nextRevision || pause.nextStepId !== step.step_id) {
        if (!current()) return consume(forbidden);
        throw failure('ClientRunDebugEntryRevisionConflict');
      }
      // observeNext rechecks the same current Account through the durable
      // read. Enter the original sink without an intervening suspension.
      return consume(answer);
    };
    if (stored.kind === 'expired') return await disclose(Object.freeze({state: 'expired'}));
    if (stored.kind !== 'available') return await reply(unavailable(
      stored.kind === 'ambiguous' ? 'selection_required' : 'not_retained',
    ));
    if (producerStep === undefined || producerPort === undefined) throw failure('ForeignClientRunSampleOutput');
    const {source, capture, emission, reference, receipt, relation} = stored;
    const view = {state: 'available', source: {run_ref: source.run_ref, compiled_plan_cid: source.compiled_plan_cid,
      logical_map_cid: source.logical_map_cid, step_id: step.step_id, role: port.role, port_id: port.port_id,
      carrier: source.carrier, carrier_contract_cid: source.carrier_contract_cid,
      source_generation_cid: source.self_cid, original_capture_cid: capture.self_cid,
      producer: {kind: 'logical_output', step_id: producerStep.step_id, output_port_id: producerPort.port_id}},
    capture: {strategy: capture.strategy, sampled_items: emission.sampled_items, total: emission.total,
      completeness: emission.completeness, truncation: emission.truncation,
      sample_ref_cid: reference.self_cid, receipt_cid: receipt.receiptCid, emission_provenance_cid: emission.self_cid},
    data: relation};
    if (!withinResultDescriptionLimits(view, request)) return await reply(unavailable('capacity'));
    if (!validWireRunSampleShape(view)) throw failure('InvalidClientHostRunSample');
    return await disclose(view);
  }
  return async <Value,>(request: SampleRequest, consume: SampleSink<Value>) => {
    if (typeof consume !== 'function') throw new TypeError('InvalidRunSampleConsumer');
    let opened = false, primary;
    try {
      request.signal?.throwIfAborted();
      readWorkspace.begin(request, control);
      opened = true;
      return await readOwned(request, consume);
    } catch (error) {primary = error; throw error;}
    finally {if (opened) readWorkspace.close(request, primary);}
  };
}

type ControlReadMeta = Readonly<{principalId: string; signal?: AbortSignal}>;
type ResumeRequest = WireClientBodyByOperation['resume-run'] & ControlReadMeta & {operationRef?: never};
type LookupRequest = WireClientBodyByOperation['lookup-control-operation'] & ControlReadMeta & {command?: never};
type ControlRequest = ResumeRequest | LookupRequest;
type CurrentAccess = Readonly<{principalId: string; connection: ControlRequest['connection']; authorize(): boolean}>;
type ControlReceipt = Extract<WireControlOperationLookup, {state: 'found'}>['receipt'];
type ControlReadResult = Readonly<{kind: 'unobserved' | 'resume_accepted'; receipt?: ControlReceipt}>;
type ControlAcceptance = Readonly<{kind: 'expired'}> | Readonly<{
  kind: 'resume_accepted'; commandCid: string; revision: number;
}>;
type ControlInstallation = Readonly<{
  authorize(request: ControlRequest): boolean | PromiseLike<boolean>;
  lookupOriginal(ref: WireControlOperationRef, scope: CurrentAccess & Readonly<{
    reserve: SampleReserve; reserveConstruction: SampleReserve;
  }>): ControlReadResult | undefined;
  authorizeResume?(request: ResumeRequest): boolean | PromiseLike<boolean>;
  resumeOriginal?(ref: WireRunRef, scope: CurrentAccess & Readonly<{reserve: SampleReserve}>,
    wire: string): ControlAcceptance | undefined;
  readWorkspace: Readonly<{
    begin(request: ControlRequest): unknown;
    metadata(request: ControlRequest, bytes: number): undefined;
    construction(request: ControlRequest, peak: number): undefined;
    metadataFinish?(request: ControlRequest): unknown;
    close(request: ControlRequest, failure: unknown): unknown;
  }>;
}>;

// Read the exact receipt retained by the accepting Journal, alongside its
// original acceptance observation, independently of the live Driver.
export function installClientControlOperationLookup({authorize, lookupOriginal, readWorkspace,
  authorizeResume, resumeOriginal}: ControlInstallation) {
  if (![authorize, lookupOriginal, readWorkspace?.begin, readWorkspace?.metadata, readWorkspace?.construction,
    readWorkspace?.close]
    .every(method => typeof method === 'function')) {
    throw new TypeError('InvalidClientControlOperationLookupInstallation');
  }
  if (resumeOriginal !== undefined && [resumeOriginal, authorizeResume, readWorkspace.metadataFinish]
    .some(method => typeof method !== 'function')) {
    throw new TypeError('InvalidClientControlOperationResumeInstallation');
  }
  const unavailable = Object.freeze({state: 'history_unavailable', reason: 'control_receipt_not_retained'});
  const unknown = Object.freeze({state: 'unknown', reason: 'control_operation_unobserved'});
  const acceptanceUnknown = Object.freeze({state: 'unknown', reason: 'control_acceptance_unknown'});
  return async <Value,>(request: ControlRequest,
    consume: (view: WireControlOperationLookup) => Value | PromiseLike<Value>) => {
    const resuming = request.command !== undefined;
    if (resuming && resumeOriginal === undefined) throw failure('ClientOperationUnavailable');
    const authorizeCurrent = () => {
      request.signal?.throwIfAborted();
      const allowed = authorize(request);
      if (allowed !== true && allowed !== false && typeof allowed?.then === 'function') {
        void Promise.resolve(allowed).catch(() => {});
      }
      if (allowed !== true || !resuming) return allowed === true;
      const canResume = authorizeResume!(request);
      if (canResume !== true && canResume !== false && typeof canResume?.then === 'function') {
        void Promise.resolve(canResume).catch(() => {});
      }
      return canResume === true;
    };
    request.signal?.throwIfAborted();
    let primary;
    readWorkspace.begin(request);
    try {
      const operationRef = resuming ? resumeControlOperationRef(request.command) : request.operationRef;
      if (!authorizeCurrent()) throw failure('RunObservationAccessDenied');
      const scope = {
        principalId: request.principalId, connection: request.connection, authorize: authorizeCurrent,
      };
      const reserveConstruction: SampleReserve = peak => readWorkspace.construction(request, peak);
      let ambiguous = false;
      if (resuming) {
        readWorkspace.metadata(request, 4096);
        if (!authorizeCurrent()) throw failure('RunObservationAccessDenied');
        try {
          const wire = canonicalJson(request.command);
          if (Buffer.byteLength(wire, 'utf8') > 4096) throw failure('ClientRunDebugEntryInvalidCommand');
          const accepted = resumeOriginal!(request.ref, {...scope, reserve: reserveConstruction}, wire);
          if (accepted?.kind === 'expired') throw failure('ClientRunDebugEntryExpired');
          if (accepted?.kind !== 'resume_accepted' || accepted.commandCid !== operationRef.command_cid ||
              accepted.revision !== operationRef.accepted_from_revision + 1) {
            throw failure('InvalidClientHostControlOperationLookup');
          }
        } catch (issue) {
          const error = issue as {code?: string; outcome?: string} | undefined;
          if (error?.outcome !== 'unknown' && error?.code !== 'ClientRunDebugEntryReconciliationRequired') throw issue;
          ambiguous = true;
        }
        // Command wire and issuance scratch have ended. The same Read funds
        // any new committed observation before its original egress.
        readWorkspace.metadataFinish!(request);
      }
      const evidence = ambiguous ? undefined : lookupOriginal(operationRef, {...scope,
        reserve: bytes => readWorkspace.metadata(request, bytes), reserveConstruction,
      });
      const receipt = evidence?.receipt;
      if (resuming && !ambiguous && receipt === undefined) throw failure('InvalidClientHostControlOperationLookup');
      const answer: WireControlOperationLookup = receipt === undefined ? (ambiguous ? acceptanceUnknown :
        evidence?.kind === 'resume_accepted' ? unavailable : unknown) :
        {state: 'found', receipt, observation: {original_receipt_cid: receipt.self_cid,
          operation_ref: {...receipt.operation_ref, run_ref: {...receipt.operation_ref.run_ref}},
          outcome: receipt.outcome, observed_at: receipt.observed_state.updated_at}};
      if (!validControlOperationLookup(answer, operationRef)) throw failure('InvalidClientHostControlOperationLookup');
      if (!withinResultDescriptionLimits(answer, request)) throw failure('RunControlReadLimit');
      if (!authorizeCurrent()) throw failure('RunObservationAccessDenied');
      return await consume(answer);
    } catch (error) {
      primary = (error as {code?: string} | undefined)?.code === 'ClientRunDebugEntryDenied'
        ? failure('RunObservationAccessDenied') : error;
      throw primary;
    } finally {readWorkspace.close(request, primary);}
  };
}
