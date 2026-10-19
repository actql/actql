import {constants} from 'node:fs';
import {lstat, mkdir, open, opendir} from 'node:fs/promises';
import {join} from 'node:path';
import {readBoundedConfigurationText, withOriginalFile} from './source-profile-json.mjs';
import {assertHostJournalDirectoryInspector, inspectHostJournalDirectoryFirstEntry}
  from './host-journal-directory.mjs';

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

async function firstEntry(root, openDirectory, directoryInspection) {
  try {
    const state = await lstat(root);
    if (!state.isDirectory() || state.isSymbolicLink()) {
      throw formatError('UnknownHostRootFormat', root);
    }
  } catch (error) {
    if (error?.code === 'ENOENT') return undefined;
    throw error;
  }
  if (directoryInspection !== undefined) {
    // The selected same-Root native original avoids stock Dir construction
    // and its platform-dependent prefetch. Its own failure/close carrier is
    // unchanged, never absence, fallback or permission to create a marker.
    return inspectHostJournalDirectoryFirstEntry(directoryInspection, root);
  }
  // Only emptiness is needed. Do not materialize an arbitrary directory and
  // count it afterward. Node's original Dir owns one buffered Dirent here;
  // the same captured close/receiver remains responsible across read await.
  let opened = false;
  try {
    return await withOriginalFile(root, async path => {
      const original = await openDirectory(path, {bufferSize: 1});
      opened = true;
      return original;
    }, original => original.read());
  } catch (cause) {
    if (!opened && cause?.code === 'ENOENT') return undefined;
    throw cause;
  }
}

async function entryExists(root, name) {
  try { await lstat(join(root, name)); return true; }
  catch (cause) { if (cause?.code === 'ENOENT') return false; throw cause; }
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
  if (!state.isFile() || state.size !== markerBytes.byteLength) {
    throw formatError('UnsupportedHostRootFormat', root);
  }
  let text;
  try { text = await readBoundedConfigurationText(path, {maxBytes: markerBytes.byteLength}); }
  catch (cause) {
    if (cause?.message === 'InvalidInstalledSourceProfile' && !cause.cleanupPending) {
      throw formatError('UnsupportedHostRootFormat', root);
    }
    throw cause;
  }
  if (text !== markerBytes.toString('utf8')) throw formatError('UnsupportedHostRootFormat', root);
}

export async function admitHostRootFormat(root, {openDirectory = opendir, directoryInspection} = {}) {
  if (directoryInspection !== undefined) assertHostJournalDirectoryInspector(directoryInspection, 1);
  let entry = await firstEntry(root, openDirectory, directoryInspection);
  // The closed format already gives the only names relevant to this choice.
  // A valid marker keeps priority even with unrelated or legacy entries; a
  // legacy name keeps priority over other unknown contents. No full listing
  // or new cardinality/language restriction is required to preserve that law.
  if (entry !== undefined && await entryExists(root, markerName)) {
    await admitMarker(root);
    return 'current';
  }
  if (entry !== undefined && entry !== null) {
    let legacy = false;
    for (const name of legacyEntries) {
      if (await entryExists(root, name)) { legacy = true; break; }
    }
    throw formatError(legacy ? 'LegacyHostRootFormat' :
      'UnknownHostRootFormat', root);
  }

  // The root is absent or empty. A second read keeps existing, unmarked
  // content from being mistaken for a fresh installation before the marker.
  await mkdir(root, {recursive: true, mode: 0o700});
  entry = await firstEntry(root, openDirectory, directoryInspection);
  if (entry !== null) {
    throw formatError('UnknownHostRootFormat', root);
  }
  const markerPath = join(root, markerName);
  try {
    await withOriginalFile(markerPath, path => open(path,
      constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600), async original => {
      await original.writeFile(markerBytes);
      await original.sync();
    });
  } catch (error) {
    if (error?.code === 'EEXIST') {
      await admitMarker(root);
      return 'current';
    }
    throw error;
  }
  await withOriginalFile(root, path => open(path, constants.O_RDONLY), original => original.sync());
  return 'new';
}
