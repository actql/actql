import type {ReactElement} from 'react';
import type {CancellationPanelProps} from './cancellation-types.js';
import type {CheckpointPanelProps} from './checkpoint-review.js';
import type {PlanReadModel} from './read-model.js';
import type {RunObservationModel} from './run-observation.js';

export type {OriginalCancellation, CancellationObservation, CancellationPanelProps} from './cancellation-types.js';

export function CancellationPanel(props: CancellationPanelProps): ReactElement;
export function CheckpointPanel(props: CheckpointPanelProps): ReactElement;
export function RunInspector(props: {model: RunObservationModel}): ReactElement;

export type PlanExplorerProps = {model: PlanReadModel; scopeKey: string; initialView?: 'list' | 'flow';
  workspace?: {stepId?: string; select(id: string): void;
    label(id: string): {kind?: string; title?: string; inputs?: string; sourceInput?: boolean; state?: string}}};
export function PlanExplorer(props: PlanExplorerProps): ReactElement;
