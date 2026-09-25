import {connectEmbeddedLocal} from './adapters/host-node/embedded-local.mjs';
import {ClientError} from '@actql/sdk';

export function connect(options) {
  if (options?.mode !== 'local' || options?.owner !== 'local') {
    throw new ClientError('LocalHybridUnavailable');
  }
  return connectEmbeddedLocal(options);
}
