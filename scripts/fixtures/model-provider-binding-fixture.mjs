// Nonsecret installation originals authored independently of the Model issuer.
// Their digest is a contract input; no product-produced binding supplies it.
import {createHash} from 'node:crypto';

const canonical = value => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const original = body => {
  const wire = canonical(body);
  return {wire, cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`};
};

export function providerBindingOriginals(providerId, {
  revision = 'independent-test-provider-1', selector = 'fixture-risk-model',
  endpoint = 'in-process://fixture-model/structured-generate',
  tenant = 'fixture-tenant', principal = 'fixture-provider-principal',
} = {}) {
  return {
    installationRevision: original({version: 'fixture-model-installation/0.1',
      provider_id: providerId, implementation_revision: revision}),
    configurationContract: original({version: 'fixture-model-configuration-contract/0.1',
      provider_id: providerId, required: ['endpoint', 'principal', 'selector', 'tenant'],
      request_shape: {input: 'canonical-json-object', output: 'structured-json',
        streaming: false, tools: false}}),
    configuration: original({version: 'fixture-model-configuration/0.1',
      provider_id: providerId, endpoint, tenant, principal, selector}),
  };
}
