// Source preparation for the existing two/three-implementation check only.
// This copies no runtime, chooses no compiler targets and supplies no ports.
import assert from 'node:assert/strict';
import {copyFileSync, lstatSync, mkdirSync, readFileSync, readdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {createHash} from 'node:crypto';
import type {BinaryLike} from 'node:crypto';

// Repository-local includes of the SQLite and Host bootstrap stubs, including
// the platform arms of the allocator source that bootstrap includes directly.
export const connectorAdditionNativeSourcePaths = Object.freeze([
  'packages/python-local-runtime/native/pre-root/owned_capacity.c',
  'packages/python-local-runtime/native/pre-root/owned_capacity.h',
  'packages/python-local-runtime/native/pre-root/owned_domain_borrow.h',
  'packages/python-local-runtime/native/pre-root/owned_domain_borrow.inc',
  'packages/python-local-runtime/native/pre-root/owned_domain_growth.inc',
  'packages/python-local-runtime/native/pre-root/owned_inventory.inc',
  'packages/python-local-runtime/native/pre-root/owned_linux_x64_bundle_profile.h',
  'packages/python-local-runtime/native/pre-root/owned_linux_x64_process_profile.h',
  'packages/python-local-runtime/native/pre-root/owned_region.h',
  'packages/python-local-runtime/native/pre-root/owned_region.inc',
  'packages/python-local-runtime/native/pre-root/owned_rust_heap.inc',
  'packages/python-local-runtime/native/pre-root/owned_thread.h',
  'packages/python-local-runtime/native/pre-root/owned_thread.inc',
  'packages/python-local-runtime/native/sqlite-component/api.h',
  'packages/python-local-runtime/native/sqlite-component/component.h',
]);

const originalPaths = Object.freeze([
  'src/connectors_builtin/local_carrier_dispatch.mbt',
  'src/connectors_builtin_node/local_carrier_bridge.mbt',
  'src/connectors_builtin_node/authorization_bridge.mbt',
]);
type OriginalInput = Readonly<{path: string; mode: number; digest: string}>;
const digest = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');

export function copyConnectorAdditionHostSource(root: string, destination: string) {
  const nodePackage = 'src/connectors_builtin_node';
  // Preserve the owning package's complete production source unit. Only the
  // assembly-owned bridge is regenerated here; other generated DATA is input.
  // Moon still owns target selection and checks every retained declaration.
  const nodeSources = readdirSync(join(root,nodePackage)).filter(name =>
    name.endsWith('.mbt') && !/_(?:wb)?test\.mbt$/u.test(name) &&
    name !== 'bridge.generated.mbt').sort().map(name => nodePackage+'/'+name);
  const paths = [...new Set([...originalPaths, ...connectorAdditionNativeSourcePaths, ...nodeSources,
    nodePackage+'/client-program-dependencies.json',
    nodePackage+'/client-execution-dependencies.json'])];
  const inputs = paths.map(path => {
    const source = join(root,path), state = lstatSync(source);
    assert(state.isFile() && !state.isSymbolicLink(),'Nonregular common Host source');
    const bytes = readFileSync(source);
    const target = join(destination,path);
    mkdirSync(dirname(target),{recursive:true});
    copyFileSync(source,target);
    return Object.freeze({path,mode:state.mode & 0o777,digest:digest(bytes)});
  });
  assertConnectorAdditionHostSource(destination,inputs);
  return Object.freeze(inputs);
}

export function assertConnectorAdditionHostSource(root: string, inputs: readonly OriginalInput[]) {
  for (const {path,mode,digest:expected} of inputs) {
    const source = join(root,path), state = lstatSync(source);
    assert(state.isFile() && !state.isSymbolicLink(),'Nonregular retained common Host source');
    assert.equal(state.mode & 0o777,mode,'Changed retained common Host source mode');
    assert.equal(digest(readFileSync(source)),expected,'Changed retained common Host source bytes');
  }
}
