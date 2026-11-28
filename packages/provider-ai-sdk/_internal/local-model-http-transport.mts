import {createRequire} from 'node:module';
import type * as Transport from '@actql/local-node/_internal/model-http-transport';

const originalRequire = createRequire(import.meta.url);

// Only configuration or an entered preparation can borrow the selected Local
// peer. Linking the optional SDK package alone cannot evaluate the transport.
export function originalLocalModelHttpTransport(): typeof Transport {
  return originalRequire('@actql/local-node/_internal/model-http-transport') as typeof Transport;
}
