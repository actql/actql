import {validWireEffectfulStaticPlanViewShape, validRunRef, validWirePlanViewShape, validWireRunPlanViewShape} from '@actql/client-wire';

export class ExplorerReadError extends Error {
  constructor(code) { super(code); this.code = code; }
}

const refuse = code => { throw new ExplorerReadError(code); };
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};

// Presentation limits refuse a complete view; they never silently page/truncate
// a map while preserving its complete identity. Public reads retain Host limits.
export const graphViewLimits = Object.freeze({steps: 256, ports: 1024});

// Accept an SDK-admitted static view, not a compiler/preparation handle or a
// permission. This model references original identities; it has no new self-CID.
export function planReadModel(view) {
  if (view?.version === 'actql-effectful-static-plan-view/0.1') {
    if (!validWireEffectfulStaticPlanViewShape(view) ||
        view.program_definition_cid !== view.computation.plan_view.logical_map.program_definition_cid) {
      refuse('ExplorerInvalidPlan');
    }
    const computation = planReadModel(view.computation.plan_view);
    // Declared Effects have no graph edges or resolved physical observations.
    return freeze({...computation, effectful: {
      scope: 'computation_component', parameterValuesCid: view.parameter_values_cid,
      checkEnvironmentCid: view.check_environment_cid, unitId: view.effect_set.unit_id,
      members: structuredClone(view.effect_set.members),
      observations: structuredClone(view.observations),
    }});
  }
  const steps = view?.logical_map?.steps;
  if (!Array.isArray(steps) || steps.length > graphViewLimits.steps) {
    refuse('ExplorerMapLimit');
  }
  let count = 0;
  for (const step of steps) {
    if (!Array.isArray(step?.ports) ||
        (count += step.ports.length) > graphViewLimits.ports) {
      refuse('ExplorerMapLimit');
    }
  }
  if (!validWirePlanViewShape(view) ||
      view.logical_map.compiled_plan_cid !== view.compiled_plan_cid) {
    refuse('ExplorerInvalidPlan');
  }
  const outputs = new Map();
  for (const step of steps) {
    for (const port of step.ports) {
      if (port.role === 'output') outputs.set(port.port_id, {step, port});
    }
  }
  const edges = [], inputs = [];
  for (const step of steps) {
    for (const port of step.ports) {
      if (port.role !== 'input') continue;
      const source = port.source;
      if (source.kind === 'stage_input') {
        // The projection has no producer mapping for this Stage input. Display
        // its exact locator, not a guessed Source/previous-Stage Compute node.
        inputs.push({stepId: step.step_id, inputPortId: port.port_id,
          locator: {...source}});
        continue;
      }
      const producer = outputs.get(source.output_port_id);
      if (producer === undefined || producer.step.step_id !== source.step_id ||
          producer.port.carrier !== port.carrier ||
          producer.port.carrier_contract_cid !== port.carrier_contract_cid) {
        refuse('ExplorerUnresolvedPort');
      }
      // The destination input port identifies an occurrence, including when
      // both Join roles consume the same output. Never deduplicate by producer.
      edges.push({id: port.port_id, sourceStepId: source.step_id,
        sourcePortId: source.output_port_id, targetStepId: step.step_id,
        targetPortId: port.port_id, targetPortOrdinal: port.port_ordinal});
    }
  }
  return freeze({compiledPlanCid: view.compiled_plan_cid,
    logicalMapCid: view.logical_map.self_cid,
    programDefinitionCid: view.logical_map.program_definition_cid,
    observation: view.observation, providerIO: view.provider_io,
    nodes: steps.map(step => ({id: step.step_id, key: structuredClone(step.key),
      names: [...step.names], operator: step.operator,
      kind: step.key.occurrence.kind,
      ports: step.ports.map(port => ({...port, source: {...port.source}}))})),
    edges, inputs, sourceOrigins: {state: 'unavailable', reason: 'not_in_projection'}});
}

// A UI epoch only discards stale presentation. It is not a Host permission,
// session, Run revision, cursor or durable operation fence. Every SDK request
// still applies the current Host authorization through its normal boundary.
export function createReadEpoch() {
  let epoch = 0;
  return Object.freeze({invalidate() { epoch++; }, capture() {
    const original = epoch;
    return Object.freeze({assertCurrent() {
      if (original !== epoch) refuse('ExplorerStaleScope');
    }});
  }});
}

const projectionLimits = Object.freeze({maxWireBytes: 65536,
  maxNodes: 10000, maxDepth: 64});
function boundedProjectionOptions(options) {
  const bounded = {...options};
  for (const [name, ceiling] of Object.entries(projectionLimits)) {
    const requested = bounded[name];
    // Never expand a tighter caller budget. Invalid values remain unchanged
    // so the existing SDK, rather than this view adapter, admits or refuses them.
    if (requested === undefined) bounded[name] = ceiling;
    else if (Number.isSafeInteger(requested)) {
      bounded[name] = Math.min(requested, ceiling);
    }
  }
  return bounded;
}
async function currentRead(ticket, read) {
  ticket.assertCurrent();
  try {
    const value = await read();
    ticket.assertCurrent();
    return value;
  } catch (error) {
    // An old-scope error (including 401) cannot end a newer session.
    ticket.assertCurrent();
    throw error;
  }
}

export async function readStaticPlan(client, input, options, ticket) {
  return currentRead(ticket, async () => {
    if (typeof client.plan !== 'function') refuse('ExplorerCapabilityUnavailable');
    const view = await client.plan(input, boundedProjectionOptions(options));
    ticket.assertCurrent();
    return planReadModel(view);
  });
}

export async function readExistingRun(client, ref, ticket) {
  const original = Object.freeze({...ref});
  const run = await currentRead(ticket, () => client.attach(original));
  return currentRead(ticket, () => {
    if (typeof run.inspect !== 'function') refuse('ExplorerCapabilityUnavailable');
    return run.inspect(projectionLimits);
  });
}

// Read the original immutable map retained for this exact admitted Run. Missing
// legacy evidence stays unavailable; static planning is never a repair path.
export async function readExistingRunPlan(client, ref, ticket) {
  const original = Object.freeze({...ref});
  if (!validRunRef(original)) refuse('ExplorerInvalidRunPlan');
  const run = await currentRead(ticket, () => client.attach(original));
  const view = await currentRead(ticket, () => {
    if (typeof run.plan !== 'function') refuse('ExplorerCapabilityUnavailable');
    return run.plan(projectionLimits);
  });
  if (!validWireRunPlanViewShape(view) ||
      view.run_ref.namespaceId !== original.namespaceId ||
      view.run_ref.authorityScopeCid !== original.authorityScopeCid ||
      view.run_ref.runDefinitionCid !== original.runDefinitionCid) {
    refuse('ExplorerInvalidRunPlan');
  }
  return freeze({runRef: original, plan: planReadModel(view.plan_view)});
}

// Metadata only: no payload read attempt/grant/open is allocated. A later
// explicit bounded Result read must retain its original attempt and receipt.
export async function describeExistingResult(client, ref, name, ticket) {
  const original = Object.freeze({...ref});
  const run = await currentRead(ticket, () => client.attach(original));
  return currentRead(ticket, () => run.result(name).describe());
}
