// The installed Host owner also backs Embedded Local. No second runtime is
// constructed here; callers supply their own HTTPS server and authentication.
export {openInstalledRemoteHttpHost} from './adapters/host-node/embedded-local.mjs';
