import {graphViewLimits, ExplorerReadError} from './read-model.mjs';

// Presentation dimensions and a Worker deadline, never execution/Host budgets.
export const flowLayoutDeadlineMs = 5000;
export const flowNodeWidth = 260;
export const flowNodeHeight = ports => 108 + ports * 18;
const refuse = () => { throw new ExplorerReadError('ExplorerInvalidLayout'); };

/** Strip names, source text and all non-layout data before crossing the Worker.
 * Original coordinates already passed flowPresentation; no edge is inferred. */
export function layoutInput(flow) {
  if (!Array.isArray(flow?.nodes) || flow.nodes.length > graphViewLimits.steps ||
      !Array.isArray(flow.edges) || flow.edges.length > graphViewLimits.ports) refuse();
  const ids = new Set(), ports = new Map();
  let count = 0;
  const nodes = flow.nodes.map(node => {
    if (typeof node.id !== 'string' || node.id.length > 256 || ids.has(node.id) ||
        !Array.isArray(node.data?.original?.ports) ||
        (count += node.data.original.ports.length) > graphViewLimits.ports) refuse();
    ids.add(node.id);
    return {id: node.id, ports: node.data.original.ports.map(port => {
      if (typeof port.port_id !== 'string' || port.port_id.length > 256 ||
          ports.has(port.port_id) || !['input', 'output'].includes(port.role)) refuse();
      ports.set(port.port_id, {node: node.id, role: port.role});
      return {id: port.port_id, role: port.role};
    })};
  });
  const edgeIds = new Set();
  const edges = flow.edges.map(edge => {
    if (typeof edge.id !== 'string' || edge.id.length > 256 || edgeIds.has(edge.id) ||
        ports.get(edge.sourceHandle)?.node !== edge.source ||
        ports.get(edge.sourceHandle)?.role !== 'output' ||
        ports.get(edge.targetHandle)?.node !== edge.target ||
        ports.get(edge.targetHandle)?.role !== 'input') refuse();
    edgeIds.add(edge.id);
    return {id: edge.id, source: edge.sourceHandle, target: edge.targetHandle};
  });
  return {nodes, edges};
}

/** The Worker receives no public model or permission; it only places a bounded
 * graph. Prefixes separate ELK node/port namespaces without changing any ID. */
export function elkGraph(input) {
  if (!Array.isArray(input?.nodes) || input.nodes.length > graphViewLimits.steps ||
      !Array.isArray(input.edges) || input.edges.length > graphViewLimits.ports) refuse();
  let count = 0;
  const ids = new Set(), ports = new Map();
  const children = input.nodes.map(node => {
    if (typeof node.id !== 'string' || node.id.length > 256 || ids.has(node.id) ||
        !Array.isArray(node.ports) || (count += node.ports.length) > graphViewLimits.ports) refuse();
    ids.add(node.id);
    const declared = node.ports.map((port, index) => {
      if (typeof port.id !== 'string' || port.id.length > 256 || ports.has(port.id) ||
          !['input', 'output'].includes(port.role)) refuse();
      ports.set(port.id, port.role);
      return {id: `port:${port.id}`, width: 0, height: 0,
        x: port.role === 'input' ? 0 : flowNodeWidth, y: 28 + index * 18,
        layoutOptions: {'elk.port.side': port.role === 'input' ? 'WEST' : 'EAST'}};
    });
    return {id: `node:${node.id}`, width: flowNodeWidth, height: flowNodeHeight(node.ports.length),
      layoutOptions: {'elk.portConstraints': 'FIXED_POS'}, ports: declared};
  });
  const edgeIds = new Set();
  const edges = input.edges.map(edge => {
    if (typeof edge.id !== 'string' || edge.id.length > 256 || edgeIds.has(edge.id) ||
        ports.get(edge.source) !== 'output' || ports.get(edge.target) !== 'input') refuse();
    edgeIds.add(edge.id);
    return {id: `edge:${edge.id}`, sources: [`port:${edge.source}`], targets: [`port:${edge.target}`]};
  });
  return {id: 'layout:root', layoutOptions: {'elk.algorithm': 'layered', 'elk.direction': 'RIGHT',
    'elk.spacing.nodeNode': '48', 'elk.layered.spacing.nodeNodeBetweenLayers': '80'}, children, edges};
}

/** Accept placement only. ELK cannot replace edges, nodes, handles or labels. */
export function layoutPositions(input, result) {
  if (!Array.isArray(result?.children) || result.children.length !== input.nodes.length) refuse();
  const expected = new Set(input.nodes.map(node => `node:${node.id}`)), seen = new Set();
  const points = new Map(result.children.map(node => {
    if (!expected.has(node.id) || seen.has(node.id) ||
        ![node.x, node.y].every(value => typeof value === 'number' && Number.isFinite(value) &&
          Math.abs(value) <= Number.MAX_SAFE_INTEGER)) refuse();
    seen.add(node.id);
    return [node.id, {x: node.x, y: node.y}];
  }));
  return input.nodes.map(node => ({id: node.id, ...points.get(`node:${node.id}`)}));
}

