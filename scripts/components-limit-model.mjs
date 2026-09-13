// Independent canonical preimage model for synthetic Unit namespaces.
// This neither evaluates graphs nor admits a Unit definition.
import {createHash} from 'node:crypto';
export function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object')
    return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return value;
}
export const cid = value => 'sha256:' + createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
export function componentLimitModel(policy, unit, rows, repeated = false) {
  const policyCid = cid(policy);
  const ref = step => `unit:${unit}#/steps/${step}`;
  const proofs = [];
  const witnesses = [];
  for (const [step, law, quantity, parent] of [
    [0,'values','rows',null], [2,'graph-nodes','nodes',0],
    [3,'components-input-nodes','nodes',1], [3,'components-nodes','rows',1],
  ]) {
    const inputs = parent === null ? [] : [witnesses[parent].witness_cid];
    const proof = {version:'actql-bound-proof/0.1', semantic_ref:ref(step), law_id:`actql.bound.${law}`, unit:quantity, value:rows, inputs};
    const witness = {version:'actql-bound-witness/0.1', unit:quantity, value:rows,
      role:'proven_upper_bound', law_id:proof.law_id,
      source:{kind:'program', semantic_ref:ref(step), proof_cid:cid(proof)},
      derivation:{op:'source'}, dependencies:[...inputs,cid(proof)].sort()};
    proofs.push(proof);
    witnesses.push({...witness,witness_cid:cid(witness)});
  }
  const host = {version:'actql-bound-witness/0.1', unit:'rows', value:policy.max_graph_output_rows,
    role:'host_ceiling', law_id:'actql.host.graph-output', dependencies:[policyCid], derivation:{op:'source'},
    source:{kind:'host_policy', policy_cid:policyCid, field:'max_graph_output_rows'}};
  const hostWire = {...host, witness_cid:cid(host)};
  const limits = ['nodes','output'].map((scope,i) => {
    const candidates = i === 0 ? [witnesses[2]] : [witnesses[3],hostWire];
    if (repeated) candidates.push(candidates[0]);
    candidates.sort((a,b) => a.witness_cid < b.witness_cid ? -1 : a.witness_cid > b.witness_cid ? 1 : 0);
    return {version:'actql-resolved-limit/0.1', author_guard_binding:'absent', breach:'fail',
      enforcement:'engine_atomic', subject_ref:`${ref(3)}/components/${scope}`, unit:i === 0 ? 'nodes':'rows',
      effective_max:Math.min(...candidates.map(c => c.value)), candidates};
  });
  return {policy_cid:policyCid, host_cid:cid(host), proof_cids:proofs.map(cid), witness_cids:witnesses.map(w=>w.witness_cid), limit_cids:limits.map(cid), limits};
}
