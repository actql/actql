import type {Client, RunReference, ResultDescription} from '@actql/sdk';
import type {WireEffectfulStaticPlanView, WirePlanView, WireRunView, WireExplanationFacts} from '@actql/client-wire';

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
  occurrences: readonly (PlanStoryModel['occurrences'][number] & Readonly<{
    explanation: Readonly<{state: 'projected' | 'not_projected'; text: string;
      meaning: WireExplanationFacts['steps'][number]['meaning']}>;
  }>)[];
}>;
export function explanationStoryModel(view: WirePlanView | WireEffectfulStaticPlanView,
  facts: WireExplanationFacts, options?: {locale?: 'en' | 'ja'}): ExplanationStoryModel;
export type ReadTicket = Readonly<{assertCurrent(): void}>;
export function createReadEpoch(): Readonly<{invalidate(): void; capture(): ReadTicket}>;
export function readStaticPlan(client: Pick<Client, 'plan'>,
  input: Parameters<Client['plan']>[0], options: Parameters<Client['plan']>[1],
  ticket: ReadTicket): Promise<PlanReadModel>;
export function readExistingRun(client: Pick<Client, 'attach'>,
  ref: RunReference, ticket: ReadTicket): Promise<WireRunView>;
export type OriginalRunPlanReadModel = Readonly<{
  runRef: RunReference; plan: PlanReadModel;
}>;
export function readExistingRunPlan(client: Pick<Client, 'attach'>,
  ref: RunReference, ticket: ReadTicket): Promise<OriginalRunPlanReadModel>;
export type OriginalRunStoryReadModel = Readonly<{
  runRef: RunReference; story: PlanStoryModel;
}>;
export function readExistingRunStory(client: Pick<Client, 'attach'>,
  ref: RunReference, options: {locale?: 'en' | 'ja'} | undefined,
  ticket: ReadTicket): Promise<OriginalRunStoryReadModel>;
export function describeExistingResult(client: Pick<Client, 'attach'>,
  ref: RunReference, name: string, ticket: ReadTicket): Promise<ResultDescription>;
