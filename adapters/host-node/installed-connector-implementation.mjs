// Bounded content observation of the selected installation's declared files.
// This is not a capability grant, execution owner or reconciliation journal.
import {createHash} from 'node:crypto';
import {closeSync, constants, fstatSync, lstatSync, openSync, readSync, realpathSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';

const fail = code => { throw Object.assign(new TypeError(code), {code}); };
const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const maxBytes = 16 * 1024 * 1024;

function observe(entry) {
  if (!/^[a-z][a-z0-9_]*$/u.test(entry?.name ?? '') ||
      entry.registration !== entry.name || typeof entry.revision !== 'string' ||
      !Array.isArray(entry.implementationFiles) || entry.implementationFiles.length < 1 ||
      entry.implementationFiles.length > 128) fail('InvalidConnectorImplementationInventory');
  let remaining = maxBytes;
  const seen = new Set();
  const files = entry.implementationFiles.map(file => {
    const path = file?.path;
    if (typeof path !== 'string' || path.includes('\\') ||
        path.split('/').some(part => !part || part === '.' || part === '..') || seen.has(path) ||
        !(path.startsWith(`adapters/connectors/${entry.name}/`) && /\.(mjs|py|in|lock|md)$/u.test(path) ||
          path.startsWith(`src/connectors/${entry.name}/`) && path.endsWith('.json') ||
          new RegExp(`^spec/contracts/actql-${entry.name}-[a-z0-9-]+\\.json$`, 'u').test(path))) {
      fail('InvalidConnectorImplementationInventory');
    }
    seen.add(path);
    let url;
    try { url = new URL(file.href); } catch { fail('InvalidConnectorImplementationInventory'); }
    if (url.protocol !== 'file:' || url.search || url.hash) fail('InvalidConnectorImplementationInventory');
    const actual = fileURLToPath(url);
    if (!actual.endsWith(`/${path}`)) fail('InvalidConnectorImplementationInventory');
    const root = actual.slice(0, -path.length);
    const components = path.split('/');
    for (let index = 0; index < components.length - 1; index++) {
      // Validate every declared parent, not only the final file. System-level
      // aliases of the package root are not Connector-owned parent aliases.
      const parent = join(root, ...components.slice(0, index + 1));
      if (!lstatSync(parent).isDirectory()) fail('InvalidConnectorImplementationFile');
    }
    if (realpathSync(dirname(actual)) !== join(realpathSync(root), dirname(path))) {
      fail('InvalidConnectorImplementationFile');
    }
    let fd;
    try {
      // A replaced FIFO must not block before fstat can reject it. This flag
      // leaves regular-file reads unchanged on the supported Local platforms.
      fd = openSync(actual, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
      const before = fstatSync(fd);
      if (!before.isFile()) fail('InvalidConnectorImplementationFile');
      if (before.size > remaining) fail('ConnectorImplementationByteLimit');
      const bytes = Buffer.alloc(before.size);
      let read = 0;
      while (read < bytes.length) {
        const count = readSync(fd, bytes, read, bytes.length - read, null);
        if (count === 0) fail('ConnectorImplementationChangedDuringRead');
        read += count;
      }
      const extra = readSync(fd, Buffer.alloc(1), 0, 1, null), after = fstatSync(fd);
      if (extra !== 0 || after.size !== before.size ||
          after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) {
        fail('ConnectorImplementationChangedDuringRead');
      }
      remaining -= bytes.length;
      return {path, cid: cid(bytes)};
    } finally { if (fd !== undefined) closeSync(fd); }
  }).sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  return cid(canonicalJson({version: 'actql-installed-connector-implementation/0.1',
    registration: entry.registration, revision: entry.revision, files}, {dataKeys: true}));
}

export function captureInstalledConnectorImplementation(entry) {
  // Snapshot metadata as data. A caller cannot mutate the inventory after its
  // CID is included in an approved installation binding.
  const selected = Object.freeze({name: entry?.name, registration: entry?.registration,
    revision: entry?.revision, implementationFiles: Array.isArray(entry?.implementationFiles)
      ? Object.freeze(entry.implementationFiles.map(file => Object.freeze({...file}))) : undefined});
  const identity = observe(selected);
  return Object.freeze({identity,
    assertCurrent() {
      if (observe(selected) !== identity) fail('InstalledConnectorImplementationChanged');
    }});
}
