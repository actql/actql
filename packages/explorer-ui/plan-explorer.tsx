export {CheckpointPanel} from './checkpoint-panel.js';
export {CancellationPanel} from './cancellation-panel.js';
export {RunInspector} from './run-inspector.js';
import {useEffect, useMemo, useRef, useState} from 'react';
import {ReactFlow, Controls, Handle, Position, BaseEdge, getBezierPath, type EdgeProps, type NodeProps, type Node, type Edge} from '@xyflow/react';
import {Button} from '@base-ui/react/button';
import {Workflow, List, CircleHelp} from 'lucide-react';
import type {PlanReadModel} from './read-model.js';
import {graphViewLimits} from './read-model.mjs';
import {flowPresentation} from './flow-model.mjs';
import {layoutInput, requestFlowLayout, flowNodeWidth, flowNodeHeight, flowPortOffsets} from './flow-layout.mjs';
import './styles.css';

type Logical = PlanReadModel['nodes'][number];
type NodePresentation = {
  kind?: string; title?: string; inputs?: string; sourceInput?: boolean; state?: string;
  effectDeclaration?: Readonly<{fields?: string; missingProducer: string}>;
};
type GraphPort = Pick<Logical['ports'][number], 'port_id' | 'role' | 'carrier' | 'port_ordinal'> & {declaredSource?: true};
type LogicalPresentation = Pick<Logical, 'names' | 'operator'> & {
  kind?: Logical['kind']; ports: readonly GraphPort[];
};
type LogicalNode = Node<{original: LogicalPresentation; presentation?: NodePresentation;
  unlinkedInput?: boolean; unlinkedEffect?: boolean}, 'logical'>;
