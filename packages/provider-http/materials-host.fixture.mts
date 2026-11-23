import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {httpMaterialsConfiguration} from './original-materials.fixture.mjs';
import {createInstalledHttpChatRegistration} from './index.mjs';
// @ts-expect-error Remove when the embedded Local Host source is migrated to TypeScript.
import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';

const register = createInstalledHttpChatRegistration(httpMaterialsConfiguration());
const moon: unknown = await import(new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
const root = await mkdtemp(join(tmpdir(), 'actql-http-materials-host-'));
let host: {close(): Promise<unknown>} | undefined, callbacks = 0, completed = false;
try {
  const options = {directory:root, authenticate:() => 'owner', registerModelProviders:(actual: Parameters<typeof register>[0]) => {
    callbacks++; assert.strictEqual(actual, moon); return register(actual);
  }};
  host = await openInstalledRemoteHttpHost(options);
  await host!.close(); await host!.close(); host = undefined;
  await assert.rejects(openInstalledRemoteHttpHost(options), error =>
    (error as Error).message === 'HTTPOriginalInstallationReused' || ((error as Error).cause as Error | undefined)?.message === 'HTTPOriginalInstallationReused');
  assert.equal(callbacks, 2);
  completed = true;
} finally {
  if (host !== undefined) await host.close();
  if (completed) await rm(root, {recursive:true,force:true});
  else console.error(`HTTP Host failure namespace retained: ${root}`);
}
console.log(JSON.stringify({callbacks,hostClosed:true,providerCalls:0,coreScopes:0,
  normalNumericProfile:null,publicE2E:0}));
