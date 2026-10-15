import type {Client, RunReference, ResultDescription} from '@actql/sdk';
import type {WireRunView} from '@actql/client-wire';
import type {PlanReadModel, OriginalRunPlanReadModel} from '@actql/explorer-ui/read-model';
export type ExplorerCapabilities = Readonly<{plan: boolean; run: true;
  resultMetadata: true; resultPayload: false; control: false; sample: false}>;
export function createExplorerBrowserSource(options: Readonly<{
  origin: string; fetch?: typeof fetch; now?: () => number;
}>): Readonly<{
  connect(bootstrap: string): Promise<ExplorerCapabilities>;
  launchView(): Promise<Readonly<{kind: 'program'; plan: PlanReadModel}> |
    Readonly<{kind: 'run'; originalPlan: OriginalRunPlanReadModel}> | null>;
  plan(input: Parameters<Client['plan']>[0], options?: Parameters<Client['plan']>[1]): Promise<PlanReadModel>;
  inspect(ref: RunReference): Promise<WireRunView>;
  runPlan(ref: RunReference): Promise<OriginalRunPlanReadModel>;
  describe(ref: RunReference, name: string): Promise<ResultDescription>;
  close(): void;
}>;