function LogicalCard({data, selected}: NodeProps<LogicalNode>) {
  const original = data.original;
  const operation = original.operator?.replaceAll('_', ' ') ?? 'Input / output';
  const title = data.presentation?.title ?? (data.presentation ? operation.replace(/^./u, char=>char.toUpperCase()) :
    original.names.join(', ') || operation);
  const offsets = flowPortOffsets(original.ports);
  const effect = data.presentation?.effectDeclaration;
  return <div className="actql-explorer-node" data-selected={selected} data-unlinked-input={data.unlinkedInput}
    data-effect-declaration={!!effect}
    style={{width: flowNodeWidth, height: effect ? Math.max(112, flowNodeHeight(original.ports.length)) :
      flowNodeHeight(original.ports.length)}}>
    <div className="actql-explorer-kind">{data.presentation?.kind ?? operation}</div>
    <strong title={title}>{title}</strong>
    {data.presentation?.inputs && <span className="actql-explorer-node-inputs"
      title={data.presentation.inputs}>{data.presentation.inputs}</span>}
    {data.unlinkedInput && <span className="actql-explorer-node-inputs">Downstream link not projected</span>}
    {effect?.fields && <span className="actql-explorer-declared-fields" title={effect.fields}>{effect.fields}</span>}
    {data.unlinkedEffect && effect ?
      <span className="actql-explorer-declaration-note">{effect.missingProducer}</span> :
      <p>{data.presentation?.state ?? original.kind}</p>}
    {original.ports.map((port, index) => <Handle key={port.port_id} id={port.port_id}
      type={port.role === 'input' ? 'target' : 'source'}
      position={port.role === 'input' ? Position.Top : Position.Bottom}
      isConnectable={false} style={{left: offsets[index]}}
      aria-label={port.declaredSource ? `Declared Source: ${port.carrier}` : `${port.role} ${port.port_ordinal}: ${port.carrier}`}/>)}
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
export type WorkspaceGraphGroup = Readonly<{
  id: string; members: readonly string[]; representative?: string;
  source?: Readonly<{stageOrdinal: number; inputOrdinal: number; inputs: readonly Readonly<{stepId: string; portId: string}>[]}>;
}>;
export type PlanExplorerProps = {model: PlanReadModel; scopeKey: string; initialView?: 'list' | 'flow';
  workspace?: {stepId?: string; select(id: string): void; groups?: readonly WorkspaceGraphGroup[]; locale?: 'en' | 'ja';
    label(id: string): NodePresentation}};

function workspaceFlow(model: PlanReadModel, groups?: readonly WorkspaceGraphGroup[]):
  {nodes: LogicalNode[]; edges: Edge[]; unavailable?: true} {
  const flow = flowPresentation(model) as {nodes: LogicalNode[]; edges: Edge[]};
  if (!groups) return flow;
  if (groups.length > graphViewLimits.steps) return {nodes: [], edges: [], unavailable: true};
  const originals = new Map(flow.nodes.map(node => [node.id, node]));
  const owner = new Map<string, string>();
  const grouped = groups.map(group => {
    const members = group.members.map(id => {
      const node = originals.get(id);
      if (!node || owner.has(id)) throw new Error('Invalid original Story group');
      owner.set(id, group.id);
      return node.data.original;
    });
    return {id: group.id, type: 'logical' as const, position: {x: 0, y: 0},
      data: {original: {...(members[0] ?? {names: [], operator: null}),
        ports: members.flatMap(node => node.ports) as GraphPort[]}}, draggable: false, connectable: false, deletable: false};
  });
  if (owner.size !== originals.size) throw new Error('Unassigned original Step');
  const edges: Edge[] = [], crossed = new Set<string>();
  for (const edge of flow.edges) {
    const source = owner.get(edge.source)!, target = owner.get(edge.target)!;
    crossed.add(edge.targetHandle!);
    if (source !== target) edges.push({...edge, source, target, label: undefined});
  }
  const nodes = new Map(grouped.map(node => [node.id, node]));
  const inputs = new Map(model.inputs.map(input => [input.inputPortId, input]));
  for (const group of groups) {
    if (!group.source) continue;
    const {stageOrdinal, inputOrdinal} = group.source;
    for (const {stepId, portId} of group.source.inputs) {
      const input = inputs.get(portId), target = input && owner.get(input.stepId);
      const port = target && nodes.get(target)?.data.original.ports.find(port => port.port_id === portId);
      if (!input || input.stepId !== stepId || !target || !port || target === group.id || crossed.has(portId) ||
          input.locator.stage_ordinal !== stageOrdinal || input.locator.input_port_ordinal !== inputOrdinal) continue;
      // A visual Source handle for the checked stage input. Only the
      // consuming handle is an original logical port.
      const handle = 'source:' + portId;
      nodes.get(group.id)!.data.original.ports.push({...port, port_id: handle, role: 'output', declaredSource: true});
      edges.push({id: portId, source: group.id, target, sourceHandle: handle, targetHandle: portId,
        type: 'default', selectable: false, focusable: false, deletable: false});
      crossed.add(portId);
    }
  }
  const drawn = new Set(edges.flatMap(edge => [edge.sourceHandle!, edge.targetHandle!]));
  if (edges.length > graphViewLimits.ports || drawn.size > graphViewLimits.ports) {
    return {nodes: [], edges: [], unavailable: true};
  }
  const nodesWithEdges = grouped.map(node => ({...node, data: {original: {
    ...node.data.original, ports: node.data.original.ports.filter(port => drawn.has(port.port_id)),
  }}}));
  return {nodes: nodesWithEdges, edges};
}

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

function placeUnlinkedEffects(nodes: LogicalNode[], edges: Edge[]): LogicalNode[] {
  const linked = new Set(edges.flatMap(edge => [edge.source, edge.target]));
  const detached = nodes.filter(node => node.data.presentation?.effectDeclaration && !linked.has(node.id));
  if (!detached.length) return nodes;
  const declarations = new Map(detached.map((node, index) => [node.id, index]));
  const body = nodes.filter(node => !declarations.has(node.id));
  const bottom = body.length ? Math.max(...body.map(node => node.position.y + node.height!)) + 46 : 0;
  const left = body.length ? Math.min(...body.map(node => node.position.x)) : 0;
  // Presentation coordinates only. A declaration without a projected
  // producer has no edge and does not take part in the data-flow ordering.
  return nodes.map(node => {
    const row = declarations.get(node.id);
    return row === undefined ? node : {...node, position: {x: left, y: bottom + row * 138},
      data: {...node.data, unlinkedEffect: true}};
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

function narrowWorkspaceViewport(placed: LogicalNode[], focus: LogicalNode, edges: Edge[], width: number) {
  const byId = new Map(placed.map(node => [node.id, node]));
  const connected = edges.find(edge => edge.source === focus.id) ??
    edges.find(edge => edge.target === focus.id);
  const source = connected && byId.get(connected.source);
  const target = connected && byId.get(connected.target);
  const first = source ?? focus;
  const second = target ?? first;
  const left = Math.min(first.position.x, second.position.x);
  const top = Math.min(first.position.y, second.position.y);
  const span = Math.abs(first.position.x - second.position.x) + flowNodeWidth;
  // Start near the top of the canvas so an original input and its real
  // connection are visible before scrolling. Keep manual pan and zoom.
  const zoom = Math.min(0.95, Math.max(0.76, (width - 28) / span));
  return {x: (width - Math.min(span * zoom, width - 28)) / 2 - left * zoom,
    y: 28 - top * zoom, zoom};
}

// Scope changes remount selection and the renderer. This component accepts an
// already admitted original model and has no Client, transport or control API.
export function PlanExplorer({model, scopeKey, initialView = 'list', workspace}: PlanExplorerProps) {
  return <BoundPlanExplorer key={`${scopeKey}:${model.compiledPlanCid}:${model.logicalMapCid}`}
    model={model} initialView={initialView} workspace={workspace}/>;
}
export function OriginalPlanMetadata({model, workspace = false, locale = 'en'}: {
  model: PlanReadModel; workspace?: boolean; locale?: 'en' | 'ja';
}) {
  const ja = locale === 'ja';
  return <>
    <dl className="actql-explorer-identities"><dt>{ja ? 'コンパイル済みプラン' : 'Compiled Plan'}</dt><dd>{model.compiledPlanCid}</dd>
      <dt>{ja ? '論理マップ' : 'Logical Map'}</dt><dd>{model.logicalMapCid}</dd></dl>
    {!workspace && <p className="actql-explorer-unavailable"><CircleHelp aria-hidden/>Source origins unavailable in this projection.
      Controls, Samples and physical observations are unavailable in this viewer.</p>}
    {model.effectful && <section aria-label="Declared Effects">
      <h3>{ja ? '宣言された Effect' : 'Declared Effects'} · <code>{model.effectful.unitId}</code></h3>
      {!workspace && <p>The graph shows the computation component. Effect declarations do not define physical execution edges.</p>}
      <dl className="actql-explorer-identities"><dt>{ja ? '検査環境' : 'Check Environment'}</dt><dd>{model.effectful.checkEnvironmentCid}</dd>
        <dt>{ja ? 'パラメータ' : 'Parameters'}</dt><dd>{model.effectful.parameterValuesCid}</dd></dl>
      <table className="actql-explorer-table"><caption>{ja ? '元の検査済み宣言' : 'Original checked declarations'}</caption>
        <thead><tr><th scope="col">{ja ? '出現箇所' : 'Occurrence'}</th><th scope="col">{ja ? '契約' : 'Contract'}</th>
          <th scope="col">{ja ? '宣言された入力' : 'Declared input'}</th><th scope="col">{ja ? '契約上の最低要件' : 'Contract minimum'}</th></tr></thead>
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
      {!workspace && <p>Contract minimum is not current permission. Required approval does not imply a human-only reviewer.
        Not represented does not mean none.</p>}
      {!workspace && <p>Resolved targets: unknown. Changed values: unknown. Current permission: unknown.
        Gate: unknown. Approval: unknown. Sealed Preview: unavailable.</p>}
    </section>}
  </>;
}

function BoundPlanExplorer({model, initialView, workspace}: Omit<PlanExplorerProps, 'scopeKey'>) {
  const groups = workspace?.groups;
  const flow = useMemo(() => workspaceFlow(model, groups), [model, groups]);
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
    if (mode !== 'flow' || flow.unavailable) return;
    const controller = new AbortController(); let active = true;
    requestFlowLayout(flow, {signal: controller.signal}).then(positions => {
      if (active) setLayout({key: layoutKey, state: 'ready', positions});
    }, () => {
      if (active) setLayout({key: layoutKey, state: 'unavailable'});
    });
    return () => { active = false; controller.abort(); };
    // layoutKey is the complete bounded Worker input. Metadata changes retain
    // the same coordinates; current labels still come from the original model.
  }, [mode, layoutKey, flow.unavailable]);
  const currentLayout = layout?.key === layoutKey ? layout : undefined;
  useEffect(() => {
    const panel = canvas.current;
    if (!panel || mode !== 'flow') return;
    setCanvasWidth(panel.clientWidth);
    const resize = new ResizeObserver(()=>setCanvasWidth(panel.clientWidth));
    resize.observe(panel);
    return ()=>resize.disconnect();
  }, [mode, currentLayout]);
  const originalSelection = workspace?.stepId ?? selected;
  const selection = groups?.find(group => group.id === originalSelection ||
    originalSelection !== undefined && group.members.includes(originalSelection))?.id ?? originalSelection;
  const selectOriginal = workspace ? (id: string) => {
    const group = groups?.find(group => group.id === id);
    if (group && originalSelection && group.members.includes(originalSelection)) return;
    workspace.select(group?.representative ?? id);
  } : select;
  const placed = useMemo(() => {
    if (currentLayout?.state !== 'ready') return [];
    const positioned = flow.nodes.map((node, index) => {
      const presentation = workspace?.label(node.id);
      const height = flowNodeHeight(node.data.original.ports.length);
      return {...node, position: {x: currentLayout.positions[index].x, y: currentLayout.positions[index].y},
        selected: node.id === selection,
        data: {...node.data, presentation},
        width: flowNodeWidth, height: presentation?.effectDeclaration ? Math.max(112, height) : height};
    });
    return placeUnlinkedEffects(groupUnlinkedInputs(positioned, flow.edges), flow.edges);
  }, [currentLayout, flow, selection, workspace]);
  const original = model.nodes.find(node => node.id === selection);
  const focus = placed.find(node=>node.id === selection) ?? placed[0];
  const fitNodes = workspace ? initialViewportNodes(placed, focus, canvasWidth) : focus ? [focus] : [];
  const openingViewport = workspace && focus && canvasWidth < flowNodeWidth * 2
    ? narrowWorkspaceViewport(placed, focus, flow.edges, canvasWidth) : undefined;
  return <section className="actql-explorer" data-workspace={!!workspace} aria-label="ActQL static Plan">
    <header className="actql-explorer-header">
      <div>{!workspace && <p className="actql-explorer-kind">STATIC PLAN · PROVIDER I/O 0</p>}
        {!workspace && <h2>{model.effectful ? 'Computation component' : 'Logical operations'}</h2>}
        <p>{workspace ? (workspace.locale === 'ja' ? 'データの流れを表示します。実行順序は示しません。' : 'Data flow, not execution order')
          : 'Data dependencies · layout does not indicate execution order.'}</p></div>
      {!workspace && <nav aria-label="Plan presentation">
        <Button aria-pressed={mode === 'list'} onClick={() => show('list')}><List aria-hidden/>List</Button>
        <Button aria-pressed={mode === 'flow'} onClick={() => show('flow')}><Workflow aria-hidden/>Flow</Button>
      </nav>}
    </header>
    {mode === 'list' && <OriginalPlanMetadata model={model}/>}
    {mode === 'flow' ? currentLayout?.state === 'ready' ? <div ref={canvas} className="actql-explorer-flow">
      {placed.some(node=>node.data.unlinkedInput) && <span className="actql-explorer-input-group">Declared inputs</span>}
      {canvasWidth > 0 && <ReactFlow key={layoutKey} fitView={openingViewport === undefined} defaultViewport={openingViewport}
        nodes={placed} edges={flow.edges} nodeTypes={nodeTypes} edgeTypes={edgeTypes}
        fitViewOptions={{nodes: fitNodes, minZoom: 0.9, maxZoom: 1, padding: 0.12}}
        nodesDraggable={false} nodesConnectable={false} edgesReconnectable={false}
        connectOnClick={false} deleteKeyCode={null} zoomOnDoubleClick={false}
        onNodeClick={(_, node) => selectOriginal(node.id)}
        minZoom={0.2} maxZoom={2} aria-label="Original logical ports">
        <Controls position="top-right" showInteractive={false} aria-label="Graph zoom"/>
      </ReactFlow>}
    </div> : <p role="status" className="actql-explorer-unavailable">
      {(flow.unavailable || currentLayout?.state === 'unavailable')
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
    {!workspace && mode === 'flow' && <details className="actql-explorer-flow-metadata">
      <summary>Original Plan metadata</summary>
      <OriginalPlanMetadata model={model}/>
    </details>}
  </section>;
}
