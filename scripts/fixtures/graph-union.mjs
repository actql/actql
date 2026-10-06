import {createHash} from 'node:crypto';
import {canonicalText} from '../check-canonical-json.mjs';
import {graphPresenceOracle, deltaApplicationScenario} from './graph-delta-application.mjs';

const digest = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');

// Only authored input declarations and independent expected records enter this
// oracle. Runtime union, snapshot encoders and actual streams are not consulted.
export function unionGraphScenario(fixture, projection, {numeric = false, empty = false} = {}) {
  if (!['node_rows','edge_rows'].includes(projection)) throw new Error('UnknownUnionProjection');
  const base = structuredClone(fixture);
  if (numeric) for (const row of base.stages[0].steps[0].values.rows) row.p = row.person_key === 1 ? 2 : 3;
  if (empty) for (const step of base.stages[0].steps.slice(0,3)) step.values.rows = [];
  const oracle = graphPresenceOracle(base);
  const before = JSON.parse(oracle.snapshot);
  const rows = structuredClone(oracle.rows[projection]);
  if (empty) {
    before[3] = [];
    before[4] = [];
    rows.splice(0);
  } else if (numeric) {
    before[3][1].props.p = 2;
    before[3][2].props.p = 3;
    if (projection === 'node_rows') {
      rows[1].p = 6;
      rows[2].p = 9;
    }
  }
  const baseSnapshot = canonicalText(before);
  const result = structuredClone(before);
  if (numeric && !empty) {
    result[3][1].props.p = 6;
    result[3][2].props.p = 9;
  }
  const unionSnapshot = canonicalText(result);
  const document = numeric || empty ? base : deltaApplicationScenario(base,projection).document;
  document.id = `union-${projection}-${numeric ? 'repeated-sum' : 'overlap'}${empty ? '-empty' : ''}`;
  const steps = document.stages[0].steps;
  let graphSnapshots, rowsTask;
  if (numeric || empty) {
    // Three authored occurrences of one immutable input: score 2 -> 6, not 2
    // or 4. The original domain, composite key and parallel edge IDs survive.
    steps.splice(4,steps.length-4,
      {from:'g',union_graphs:{with:['g','g'],...(numeric ? {merge:{node_properties:{p:'number_sum'}}} : {})},as:'combined'});
    graphSnapshots = [[3,baseSnapshot],[4,unionSnapshot]];
    rowsTask = 5;
  } else {
    const peer = structuredClone(before);
    if (!empty) peer[4].splice(1);
    const peerSnapshot = canonicalText(peer);
    const delta = steps[4].derive.delta.literal;
    delta.base_graph_cid = digest(baseSnapshot);
    delta.target_graph_cid = digest(peerSnapshot);
    delta.nodes.update = [];
    delta.edges.remove = empty ? [] : [before[4][1]];
    // Reuse the existing Delta owner to construct the compatible strict
    // subset. Union must restore the independently keyed second parallel edge.
    steps.splice(6,steps.length-6,
      {from:'g',union_graphs:{with:['applied','g']},as:'combined'});
    graphSnapshots = [[3,baseSnapshot],[5,peerSnapshot],[6,unionSnapshot]];
    rowsTask = 7;
  }
  steps.push({from:'combined',[projection]:true,as:'rows'},
    {filter:'labels IS NOT NULL',as:'filtered'},
    {select:projection === 'node_rows' ? ['id','labels'] : ['id','src','dst','labels','edge_key','tenant_key'],as:'projected'});
  const fields = steps.at(-1).select;
  document.stages[0].results.out.fields = fields;
  // Both bridges cross the retained Relation boundary before publication.
  // Sparse node rows also retain filter's unprojected output. Dense edge
  // filter/select uses the existing fused final task, not another Store lease.
  const relationSnapshots = [[rowsTask,rows]];
  if (projection === 'node_rows') relationSnapshots.push([rowsTask+1,rows]);
  return {document,graphSnapshots,relationSnapshots,fields,
    expected:rows.map(row=>Object.fromEntries(fields.map(field=>[field,row[field]])))};
}

// The existing Delta owner makes an individually valid peer in the original
// domain. Its first parallel edge keeps its complete ID/key but reverses its
// endpoints. No product union output participates in this refusal fixture.
export function unionEndpointConflictScenario(fixture) {
  const {document,graphSnapshots} = unionGraphScenario(fixture,'edge_rows');
  const base = JSON.parse(graphSnapshots[0][1]);
  const peer = JSON.parse(graphSnapshots[1][1]);
  const before = structuredClone(base[4][0]);
  const after = structuredClone(peer[4][0]);
  after.src = structuredClone(before.dst);
  after.dst = structuredClone(before.src);
  peer[4][0] = after;
  const peerSnapshot = canonicalText(peer);
  const delta = document.stages[0].steps[4].derive.delta.literal;
  delta.edges.update = [{before,after}];
  delta.target_graph_cid = digest(peerSnapshot);
  document.id = 'union-shared-edge-endpoint-conflict';
  return {document,before,after,baseSnapshot:graphSnapshots[0][1],peerSnapshot};
}
