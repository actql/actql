import {explorerCopy, type ExplorerLocale} from './i18n.mjs';
import type * as Public from './read-model.js';
import type {Client,Execution,RunReference} from '@actql/sdk';
import type {WirePlanView,WireEffectfulStaticPlanView,WireExplanationFacts,
  WireExplanationContext,WireStaticExplanationView,WireExplanationNarrative,WireRunSample,WireSampleCapture} from '@actql/client-wire';
type StaticPlan = WirePlanView|WireEffectfulStaticPlanView;
type Step = WirePlanView['logical_map']['steps'][number];
type Port = Step['ports'][number];
type StepKey = Step['key'];
type LocaleOptions = Parameters<typeof Public.planStoryModel>[1];
type ExplanationPresentation = Parameters<typeof Public.staticExplanationReadModel>[1];
type StageInput = NonNullable<Public.PlanStoryModel['stageInputs'][number]['locator']>;
interface PlanInputFields {logical_map?:WirePlanView['logical_map']}
interface MeaningCollections {schema?:{fields?:readonly unknown[]};fields?:readonly unknown[];keys?:readonly unknown[]}

import {validWireEffectfulStaticPlanViewShape, validRunRef, validWirePlanViewShape, validWireRunPlanViewShape, validWireExplanationFactsShape} from '@actql/client-wire';
import {validWireRunExplanationViewShape, validWireRunExplanationContextViewShape, validWireStaticExplanationViewShape, validWireRunSampleShape, withinResultDescriptionLimits} from '@actql/client-wire';

import {ExplorerReadError, graphViewLimits} from './presentation-limits.mjs';
export {ExplorerReadError, graphViewLimits} from './presentation-limits.mjs';

const refuse:(code:string)=>never = code => { throw new ExplorerReadError(code); };
const freeze = <T,>(value:T):T => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};

