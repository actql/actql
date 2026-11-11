// The existing independent opaque-component fixture used by Native recovery.
// Its target is a contract fixture, not a platform executable to be launched.
import {createHash, generateKeyPairSync, sign} from 'node:crypto';

export function nativeCompletedRestorationBundle() {
  const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  const component = Buffer.from('native-runtime');
  const target = 'aarch64-apple-darwin';
  // Independently authored canonical fixture, admitted and verified by Native.
  // Its target matches the opaque test component; no platform executable is run.
  const body = JSON.stringify({
    bundle_name: 'native-runtime',
    components: [{bytes: String(component.length), cid: hash(component),
      role: 'runtime_executable'}],
    connector_registration: 'local',
    connector_revision: 'local/1',
    issuer_authority: 'bundle-authority-a',
    revision: 'native/1',
    strategy_revision: 'strategy/1',
    target_triple: target,
    version: 'actql-remote-runtime-bundle/0.1',
  });
  const cid = hash(body);
  const keys = generateKeyPairSync('ed25519');
  const signature = sign(null, Buffer.from(
    `actql-remote-runtime-bundle-signature/0.1\0${cid}\0${body}`,
  ), keys.privateKey).toString('base64url');
  return {
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: target,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
      keys.publicKey.export({type: 'spki', format: 'pem'}),
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: body,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: cid,
    ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: signature,
  };
}
