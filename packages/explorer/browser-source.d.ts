import type {CheckpointPageModel,ReviewObservation,ReviewReference} from '@actql/explorer-ui/checkpoint-review';
import type {OriginalCancellation, CancellationObservation} from '@actql/explorer-ui/cancellation';
import type {Client, RunReference, ResultDescription, CancellationReference} from '@actql/sdk';
import type {WireCancellationLookup, WireRunView, WireRunExplanationView} from '@actql/client-wire';
import type {RunObservationModel} from '@actql/explorer-ui/run-observation';
import type {PlanReadModel, StaticExplanationReadModel, OriginalRunPlanReadModel, OriginalRunPresentationReadModel} from '@actql/explorer-ui/read-model';
export type ExplorerCapabilities = Readonly<{plan: boolean; run: true;
  resultMetadata: true; resultPayload: false; control: false; sample: false; cancellation: boolean;checkpointList:boolean;checkpointReview:boolean}>;
export function createExplorerBrowserSource(options: Readonly<{
  origin: string; fetch?: typeof fetch; now?: () => number;
}>): Readonly<{
  connect(bootstrap: string): Promise<ExplorerCapabilities>;
  launchView(): Promise<Readonly<{kind: 'program'; plan: PlanReadModel}> |
    Readonly<{kind: 'run'; originalPlan: OriginalRunPlanReadModel}> | null>;
  plan(input: Parameters<Client['plan']>[0], options?: Parameters<Client['plan']>[1]): Promise<PlanReadModel>;
  staticExplanation(input: Parameters<Client['explain']>[0], options?: Parameters<Client['explain']>[1],
    locale?: 'en' | 'ja'): Promise<StaticExplanationReadModel>;
  inspect(ref: RunReference): Promise<WireRunView>;
  observe(ref: RunReference): Promise<RunObservationModel>;
  runPlan(ref: RunReference): Promise<OriginalRunPlanReadModel>;
  explain(ref: RunReference): Promise<WireRunExplanationView>;
  runPresentation(ref: RunReference, options?: {locale?: 'en' | 'ja'}): Promise<OriginalRunPresentationReadModel>;
  describe(ref: RunReference, name: string): Promise<ResultDescription>;
  cancel(original: OriginalCancellation): Promise<CancellationObservation>;
  lookupCancellation(ref: CancellationReference): Promise<WireCancellationLookup>;
  checkpoints():Promise<CheckpointPageModel>;
  reviewCheckpoint(checkpoint:ReviewReference):Promise<ReviewObservation>;
  close(): void;
}>;
