import {useMemo, useState} from 'react';
import {ReactFlow, Handle, Position, type NodeProps, type Node, type Edge} from '@xyflow/react';
import {Button} from '@base-ui/react/button';
import {Workflow, List, CircleHelp} from 'lucide-react';
import type {PlanReadModel} from './read-model.js';
import {flowPresentation} from './flow-model.mjs';
import './styles.css';

type Logical = PlanReadModel['nodes'][number];
type LogicalNode = Node<{original: Logical}, 'logical'>;
function LogicalCard({data, selected}: NodeProps<LogicalNode>) {
  const original = data.original;
  return <div className="actql-explorer-node" data-selected={selected}>
    <div className="actql-explorer-kind">{original.operator}</div>
    <strong>{original.names.join(', ') || original.id}</strong>
    <p>{original.kind}</p>
    {original.ports.map((port, index) => <Handle key={port.port_id} id={port.port_id}
      type={port.role === 'input' ? 'target' : 'source'}
      position={port.role === 'input' ? Position.Left : Position.Right}
      isConnectable={false} style={{top: 28 + index * 18}}
      aria-label={`${port.role} ${port.port_ordinal}: ${port.carrier}`}/>)}
  </div>;
}
const nodeTypes = {logical: LogicalCard};
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
  const original = model.nodes.find(node => node.id === selected);
  return <section className="actql-explorer" aria-label="ActQL static Plan">
    <header className="actql-explorer-header">
      <div><p className="actql-explorer-kind">STATIC PLAN · PROVIDER I/O 0</p>
        <h2>{model.effectful ? 'Computation component' : 'Logical operations'}</h2>
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
    {mode === 'flow' ? <div className="actql-explorer-flow">
      <ReactFlow nodes={flow.nodes} edges={flow.edges} nodeTypes={nodeTypes}
        nodesDraggable={false} nodesConnectable={false} edgesReconnectable={false}
        connectOnClick={false} deleteKeyCode={null} zoomOnDoubleClick={false}
        onNodeClick={(_, node) => select(node.id)}
        minZoom={0.2} maxZoom={2} aria-label="Original logical ports"/>
    </div> : <table className="actql-explorer-table"><caption>Original logical occurrences</caption>
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
