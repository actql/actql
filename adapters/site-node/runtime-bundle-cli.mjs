import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import process from 'node:process';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {runRuntimeBundleOperation} from
  './runtime-bundle-operations.mjs';
import {openRuntimeBundleStore} from './runtime-bundle-store.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};
const text = value => typeof value === 'string' && value.length > 0;

async function readConfiguration(path) {
  const value = JSON.parse(await readFile(path, 'utf8'));
  if (value === null || typeof value !== 'object' ||
      !text(value.storeRoot) || !text(value.targetTriple) ||
      !Array.isArray(value.authorities) || value.authorities.length === 0) {
    fail('InvalidRemoteBundleCliConfiguration');
  }
  const bundleAuthorities = new Map();
  for (const entry of value.authorities) {
    if (entry === null || typeof entry !== 'object' ||
        !text(entry.authority) || !text(entry.keyId) ||
        !text(entry.publicKeyPath)) {
      fail('InvalidRemoteBundleCliConfiguration');
    }
    let keys = bundleAuthorities.get(entry.authority);
    if (keys === undefined) {
      keys = new Map();
      bundleAuthorities.set(entry.authority, keys);
    }
    if (keys.has(entry.keyId)) fail('RemoteBundleCliAuthorityCollision');
    keys.set(entry.keyId, await readFile(entry.publicKeyPath));
  }
  return Object.freeze({
    storeRoot: value.storeRoot,
    options: Object.freeze({
      bundleAuthorities,
      targetTriple: value.targetTriple,
      ...(value.maxBundles === undefined
        ? {} : {maxBundles: Number(value.maxBundles)}),
      ...(value.maxOwners === undefined
        ? {} : {maxOwners: Number(value.maxOwners)}),
      ...(value.maxComponentBytes === undefined
        ? {} : {maxComponentBytes: BigInt(value.maxComponentBytes)}),
    }),
  });
}

async function parseOperation(arguments_) {
  const [kind, first, second] = arguments_;
  if (!text(kind)) fail('MissingRemoteBundleOperation');
  if (kind === 'install') {
    if (!text(first) || !text(second)) fail('InvalidRemoteBundleOperation');
    return Object.freeze({
      kind,
      envelope: JSON.parse(await readFile(first, 'utf8')),
      componentPath: second,
    });
  }
  if (kind === 'list' || kind === 'active' || kind === 'recover') {
    if (first !== undefined) fail('InvalidRemoteBundleOperation');
    return Object.freeze({kind});
  }
  if (!text(first) || second !== undefined) {
    fail('InvalidRemoteBundleOperation');
  }
  return Object.freeze({kind, runtimeBundleCid: first});
}

export async function main(arguments_ = process.argv.slice(2)) {
  const [configurationPath, ...operationArguments] = arguments_;
  if (!text(configurationPath)) fail('MissingRemoteBundleConfiguration');
  const configuration = await readConfiguration(configurationPath);
  const control = runtimeCore(moon).remoteBundleControl;
  const store = await openRuntimeBundleStore(
    configuration.storeRoot,
    configuration.options,
  );
  try {
    await store.recover(control);
    const result = await runRuntimeBundleOperation({
      store,
      control,
      operation: await parseOperation(operationArguments),
    });
    process.stdout.write(`${JSON.stringify(result ?? null)}\n`);
  } finally {
    store.close();
  }
}

if (process.argv[1] !== undefined &&
    import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
