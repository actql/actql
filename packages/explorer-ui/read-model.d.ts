import type {WireExplanationNarrative} from '@actql/client-wire';
import type {Client, RunReference, ResultDescription} from '@actql/sdk';
import type {WireEffectfulStaticPlanView, WirePlanView, WireRunView, WireExplanationFacts, WireRunExplanationView,
  WireExplanationContext, WireStaticExplanationView, WireRunExplanationContextView} from '@actql/client-wire';

export class ExplorerReadError extends Error { readonly code: string }
export const graphViewLimits: Readonly<{steps: 256; ports: 1024}>;
type Step = WirePlanView['logical_map']['steps'][number];
export type PlanReadModel = Readonly<{
  compiledPlanCid: string; logicalMapCid: string; programDefinitionCid: string;
  observation: 'static'; providerIO: 0;
  effectful?: Readonly<{scope: 'computation_component'; parameterValuesCid: string;
    checkEnvironmentCid: string; unitId: string;
    members: WireEffectfulStaticPlanView['effect_set']['members'];
    observations: WireEffectfulStaticPlanView['observations']}>;
  nodes: readonly Readonly<{id: string; key: Step['key'];
    names: readonly string[]; operator: Step['operator'];
    kind: Step['key']['occurrence']['kind']; ports: Step['ports']}>[];
  edges: readonly Readonly<{id: string; sourceStepId: string;
    sourcePortId: string; targetStepId: string; targetPortId: string;
    targetPortOrdinal: number}>[];
  inputs: readonly Readonly<{stepId: string; inputPortId: string;
    locator: Extract<Step['ports'][number]['source'], {kind: 'stage_input'}>}>[];
  sourceOrigins: Readonly<{state: 'unavailable'; reason: 'not_in_projection'}>;
}>;
export function planReadModel(view: WirePlanView | WireEffectfulStaticPlanView): PlanReadModel;
export type PlanStoryModel = Readonly<{
  locale: 'en' | 'ja'; compiledPlanCid: string; logicalMapCid: string;
  programDefinitionCid: string; observation: 'static';
  scope: 'compiled_plan' | 'computation_component';
  ordering: Readonly<{kind: 'logical_dependencies'; text: string}>;
  occurrences: readonly Readonly<{stepId: string; key: Step['key'];
    names: readonly string[]; title: string; operator: Step['operator'];
    kind: Step['key']['occurrence']['kind']; text: string; ports: Step['ports']}>[];
  stageInputs: readonly (PlanReadModel['inputs'][number] & Readonly<{text: string}>)[];
  dependencies: PlanReadModel['edges']; quantities: WirePlanView['quantities'];
  capabilities: WirePlanView['capabilities']; sourceOrigins: PlanReadModel['sourceOrigins'];
  declaredEffects?: PlanReadModel['effectful'];
}>;
export function planStoryModel(view: WirePlanView | WireEffectfulStaticPlanView,
  options?: {locale?: 'en' | 'ja'}): PlanStoryModel;
export type ExplanationStoryModel = Omit<PlanStoryModel, 'occurrences'> & Readonly<{
  factsCid: string; parameterValuesCid: string;
  narrative: Pick<WireExplanationNarrative, 'version' | 'summary' | 'clauses' | 'items'>;
  occurrences: readonly (PlanStoryModel['occurrences'][number] & Readonly<{
    explanation: Readonly<{state: 'projected' | 'not_projected'; text: string;
      meaning: WireExplanationFacts['steps'][number]['meaning']}>;
  }>)[];
}>;
type FactsPresentation = Readonly<{locale?: 'en' | 'ja';
  render(facts: WireExplanationFacts, locale: 'en' | 'ja'): WireExplanationNarrative}>;
export function explanationStoryModel(view: WirePlanView | WireEffectfulStaticPlanView,
  facts: WireExplanationFacts, presentation: FactsPresentation): ExplanationStoryModel;
export type StaticExplanationReadModel = Readonly<{plan: PlanReadModel; story: ExplanationStoryModel;
  context: readonly Readonly<{origin: WireExplanationContext['items'][number]; text: string}>[]}>;
type StaticExplanationPresentation = Readonly<{locale?: 'en' | 'ja';
  render(view: WireStaticExplanationView, locale: 'en' | 'ja'):
    WireExplanationNarrative}>;
export function staticExplanationReadModel(view: WireStaticExplanationView,
  presentation: StaticExplanationPresentation): StaticExplanationReadModel;
export type ReadTicket = Readonly<{assertCurrent(): void}>;
export function createReadEpoch(): Readonly<{invalidate(): void; capture(): ReadTicket}>;
export function readStaticPlan(client: Pick<Client, 'plan'>,
  input: Parameters<Client['plan']>[0], options: Parameters<Client['plan']>[1],
  ticket: ReadTicket): Promise<PlanReadModel>;
export function readStaticExplanation(client: Pick<Client, 'explain'>,
  input: Parameters<Client['explain']>[0], options: Parameters<Client['explain']>[1],
  presentation: StaticExplanationPresentation, ticket: ReadTicket): Promise<StaticExplanationReadModel>;
export function readExistingRun(client: Pick<Client, 'attach'>,
  ref: RunReference, ticket: ReadTicket): Promise<WireRunView>;
export type OriginalRunPlanReadModel = Readonly<{
  runRef: RunReference; plan: PlanReadModel;
}>;
export function readExistingRunPlan(client: Pick<Client, 'attach'>,
  ref: RunReference, ticket: ReadTicket): Promise<OriginalRunPlanReadModel>;
export function readExistingRunExplanation(client: Pick<Client, 'attach'>,
  ref: RunReference, ticket: ReadTicket): Promise<WireRunExplanationView>;
export type OriginalRunPresentationReadModel = Readonly<{
  runRef: RunReference; plan: PlanReadModel;
  explanation: Readonly<{state: 'projected'; story: ExplanationStoryModel}>;
}> | Readonly<{runRef: RunReference; plan: null;
  explanation: Extract<WireRunExplanationView['explanation'], {state: 'not_projected'}>}>;
export function readExistingRunPresentation(client: Pick<Client, 'attach'>,
  ref: RunReference, presentation: FactsPresentation,
  ticket: ReadTicket): Promise<OriginalRunPresentationReadModel>;
export type SavedExplanationReadModel = Readonly<{
  runRef: RunReference; plan: PlanReadModel;
  explanation: Readonly<{state: 'projected'}> & Pick<StaticExplanationReadModel, 'story' | 'context'>;
}> | Readonly<{runRef: RunReference; plan: null;
  explanation: Extract<WireRunExplanationContextView['explanation'], {state: 'not_projected'}>}>;
export function readExistingRunContext(client: Pick<Client, 'attach'>,
  ref: RunReference, presentation: StaticExplanationPresentation,
  ticket: ReadTicket): Promise<SavedExplanationReadModel>;
export type OriginalRunStoryReadModel = Readonly<{
  runRef: RunReference; story: PlanStoryModel;
}>;
export function readExistingRunStory(client: Pick<Client, 'attach'>,
  ref: RunReference, options: {locale?: 'en' | 'ja'} | undefined,
  ticket: ReadTicket): Promise<OriginalRunStoryReadModel>;
export function describeExistingResult(client: Pick<Client, 'attach'>,
  ref: RunReference, name: string, ticket: ReadTicket): Promise<ResultDescription>;
