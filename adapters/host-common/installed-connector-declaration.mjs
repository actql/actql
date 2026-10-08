// The finite declarations shared by generated Host manifests and trusted
// process-local installation tables. These checks never load a connector.
import {reservedHttpHeader} from './http-exchange.mjs';

const identityProfileKeys = ['continuation', 'continuationBinding', 'dispatch',
  'recovery', 'source', 'targetCheck', 'unit'];
const identityVersion = /^actql-[a-z0-9-]+\/0\.1$/u;
const continuationBindings = ['binding_cid', 'publication_generation_cid'];
const headerName = /^[a-z0-9][a-z0-9-]*$/u;

export function validInstalledEffectIdentityProfile(value) {
  return value !== null && typeof value === 'object' &&
    !Array.isArray(value) &&
    Object.keys(value).sort().join() === identityProfileKeys.join() &&
    continuationBindings.includes(value.continuationBinding) &&
    identityProfileKeys.filter(key => key !== 'continuationBinding')
      .every(key => typeof value[key] === 'string' &&
        identityVersion.test(value[key]));
}

export function validInstalledResponseHeaders(value) {
  return Array.isArray(value) && value.length <= 16 &&
    new Set(value).size === value.length &&
    value.every(header => typeof header === 'string' &&
      headerName.test(header) && !reservedHttpHeader(header));
}
