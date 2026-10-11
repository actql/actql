import {graphViewLimits, ExplorerReadError} from './read-model.mjs';

// Positions are presentation only. They do not imply Stage order, a physical
// execution, a source origin or a missing dependency.
export function flowPresentation(model) {
  const refuse = () => {throw new ExplorerReadError('ExplorerInvalidPresentation');};
  if (model?.observation !== 'static' || model.providerIO !== 0 ||
      !Array.isArray(model.nodes) || model.nodes.length > graphViewLimits.steps ||
      !Array.isArray(model.edges) || !Array.isArray(model.inputs) ||
      model.edges.length + model.inputs.length > graphViewLimits.ports) refuse();
  const nodes = new Map(), ports = new Map(); let count = 0;
  for (const node of model.nodes) {
    if (typeof node.id !== 'string' || nodes.has(node.id) ||
        !Array.isArray(node.ports) || (count += node.ports.length) > graphViewLimits.ports) refuse();
    nodes.set(node.id, node);
    for (const port of node.ports) {
      if (typeof port.port_id !== 'string' || ports.has(port.port_id) ||
          !['input', 'output'].includes(port.role)) refuse();
      ports.set(port.port_id, {node, port});
    }
  }
  const seen = new Set();
  const edges = model.edges.map(edge => {
    const source = ports.get(edge.sourcePortId), target = ports.get(edge.targetPortId);
    if (!source || !target || source.node.id !== edge.sourceStepId ||
        target.node.id !== edge.targetStepId || source.port.role !== 'output' ||
        target.port.role !== 'input' || edge.id !== edge.targetPortId || seen.has(edge.id) ||
        target.port.source.kind !== 'logical_output' ||
        target.port.source.step_id !== edge.sourceStepId ||
        target.port.source.output_port_id !== edge.sourcePortId ||
        target.port.port_ordinal !== edge.targetPortOrdinal ||
        source.port.carrier !== target.port.carrier ||
        source.port.carrier_contract_cid !== target.port.carrier_contract_cid) refuse();
    seen.add(edge.id);
    return {id: edge.id, source: edge.sourceStepId, sourceHandle: edge.sourcePortId,
      target: edge.targetStepId, targetHandle: edge.targetPortId,
      label: `input ${edge.targetPortOrdinal}`, type: 'default', selectable: false,
      focusable: false, deletable: false};
  });
  for (const input of model.inputs) {
    const original = ports.get(input.inputPortId);
    if (!original || original.node.id !== input.stepId || original.port.role !== 'input' ||
        original.port.source.kind !== 'stage_input' || seen.has(input.inputPortId) ||
        input.locator?.kind !== 'stage_input' ||
        input.locator.input_port_ordinal !== original.port.source.input_port_ordinal ||
        input.locator.stage_ordinal !== original.port.source.stage_ordinal) refuse();
    seen.add(input.inputPortId);
  }
  if ([...ports.values()].some(({port}) => port.role === 'input' && !seen.has(port.port_id))) refuse();
  return {nodes: model.nodes.map((node, index) => ({id: node.id, type: 'logical',
    position: {x: (index % 4) * 290, y: Math.floor(index / 4) * 240},
    data: {original: node}, draggable: false, connectable: false, deletable: false})), edges};
}
