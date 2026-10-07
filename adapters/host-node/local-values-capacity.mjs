// Host-private finite Values profile; common owners still admit and execute it.
import {createHash} from 'node:crypto';
const digest = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;

export function valuesHostPolicyOriginal(maxRows) {
  if (!Number.isSafeInteger(maxRows) || maxRows < 1 || maxRows > 10000) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
  if (maxRows === 100) return undefined;
  const wire = JSON.stringify({max_rows: maxRows, name: 'source-free-values',
    version: 'actql-installed-local-policy/0.1'});
  return Object.freeze({cid: digest(wire), wire});
}

export function valuesExecutionContextCid(authorityScopeCid, original) {
  // Preserve the default profile's preimage. A configured ceiling becomes
  // part of the context that the common owner binds to the Run Definition.
  return digest(JSON.stringify({version: 'actql-installed-local-context/0.1',
    authority_scope_cid: authorityScopeCid,
    ...(original === undefined ? {} : {host_policy_cid: original.cid})}));
}
