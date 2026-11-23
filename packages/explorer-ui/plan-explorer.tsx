export {CheckpointPanel} from './checkpoint-panel.js';
export {CancellationPanel} from './cancellation-panel.js';
export {RunInspector} from './run-inspector.js';
import {useEffect, useMemo, useRef, useState} from 'react';
import {ReactFlow, Controls, Handle, Position, BaseEdge, getBezierPath, type EdgeProps, type NodeProps, type Node, type Edge} from '@xyflow/react';
import {Button} from '@base-ui/react/button';
import {Workflow, List, CircleHelp} from 'lucide-react';
import type {PlanReadModel} from './read-model.js';
import {flowPresentation} from './flow-model.mjs';
import {layoutInput, requestFlowLayout, flowNodeWidth, flowNodeHeight, flowPortOffsets} from './flow-layout.mjs';
import './styles.css';

type Logical = PlanReadModel['nodes'][number];
type NodePresentation = {kind?: string; title?: string; inputs?: string; sourceInput?: boolean; state?: string};
type LogicalNode = Node<{original: Logical; presentation?: NodePresentation; unlinkedInput?: boolean}, 'logical'>;
function LogicalCard({data, selected}: NodeProps<LogicalNode>) {
  const original = data.original;
  const operation = original.operator?.replaceAll('_', ' ') ?? 'Input / output';
  const title = data.presentation?.title ?? (data.presentation ? operation.replace(/^./u, char=>char.toUpperCase()) :
    original.names.join(', ') || operation);
  const offsets = flowPortOffsets(original.ports);
  return <div className="actql-explorer-node" data-selected={selected} data-unlinked-input={data.unlinkedInput}
    style={{width: flowNodeWidth, height: flowNodeHeight(original.ports.length)}}>
    <div className="actql-explorer-kind">{data.presentation?.kind ?? operation}</div>
    <strong title={title}>{title}</strong>
    {data.presentation?.inputs && <span className="actql-explorer-node-inputs"
      title={data.presentation.inputs}>{data.presentation.inputs}</span>}
    {data.unlinkedInput && <span className="actql-explorer-node-inputs">Downstream link not projected</span>}
    <p>{data.presentation?.state ?? original.kind}</p>
    {original.ports.map((port, index) => <Handle key={port.port_id} id={port.port_id}
      type={port.role === 'input' ? 'target' : 'source'}
      position={port.role === 'input' ? Position.Top : Position.Bottom}
      isConnectable={false} style={{left: offsets[index]}}
      aria-label={`${port.role} ${port.port_ordinal}: ${port.carrier}`}/>)}
  </div>;
}
const nodeTypes = {logical: LogicalCard};
function OriginalEdge({id, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, label}: EdgeProps) {
  const [path] = getBezierPath({sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition});
  return <><BaseEdge id={id} path={path}/><text x={targetX} y={targetY - 9}
    textAnchor="middle" className="actql-explorer-edge-label">{label}</text></>;
}
// Keep parallel Join input labels at their original target ports, rather than
// overlapping at the midpoint shared by two edges from one producer.
const edgeTypes = {default: OriginalEdge};
export type PlanExplorerProps = {model: PlanReadModel; scopeKey: string; initialView?: 'list' | 'flow';
  workspace?: {stepId?: string; select(id: string): void;
    label(id: string): NodePresentation}};

function groupUnlinkedInputs(nodes: LogicalNode[], edges: Edge[]) {
  const linked = new Set(edges.flatMap(edge=>[edge.source, edge.target]));
  const inputs = nodes.filter(node=>node.data.presentation?.sourceInput && !linked.has(node.id));
  if (!inputs.length || inputs.length === nodes.length) return nodes;
  const inputIds = new Set(inputs.map(node=>node.id));
  const computation = nodes.filter(node=>!inputIds.has(node.id));
  const top = Math.min(...computation.map(node=>node.position.y));
  const leading = computation.filter(node=>node.position.y - top < 300);
  const middle = (Math.min(...leading.map(node=>node.position.x)) +
    Math.max(...leading.map(node=>node.position.x)) + flowNodeWidth) / 2;
  const rowHeight = Math.max(...inputs.map(node=>flowNodeHeight(node.data.original.ports.length))) + 26;
  const columnWidth = flowNodeWidth + 26;
  const positions = new Map(inputs.map(({id}, index)=>{
    const row = Math.floor(index / 3);
    const rowCount = Math.min(3, inputs.length - row * 3);
    return [id, {x: middle - ((rowCount - 1) * columnWidth + flowNodeWidth) / 2 +
      index % 3 * columnWidth, y: row * rowHeight}] as const;
  }));
  const computationTop = Math.ceil(inputs.length / 3) * rowHeight + 6;
  // Only move whole isolated input cards. Shift everything else by one
  // uniform offset so every original Plan edge remains unchanged.
  return nodes.map(node=>{
    const position = positions.get(node.id);
    return position ? {...node, position, data: {...node.data, unlinkedInput: true}} :
      {...node, position: {...node.position, y: node.position.y - top + computationTop}};
  });
}

