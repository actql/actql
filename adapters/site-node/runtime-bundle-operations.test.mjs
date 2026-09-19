import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {signRemoteRuntimeBundle} from
  './remote-bundle-signature.mjs';

const execute = promisify(execFile);
const control = runtimeCore(moon).remoteBundleControl;

test('bundle CLI installs updates rolls back and reclaims durably',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-bundle-cli-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const keys = generateKeyPairSync('ed25519');
    const component = Buffer.from('runtime-component', 'utf8');
    const componentPath = join(root, 'component');
    const publicKeyPath = join(root, 'bundle-public.pem');
    const configurationPath = join(root, 'configuration.json');
    const envelopePath = join(root, 'bundle.json');
    const manifest = control.prepare({
      issuerAuthority: 'bundle-authority-a',
      bundleName: 'site-runtime',
      revision: '1',
      targetTriple: 'test-native-target',
      componentCid: `sha256:${createHash('sha256')
        .update(component).digest('hex')}`,
      componentBytes: BigInt(component.byteLength),
      connectorRegistration: 'local',
      connectorRevision: 'local/1',
      strategyRevision: 'strategy/1',
    });
    const runtimeBundleCid = control.identity(manifest);
    const envelope = signRemoteRuntimeBundle(manifest, control, {
      keyId: 'key-a',
      privateKey: keys.privateKey,
    });
    await Promise.all([
      writeFile(componentPath, component, {mode: 0o600}),
      writeFile(
        publicKeyPath,
        keys.publicKey.export({type: 'spki', format: 'pem'}),
        {mode: 0o600},
      ),
      writeFile(envelopePath, JSON.stringify(envelope), {mode: 0o600}),
      writeFile(configurationPath, JSON.stringify({
        storeRoot: join(root, 'store'),
        targetTriple: 'test-native-target',
        maxBundles: 4,
        maxOwners: 4,
        maxComponentBytes: '1024',
        authorities: [{
          authority: 'bundle-authority-a',
          keyId: 'key-a',
          publicKeyPath,
        }],
      }), {mode: 0o600}),
    ]);
    const cli = new URL('./runtime-bundle-cli.mjs', import.meta.url);
    const run = async (...arguments_) => {
      const {stdout} = await execute(process.execPath, [
        cli.pathname,
        configurationPath,
        ...arguments_,
      ]);
      return JSON.parse(stdout);
    };

    assert.deepEqual(
      (await run('install', envelopePath, componentPath)).state,
      ['0', '0', '0'],
    );
    assert.deepEqual(
      (await run('activate', runtimeBundleCid)).state,
      ['1', '1', '0'],
    );
    assert.equal((await run('active')).runtimeBundleCid, runtimeBundleCid);
    assert.deepEqual(
      (await run('drain', runtimeBundleCid)).state,
      ['2', '2', '0'],
    );
    assert.equal(await run('active'), null);
    assert.deepEqual(
      (await run('rollback', runtimeBundleCid)).state,
      ['3', '1', '0'],
    );
    assert.deepEqual(
      (await run('drain', runtimeBundleCid)).state,
      ['4', '2', '0'],
    );
    assert.deepEqual(
      (await run('reclaim', runtimeBundleCid)).state,
      ['5', '3', '0'],
    );
    assert.deepEqual(
      (await run('reclaim', runtimeBundleCid)).state,
      ['5', '3', '0'],
    );
  });
