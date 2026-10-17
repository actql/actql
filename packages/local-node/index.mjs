import {connectEmbeddedLocal, publishInstalledEffect,
  publishInstalledSource} from './adapters/host-node/embedded-local.mjs';
import {ClientError} from '@actql/sdk';
export {createInstalledConnectorTable} from './adapters/host-node/installed-connectors.mjs';

// Publish the installed source's declaration (for example a Salesforce
// source's targeted Catalog) before the embedded Host uses it.
export function publishSource(options) {
  return publishInstalledSource(options);
}

// Publish the installed Effect's declaration, execution Mappings and Check
// Environment as one generation before the embedded Host uses it.
export function publishEffect(options) {
  return publishInstalledEffect(options);
}

export function connect(options) {
  const mode = options?.mode, owner = options?.owner;
  if (mode !== 'local' || owner !== undefined && owner !== 'local') {
    throw new ClientError('LocalHybridUnavailable');
  }
  if (owner === 'local') return connectEmbeddedLocal(options);
  // Explicit embedded Local already selects this physical provider. Omission
  // is not another Account/Run authority: the original Host still admits the
  // same closed connection and its current policy. Never default null/foreign
  // ownership or Hybrid, and do not reread mode/owner through caller getters.
  // Preserve other original descriptors/prototype rather than invoking their
  // getters here or dropping hidden/symbol installation inputs during a copy.
  return connectEmbeddedLocal(Object.create(Object.getPrototypeOf(options), {
    ...Object.getOwnPropertyDescriptors(options),
    mode: {value: mode, enumerable: true},
    owner: {value: 'local', enumerable: true},
  }));
}
