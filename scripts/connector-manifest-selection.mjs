// A selection names Connectors, not a promise that each has every role.
// Read only declared manifest paths here; each role's existing checker owns
// its contents. Unselected manifests are never parsed or imported.
import {existsSync, readdirSync} from 'node:fs';
import {join} from 'node:path';

const identifier = value => typeof value === 'string' && /^[a-z][a-z0-9_]*$/.test(value);
const roles = ['compute', 'node', 'host'];

export function connectorManifestSelection(root, {names} = {}) {
  if (names !== undefined && (!Array.isArray(names) ||
      new Set(names).size !== names.length || !names.every(identifier))) {
    throw new Error('Invalid explicit Connector composition');
  }
  const entries = [];
  for (const name of readdirSync(join(root, 'src/connectors')).sort()) {
    if (names !== undefined && !names.includes(name)) continue;
    const paths = Object.fromEntries(roles.flatMap(role => {
      const path = join(root, 'src/connectors', name, `${role}-bundle.json`);
      return existsSync(path) ? [[role, path]] : [];
    }));
    if (Object.keys(paths).length === 0) continue;
    if (!identifier(name)) throw new Error('Invalid Connector manifest name');
    entries.push(Object.freeze({name, ...paths}));
  }
  if (names !== undefined && entries.length !== names.length) {
    throw new Error('Missing selected Connector manifest');
  }
  return Object.freeze(entries);
}
