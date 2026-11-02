// Authorization/driver/native composition fixture. Run and Content are explicit
// domain ports, not fabricated Core tokens or evidence of managed STORE funding.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {mkdir, mkdtemp} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonicalJson} from '../../../../../packages/sdk/host-port.mjs';
import {createLocalFileStoreDriver, LOCAL_STORE_LIMITS} from '../../host/installed-project-file-effects.mjs';
const root = fileURLToPath(new URL('../../../../../', import.meta.url));
const cid = digit => 'sha256:' + digit.repeat(64);
const wire = value => canonicalJson(value, {dataKeys: true});
let native;
export async function nativeFiles() {
  if (native) return native;
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  await mkdir(join(root, '_build'), {recursive: true});
  const scratch = await mkdtemp(join(root, '_build/local-authorization-native-'));
  const binary = join(scratch, 'fault.node');
  const result = spawnSync('/usr/bin/gcc', ['-std=c11', '-D_GNU_SOURCE', '-Wall', '-Wextra', '-Werror',
    '-O0', '-g', '-shared', '-fPIC', '-DNAPI_VERSION=8', '-DNODE_GYP_MODULE_NAME=actql_files',
    '-I', resolve(dirname(process.execPath), '../include/node'),
    join(root, 'adapters/host-node/native/fixtures/local-files-linux-publish-fault.c'), '-o', binary],
  {encoding: 'utf8', timeout: 30000});
  assert.ifError(result.error); assert.equal(result.status, 0, result.stderr);
  return native = createRequire(import.meta.url)(binary);
}
export async function physicalLocal(t, authorization, {subjectCid = cid('4'), fault = 0} = {}) {
  const module = await nativeFiles(); module.select(fault);
  const directory = await mkdtemp(join(root, '_build/local-authorization-write-'));
  // Retain every fixture, including Unknown, for inspection; no replay cleanup.
  t.diagnostic(`Local authorization filesystem evidence: ${directory}`);
  const run = Object.freeze({domainPort: 'Run'}), binding = Object.freeze({domainPort: 'Content'});
  const storage = Object.freeze({domainPort: 'selected storage'});
  const bytes = Buffer.from('exact authorized bytes\n');
  const resource = {$actql_ref: 'resource', version: 'actql-resource-ref/0.1', provider_namespace: 'local',
    resource_kind: 'file_collection', provider_identity_cid: cid('a'), authority_scope_cid: cid('b'),
    boundary_cid: cid('c'), identity_cid: cid('d')};
  const content = {$actql_ref: 'content', identity_cid: cid('e')};
  const command = {command_id: 'command:local.local.files.store.v1', contract_cid: cid('f')};
  const member = {kind: 'command', resource: 'files', command: {
    commandRef: command.command_id, commandCid: command.contract_cid}};
  const limits = {...LOCAL_STORE_LIMITS, maxFileBytes: 1024};
  let live = true, nativeCalls = 0, reads = 0;
  const current = original => {assert.strictEqual(original, run); assert.equal(live, true);};
  const nativeFilesystem = Object.freeze(Object.fromEntries(Object.keys(module.operations).map(name =>
    [name, (...args) => {nativeCalls++; return module.operations[name](...args);}])));
  const contentOwner = Object.freeze({storageForContent(selected) {
    assert.strictEqual(selected, binding); return storage;
  }, storageCurrentForContent(selected, token) {
    return selected === storage && token === binding && live;
  }, consumeContent(selected, accept) {
    assert.strictEqual(selected, binding); assert.equal(live, true); reads++; accept(bytes);
  }});
  const {driver, site} = createLocalFileStoreDriver({entry: {connection: 'local', rootPath: directory,
    limits: {maxPathBytes: 1024}}, target: {resourceWire: wire(resource)}, command, bindingCid: cid('1'),
    principalId: 'owner', authorization, assertCurrent() {}, limits, nativeFilesystem,
    resources: {assertCurrent: current, limits(original) {current(original); return limits;}}});
  const selected = driver.describe({member, runOriginal: run, runInvocationCid: cid('2'), dispatchRequestCid: cid('3')});
  const child = driver.prepareRequestChild({member, runOriginal: run,
    value: {path: 'result.txt', content}, selector: resource, current: selected,
    content: () => ({binding, current: () => live, wire: () => wire(content)}), contentOwner});
  const prepared = child.prepare();
  t.after(async () => {assert.equal(await child.release(), true); await site.close();});
  const grant = (decision, changes = {}) => site.issueEffectGrant({operation: 'files.write', resource: 'files',
    runInvocationCid: cid('2'), dispatchRequestCid: cid('3'), subjectCid, decision, ...changes});
  return {directory, bytes, driver, site, run, member, prepared, selected, grant,
    send(permission, changes = {}) {return driver.send({member, request: prepared.request, current: selected,
      authorization: {...permission, useId: 'original-use'}, runOriginal: run, ...changes});},
    async rejectForeignTarget() {
      const foreign = driver.prepareRequestChild({member, runOriginal: run,
        value: {path: 'foreign.txt', content}, selector: {...resource, identity_cid: cid('9')}, current: selected,
        content: () => ({binding, current: () => live, wire: () => wire(content)}), contentOwner});
      try {assert.throws(() => foreign.prepare(), {code: 'InvalidLocalStoreRequest'});}
      finally {assert.equal(await foreign.release(), true);}
    },
    nativeCalls: () => nativeCalls, reads: () => reads, renames: () => module.renames(),
    retire() {live = false;}};
}
