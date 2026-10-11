import type {PlanReadModel} from './read-model.js';
import type {Node, Edge} from '@xyflow/react';
export function flowPresentation(model: PlanReadModel): {nodes: Node[]; edges: Edge[]};
