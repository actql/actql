import {connectEmbeddedLocal, publishInstalledSource} from
  './adapters/host-node/embedded-local.mjs';
import {ClientError} from '@actql/sdk';

// Publish the installed source's declaration (for example a Salesforce
// source's targeted Catalog) before the embedded Host uses it.
export function publishSource(options) {
  return publishInstalledSource(options);
}

export function connect(options) {
  if (options?.mode !== 'local' || options?.owner !== 'local') {
    throw new ClientError('LocalHybridUnavailable');
  }
  return connectEmbeddedLocal(options);
}
