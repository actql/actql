import {constants} from 'node:fs';
import {lstat, mkdir, open, readFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';

const markerName = 'host-format.json';
const markerBytes = Buffer.from(JSON.stringify({
  version: 'actql-local-host-root/0.1',
  isolation: 'execution-namespace',
}), 'utf8');
const legacyEntries = new Set([
  'requests', 'checkpoints', 'publication', 'state',
]);

function formatError(code, root) {
  return Object.assign(new Error(code), {code, root});
}

async function entryNames(root) {
  try {
    const state = await lstat(root);
    if (!state.isDirectory() || state.isSymbolicLink()) {
      throw formatError('UnknownHostRootFormat', root);
    }
    return await readdir(root);
  } catch (error) {
    if (error?.code === 'ENOENT') return undefined;
    throw error;
  }
}

async function admitMarker(root) {
  const path = join(root, markerName);
  let state;
  try { state = await lstat(path); }
  catch (error) {
    if (error?.code === 'ENOENT') {
      throw formatError('UnknownHostRootFormat', root);
    }
    throw error;
  }
  if (!state.isFile() || state.size !== markerBytes.byteLength ||
      !(await readFile(path)).equals(markerBytes)) {
    throw formatError('UnsupportedHostRootFormat', root);
  }
}

export async function admitHostRootFormat(root) {
  let names = await entryNames(root);
  if (names?.includes(markerName)) {
    await admitMarker(root);
    return 'current';
  }
  if (names !== undefined && names.length > 0) {
    const legacy = names.some(name => legacyEntries.has(name));
    throw formatError(legacy ? 'LegacyHostRootFormat' :
      'UnknownHostRootFormat', root);
  }

  // The root is absent or empty. A second read keeps existing, unmarked
  // content from being mistaken for a fresh installation before the marker.
  await mkdir(root, {recursive: true, mode: 0o700});
  names = await entryNames(root);
  if (names === undefined || names.length > 0) {
    throw formatError('UnknownHostRootFormat', root);
  }
  const markerPath = join(root, markerName);
  let handle;
  try {
    handle = await open(markerPath, constants.O_CREAT | constants.O_EXCL |
      constants.O_WRONLY, 0o600);
    await handle.writeFile(markerBytes);
    await handle.sync();
  } catch (error) {
    if (error?.code === 'EEXIST') {
      await admitMarker(root);
      return 'current';
    }
    throw error;
  } finally {
    await handle?.close();
  }
  return 'new';
}
