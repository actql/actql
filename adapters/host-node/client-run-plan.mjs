// Read the original compiler evidence of an admitted Run. Authorization is
// current; the stored map never creates an inspection or control permission.
import {validClientBody, snapshotClientRequest, validWireRunPlanViewShape, validWireRunSampleShape,
  withinResultDescriptionLimits} from
  '../../packages/client-wire/index.mjs';
const failure = code => Object.assign(new Error(code), {code});
export function installClientRunPlan({authorize, lookupOriginal, control}) {
  if (typeof authorize !== 'function' || typeof lookupOriginal !== 'function' ||
      typeof control?.readStoredRunPlanOriginal !== 'function') {
    throw new TypeError('InvalidClientRunPlanInstallation');
  }
  return async request => {
    const {signal, ...data} = request;
    const selected = Object.freeze({...snapshotClientRequest(data),
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
      plan_view: JSON.parse(wire)};
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
function samplePortSelection(map, selector) {
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
  if (port.source.kind !== 'logical_output') return {reason: 'not_retained'};
  const producerStep = map.steps.find(candidate => candidate.step_id === port.source.step_id);
  const producerPort = producerStep?.ports.find(candidate => candidate.role === 'output' &&
    candidate.port_id === port.source.output_port_id);
  if (producerPort?.carrier_contract_cid !== port.carrier_contract_cid ||
      producerPort?.carrier !== port.carrier) throw failure('ForeignClientRunSampleOutput');
  return {step, port, producerStep, producerPort};
}

export function installClientRunSample({authorize, probeOriginal, lookupOriginal,
  readRetained, readWorkspace, control}) {
  if (![authorize, probeOriginal, lookupOriginal, readRetained, readWorkspace?.begin,
    readWorkspace?.metadata, readWorkspace?.close, control?.admit, control?.readStoredRunPlanOriginal]
    .every(method => typeof method === 'function')) {
    throw new TypeError('InvalidClientRunSampleInstallation');
  }
  const forbidden = Object.freeze({state: 'forbidden'});
  const unavailable = reason => Object.freeze({state: 'unavailable', reason});
  async function readOwned(request, consume) {
    const {ref, selector} = request;
    const current = () => {
      request.signal?.throwIfAborted();
      const permission = authorize(request);
      if (typeof permission?.then === 'function') void Promise.resolve(permission).catch(() => {});
      return permission === true;
    };
    const reply = async answer => await consume(current() ? answer : forbidden);
    if (!current()) return await consume(forbidden);
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
      JSON.parse(original.admissionEvidenceWire).logicalPlanOriginal;
    const hasCompiledPlan = original.compiledPlanWire !== undefined;
    const hasPlanView = original.planViewWire !== undefined;
    if (hasCompiledPlan !== hasPlanView || hasCompiledPlan && inline !== undefined) {
      throw failure('ForeignClientRunSampleOutput');
    }
    const saved = hasCompiledPlan ? {
      compiledPlanWire: original.compiledPlanWire, planViewWire: original.planViewWire,
    } : inline;
    if (saved === undefined) return await reply(unavailable('not_retained'));
    const definition = control.admit('run_definition', original.definitionWire, request);
    if (definition.identity !== ref.runDefinitionCid) throw failure('ForeignClientRunSampleOutput');
    const planWire = control.readStoredRunPlanOriginal(saved, definition, original.programDefinitionCid, request);
    if (planWire !== saved.planViewWire) throw failure('ForeignClientRunSampleOutput');
    const map = JSON.parse(planWire).logical_map;
    const selected = samplePortSelection(map, selector);
    if (selected.reason !== undefined) return await reply(unavailable(selected.reason));
    const {step, port, producerStep, producerPort} = selected;
    let stored;
    try {
      stored = readRetained(ref, {compiledPlanCid: map.compiled_plan_cid, logicalMapCid: map.self_cid,
        stepId: producerStep.step_id, outputPortId: producerPort.port_id,
        carrierContractCid: producerPort.carrier_contract_cid, maxBytes: request.maxWireBytes},
      {current, reserve: bytes => {readWorkspace.metadata(request, bytes);}});
    } catch (error) {
      if (error?.code === 'ClientRelationSampleDenied') return await consume(forbidden);
      if (error?.code === 'ClientRelationSampleCapacity') return await reply(unavailable('capacity'));
      if (error?.code === 'ClientRelationSampleReadUnknown' && error.outcome === 'unknown') {
        return await reply(Object.freeze({state: 'unknown', reason: 'sample_read_unknown'}));
      }
      throw error;
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
    if (stored.kind === 'expired') return await reply(Object.freeze({state: 'expired'}));
    if (stored.kind !== 'available') return await reply(unavailable(
      stored.kind === 'ambiguous' ? 'selection_required' : 'not_retained',
    ));
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
    return await reply(view);
  }
  return async (request, consume) => {
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
