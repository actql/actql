// Installed providers use the same Client facade without an HTTP transport.
export {connectInProcess} from './index.mjs';

// Host context bindings share the SDK's value-preserving canonical encoding.
export {canonicalJson} from './checkpoints.mjs';
