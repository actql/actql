// A Host process over a cross-version installation: it opens the installed
// Remote Host, which resumes approved Runs at start, and waits to be killed.
import {openInstalledRemoteHttpHost} from
  '../../../../host-node/embedded-local.mjs';
import {hostAuthorization, secret, tokens} from './update-state.mjs';

const {installation, orgId, keys} = JSON.parse(
  process.env.ACTQL_CROSS_VERSION_HOST);
await openInstalledRemoteHttpHost({directory: installation.directory,
  authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
  sourceProfilePath: installation.sourceProfilePath,
  resolveSourceSecret: secret,
  effectProfilePath: installation.effectProfilePath,
  resolveEffectSecret: secret,
  authorization: hostAuthorization(orgId, keys)});
console.log('host-open');
setInterval(() => {}, 1 << 30);
