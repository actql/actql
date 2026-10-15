import {useEffect, useMemo, useState} from 'react';
import {ReactFlow, Handle, Position, BaseEdge, getBezierPath, type EdgeProps, type NodeProps, type Node, type Edge} from '@xyflow/react';
import {Button} from '@base-ui/react/button';
import {Workflow, List, CircleHelp} from 'lucide-react';
import type {PlanReadModel} from './read-model.js';
import {flowPresentation} from './flow-model.mjs';
import {layoutInput, requestFlowLayout, flowNodeWidth, flowNodeHeight} from './flow-layout.mjs';
import './styles.css';

type Logical = PlanReadModel['nodes'][number];
type LogicalNode = Node<{original: Logical}, 'logical'>;
function LogicalCard({data, selected}: NodeProps<LogicalNode>) {
  const original = data.original;
  return <div className="actql-explorer-node" data-selected={selected}
    style={{width: flowNodeWidth, height: flowNodeHeight(original.ports.length)}}>
    <div className="actql-explorer-kind">{original.operator}</div>
    <strong title={original.names.join(', ') || original.id}>{original.names.join(', ') || original.id}</strong>
    <p>{original.kind}</p>
    {original.ports.map((port, index) => <Handle key={port.port_id} id={port.port_id}
      type={port.role === 'input' ? 'target' : 'source'}
      position={port.role === 'input' ? Position.Left : Position.Right}
      isConnectable={false} style={{top: 28 + index * 18}}
      aria-label={`${port.role} ${port.port_ordinal}: ${port.carrier}`}/>)}
  </div>;
}
const nodeTypes = {logical: LogicalCard};
function OriginalEdge({id, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, label}: EdgeProps) {
  const [path] = getBezierPath({sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition});
  return <><BaseEdge id={id} path={path}/><text x={targetX - 12} y={targetY - 4}
    textAnchor="end" className="actql-explorer-edge-label">{label}</text></>;
}
// Keep parallel Join input labels at their original target ports, rather than
// overlapping at the midpoint shared by two edges from one producer.
const edgeTypes = {default: OriginalEdge};
export type PlanExplorerProps = {model: PlanReadModel; scopeKey: string};

// Scope changes remount selection and the renderer. This component accepts an
// already admitted original model and has no Client, transport or control API.
export function PlanExplorer({model, scopeKey}: PlanExplorerProps) {
  return <BoundPlanExplorer key={`${scopeKey}:${model.compiledPlanCid}:${model.logicalMapCid}`}
    model={model}/>;
}
function BoundPlanExplorer({model}: {model: PlanReadModel}) {
  const flow = useMemo(() => flowPresentation(model) as {nodes: LogicalNode[]; edges: Edge[]}, [model]);
  const [selected, select] = useState<string | undefined>();
  const [mode, show] = useState<'flow' | 'list'>('list');
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
  const placed = useMemo(() => currentLayout?.state === 'ready' ? flow.nodes.map((node, index) => ({
    ...node, position: {x: currentLayout.positions[index].x, y: currentLayout.positions[index].y},
    width: flowNodeWidth, height: flowNodeHeight(node.data.original.ports.length),
  })) : [], [currentLayout, flow]);
  const original = model.nodes.find(node => node.id === selected);
  return <section className="actql-explorer" aria-label="ActQL static Plan">
    <header className="actql-explorer-header">
      <div><p className="actql-explorer-kind">STATIC PLAN · PROVIDER I/O 0</p>
        <h2>Logical operations</h2>
        <p>Recorded ports. Layout does not indicate execution order.</p></div>
      <nav aria-label="Plan presentation">
        <Button aria-pressed={mode === 'list'} onClick={() => show('list')}><List aria-hidden/>List</Button>
        <Button aria-pressed={mode === 'flow'} onClick={() => show('flow')}><Workflow aria-hidden/>Flow</Button>
      </nav>
    </header>
    <dl className="actql-explorer-identities"><dt>Compiled Plan</dt><dd>{model.compiledPlanCid}</dd>
      <dt>Logical Map</dt><dd>{model.logicalMapCid}</dd></dl>
    <p className="actql-explorer-unavailable"><CircleHelp aria-hidden/>Source origins unavailable in this projection.
      Controls, Samples and physical observations are unavailable in this viewer.</p>
    {mode === 'flow' ? currentLayout?.state === 'ready' ? <div className="actql-explorer-flow">
      <ReactFlow key={layoutKey} fitView nodes={placed} edges={flow.edges} nodeTypes={nodeTypes} edgeTypes={edgeTypes}
        nodesDraggable={false} nodesConnectable={false} edgesReconnectable={false}
        connectOnClick={false} deleteKeyCode={null} zoomOnDoubleClick={false}
        onNodeClick={(_, node) => select(node.id)}
        minZoom={0.2} maxZoom={2} aria-label="Original logical ports"/>
    </div> : <p role="status" className="actql-explorer-unavailable">
      {currentLayout?.state === 'unavailable'
        ? 'Flow layout unavailable. Use List to inspect the original occurrences.'
        : 'Placing original logical ports…'}</p> : <table className="actql-explorer-table"><caption>Original logical occurrences</caption>
      <thead><tr><th scope="col">Operation</th><th scope="col">Identity</th><th scope="col">Ports</th></tr></thead>
      <tbody>{model.nodes.map(node => <tr key={node.id}><td>
        <Button onClick={() => select(node.id)} aria-pressed={selected === node.id}>
          {node.names.join(', ') || node.operator}</Button></td>
        <td>{node.id}</td><td>{node.ports.length}</td></tr>)}</tbody></table>}
    <aside aria-label="Selected original occurrence" aria-live="polite">
      {original ? <><h3>{original.names.join(', ') || original.id}</h3>
        <dl><dt>Step</dt><dd>{original.id}</dd><dt>Operator</dt><dd>{original.operator}</dd></dl>
        <ul>{original.ports.map(port => <li key={port.port_id}>
          {port.role} {port.port_ordinal} · {port.carrier} · {port.port_id}
          {port.source.kind === 'stage_input' ? ' · unresolved Stage input locator' : ''}
        </li>)}</ul></> : <p>Select an original occurrence to inspect its ports.</p>}
    </aside>
  </section>;
}
