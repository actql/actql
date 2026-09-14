// Independent preimage model, not a graph evaluator or Unit-admission routine.
import {cid} from './components-limit-model.mjs';
export function traversalLimitModel(policy, unit, repeated = false, guard = null) {
  const policyCid = cid(policy);
  const hosts = [['max_graph_paths','graph-paths','paths'], ['max_graph_output_rows','graph-output','rows']].map(([field, law, quantity]) => {
    const body = {version:'actql-bound-witness/0.1', unit:quantity, value:policy[field],
      role:'host_ceiling', law_id:`actql.host.${law}`, dependencies:[policyCid], derivation:{op:'source'},
      source:{kind:'host_policy', policy_cid:policyCid, field}};
    return {...body, witness_cid:cid(body)};
  });
  const limits = hosts.map((host, i) => ({version:'actql-resolved-limit/0.1', author_guard_binding:'absent',
    breach:'fail', enforcement:'engine_atomic', subject_ref:`unit:${unit}#/steps/3/traverse/${i===0?'paths':'output'}`,
    unit:host.unit, effective_max:host.value, candidates:repeated?[host,host]:[host]}));
  if (guard !== null) {
    const body = {version:'actql-bound-witness/0.1', unit:'rows', value:guard,
      role:'author_guard', law_id:'actql.guard.traverse-output', dependencies:[unit], derivation:{op:'source'},
      source:{kind:'author_guard',program_definition_cid:unit,source_path:'$.steps[3].traverse.max_output_rows'}};
    limits[1].candidates.push({...body,witness_cid:cid(body)});
    limits[1].candidates.sort((a,b)=>a.witness_cid.localeCompare(b.witness_cid));
    limits[1].author_guard_binding=guard<hosts[1].value?'binding':'currently_non_binding';
    limits[1].effective_max=Math.min(guard,hosts[1].value);
  }
  return {policy_cid:policyCid,host_cids:hosts.map(w=>w.witness_cid),limit_cids:limits.map(cid),limits};
}