function initialViewportNodes(placed: LogicalNode[], focus: LogicalNode | undefined, canvasWidth: number) {
  if (!focus) return [];
  const top = Math.min(...placed.map(node=>node.position.y));
  // Fit the opening rows around the selected original. Keep a readable
  // minimum scale even when the whole graph is much larger than the canvas.
  if (focus.position.y - top >= 320 || canvasWidth < flowNodeWidth * 2) return [focus];
  const opening = placed.filter(node=>node.position.y - top < 320);
  const width = Math.max(...opening.map(node=>node.position.x)) -
    Math.min(...opening.map(node=>node.position.x)) + flowNodeWidth;
  if (width * 0.9 <= canvasWidth * 0.87) return opening;
  const reach = (canvasWidth * 0.87 / 0.9 - flowNodeWidth) / 2;
  return opening.filter(node=>Math.abs(node.position.x - focus.position.x) <= reach);
}

// Scope changes remount selection and the renderer. This component accepts an
// already admitted original model and has no Client, transport or control API.
export function PlanExplorer({model, scopeKey, initialView = 'list', workspace}: PlanExplorerProps) {
  return <BoundPlanExplorer key={`${scopeKey}:${model.compiledPlanCid}:${model.logicalMapCid}`}
    model={model} initialView={initialView} workspace={workspace}/>;
}
function BoundPlanExplorer({model, initialView, workspace}: Omit<PlanExplorerProps, 'scopeKey'>) {
  const flow = useMemo(() => flowPresentation(model) as {nodes: LogicalNode[]; edges: Edge[]}, [model]);
  const [selected, select] = useState<string | undefined>();
  const [view, show] = useState<'flow' | 'list'>(initialView ?? 'list');
  const mode = workspace ? 'flow' : view;
  const canvas = useRef<HTMLDivElement>(null);
  const [canvasWidth, setCanvasWidth] = useState(0);
  // This bounded presentation key excludes labels/observations. Repeated reads
  // of the same topology do not restart ELK or reset the user's viewport.
  const layoutKey = useMemo(() => JSON.stringify(layoutInput(flow)), [flow]);
  const [layout, setLayout] = useState<{key: string; state: 'ready'; positions: readonly {id: string; x: number; y: number}[]}
    | {key: string; state: 'unavailable'}>();
  useEffect(() => {
    if (mode !== 'flow') return;
    const controller = new AbortController(); let active = true;
    requestFlowLayout(flow, {signal: controller.signal}).then(positions => {
      if (active) setLayout({key: layoutKey, state: 'ready', positions});
    }, () => {
      if (active) setLayout({key: layoutKey, state: 'unavailable'});
    });
    return () => { active = false; controller.abort(); };
    // layoutKey is the complete bounded Worker input. Metadata changes retain
    // the same coordinates; current labels still come from the original model.
  }, [mode, layoutKey]);
  const currentLayout = layout?.key === layoutKey ? layout : undefined;
  useEffect(() => {
    const panel = canvas.current;
    if (!panel || mode !== 'flow') return;
    setCanvasWidth(panel.clientWidth);
    const resize = new ResizeObserver(()=>setCanvasWidth(panel.clientWidth));
    resize.observe(panel);
    return ()=>resize.disconnect();
  }, [mode, currentLayout]);
  const selection = workspace?.stepId ?? selected;
  const selectOriginal = workspace ? workspace.select : select;
  const placed = useMemo(() => {
    if (currentLayout?.state !== 'ready') return [];
    return groupUnlinkedInputs(flow.nodes.map((node, index) => ({
      ...node, position: {x: currentLayout.positions[index].x, y: currentLayout.positions[index].y},
      selected: node.id === selection,
      data: {...node.data, presentation: workspace?.label(node.id)},
      width: flowNodeWidth, height: flowNodeHeight(node.data.original.ports.length),
    })), flow.edges);
  }, [currentLayout, flow, selection, workspace]);
  const original = model.nodes.find(node => node.id === selection);
  const focus = placed.find(node=>node.id === selection) ?? placed[0];
  const fitNodes = workspace ? initialViewportNodes(placed, focus, canvasWidth) : focus ? [focus] : [];
  const originalMetadata = <>
    <dl className="actql-explorer-identities"><dt>Compiled Plan</dt><dd>{model.compiledPlanCid}</dd>
      <dt>Logical Map</dt><dd>{model.logicalMapCid}</dd></dl>
    <p className="actql-explorer-unavailable"><CircleHelp aria-hidden/>Source origins unavailable in this projection.
      Controls, Samples and physical observations are unavailable in this viewer.</p>
    {model.effectful && <section aria-label="Declared Effects">
      <h3>Declared Effects · unit {model.effectful.unitId}</h3>
      <p>The graph shows the computation component. Effect declarations do not define physical execution edges.</p>
      <dl className="actql-explorer-identities"><dt>Check Environment</dt><dd>{model.effectful.checkEnvironmentCid}</dd>
        <dt>Parameters</dt><dd>{model.effectful.parameterValuesCid}</dd></dl>
      <table className="actql-explorer-table"><caption>Original checked declarations</caption>
        <thead><tr><th scope="col">Occurrence</th><th scope="col">Contract</th>
          <th scope="col">Declared input</th><th scope="col">Contract minimum</th></tr></thead>
        <tbody>{model.effectful.members.map(entry => <tr key={entry.member_ordinal}>
          <td>Stage {entry.stage_ordinal} · {entry.effect_id} · {entry.effect_kind}</td>
          <td>{entry.contract.reference} · {entry.contract.contract_cid}<br/>
            {entry.contract.kind === 'mapping' ? `Declared target: ${entry.contract.declared_target}`
              : `Command Resource kind: ${entry.contract.resource_kind}`}</td>
          <td>{entry.input.kind === 'result' ? `Result: ${entry.input.result_name}`
            : entry.input.kind === 'table' ? `Table: ${entry.input.table_name}` : 'No row input'}</td>
          <td>{entry.minimum_approval.kind === 'contract_minimum'
            ? entry.minimum_approval.value : 'Not represented'}</td>
        </tr>)}</tbody>
      </table>
      <p>Contract minimum is not current permission. Required approval does not imply a human-only reviewer.
        Not represented does not mean none.</p>
      <p>Resolved targets: unknown. Changed values: unknown. Current permission: unknown.
        Gate: unknown. Approval: unknown. Sealed Preview: unavailable.</p>
    </section>}
  </>;
  return <section className="actql-explorer" data-workspace={!!workspace} aria-label="ActQL static Plan">
    <header className="actql-explorer-header">
      <div>{!workspace && <p className="actql-explorer-kind">STATIC PLAN · PROVIDER I/O 0</p>}
        <h2>{model.effectful ? 'Computation component' : 'Logical operations'}</h2>
        <p>{workspace && model.inputs.length > 0 ? 'Projected dependencies only · ' : 'Data dependencies · '}
          layout does not indicate execution order.</p></div>
      {!workspace && <nav aria-label="Plan presentation">
        <Button aria-pressed={mode === 'list'} onClick={() => show('list')}><List aria-hidden/>List</Button>
        <Button aria-pressed={mode === 'flow'} onClick={() => show('flow')}><Workflow aria-hidden/>Flow</Button>
      </nav>}
    </header>
    {mode === 'list' && originalMetadata}
    {mode === 'flow' ? currentLayout?.state === 'ready' ? <div ref={canvas} className="actql-explorer-flow">
      {placed.some(node=>node.data.unlinkedInput) && <span className="actql-explorer-input-group">Declared inputs</span>}
      {canvasWidth > 0 && <ReactFlow key={layoutKey} fitView nodes={placed} edges={flow.edges} nodeTypes={nodeTypes} edgeTypes={edgeTypes}
        fitViewOptions={{nodes: fitNodes, minZoom: 0.9, maxZoom: 1, padding: 0.12}}
        nodesDraggable={false} nodesConnectable={false} edgesReconnectable={false}
        connectOnClick={false} deleteKeyCode={null} zoomOnDoubleClick={false}
        onNodeClick={(_, node) => selectOriginal(node.id)}
        minZoom={0.2} maxZoom={2} aria-label="Original logical ports">
        <Controls position="top-right" showInteractive={false} aria-label="Graph zoom"/>
      </ReactFlow>}
    </div> : <p role="status" className="actql-explorer-unavailable">
      {currentLayout?.state === 'unavailable'
        ? workspace ? 'Graph layout unavailable. Use Steps to inspect the original occurrences.'
          : 'Flow layout unavailable. Use List to inspect the original occurrences.'
        : 'Placing original logical ports…'}</p> : <table className="actql-explorer-table"><caption>Original logical occurrences</caption>
      <thead><tr><th scope="col">Operation</th><th scope="col">Identity</th><th scope="col">Ports</th></tr></thead>
      <tbody>{model.nodes.map(node => <tr key={node.id}><td>
        <Button onClick={() => selectOriginal(node.id)} aria-pressed={selection === node.id}>
          {node.names.join(', ') || node.operator}</Button></td>
        <td>{node.id}</td><td>{node.ports.length}</td></tr>)}</tbody></table>}
    {!workspace && <aside aria-label="Selected original occurrence" aria-live="polite">
      {original ? <><h3>{original.names.join(', ') || original.id}</h3>
        <dl><dt>Step</dt><dd>{original.id}</dd><dt>Operator</dt><dd>{original.operator}</dd></dl>
        <ul>{original.ports.map(port => <li key={port.port_id}>
          {port.role} {port.port_ordinal} · {port.carrier} · {port.port_id}
          {port.source.kind === 'stage_input' ? ' · unresolved Stage input locator' : ''}
        </li>)}</ul></> : <p>Select an original occurrence to inspect its ports.</p>}
    </aside>}
    {mode === 'flow' && <details className="actql-explorer-flow-metadata">
      <summary>Original Plan metadata</summary>
      {originalMetadata}
    </details>}
  </section>;
}