// Accept an SDK-admitted static view, not a compiler/preparation handle or a
// permission. This model references original identities; it has no new self-CID.
export function planReadModel(view:StaticPlan):Public.PlanReadModel {
  if (view?.version === 'actql-effectful-static-plan-view/0.1') {
    if (!validWireEffectfulStaticPlanViewShape(view) ||
        view.program_definition_cid !== view.computation.plan_view.logical_map.program_definition_cid) {
      refuse('ExplorerInvalidPlan');
    }
    const computation = planReadModel(view.computation.plan_view);
    // Declared Effects have no graph edges or resolved physical observations.
    if (computation.debugEntry === true) refuse('ExplorerInvalidPlan');
    return freeze({...computation, effectful: {
      scope: 'computation_component', parameterValuesCid: view.parameter_values_cid,
      checkEnvironmentCid: view.check_environment_cid, unitId: view.effect_set.unit_id,
      members: structuredClone(view.effect_set.members),
      observations: structuredClone(view.observations),
    }});
  }
  const steps = (view as PlanInputFields)?.logical_map?.steps;
  if (!Array.isArray(steps) || steps.length > graphViewLimits.steps) {
    refuse('ExplorerMapLimit');
  }
  let count = 0;
  for (const step of steps as readonly Step[]) {
    if (!Array.isArray(step?.ports) ||
        (count += step.ports.length) > graphViewLimits.ports) {
      refuse('ExplorerMapLimit');
    }
  }
  if (!validWirePlanViewShape(view) ||
      view.logical_map.compiled_plan_cid !== view.compiled_plan_cid) {
    refuse('ExplorerInvalidPlan');
  }
  const outputs = new Map<string,{step:Step;port:Port}>();
  for (const step of steps as readonly Step[]) {
    for (const port of step.ports) {
      if (port.role === 'output') outputs.set(port.port_id, {step, port});
    }
  }
  const edges:Public.PlanReadModel['edges'][number][] = [], inputs:Public.PlanReadModel['inputs'][number][] = [];
  for (const step of steps as readonly Step[]) {
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
  return freeze<Public.PlanReadModel>({compiledPlanCid: view.compiled_plan_cid,
    logicalMapCid: view.logical_map.self_cid,
    programDefinitionCid: view.logical_map.program_definition_cid,
    observation: view.observation, providerIO: view.provider_io,
    ...(view.capabilities.debug_entry === true ? {debugEntry: true} : {}),
    nodes: steps.map((step:Step) => ({id: step.step_id, key: structuredClone(step.key),
      names: [...step.names], operator: step.operator,
      kind: step.key.occurrence.kind,
      ports: step.ports.map((port:Port) => ({...port, source: {...port.source}}))})),
    edges, inputs, sourceOrigins: {state: 'unavailable', reason: 'not_in_projection'}});
}

const storyText = Object.freeze({
  en: Object.freeze({operation: 'Logical operation', inputOutput: 'Input/output occurrence',
    stageInput: 'Stage input', unresolved: 'Origin not represented',
    ordering: 'Logical dependencies, not execution order'}),
  ja: Object.freeze({operation: '論理演算', inputOutput: '入力の出力',
    stageInput: 'Stage入力', unresolved: '取得元の対応は未提供',
    ordering: '論理的な依存関係。実行順序ではありません'}),
});

// A deterministic presentation of the existing compiler-issued projection.
// It issues no Story identities, parses no Program and infers no execution
// boundary. The caller must obtain the original view through the current SDK
// authorization path, including Run.plan() when explaining a Saved Run.
export function planStoryModel(view:StaticPlan, {locale = 'en'}:LocaleOptions = {}):Public.PlanStoryModel {
  if (!Object.hasOwn(storyText, locale)) refuse('ExplorerUnsupportedLocale');
  return planStory(view, planReadModel(view), locale);
}

function planStory(view: StaticPlan, model: Public.PlanReadModel, locale: NonNullable<ExplanationPresentation['locale']>): Public.PlanStoryModel {
  const text = storyText[locale];
  const original = view.version === 'actql-effectful-static-plan-view/0.1'
    ? view.computation.plan_view : view;
  return freeze<Public.PlanStoryModel>({locale, compiledPlanCid: model.compiledPlanCid,
    logicalMapCid: model.logicalMapCid, programDefinitionCid: model.programDefinitionCid,
    observation: model.observation,
    scope: model.effectful ? 'computation_component' : 'compiled_plan',
    ordering: {kind: 'logical_dependencies', text: text.ordering},
    occurrences: model.nodes.map(node => ({stepId: node.id, key: node.key,
      names: node.names, title: node.names.length === 0 ? node.id : node.names.join(', '),
      operator: node.operator, kind: node.kind,
      text: node.kind === 'input_output' ? text.inputOutput
        : `${text.operation}: ${node.operator}`,
      ports: node.ports})),
    // Each input occurrence keeps its own original locator and destination.
    // A Stage input is not evidence of a Source, Result or physical reader.
    stageInputs: model.inputs.map(input => ({...input,
      text: `${text.stageInput} ${input.locator.stage_ordinal}:${input.locator.input_port_ordinal} · ${text.unresolved}`})),
    dependencies: model.edges,
    quantities: structuredClone(original.quantities),
    capabilities: structuredClone(original.capabilities),
    sourceOrigins: model.sourceOrigins,
    ...(model.effectful ? {declaredEffects: model.effectful} : {}),
  });
}

// These finite presentation bounds do not change the Core expression language.
const explanationLimits = Object.freeze({nodes: 1024, depth: 64, characters: 65536});
const sameKey = (a:StepKey, b:StepKey) => a.self_cid === b.self_cid &&
  a.compiled_plan_cid === b.compiled_plan_cid && a.stage_ordinal === b.stage_ordinal &&
  a.occurrence.kind === b.occurrence.kind &&
  (a.occurrence.kind === 'operation'
    ? a.occurrence.operation_ordinal === (b.occurrence as Extract<StepKey['occurrence'],{kind:'operation'}>).operation_ordinal
    : a.occurrence.input_port_ordinal === (b.occurrence as Extract<StepKey['occurrence'],{kind:'input_output'}>).input_port_ordinal);
const sameIds = (ids:readonly string[], ports:readonly Port[], role:'input'|'output') => {
  const original = ports.filter(port => port.role === role);
  return ids.length === original.length && ids.every((id, index) => id === original[index].port_id);
};

// Consume SDK-admitted facts and original Plan DATA only. Shape/CID equality
// here protects presentation correspondence; it cannot replace Host current
// read/egress admission or establish compiler provenance by itself.
export function explanationStoryModel(view: StaticPlan, facts: WireExplanationFacts,
  {locale = 'en', render}: Parameters<typeof Public.explanationStoryModel>[2]): Public.ExplanationStoryModel {
  const story = planStoryModel(view, {locale});
  checkExplanationFacts(story, facts);
  const {lines, presentation} = renderExplanation(render, facts, locale, facts, []);
  return attachExplanationFacts({...story, narrative: presentation}, facts, index => lines.steps[index]);
}

function checkExplanationFacts(story: Public.PlanStoryModel, facts: WireExplanationFacts) {
  if (!Array.isArray(facts?.steps) || facts.steps.length > graphViewLimits.steps) refuse('ExplorerExplanationLimit');
  if (!withinResultDescriptionLimits(facts, projectionLimits)) refuse('ExplorerExplanationLimit');
  let nodes = 0, edges = 0, fields = 0;
  for (const step of facts.steps) {
    const meaning = step?.meaning;
    if (meaning?.kind === 'filter' && meaning.predicate?.state === 'projected') {
      if (!Array.isArray(meaning.predicate.nodes) ||
          (nodes += meaning.predicate.nodes.length) > explanationLimits.nodes) refuse('ExplorerExplanationLimit');
      for (const node of meaning.predicate.nodes) {
        if (node?.form === 'operation' && (!Array.isArray(node.children) ||
            (edges += node.children.length) > explanationLimits.nodes)) refuse('ExplorerExplanationLimit');
        if (node?.form === 'property' && ++edges > explanationLimits.nodes) refuse('ExplorerExplanationLimit');
      }
    }
    const collection = (meaning as MeaningCollections)?.schema?.fields ?? (meaning as MeaningCollections)?.fields ?? (meaning as MeaningCollections)?.keys ?? [];
    if (!Array.isArray(collection) || (fields += collection.length) > graphViewLimits.ports) refuse('ExplorerExplanationLimit');
  }
  if (!validWireExplanationFactsShape(facts) ||
      facts.compiled_plan_cid !== story.compiledPlanCid ||
      facts.program_definition_cid !== story.programDefinitionCid ||
      facts.logical_map_cid !== story.logicalMapCid ||
      facts.steps.length !== story.occurrences.length ||
      (story.declaredEffects !== undefined && facts.parameter_values_cid !== story.declaredEffects.parameterValuesCid)) {
    refuse('ExplorerInvalidExplanation');
  }
  for (const [index, occurrence] of story.occurrences.entries()) {
    const fact = facts.steps[index];
    if (fact.step_id !== occurrence.stepId || fact.operator !== occurrence.operator ||
        !sameKey(fact.key, occurrence.key) || !sameIds(fact.input_ports, occurrence.ports, 'input') ||
        !sameIds(fact.output_ports, occurrence.ports, 'output')) refuse('ExplorerInvalidExplanation');
  }
}

function attachExplanationFacts(story: Public.PlanStoryModel & Pick<Public.ExplanationStoryModel, 'narrative'>, facts: WireExplanationFacts,
  describe: (index: number) => string): Public.ExplanationStoryModel {
  return freeze<Public.ExplanationStoryModel>({...story, factsCid: facts.self_cid, parameterValuesCid: facts.parameter_values_cid,
    occurrences: story.occurrences.map((occurrence, index) => {
      const fact = facts.steps[index];
      return {...occurrence, explanation: {state: fact.meaning.kind === 'not_projected' ? 'not_projected' : 'projected',
        meaning: structuredClone(fact.meaning), text: describe(index)}};
    })});
}

function sameDeclaration(actual: unknown, expected: unknown): boolean {
  if (actual === expected) return true;
  if (typeof actual !== 'object' || actual === null || typeof expected !== 'object' || expected === null) return false;
  const names = Object.keys(actual);
  return names.length === Object.keys(expected).length && names.every(name =>
    Object.hasOwn(expected, name) && sameDeclaration((actual as Record<string, unknown>)[name], (expected as Record<string, unknown>)[name]));
}

function checkedContext(story: Public.PlanStoryModel, facts: WireExplanationFacts,
  context: WireExplanationContext, saved: boolean) {
  const binding = context.binding;
  const effects = story.declaredEffects;
  if (binding.compiled_plan_cid !== story.compiledPlanCid || binding.logical_map_cid !== story.logicalMapCid ||
      binding.program_definition_cid !== story.programDefinitionCid || binding.parameter_values_cid !== facts.parameter_values_cid ||
      effects !== undefined && binding.check_environment_cid !== effects.checkEnvironmentCid) refuse('ExplorerInvalidExplanation');
  const locator = ({stage_ordinal, input_port_ordinal}: StageInput) => `${stage_ordinal}:${input_port_ordinal}`;
  const inputs = new Map<string, {step_id: string; port_id: string}[]>();
  for (const {locator: original, stepId, inputPortId} of story.stageInputs) {
    const key = locator(original!);
    if (!inputs.has(key)) inputs.set(key, []);
    inputs.get(key)!.push({step_id: stepId, port_id: inputPortId});
  }
  const steps = new Map(story.occurrences.map(step => [step.stepId, step]));
  if (context.stage_result_links !== undefined) {
    const imported = new Set();
    for (const {producer, consumer, result_projection} of context.stage_result_links) {
      const original = steps.get(producer.step_id), destination = steps.get(consumer.step_id);
      if (original === undefined || destination === undefined) refuse('ExplorerInvalidExplanation');
      const output = original.ports.find(port => port.port_id === producer.port_id);
      const input = destination.ports.find(port => port.port_id === consumer.port_id);
      if (output?.role !== 'output' || input?.role !== 'input' ||
          input.source.kind !== 'stage_input' ||
          input.source.stage_ordinal !== destination.key.stage_ordinal ||
          original.key.stage_ordinal >= destination.key.stage_ordinal ||
          output.carrier !== input.carrier ||
          (!result_projection && output.carrier_contract_cid !== input.carrier_contract_cid) ||
          imported.has(consumer.port_id)) refuse('ExplorerInvalidExplanation');
      imported.add(consumer.port_id);
    }
  }
  const sources = new Set();
  let sawEffects = false;
  for (const item of context.items) {
    if (item.kind === 'source') {
      const key = locator(item.stage_input);
      const ports = inputs.get(key) ?? [];
      if (sources.has(key) || ports.length !== item.consuming_ports.length ||
          !ports.every((port, index) => sameDeclaration(port, item.consuming_ports[index]))) refuse('ExplorerInvalidExplanation');
      sources.add(key);
    } else if (item.kind === 'effect_set') {
      // A Saved reply carries the computation map and the committed Effect
      // declarations in Context. A static reply also carries the separate
      // Effect set, against which every declaration must still agree.
      if (sawEffects || !saved && (effects === undefined || item.unit_id !== effects.unitId ||
          item.members.length !== effects.members.length || !item.members.every((member, index) =>
            sameDeclaration(member.declaration, effects.members[index])))) refuse('ExplorerInvalidExplanation');
      sawEffects = true;
    } else if (item.producer.state === 'projected') {
      const {step_id, port_id} = item.producer, step = steps.get(step_id);
      if (!step?.ports.some(port => port.role === 'output' && port.port_id === port_id) ||
          item.kind === 'model_task' && step.operator !== 'infer') refuse('ExplorerInvalidExplanation');
    }
  }
  if (!saved && sawEffects !== (effects !== undefined)) refuse('ExplorerInvalidExplanation');
}

// The public SDK is the disclosure boundary. These checks prevent mixing
// presentation originals after the read and confer no new authority.
export function staticExplanationReadModel(view: WireStaticExplanationView,
  {locale = 'en', render}: ExplanationPresentation): Public.StaticExplanationReadModel {
  if (!Object.hasOwn(storyText, locale)) refuse('ExplorerUnsupportedLocale');
  if (!withinResultDescriptionLimits(view, projectionLimits)) refuse('ExplorerExplanationLimit');
  if (!validWireStaticExplanationViewShape(view)) refuse('ExplorerInvalidExplanation');
  return explanationContextReadModel(view, locale, render, false);
}

// The already admitted Context and Facts retain the original indices and
// Step IDs. A presenter cannot point its summary at a different item or Step.
function renderExplanation<Input>(render: (wire: Input, locale: 'en' | 'ja') => WireExplanationNarrative,
  wire: Input, locale: NonNullable<ExplanationPresentation['locale']>,
  facts: WireExplanationFacts, context: WireExplanationContext['items']) {
  let narrative: WireExplanationNarrative;
  try {
    narrative = render(wire, locale);
  } catch (error) {
    if ((error as {code?: string} | null)?.code === 'StaticExplanationNarrativeLimit') refuse('ExplorerExplanationLimit');
    if ((error as {code?: string} | null)?.code === 'InvalidStaticExplanationNarrative') refuse('ExplorerInvalidExplanation');
    throw error;
  }
  const steps = facts.steps;
  if (!Array.isArray(narrative?.steps) || narrative.steps.length !== steps.length ||
      !Array.isArray(narrative.context) || narrative.context.length !== context.length) {
    refuse('ExplorerInvalidExplanation');
  }
  const {version, summary, clauses, items} = narrative;
  if (version !== 'actql-explanation-narrative/0.1' || typeof summary !== 'string' || summary.length === 0 ||
      !Array.isArray(clauses) || clauses.length > 6 ||
      !Array.isArray(items) || items.length !== context.length + steps.length) refuse('ExplorerInvalidExplanation');
  const exactSteps = new Map(steps.map(step => [step.step_id, step.operator]));
  for (const [index, item] of items.entries()) {
    if (index < context.length) {
      if (item?.kind !== 'context' || item.index !== index) refuse('ExplorerInvalidExplanation');
    } else {
      const ordinal = index - context.length;
      if (item?.kind !== 'step' || item.index !== ordinal || item.step_id !== steps[ordinal].step_id) {
        refuse('ExplorerInvalidExplanation');
      }
    }
  }
  let characters = summary.length;
  for (const lines of [narrative.context, narrative.steps]) for (const line of lines) {
    if (typeof line !== 'string') refuse('ExplorerInvalidExplanation');
    if ((characters += line.length) > explanationLimits.characters) refuse('ExplorerExplanationLimit');
  }
  const kinds = new Set();
  for (const clause of clauses) {
    const {kind, text, context_items: indices, step_ids: ids} = clause ?? {};
    if (typeof text !== 'string' || !Array.isArray(indices) || !Array.isArray(ids) ||
        indices.length > context.length || ids.length > steps.length || kinds.has(kind)) refuse('ExplorerInvalidExplanation');
    kinds.add(kind);
    if (kind === 'join' || kind === 'filter') {
      if (indices.length !== 0 || !ids.length || new Set(ids).size !== ids.length ||
          ids.some(id => exactSteps.get(id) !== kind)) refuse('ExplorerInvalidExplanation');
    } else {
      const origin = kind === 'effect' ? 'effect_set' : kind;
      if (!['source', 'model_task', 'result', 'effect_set'].includes(origin) || ids.length !== 0 ||
          !indices.length || new Set(indices).size !== indices.length ||
          indices.some(index => !Number.isSafeInteger(index) || context[index]?.kind !== origin)) {
        refuse('ExplorerInvalidExplanation');
      }
    }
    characters += text.length;
  }
  if (characters > explanationLimits.characters) refuse('ExplorerExplanationLimit');
  const presentation: Public.ExplanationStoryModel['narrative'] = {version, summary,
    clauses: clauses.map(({kind, text, context_items, step_ids}) =>
      ({kind, text, context_items: [...context_items], step_ids: [...step_ids]})),
    items: items.map(item => item.kind === 'context' ? {kind: item.kind, index: item.index}
      : {kind: item.kind, index: item.index, step_id: item.step_id})};
  return {lines: narrative, presentation};
}

function explanationContextReadModel(view: WireStaticExplanationView, locale: NonNullable<ExplanationPresentation['locale']>,
  render: ExplanationPresentation['render'], saved: boolean): Public.StaticExplanationReadModel {
  const plan = planReadModel(view.plan), original = planStory(view.plan, plan, locale);
  checkExplanationFacts(original, view.facts);
  checkedContext(original, view.facts, view.context, saved);
  const {lines, presentation} = renderExplanation(render, view, locale, view.facts, view.context.items);
  const scope = saved && view.context.items.some(item => item.kind === 'effect_set')
    ? 'computation_component' : original.scope;
  const story = attachExplanationFacts({...original, scope, narrative: presentation},
    view.facts, index => lines.steps[index]);
  const projectedPlan = view.context.stage_result_links === undefined ? plan
    : {...plan, stageResultLinks: structuredClone(view.context.stage_result_links)};
  return freeze({plan: projectedPlan, story, context: view.context.items.map((item, index) =>
    ({origin: structuredClone(item), text: lines.context[index]}))});
}

// A UI epoch only discards stale presentation. It is not a Host permission,
// session, Run revision, cursor or durable operation fence. Every SDK request
// still applies the current Host authorization through its normal boundary.
export function createReadEpoch():ReturnType<typeof Public.createReadEpoch> {
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
function boundedProjectionOptions(options:Parameters<Client['plan']>[1]) {
  const bounded = {...options};
  for (const [name, ceiling] of Object.entries(projectionLimits)) {
    const requested = (bounded as Record<string,unknown>)[name];
    // Never expand a tighter caller budget. Invalid values remain unchanged
    // so the existing SDK, rather than this view adapter, admits or refuses them.
    if (requested === undefined) (bounded as Record<string,unknown>)[name] = ceiling;
    else if (Number.isSafeInteger(requested)) {
      (bounded as Record<string,unknown>)[name] = Math.min(requested as number, ceiling);
    }
  }
  return bounded;
}
async function currentRead<T>(ticket:Public.ReadTicket, read:()=>T|Promise<T>):Promise<T> {
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

export async function readStaticPlan(client:Parameters<typeof Public.readStaticPlan>[0], input:Parameters<typeof Public.readStaticPlan>[1], options:Parameters<typeof Public.readStaticPlan>[2], ticket:Parameters<typeof Public.readStaticPlan>[3]):ReturnType<typeof Public.readStaticPlan> {
  return currentRead(ticket, async () => {
    if (typeof client.plan !== 'function') refuse('ExplorerCapabilityUnavailable');
    const view = await client.plan(input, boundedProjectionOptions(options));
    ticket.assertCurrent();
    return planReadModel(view);
  });
}

export async function readStaticExplanation(client: Pick<Client, 'explain'>, input: Parameters<Client['explain']>[0],
  options: Parameters<Client['explain']>[1], {locale = 'en', render}: ExplanationPresentation,
  ticket: Public.ReadTicket): Promise<Public.StaticExplanationReadModel> {
  if (!Object.hasOwn(storyText, locale)) refuse('ExplorerUnsupportedLocale');
  return currentRead(ticket, async () => {
    if (typeof client.explain !== 'function') refuse('ExplorerCapabilityUnavailable');
    const view = await client.explain(input, boundedProjectionOptions(options));
    ticket.assertCurrent();
    return staticExplanationReadModel(view, {locale, render});
  });
}

export async function readExistingRun(client:Parameters<typeof Public.readExistingRun>[0], ref:Parameters<typeof Public.readExistingRun>[1], ticket:Parameters<typeof Public.readExistingRun>[2]):ReturnType<typeof Public.readExistingRun> {
  const original = Object.freeze({...ref});
  const run = await currentRead(ticket, () => client.attach(original));
  return currentRead(ticket, () => {
    if (typeof run.inspect !== 'function') refuse('ExplorerCapabilityUnavailable');
    return run.inspect(projectionLimits);
  });
}

// Read the original immutable map retained for this exact admitted Run. Missing
// legacy evidence stays unavailable; static planning is never a repair path.
async function originalRunPlan(client:Pick<Client,'attach'>, ref:RunReference, ticket:Public.ReadTicket) {
  const original = Object.freeze({...ref});
  if (!validRunRef(original)) refuse('ExplorerInvalidRunPlan');
  const run = await currentRead(ticket, () => client.attach(original));
  return {original, view: await originalRunPlanOnExecution(run, original, ticket)};
}

async function originalRunPlanOnExecution(run:Execution, original:RunReference, ticket:Public.ReadTicket) {
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
  ticket.assertCurrent();
  return view;
}

export async function readExistingRunPlan(client:Parameters<typeof Public.readExistingRunPlan>[0], ref:Parameters<typeof Public.readExistingRunPlan>[1], ticket:Parameters<typeof Public.readExistingRunPlan>[2]):ReturnType<typeof Public.readExistingRunPlan> {
  const {original, view} = await originalRunPlan(client, ref, ticket);
  ticket.assertCurrent();
  return freeze({runRef: original, plan: planReadModel(view.plan_view)});
}

// Only the existing public Execution read may supply these retained originals.
// Missing legacy Facts remain its authorized NotProjected result; neither Plan
// nor static compilation is a fallback for this separate disclosure operation.
export async function readExistingRunExplanation(client:Parameters<typeof Public.readExistingRunExplanation>[0], ref:Parameters<typeof Public.readExistingRunExplanation>[1], ticket:Parameters<typeof Public.readExistingRunExplanation>[2]):ReturnType<typeof Public.readExistingRunExplanation> {
  const original = Object.freeze({...ref});
  if (!validRunRef(original)) refuse('ExplorerInvalidExplanation');
  const run = await currentRead(ticket, () => client.attach(original));
  return originalRunExplanationOnExecution(run, original, ticket);
}

async function originalRunExplanationOnExecution(run:Execution, original:RunReference, ticket:Public.ReadTicket) {
  const explain = run.explain;
  ticket.assertCurrent();
  if (typeof explain !== 'function') refuse('ExplorerCapabilityUnavailable');
  const view:unknown = await currentRead(ticket, () => Reflect.apply(explain, run, [projectionLimits]));
  if (!withinResultDescriptionLimits(view, projectionLimits) ||
      !validWireRunExplanationViewShape(view) ||
      view.run_ref.namespaceId !== original.namespaceId ||
      view.run_ref.authorityScopeCid !== original.authorityScopeCid ||
      view.run_ref.runDefinitionCid !== original.runDefinitionCid) refuse('ExplorerInvalidExplanation');
  ticket.assertCurrent();
  return freeze(view);
}

// A private presentation composition of two existing public reads. It does
// not change either closed wire family or recover originals from UI cards.
export async function readExistingRunPresentation(client: Parameters<typeof Public.readExistingRunPresentation>[0],
  ref: Parameters<typeof Public.readExistingRunPresentation>[1],
  {locale = 'en', render}: Parameters<typeof Public.readExistingRunPresentation>[2],
  ticket: Parameters<typeof Public.readExistingRunPresentation>[3]): ReturnType<typeof Public.readExistingRunPresentation> {
  if (!Object.hasOwn(storyText, locale)) refuse('ExplorerUnsupportedLocale');
  const original = Object.freeze({...ref});
  if (!validRunRef(original)) refuse('ExplorerInvalidExplanation');
  const run = await currentRead(ticket, () => client.attach(original));
  const explanation = await originalRunExplanationOnExecution(run, original, ticket);
  if (explanation.explanation.state === 'not_projected') {
    ticket.assertCurrent();
    return freeze({runRef: original, plan: null, explanation: explanation.explanation});
  }
  const view = await originalRunPlanOnExecution(run, original, ticket);
  // This original renderer checks the actual map/key/port anchors, and the
  // parameter binding where declared Effects supply it. IDs grant nothing.
  const story = explanationStoryModel(view.plan_view, explanation.explanation.facts, {locale, render});
  const plan = planReadModel(view.plan_view);
  ticket.assertCurrent();
  return freeze({runRef: original, plan, explanation: {state: 'projected', story}});
}

// One authorized read of the attached execution supplies every Saved
// presentation original, including the immutable computation map.
export async function readExistingRunContext(client: Pick<Client, 'attach'>, ref: RunReference,
  {locale = 'en', render}: ExplanationPresentation, ticket: Public.ReadTicket): Promise<Public.SavedExplanationReadModel> {
  if (!Object.hasOwn(storyText, locale)) refuse('ExplorerUnsupportedLocale');
  const original = Object.freeze({...ref});
  if (!validRunRef(original)) refuse('ExplorerInvalidExplanation');
  const run = await currentRead(ticket, () => client.attach(original));
  const view = await currentRead(ticket, () => {
    if (typeof run.explainContext !== 'function') refuse('ExplorerCapabilityUnavailable');
    return run.explainContext(projectionLimits);
  });
  if (!withinResultDescriptionLimits(view, projectionLimits) ||
      !validWireRunExplanationContextViewShape(view) ||
      view.run_ref.namespaceId !== original.namespaceId ||
      view.run_ref.authorityScopeCid !== original.authorityScopeCid ||
      view.run_ref.runDefinitionCid !== original.runDefinitionCid) refuse('ExplorerInvalidExplanation');
  ticket.assertCurrent();
  if (view.explanation.state === 'not_projected') {
    return freeze({runRef: original, plan: null, explanation: view.explanation});
  }
  const {plan, story, context} = explanationContextReadModel(view.explanation.view, locale, render, true);
  ticket.assertCurrent();
  return freeze({runRef: original, plan, explanation: {state: 'projected', story, context}});
}

// Capture presentation options before the first asynchronous read, then use
// the SAME original-Run acquisition and binding check as the existing viewer.
export async function readExistingRunStory(client:Parameters<typeof Public.readExistingRunStory>[0], ref:Parameters<typeof Public.readExistingRunStory>[1], options:Parameters<typeof Public.readExistingRunStory>[2], ticket:Parameters<typeof Public.readExistingRunStory>[3]):ReturnType<typeof Public.readExistingRunStory> {
  const locale = options?.locale ?? 'en';
  if (!Object.hasOwn(storyText, locale)) refuse('ExplorerUnsupportedLocale');
  const {original, view} = await originalRunPlan(client, ref, ticket);
  ticket.assertCurrent();
  return freeze({runRef: original, story: planStoryModel(view.plan_view, {locale})});
}

// Metadata only: no payload read attempt/grant/open is allocated. A later
// explicit bounded Result read must retain its original attempt and receipt.
// Use only a complete column list projected for this exact original carrier.
export function expectedStoryPortColumns(
  steps: ReadonlyMap<string, Public.ExplanationStoryModel['occurrences'][number]>,
  step: Public.ExplanationStoryModel['occurrences'][number], port: Port | undefined,
) {
  if (port?.carrier !== 'relation' || !step.ports.includes(port)) return undefined;
  const origin = port.role === 'input' ? port.source : undefined;
  if (origin !== undefined && origin.kind !== 'logical_output') return undefined;
  const producer = origin === undefined ? step : steps.get(origin.step_id);
  if (producer === undefined) return undefined;
  const outputs = producer.ports.filter(item => item.role === 'output');
  const output = outputs[0];
  const outputId = origin === undefined ? port.port_id : origin.output_port_id;
  if (outputs.length !== 1 || output.port_id !== outputId ||
      output.carrier !== port.carrier || output.carrier_contract_cid !== port.carrier_contract_cid) return undefined;
  const meaning = producer.explanation.meaning;
  if (meaning.kind === 'values') return meaning.schema.fields.map(field => field.name);
  if (meaning.kind === 'projection' && meaning.operation === 'select') return meaning.fields.map(field => field.output);
  return undefined;
}

// The installed compiler issues ordinal zero as the only output. The
// selector names an exact input port but selects an output by Step alone.
export function storySamplePorts(step: Pick<Step, 'ports'>) {
  const outputs = step.ports.filter(port => port.role === 'output');
  return step.ports.filter(port => port.carrier === 'relation' &&
    (port.role === 'input' ? port.source.kind === 'logical_output' :
      outputs.length === 1 && port.port_ordinal === 0));
}

export function sampleCaptureCaption({strategy, sampled_items: sampled, total, completeness, truncation}: WireSampleCapture, locale?: ExplorerLocale) {
  const words = explorerCopy(locale);
  const exactTotal = total.kind === 'exact' && total.unit === 'rows' ? total.value : undefined;
  if (exactTotal === sampled && completeness === 'complete' && truncation !== 'confirmed') {
    return words.allRows(sampled);
  }
  const prefix = strategy === 'execution_prefix' && completeness !== 'complete' &&
    truncation !== 'not_truncated' && (completeness === 'partial' || truncation === 'confirmed');
  const belowTotal = exactTotal !== undefined &&
    (sampled.length < exactTotal.length || sampled.length === exactTotal.length && sampled < exactTotal);
  if (prefix && belowTotal) return words.firstOfRows(sampled, exactTotal);
  if (prefix && total.kind === 'unknown' && total.unit === 'rows') {
    return words.firstRows(sampled);
  }
  const observation = belowTotal || exactTotal === sampled ? words.totalRows(exactTotal) :
    exactTotal === undefined ? words.captureNotObserved : words.captureInconsistent;
  return words.observedRows(sampled, observation);
}

export function sampleCellPreview(text: string) {
  let count = 0, end = 0;
  for (const character of text) {
    if (count === 200) return text.slice(0, end);
    count++;
    end += character.length;
  }
  return text;
}

// Presentation correlation only. These IDs identify the card the operator
// selected. The SDK and its current Sample/Run authority still own the read.
export function validSamplePortSelection(value: unknown): value is Public.SamplePortSelection {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const fields = value as Record<string, unknown>;
  const next = Object.hasOwn(fields, 'nextRevision');
  return Object.keys(fields).length === (next ? 7 : 6) &&
    (fields.role === 'input' || fields.role === 'output') &&
    (!next || fields.role === 'input' && typeof fields.nextRevision === 'number' &&
      Number.isInteger(fields.nextRevision) && fields.nextRevision >= 1 && fields.nextRevision <= 2147483647) &&
    ['stepId', 'portId', 'compiledPlanCid', 'logicalMapCid', 'carrierContractCid'].every(key =>
      Object.hasOwn(fields, key) && typeof fields[key] === 'string' && /^sha256:[0-9a-f]{64}$/u.test(fields[key]));
}

export function sampleMatchesPort(value: unknown, ref: RunReference,
  port: Public.SamplePortSelection): value is WireRunSample {
  if (!withinResultDescriptionLimits(value, projectionLimits) || !validWireRunSampleShape(value)) return false;
  if (value.state !== 'available') return true;
  const {source, capture, data} = value;
  return source.run_ref.namespaceId === ref.namespaceId &&
    source.run_ref.authorityScopeCid === ref.authorityScopeCid &&
    source.run_ref.runDefinitionCid === ref.runDefinitionCid &&
    source.compiled_plan_cid === port.compiledPlanCid && source.logical_map_cid === port.logicalMapCid &&
    source.step_id === port.stepId && source.role === port.role && source.port_id === port.portId &&
    source.carrier_contract_cid === port.carrierContractCid &&
    source.carrier === 'relation' && data.kind === 'relation' &&
    capture.sampled_items === String(data.rows.length) &&
    data.columns.every((column, index) => column.position === index) &&
    data.rows.every(row => row.length === data.columns.length);
}

export async function readExistingRunSample(client: Pick<Client, 'attach'>, ref: RunReference,
  port: Public.SamplePortSelection, ticket: Public.ReadTicket): Promise<WireRunSample> {
  const original = Object.freeze({...ref}), selected = Object.freeze({...port});
  if (!validRunRef(original) || !validSamplePortSelection(selected)) refuse('ExplorerInvalidRequest');
  const run = await currentRead(ticket, () => client.attach(original));
  if (typeof run.sample !== 'function') return Object.freeze({state: 'unavailable', reason: 'not_supported'});
  const selector = {step: {by: 'id' as const, step_id: selected.stepId}, role: selected.role,
    ...(selected.role === 'input' ? {input_port_id: selected.portId} : {})};
  const limits = selected.nextRevision === undefined ? projectionLimits
    : {...projectionLimits, nextRevision: selected.nextRevision};
  const value = await currentRead(ticket, () => run.sample(selector, limits));
  if (!sampleMatchesPort(value, original, selected)) refuse('ExplorerInvalidSample');
  ticket.assertCurrent();
  return freeze(value);
}

export async function describeExistingResult(client:Parameters<typeof Public.describeExistingResult>[0], ref:Parameters<typeof Public.describeExistingResult>[1], name:Parameters<typeof Public.describeExistingResult>[2], ticket:Parameters<typeof Public.describeExistingResult>[3]):ReturnType<typeof Public.describeExistingResult> {
  const original = Object.freeze({...ref});
  const run = await currentRead(ticket, () => client.attach(original));
  return currentRead(ticket, () => run.result(name).describe());
}
