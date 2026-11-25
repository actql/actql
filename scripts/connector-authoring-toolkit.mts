import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {lstat} from 'node:fs/promises';
import {basename, dirname, join, resolve} from 'node:path';
import {inventory} from './package-inventory.mjs';

export const authoringToolkitPath = '_build/connector-authoring';
export const authoringBinPath = authoringToolkitPath + '/scripts/connector.mjs';

export function isInstalledAuthoringToolkit(root: string) {
  root = resolve(root);
  const packageRoot = dirname(dirname(root));
  if (join(packageRoot, authoringToolkitPath) !== root) return false;
  const manifest = JSON.parse(readFileSync(join(packageRoot, 'package.json'), 'utf8'));
  assert.equal(manifest.name, '@actql/local-node');
  assert.equal(manifest.bin?.['actql-connector'], authoringBinPath);
  return true;
}

// Use the authoritative selected tarball inventory. Nothing inside the
// toolkit can assert that its own bytes or source are the selected ones.
type InventoryEntry = Awaited<ReturnType<typeof inventory>>[number];
type ToolkitManifest = Readonly<{sourceSha: string; sourceTree: string;
  packages: readonly Readonly<{name: string; sha256: string; files: readonly InventoryEntry[]}>[]}>;

export async function observeInstalledAuthoringToolkit(root: string, {manifest}: Readonly<{manifest: ToolkitManifest}>) {
  assert(isInstalledAuthoringToolkit(root));
  const info = await lstat(root);
  assert(info.isDirectory(), 'Installed REST authoring toolkit must be a real directory');
  const host = manifest.packages.find(pkg => pkg.name === '@actql/local-node');
  const prefix = authoringToolkitPath + '/';
  const expected = host!.files.filter(file => file.path.startsWith(prefix))
    .map(file => ({...file, path: file.path.slice(prefix.length)}));
  assert(expected.some(file => file.path === 'scripts/connector.mjs' && (file.mode & 0o111) !== 0),
    'Selected normal Local Host does not include the authoring toolkit');
  const sort = (files: readonly InventoryEntry[]) => files.toSorted((left, right) => left.path.localeCompare(right.path));
  assert.deepEqual(sort(await inventory(root)), sort(expected), 'Installed REST authoring toolkit payload mismatch');
  return {source: manifest.sourceSha, tree: manifest.sourceTree, package: host!.name,
    sha256: host!.sha256, files: expected.length};
}
