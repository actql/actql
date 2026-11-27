import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {packedClientPackage} from '../../scripts/packed-client-packages.mjs';

// The actual tarball supplies the package report. A standalone run still
// executes normal prepack, whose diagnostics can surround npm's JSON output.
export async function packSdkFixture({name, repository, destination, run, shared}: {
  name: string;
  repository: string;
  destination: string;
  run: (command: string, args: readonly string[], cwd?: string) => string;
  shared?: string;
}) {
  const directory = join(repository, 'packages', name);
  const original = readFileSync(join(directory, 'package.json'), 'utf8');
  const manifest = JSON.parse(original) as {name: string; version: string};
  assert.equal(manifest.name, `@actql/${name}`);
  assert.match(manifest.version, /^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$/u);
  const filename = `actql-${name}-${manifest.version}.tgz`;
  await packedClientPackage({repository, name, destination, shared, pack() {
    run('npm', ['pack', '--json', '--cache', destination,
      '--pack-destination', destination], directory);
  }});
  const archive = join(destination, filename);
  const info = lstatSync(archive);
  assert(info.isFile() && !info.isSymbolicLink() && info.size > 0);
  const members = run('tar', ['-tf', archive]).trimEnd().split('\n');
  assert.equal(new Set(members).size, members.length);
  assert(members.every(path => path.startsWith('package/') &&
    !/[\u0000-\u001f\u007f]/u.test(path) &&
    !path.split('/').some(part => part === '.' || part === '..')));
  const kinds = run('tar', ['-tvf', archive]).trimEnd().split('\n');
  assert.equal(kinds.length, members.length);
  assert(kinds.every(line => line.startsWith('-') || line.startsWith('d')));
  const files = members.filter(path => !path.endsWith('/'));
  assert.equal(files.filter(path => path === 'package/package.json').length, 1);
  assert.equal(run('tar', ['-xOf', archive, 'package/package.json']), original);
  const bytes = readFileSync(archive);
  return {name: manifest.name, filename,
    shasum: createHash('sha1').update(bytes).digest('hex'),
    integrity: 'sha512-' + createHash('sha512').update(bytes).digest('base64'),
    files: files.map(path => ({path: path.slice('package/'.length)}))};
}
