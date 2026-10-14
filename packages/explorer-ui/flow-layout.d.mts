import type {Node, Edge} from '@xyflow/react';
export const flowLayoutDeadlineMs: number;
export const flowNodeWidth: number;
export function flowNodeHeight(ports: number): number;
export function requestFlowLayout(flow: {nodes: Node[]; edges: Edge[]},
  options?: {signal?: AbortSignal}): Promise<readonly {id: string; x: number; y: number}[]>;
