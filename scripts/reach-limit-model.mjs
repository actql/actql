// Independent canonical preimages, not product lowering or reach evaluation.
import {cid} from './components-limit-model.mjs';
import {traversalLimitModel} from './traversal-limit-model.mjs';
export function reachLimitModel(policy, unit, repeated = false) {
  const base=traversalLimitModel(policy,unit,repeated);
  const limits=base.limits.map((limit,i)=>({...limit,subject_ref:`unit:${unit}#/steps/3/reach/${i===0?'paths':'output'}`}));
  return {...base,limits,limit_cids:limits.map(cid)};
}
