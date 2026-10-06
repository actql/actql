import {createHash} from 'node:crypto';
import {canonicalText} from '../check-canonical-json.mjs';
import {propertyGraphPresenceOracle} from './property-graph-delta-application.mjs';

const digest = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
// Fixed authored cases, not a second Graph implementation. No product checker,
// subtraction kernel, serializer or actual output generates an expectation.
export function subtractionScenario(fixture, kind, projection = 'node_rows') {
  if (!['node_rows', 'edge_rows'].includes(projection)) throw new Error('UnknownSubtractionProjection');
  const document = structuredClone(fixture);
  const oracle = propertyGraphPresenceOracle(fixture);
  const base = JSON.parse(oracle.snapshot);
  const nodes = base[3], edges = base[4];
  let rightNodes = structuredClone(nodes), rightEdges = structuredClone(edges);
  let expectedNodes, expectedEdges, merge, failure;
  switch (kind) {
    case 'empty-right':
      rightNodes = []; rightEdges = [];
      expectedNodes = nodes; expectedEdges = edges;
      break;
    case 'self-remove':
      expectedNodes = []; expectedEdges = [];
      break;
    case 'explicit-equality-keeps-nodes':
      merge = {node_properties:{p:'exact_equal'}};
      expectedNodes = nodes; expectedEdges = [];
      break;
    case 'remove-one-node-endpoint-closure':
      rightNodes = [structuredClone(nodes[1])]; rightEdges = [];
      expectedNodes = [nodes[0], nodes[2]]; expectedEdges = [];
      break;
    case 'keep-nodes-remove-one-parallel-edge':
      merge = {node_properties:{p:'exact_equal'}};
      rightEdges = [structuredClone(edges[0])];
      expectedNodes = nodes; expectedEdges = [edges[1]];
      break;
    case 'numeric-strategy-is-addition':
      merge = {node_properties:{p:'number_sum'}};
      rightNodes = [structuredClone(nodes[1])]; rightEdges = [];
      expectedNodes = structuredClone(nodes); expectedNodes[1].props.p = 14;
      expectedEdges = edges;
      break;
    case 'shared-payload-conflict':
      rightNodes = [structuredClone(nodes[1])]; rightNodes[0].props.p = 8;
      rightEdges = [];
      failure = 'complete-payload-conflict';
      break;
    case 'shared-null-numeric-rejected':
      merge = {node_properties:{p:'number_sum'}};
      rightNodes = [structuredClone(nodes[2])]; rightEdges = [];
      failure = 'null-numeric-operands';
      break;
    case 'endpoint-conflict-before-induced-closure':
      rightEdges = [structuredClone(edges[0])];
      rightEdges[0].src = structuredClone(edges[0].dst);
      rightEdges[0].dst = structuredClone(edges[0].src);
      failure = 'complete-edge-payload-conflict';
      break;
    default: throw new Error('UnknownSubtractionCase');
  }
  const rightSnapshot = canonicalText([...base.slice(0,3), rightNodes, rightEdges]);
  const sameIdentity = (left, right) => canonicalText(left) === canonicalText(right);
  const actions = (before, after) => ({add:[],
    remove:before.filter(record => !after.some(next => sameIdentity(record.id, next.id))),
    update:before.flatMap(record => {
      const next = after.find(value => sameIdentity(record.id, value.id));
      return next && canonicalText(record) !== canonicalText(next) ? [{before:record,after:next}] : [];
    })});
  // The existing Delta owner constructs the right input within the original
  // identity domain; editing inline VALUES would instead change the definition.
  const delta = {version:'actql-graph-delta/0.1',graph_contract_cid:base[1],
    base_graph_cid:oracle.snapshotCid,target_graph_cid:digest(rightSnapshot),
    nodes:actions(nodes,rightNodes),edges:actions(edges,rightEdges)};
  document.id = `subtraction-${kind}-${projection}`;
  const fields = projection === 'node_rows' ? ['id','labels']
    : ['id','src','dst','labels','edge_key','tenant_key'];
  document.stages[0].steps.splice(4, document.stages[0].steps.length - 4,
    {from:'companies',derive:{delta:{literal:delta}},as:'changes'},
    {from:'g',apply_graph_delta:{with:'changes',field:'delta'},as:'right'},
    {from:'g',subtract_graphs:{with:'right',...(merge ? {merge} : {})},as:'difference'},
    {from:'difference',[projection]:true,as:'rows'},
    {select:fields,as:'projected'});
  document.stages[0].results.out.fields = fields;
  if (failure) return {document,delta,rightSnapshot,failure,fields};
  const expectedSnapshot = canonicalText([...base.slice(0,3), expectedNodes, expectedEdges]);
  const expectedRows = (projection === 'node_rows' ? expectedNodes : expectedEdges).map(record => {
    const row = structuredClone(oracle.rows[projection].find(value => sameIdentity(record.id,value.id)));
    if (projection === 'node_rows') for (const [name,value] of Object.entries(record.props)) row[name] = value;
    return row;
  });
  return {document,delta,rightSnapshot,fields,expectedSnapshot,
    expectedSnapshotCid:digest(expectedSnapshot),expectedRows,
    expected:expectedRows.map(row => Object.fromEntries(fields.map(field => [field,row[field]])))};
}
