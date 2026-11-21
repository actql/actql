import type * as Public from './read-model.js';
import type {Client,Execution,RunReference} from '@actql/sdk';
import type {WirePlanView,WireEffectfulStaticPlanView,WireExplanationFacts} from '@actql/client-wire';
type StaticPlan = WirePlanView|WireEffectfulStaticPlanView;
type Step = WirePlanView['logical_map']['steps'][number];
type Port = Step['ports'][number];
type Meaning = WireExplanationFacts['steps'][number]['meaning'];
type Predicate = Extract<Meaning,{kind:'filter'}>['predicate'];
type FieldType = Extract<Meaning,{kind:'values'}>['schema']['fields'][number]['type'];
type StepKey = Step['key'];
type LocaleOptions = Parameters<typeof Public.planStoryModel>[1];
interface PlanInputFields {logical_map?:WirePlanView['logical_map']}
interface MeaningCollections {schema?:{fields?:readonly unknown[]};fields?:readonly unknown[];keys?:readonly unknown[]}

import {validWireEffectfulStaticPlanViewShape, validRunRef, validWirePlanViewShape, validWireRunPlanViewShape, validWireExplanationFactsShape} from '@actql/client-wire';
import {validWireRunExplanationViewShape, withinResultDescriptionLimits} from '@actql/client-wire';

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
  const model = planReadModel(view), text = storyText[locale];
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
const explanationText = Object.freeze({
  en: Object.freeze({values: 'Declared input fields', input: 'Original input/output binding',
    filter: 'Keep rows where', select: 'Select output fields', rename: 'Rename output fields',
    drop: 'Output fields after dropping', join: 'join on', nullKey: 'Null keys',
    no_match: 'do not match', fail: 'fail', redacted: 'redacted',
    unprojected: 'Meaning not projected', predicate: 'Predicate form not projected',
    conditional: 'conditional',
    operators: Object.freeze({and: 'AND', or: 'OR', not: 'NOT', eq: '=', neq: '≠',
      lt: '<', lte: '≤', gt: '>', gte: '≥', is_null: 'IS NULL', not_null: 'IS NOT NULL',
      is_distinct_from: 'IS DISTINCT FROM'})}),
  ja: Object.freeze({values: '宣言された入力フィールド', input: '元の入力と出力の対応',
    filter: 'この条件を満たす行を残す', select: '出力するフィールド', rename: '出力フィールド名の変更',
    drop: '削除後の出力フィールド', join: '結合のキー', nullKey: 'NULLキー',
    no_match: '一致させない', fail: '失敗', redacted: '非開示',
    unprojected: '意味の説明は未提供', predicate: 'この述語形式の説明は未提供',
    conditional: '条件付き',
    operators: Object.freeze({and: 'かつ', or: 'または', not: '否定', eq: '=', neq: '≠',
      lt: '<', lte: '≤', gt: '>', gte: '≥', is_null: 'NULLである', not_null: 'NULLではない',
      is_distinct_from: 'NULLを区別して異なる'})}),
});
// Debit before quoting or copying a child into a parent. The final join only
// combines already-admitted pieces; it cannot first create an oversized text.
function storyConstructionBudget() {
  let remaining = explanationLimits.characters;
  const reserve = (size:number) => {
    if (!Number.isSafeInteger(size) || size < 0 || size > remaining) refuse('ExplorerExplanationLimit');
    remaining -= size;
  };
  function quoteSize(value:string) {
    let size = 2;
    if (value.length > remaining - size) refuse('ExplorerExplanationLimit');
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code === 34 || code === 92 || code === 8 || code === 9 ||
          code === 10 || code === 12 || code === 13) size += 2;
      else if (code < 32) size += 6;
      else if (code >= 0xd800 && code <= 0xdbff) {
        const next = value.charCodeAt(index + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {size += 2; index++;}
        else size += 6;
      } else size += code >= 0xdc00 && code <= 0xdfff ? 6 : 1;
      if (size > remaining) refuse('ExplorerExplanationLimit');
    }
    return size;
  }
  return {text() {
    const parts:string[] = [];
    return {
      append(value:string) {reserve(value.length); parts.push(value);},
      quote(value:string) {reserve(quoteSize(value)); parts.push(JSON.stringify(value));},
      finish() {return parts.join('');},
    };
  }};
}
function appendType(output:ReturnType<ReturnType<typeof storyConstructionBudget>['text']>, type:FieldType) {
  output.append(type.kind);
  if (type.nullable) output.append('?');
}
function predicateStory(predicate:Predicate, text:typeof explanationText[keyof typeof explanationText], budget:ReturnType<typeof storyConstructionBudget>):string {
  if (predicate.state === 'not_projected') return text.predicate;
  const nodes = predicate.nodes;
  const states = new Uint8Array(nodes.length), rendered:string[] = new Array(nodes.length);
  function render(index:number, depth:number):string {
    if (!Number.isSafeInteger(index) || index < 0 || index >= nodes.length ||
        states[index] === 1) refuse('ExplorerInvalidExplanation');
    if (depth > explanationLimits.depth) refuse('ExplorerExplanationLimit');
    if (states[index] === 2) return rendered[index];
    states[index] = 1;
    const node = nodes[index], output = budget.text();
    if (node.form === 'literal_redacted') {
      output.append('['); output.append(text.redacted); output.append(' ');
      appendType(output, node.type); output.append(']');
    } else if (node.form === 'field') {
      output.append(node.scope); output.append('.'); output.quote(node.name); output.append(':');
      appendType(output, node.type);
    } else if (node.form === 'parameter') {
      output.append('$'); output.append(node.name); output.append(':'); appendType(output, node.type);
    } else {
      const children = node.children, operator = text.operators[node.operator];
      if (['not', 'is_null', 'not_null'].includes(node.operator)) {
        if (children.length !== 1) refuse('ExplorerInvalidExplanation');
        if (node.operator === 'not') {output.append(operator); output.append(' ');}
        output.append('('); output.append(render(children[0], depth + 1)); output.append(')');
        if (node.operator !== 'not') {output.append(' '); output.append(operator);}
      } else if (node.operator === 'and' || node.operator === 'or') {
        if (children.length < 2) refuse('ExplorerInvalidExplanation');
        for (let i = 0; i < children.length; i++) {
          if (i > 0) {output.append(' '); output.append(operator); output.append(' ');}
          output.append('('); output.append(render(children[i], depth + 1)); output.append(')');
        }
      } else {
        if (children.length !== 2) refuse('ExplorerInvalidExplanation');
        output.append('('); output.append(render(children[0], depth + 1)); output.append(' ');
        output.append(operator); output.append(' '); output.append(render(children[1], depth + 1)); output.append(')');
      }
    }
    rendered[index] = output.finish();
    states[index] = 2;
    return rendered[index];
  }
  const result = render(predicate.root, 0);
  // The supplied projection cannot hide an unrelated node outside its root.
  if (states.some(state => state !== 2)) refuse('ExplorerInvalidExplanation');
  return result;
}
function meaningStory(meaning:Meaning, text:typeof explanationText[keyof typeof explanationText], budget:ReturnType<typeof storyConstructionBudget>):string {
  const output = budget.text();
  switch (meaning.kind) {
    case 'input_output': output.append(text.input); break;
    case 'values':
      output.append(text.values); output.append(': ');
      for (let i = 0; i < meaning.schema.fields.length; i++) {
        const field = meaning.schema.fields[i];
        if (i > 0) output.append(', ');
        output.quote(field.name); output.append(':'); appendType(output, field.type);
        if (field.presence === 'conditional') {
          output.append(' ('); output.append(text.conditional); output.append(')');
        }
      }
      break;
    case 'filter':
      output.append(text.filter); output.append(': ');
      output.append(predicateStory(meaning.predicate, text, budget)); break;
    case 'projection':
      output.append(text[meaning.operation]); output.append(': ');
      for (let i = 0; i < meaning.fields.length; i++) {
        if (i > 0) output.append(', ');
        output.quote(meaning.fields[i].output); output.append(' ← '); output.quote(meaning.fields[i].input);
      }
      break;
    case 'join':
      output.append(meaning.join_kind); output.append(' '); output.append(text.join); output.append(': ');
      for (let i = 0; i < meaning.keys.length; i++) {
        if (i > 0) output.append(', ');
        output.append('left.'); output.quote(meaning.keys[i].left);
        output.append(' = right.'); output.quote(meaning.keys[i].right);
      }
      output.append('; '); output.append(text.nullKey); output.append(': '); output.append(text[meaning.null_key]);
      break;
    case 'not_projected': output.append(text.unprojected); break;
    default: refuse('ExplorerInvalidExplanation');
  }
  return output.finish();
}
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
export function explanationStoryModel(view:StaticPlan, facts:WireExplanationFacts, {locale = 'en'}:LocaleOptions = {}):Public.ExplanationStoryModel {
  const story = planStoryModel(view, {locale});
  if (!Array.isArray(facts?.steps) || facts.steps.length > graphViewLimits.steps) refuse('ExplorerExplanationLimit');
  let nodes = 0, edges = 0, fields = 0;
  for (const step of facts.steps) {
    const meaning = step?.meaning;
    if (meaning?.kind === 'filter' && meaning.predicate?.state === 'projected') {
      if (!Array.isArray(meaning.predicate.nodes) ||
          (nodes += meaning.predicate.nodes.length) > explanationLimits.nodes) refuse('ExplorerExplanationLimit');
      for (const node of meaning.predicate.nodes) {
        if (node?.form === 'operation' && (!Array.isArray(node.children) ||
            (edges += node.children.length) > explanationLimits.nodes)) refuse('ExplorerExplanationLimit');
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
  const text = explanationText[locale], budget = storyConstructionBudget();
  return freeze<Public.ExplanationStoryModel>({...story, factsCid: facts.self_cid, parameterValuesCid: facts.parameter_values_cid,
    occurrences: story.occurrences.map((occurrence, index) => {
      const fact = facts.steps[index];
      if (fact.step_id !== occurrence.stepId || fact.operator !== occurrence.operator ||
          !sameKey(fact.key, occurrence.key) || !sameIds(fact.input_ports, occurrence.ports, 'input') ||
          !sameIds(fact.output_ports, occurrence.ports, 'output')) refuse('ExplorerInvalidExplanation');
      const rendered = meaningStory(fact.meaning, text, budget);
      return {...occurrence, explanation: {state: fact.meaning.kind === 'not_projected' ? 'not_projected' : 'projected',
        meaning: structuredClone(fact.meaning), text: rendered}};
    })});
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
export async function readExistingRunPresentation(client:Parameters<typeof Public.readExistingRunPresentation>[0], ref:Parameters<typeof Public.readExistingRunPresentation>[1], options:Parameters<typeof Public.readExistingRunPresentation>[2], ticket:Parameters<typeof Public.readExistingRunPresentation>[3]):ReturnType<typeof Public.readExistingRunPresentation> {
  const locale = options?.locale ?? 'en';
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
  const story = explanationStoryModel(view.plan_view, explanation.explanation.facts, {locale});
  const plan = planReadModel(view.plan_view);
  ticket.assertCurrent();
  return freeze({runRef: original, plan, explanation: {state: 'projected', story}});
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
export async function describeExistingResult(client:Parameters<typeof Public.describeExistingResult>[0], ref:Parameters<typeof Public.describeExistingResult>[1], name:Parameters<typeof Public.describeExistingResult>[2], ticket:Parameters<typeof Public.describeExistingResult>[3]):ReturnType<typeof Public.describeExistingResult> {
  const original = Object.freeze({...ref});
  const run = await currentRead(ticket, () => client.attach(original));
  return currentRead(ticket, () => run.result(name).describe());
}
