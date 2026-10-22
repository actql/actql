import {constants} from 'node:fs';
import {lstat, mkdir, open, opendir, rename} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {readBoundedConfigurationText, withOriginalFile} from './source-profile-json.mjs';
import {assertHostJournalDirectoryInspector, inspectHostJournalDirectoryFirstEntry}
  from './host-journal-directory.mjs';
import {assertOriginalPreparedLocalPublicationStoreOwnership} from '../store-local/publication-store.mjs';

const markerName = 'host-format.json';
const markerBytes = Buffer.from(JSON.stringify({
  version: 'actql-local-host-root/0.1',
  isolation: 'execution-namespace',
}), 'utf8');
const markerMaximumBytes = 4096;
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
function validAccountAdoption(value) {
  return exact(value, ['record_id', 'account_id', 'configuration_cid', 'initialization_cid',
    'subject_cid', 'profile']) && [value.record_id, value.account_id].every(text =>
    typeof text === 'string' && text.length > 0 && text.length <= 128) &&
    [value.configuration_cid, value.initialization_cid, value.subject_cid].every(cid) &&
    exact(value.profile, ['profile_id', 'profile_version', 'profile_cid']) &&
    value.profile.profile_id === 'actql-local-standard' &&
    value.profile.profile_version === '0.1' && cid(value.profile.profile_cid);
}
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
  if (!state.isFile() || state.isSymbolicLink() || state.size > markerMaximumBytes) {
    throw formatError('UnsupportedHostRootFormat', root);
  }
  let text;
  try { text = await readBoundedConfigurationText(path, {maxBytes: markerMaximumBytes}); }
  catch (cause) {
    if (cause?.message === 'InvalidInstalledSourceProfile' && !cause.cleanupPending) {
      throw formatError('UnsupportedHostRootFormat', root);
    }
    throw cause;
  }
  if (text === markerBytes.toString('utf8')) return JSON.parse(text);
  let value;
  try { value = JSON.parse(text); } catch { throw formatError('UnsupportedHostRootFormat', root); }
  if (!exact(value, ['version', 'isolation', 'account_bootstrap']) ||
      value.version !== 'actql-local-host-root/0.1' || value.isolation !== 'execution-namespace' ||
      !validAccountAdoption(value.account_bootstrap)) throw formatError('UnsupportedHostRootFormat', root);
  return value;
}

// A durable selection record in the existing Host format, not an Account
// permit. The same Store exclusion guards first adoption and its confirmation.
// Keeping it outside the configuration directory detects missing adopted
// files. Its absence is NOT first-initialization authority: the initializer
// separately needs actual fresh creation or its same saved pending intent.
export async function readHostRootAccountAdoption(root, preparedOriginal) {
  assertOriginalPreparedLocalPublicationStoreOwnership(preparedOriginal, join(root, 'publication'));
  const marker = await admitMarker(root);
  assertOriginalPreparedLocalPublicationStoreOwnership(preparedOriginal, join(root, 'publication'));
  return marker.account_bootstrap;
}

export async function adoptHostRootAccount(root, preparedOriginal, supplied) {
  assertOriginalPreparedLocalPublicationStoreOwnership(preparedOriginal, join(root, 'publication'));
  if (!validAccountAdoption(supplied)) throw formatError('InvalidHostAccountAdoption', root);
  const record = {...supplied, profile: {...supplied.profile}};
  const marker = await admitMarker(root);
  const assertCurrent = () => assertOriginalPreparedLocalPublicationStoreOwnership(
    preparedOriginal, join(root, 'publication'));
  assertCurrent();
  if (marker.account_bootstrap !== undefined &&
      JSON.stringify(marker.account_bootstrap) !== JSON.stringify(record)) {
    throw formatError('HostAccountAdoptionConflict', root);
  }
  if (marker.account_bootstrap === undefined) {
    const temporary = join(root, `.account-adoption-${randomUUID()}`);
    const bytes = Buffer.from(JSON.stringify({...marker, account_bootstrap: record}), 'utf8');
    if (bytes.byteLength > markerMaximumBytes) throw formatError('InvalidHostAccountAdoption', root);
    // The existing original-file owner retains a failed close. Uncertain
    // initialization never deletes or replays that original policy material.
    await withOriginalFile(temporary, path => open(path,
      constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600), async original => {
      assertCurrent();
      await original.writeFile(bytes);
      await original.sync();
      assertCurrent();
    });
    assertCurrent();
    await rename(temporary, join(root, markerName));
  }
  // Also confirm the same visible record after a previous uncertain commit.
  await withOriginalFile(root, path => open(path, constants.O_RDONLY), original => original.sync());
  const confirmed = await admitMarker(root);
  assertCurrent();
  if (JSON.stringify(confirmed.account_bootstrap) !== JSON.stringify(record)) {
    throw formatError('HostAccountAdoptionConflict', root);
  }
  return Object.freeze({...record, profile: Object.freeze({...record.profile})});
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
