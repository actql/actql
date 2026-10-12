import type {Client, RunReference, ResultDescription} from '@actql/sdk';
import type {WirePlanView, WireRunView} from '@actql/client-wire';

export class ExplorerReadError extends Error { readonly code: string }
export const graphViewLimits: Readonly<{steps: 256; ports: 1024}>;
type Step = WirePlanView['logical_map']['steps'][number];
export type PlanReadModel = Readonly<{
  compiledPlanCid: string; logicalMapCid: string; programDefinitionCid: string;
  observation: 'static'; providerIO: 0;
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
export function planReadModel(view: WirePlanView): PlanReadModel;
export type ReadTicket = Readonly<{assertCurrent(): void}>;
export function createReadEpoch(): Readonly<{invalidate(): void; capture(): ReadTicket}>;
export function readStaticPlan(client: Pick<Client, 'plan'>,
  input: Parameters<Client['plan']>[0], options: Parameters<Client['plan']>[1],
  ticket: ReadTicket): Promise<PlanReadModel>;
export function readExistingRun(client: Pick<Client, 'attach'>,
  ref: RunReference, ticket: ReadTicket): Promise<WireRunView>;
export function describeExistingResult(client: Pick<Client, 'attach'>,
  ref: RunReference, name: string, ticket: ReadTicket): Promise<ResultDescription>;
