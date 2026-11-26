import {explorerCopy, type ExplorerLocale} from './i18n.mjs';
import type {PlanReadModel} from './read-model.js';
import type {Node,Edge} from '@xyflow/react';
type OriginalNode = PlanReadModel['nodes'][number];
type OriginalPort = OriginalNode['ports'][number];
import {graphViewLimits, ExplorerReadError} from './read-model.mjs';

// Positions are presentation only. They do not imply Stage order, a physical
// execution, a source origin or a missing dependency.
export function flowPresentation(model:PlanReadModel, locale?: ExplorerLocale):{nodes:Node<{original:OriginalNode}>[];edges:Edge[]} {
  const words = explorerCopy(locale);
  const refuse:()=>never = () => {throw new ExplorerReadError('ExplorerInvalidPresentation');};
  if (model?.observation !== 'static' || model.providerIO !== 0 ||
      !Array.isArray(model.nodes) || model.nodes.length > graphViewLimits.steps ||
      !Array.isArray(model.edges) || !Array.isArray(model.inputs) ||
      model.edges.length + model.inputs.length > graphViewLimits.ports) refuse();
  const nodes = new Map<string,OriginalNode>(), ports = new Map<string,{node:OriginalNode;port:OriginalPort}>(); let count = 0;
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
      label: words.graphInput(edge.targetPortOrdinal), type: 'default', selectable: false,
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
  if (model.stageResultLinks !== undefined) {
    const links = model.stageResultLinks;
    if (!Array.isArray(links) || links.length > model.inputs.length) refuse();
    const used = new Set();
    for (const link of links) {
      const source = ports.get(link?.producer?.port_id), target = ports.get(link?.consumer?.port_id);
      if (!source || !target || source.node.id !== link.producer.step_id ||
          target.node.id !== link.consumer.step_id || source.port.role !== 'output' ||
          target.port.role !== 'input' || target.port.source.kind !== 'stage_input' ||
          !Number.isSafeInteger(source.node.key?.stage_ordinal) ||
          target.port.source.stage_ordinal !== target.node.key?.stage_ordinal ||
          source.node.key.stage_ordinal >= target.node.key.stage_ordinal ||
          source.port.carrier !== target.port.carrier ||
          typeof link.result_projection !== 'boolean' ||
          !link.result_projection && source.port.carrier_contract_cid !== target.port.carrier_contract_cid ||
          used.has(target.port.port_id)) refuse();
      used.add(target.port.port_id);
      edges.push({id: target.port.port_id, source: source.node.id, target: target.node.id,
        sourceHandle: source.port.port_id, targetHandle: target.port.port_id,
        label: link.result_projection ? words.resultProjection : words.stageResult, type: 'default',
        selectable: false, focusable: false, deletable: false});
    }
  }
  return {nodes: model.nodes.map((node:OriginalNode, index:number) => ({id: node.id, type: 'logical',
    position: {x: (index % 4) * 290, y: Math.floor(index / 4) * 240},
    data: {original: node}, draggable: false, connectable: false, deletable: false})), edges};
}
