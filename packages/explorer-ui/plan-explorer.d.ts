import type {ReactElement} from 'react';
import type {CancellationPanelProps} from './cancellation-types.js';
import type {CheckpointPanelProps} from './checkpoint-review.js';
import type {PlanReadModel} from './read-model.js';
import type {RunObservationModel} from './run-observation.js';

export type {OriginalCancellation, CancellationObservation, CancellationPanelProps} from './cancellation-types.js';

export function CancellationPanel(props: CancellationPanelProps): ReactElement;
export function CheckpointPanel(props: CheckpointPanelProps): ReactElement;
export function RunInspector(props: {model: RunObservationModel}): ReactElement;

export type WorkspaceGraphGroup = Readonly<{
  id: string; members: readonly string[]; representative?: string;
  source?: Readonly<{stageOrdinal: number; inputOrdinal: number; inputs: readonly Readonly<{stepId: string; portId: string}>[]}>;
}>;
export type PlanExplorerProps = {model: PlanReadModel; scopeKey: string; initialView?: 'list' | 'flow';
  workspace?: {stepId?: string; select(id: string): void; groups?: readonly WorkspaceGraphGroup[]; locale?: 'en' | 'ja';
    label(id: string): {kind?: string; title?: string; inputs?: string; sourceInput?: boolean; state?: string;
      effectDeclaration?: Readonly<{fields?: string; missingProducer: string}>}}};
export function OriginalPlanMetadata(props: {model: PlanReadModel; workspace?: boolean; locale?: 'en' | 'ja'}): ReactElement;
export function PlanExplorer(props: PlanExplorerProps): ReactElement;
