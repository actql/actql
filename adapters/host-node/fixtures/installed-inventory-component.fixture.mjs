// Inventory DATA controls use the actual folds and funded Environment owner.
// The explicit member-load port does not qualify module initialization: these
// fixtures deliberately return malformed publication metadata. Genuine bound
// factory/context controls exercise that separate boundary in loader tests.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {writeFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {parse} from 'acorn';
import {createInstalledLoaderParent} from './installed-loader-parent.fixture.mjs';
import {createInstalledHostServices, installedSourceConfigurationReader,
  installedSourceEnvironmentConstructionReader} from '../installed-host-services.mjs';
import {composeInstalledSourceEnvironment, composeInstalledInventoryEnvironment} from '../installed-funded-environment.mjs';
import {verifyInstalledConnectorBindings} from '../installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from '../installed-host-cleanup.mjs';
import {captureSourceAliasConstruction, sourceAliasCollectionConstructionGeometry}
  from '../source-alias-construction.mjs';
import {MAX_INSTALLED_SOURCE_AUTHORITIES} from '../installed-source-limits.mjs';
import {installedSourceReadBindings} from '../installed-source.mjs';
import {composeInstalledEffects} from '../installed-effect-inventory.mjs';

const source = readFileSync(new URL('../installed-source.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => {
  const nodes = tree.body.map(node => node.declaration ?? node)
    .filter(node => node.type === 'FunctionDeclaration' && node.id.name === name);
  assert.equal(nodes.length, 1, name); return source.slice(nodes[0].start, nodes[0].end);
};
// Match Node's ordinary realpath behavior for the copied loader's existing
// dependencies, including the nominal HostServices registry. Only its authored
// connector table remains relative to the isolated installation tree.
export async function copyInstalledInventoryLoader(from, to) {
  const body = readFileSync(from, 'utf8');
  const ast = parse(body, {ecmaVersion: 'latest', sourceType: 'module'});
  const imports = ast.body.filter(node => ['ImportDeclaration', 'ExportNamedDeclaration', 'ExportAllDeclaration'].includes(node.type) &&
    typeof node.source?.value === 'string' && node.source.value.startsWith('.') && node.source.value !== '../connectors-builtin/installations.generated.mjs');
  let copied = body;
  for (const node of imports.reverse()) copied = copied.slice(0, node.source.start) +
    JSON.stringify(new URL(node.source.value, from).href) + copied.slice(node.source.end);
  await writeFile(to, copied);
}

function sourceFold(loadInstalledSource) {
  const ports = {isAbsolute, MAX_INSTALLED_SOURCE_AUTHORITIES, loadInstalledSource,
    installedSourceReadBindings, installedSourceConfigurationReader, installedSourceEnvironmentConstructionReader,
    captureSourceAliasConstruction, sourceAliasCollectionConstructionGeometry,
    composeInstalledSourceEnvironment, composeInstalledInventoryEnvironment, verifyInstalledConnectorBindings, retainInstalledHostInitializationFailure};
  return Function(...Object.keys(ports), declaration('validPluralSourcePaths') + '\n' +
    declaration('loadInstalledSources') + '\nreturn loadInstalledSources;')(...Object.values(ports));
}

export function installedInventoryComponent(loader, authoredMembers, effectMember) {
  const parents = new Set();
  return Object.freeze({
    async close() {
      const errors = [];
      for (const parent of parents) {
        try {await parent.close(); parents.delete(parent);}
        catch (error) {errors.push(error);}
      }
      if (errors.length) throw new AggregateError(errors, 'InventoryComponentParentsCleanupPending');
    },
    async load(role, paths, options) {
      // Each independent inventory attempt has its own original installer.
      // Cleanup retries retain that SAME parent through the returned handle.
      const parent = createInstalledLoaderParent(options);
      parents.add(parent); parent.open();
      const memberServices = createInstalledHostServices({...options, assertCurrent() {
        installedSourceEnvironmentConstructionReader(parent.services, options.moon);
      }});
      const member = async (path, captured, retain) => {
        if (role === 'effect' && effectMember !== undefined) return effectMember(path, captured, retain);
        const before = role === 'source' ? new Set(authoredMembers.values()) : undefined;
        let value;
        try {
          value = await loader[role === 'source' ? 'loadInstalledSource' : 'loadInstalledEffect'](path,
            {...captured, installationServices: memberServices});
        } catch (cause) {
          // A component member port owns the adapter its authored constructor
          // returned before registration failed. It cannot register that
          // adapter or let a rejected return erase its actual cleanup duty.
          const acquired = before === undefined ? [] : [...authoredMembers.values()].filter(value => !before.has(value));
          assert(acquired.length <= 1);
          if (acquired.length) throw await retainInstalledHostInitializationFailure(cause, {sourceProfile: acquired[0]});
          throw cause;
        }
        retain?.(value); return value;
      };
      const fold = role === 'source' ? sourceFold(member) :
        (paths, captured) => composeInstalledEffects(paths, captured, member);
      return parent.load(fold, paths, {...options, installationServices: parent.services});
    },
  });
}
