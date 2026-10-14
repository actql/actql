// Private formal-package metadata. This module neither opens product files nor
// constructs a physical witness, grants authority or issues a contract CID.
import assert from 'node:assert/strict';
import {dirname, join} from 'node:path';

export const PRODUCT_MEMBERS_FILE = 'local-product-members.json';
const component = /^[A-Za-z0-9_.-]{1,128}$/u;
const exact = (value, names) => {
  assert(value && typeof value === 'object' && !Array.isArray(value));
  assert.deepEqual(Object.keys(value).sort(), [...names].sort());
};
const parts = path => {
  assert.equal(typeof path, 'string');
  const result = path.split('/');
  // The formal CLI payload consists of root files and one-level directories.
  // Dependency placement is separately selected, not another payload subtree.
  assert(result.length <= 2);
  for (const part of result) assert(component.test(part) && part !== '.' && part !== '..');
  return result;
};
const selectors = value => {
  assert.match(value.sourceSha, /^[a-f0-9]{40}$/u);
  assert(['darwin-arm64', 'linux-x64-gnu'].includes(value.platform));
  assert(['actql', `@actql/cli-${value.platform}`].includes(value.packageName));
};

// The input entries are the existing formal inventory's path/bytes/mode/hash.
// Canonical private bytes bind metadata only; source labels need independent
// release/runtime correspondence and every member still needs physical checks.
export function productMembersBody(value) {
  exact(value, ['sourceSha', 'platform', 'packageName', 'files']);
  selectors(value);
  assert(Array.isArray(value.files) && value.files.length > 0);
  // Preserve the existing runtime intake ceilings. These are not funding.
  assert(5 + value.files.length * 5 <= 8192);
  let previous = '';
  const files = value.files.map(entry => {
    exact(entry, ['path', 'bytes', 'mode', 'sha256']);
    parts(entry.path);
    assert(entry.path !== PRODUCT_MEMBERS_FILE, 'The descriptor must not hash itself');
    assert(entry.path > previous, 'Formal inventory must have exact ordered unique paths');
    previous = entry.path;
    assert(Number.isSafeInteger(entry.bytes) && entry.bytes >= 0 && entry.bytes <= 67108864);
    assert(Number.isSafeInteger(entry.mode) && entry.mode >= 0 && entry.mode <= 0o777);
    assert.match(entry.sha256, /^[a-f0-9]{64}$/u);
    return {bytes: entry.bytes, mode: entry.mode, path: entry.path, sha256: entry.sha256};
  });
  const wire = JSON.stringify({files, packageName: value.packageName,
    platform: value.platform, sourceSha: value.sourceSha});
  assert(Buffer.byteLength(wire) <= 65536);
  return wire;
}

// Reject duplicates, alternate encodings and extra fields before returning
// metadata. The expected selectors are comparison inputs, not trusted permits.
export function readProductMembers(wire, expected) {
  assert.equal(typeof wire, 'string');
  assert(Buffer.byteLength(wire) <= 65536);
  exact(expected, ['sourceSha', 'platform', 'packageName']);
  selectors(expected);
  const value = JSON.parse(wire);
  assert.equal(productMembersBody(value), wire);
  for (const field of ['sourceSha', 'platform', 'packageName']) assert.equal(value[field], expected[field]);
  return value;
}

// Derived bounded census inputs only. No arbitrary directory names are read or
// retained here. The descriptor's one self-hash exception is still a required
// file, whose bytes/generation/digest must be verified by the physical Owner.
export function productMembersCensus(value) {
  const descriptor = JSON.parse(productMembersBody(value));
  const directories = new Map([['', new Map([[PRODUCT_MEMBERS_FILE, 'file']])]]);
  for (const entry of descriptor.files) {
    const names = parts(entry.path);
    let parent = '';
    for (let index = 0; index < names.length; index++) {
      const name = names[index], kind = index + 1 === names.length ? 'file' : 'directory';
      const entries = directories.get(parent), existing = entries.get(name);
      assert(existing === undefined || existing === kind, 'A file cannot also be a directory');
      entries.set(name, kind);
      if (kind === 'directory') {
        parent = name;
        if (!directories.has(parent)) directories.set(parent, new Map());
      }
    }
  }
  return [...directories].map(([path, entries]) => ({path,
    entries: [...entries].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
      .map(([name, kind]) => ({name, kind}))}));
}

const absolute = path => {
  assert.equal(typeof path, 'string');
  assert(path.startsWith('/') && !path.endsWith('/') && !path.includes('//') && !path.includes('\0'));
  assert(!path.split('/').some(v => v === '.' || v === '..'));
};

// Compare the existing launcher's exact selected optional package location.
// These strings do not authenticate a Root, permit node_modules generally or
// verify a symlink. Physical OriginalRoots must independently establish them.
export function selectedPlatformPlacement(launcherRoot, platformRoot, platform) {
  absolute(launcherRoot);
  absolute(platformRoot);
  assert(['darwin-arm64', 'linux-x64-gnu'].includes(platform));
  assert(launcherRoot.endsWith('/actql'));
  const child = `cli-${platform}`;
  if (platformRoot === join(dirname(launcherRoot), '@actql', child)) {
    return {layout: 'hoisted', route: []};
  }
  assert.equal(platformRoot, join(launcherRoot, 'node_modules', '@actql', child));
  return {layout: 'nested', route: ['node_modules', '@actql', child]};
}

// Closed expected membership for the selected installed pair only. No file is
// opened and no OriginalRoot/witness is constructed. In the nested layout the
// dependency route is checked separately from the platform payload Root; it is
// not an exemption for arbitrary node_modules content or another package.
export function installedProductCensus(launcher, platform, launcherRoot, platformRoot) {
  const launcherValue = JSON.parse(productMembersBody(launcher));
  const platformValue = JSON.parse(productMembersBody(platform));
  assert.equal(launcherValue.packageName, 'actql');
  assert.equal(platformValue.packageName, `@actql/cli-${launcherValue.platform}`);
  assert.equal(platformValue.platform, launcherValue.platform);
  assert.equal(platformValue.sourceSha, launcherValue.sourceSha);
  const placement = selectedPlatformPlacement(launcherRoot, platformRoot, launcherValue.platform);
  const directories = productMembersCensus(launcherValue);
  if (placement.layout === 'nested') {
    const entries = directories[0].entries;
    assert(!entries.some(entry => entry.name === 'node_modules'),
      'Dependency placement cannot replace a declared payload member');
    entries.push({name: 'node_modules', kind: 'directory'});
    entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    directories.push({path: 'node_modules', entries: [{name: '@actql', kind: 'directory'}]},
      {path: 'node_modules/@actql', entries: [{name: `cli-${launcherValue.platform}`, kind: 'directory'}]});
  }
  return {layout: placement.layout,
    launcher: {root: launcherRoot, directories},
    platform: {root: platformRoot, directories: productMembersCensus(platformValue)}};
}
