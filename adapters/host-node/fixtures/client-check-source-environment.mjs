// The public-check fixture adds Source facts to the supplied Host policy.
// This is fixture DATA, never a runtime admission or permission replacement.
import {contentCid} from '../local-account-config.mjs';

export function clientCheckSourceEnvironment(original, hostEnvironmentWire) {
  const base = JSON.parse(hostEnvironmentWire);
  const environment = {...original, host_policy_profile:base.host_policy_profile};
  delete environment.evidence_bundle_cid;
  environment.evidence_bundle_cid = contentCid(environment);
  return environment;
}
