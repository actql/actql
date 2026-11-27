import type {InternalNode, Node} from '@xyflow/react';

type ExplorerNode = Node<{label: string}, 'logical'>;
declare const internal: InternalNode<ExplorerNode>;
const base: InternalNode = internal;
const original: ExplorerNode = internal.internals.userNode;
const renderedLabel: string = internal.data.label;
const measuredWidth: number | undefined = internal.measured.width;
const logical: ExplorerNode = {id: 'step', position: {x: 0, y: 0}, data: {label: 'Read'}, type: 'logical'};
// @ts-expect-error An optional origin can be omitted; an explicitly undefined origin is still invalid.
const invalidOrigin: ExplorerNode = {...logical, origin: undefined};
// @ts-expect-error The internal node retains the original specialized data type.
const invalidData: number = internal.data.label;
void base; void original; void renderedLabel; void measuredWidth; void invalidOrigin; void invalidData;
