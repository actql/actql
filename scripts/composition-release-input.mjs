// The existing composition consumer can admit a normal release without packing
// development artifacts or changing its authored Source/Model/Effect fixtures.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute, join, relative, resolve} from 'node:path';
import {checkoutState} from './packed-client-packages.mjs';
import {verifyPackageRelease} from './package-release.mjs';

const sha256 = value => createHash('sha256').update(value).digest('hex');

export function compositionReleaseDirectory(argv) {
  assert(!argv.some(value => value.startsWith('--release-dir') && value !== '--release-dir'),
    'Use --release-dir followed by its absolute directory');
  const positions = argv.flatMap((value, index) => value === '--release-dir' ? [index] : []);
  assert(positions.length <= 1, 'Supply at most one normal release directory');
  if (positions.length === 0) return undefined;
  const directory = argv[positions[0] + 1];
  assert(typeof directory === 'string' && isAbsolute(directory),
    '--release-dir requires an absolute normal release directory');
  return resolve(directory);
}

export async function admitCompositionRelease({repository, directory}) {
  assert(isAbsolute(directory));
  assert(relative(resolve(repository), resolve(directory)).startsWith('../'),
    'Normal release artifacts must remain outside the source checkout');
  const source = checkoutState(repository);
  assert(source.clean, 'Composition release consumer needs clean source');
  const manifestWire = await readFile(join(directory, 'release.json'));
  const manifest = await verifyPackageRelease(directory);
  assert.equal(manifest.sourceSha, source.revision,
    'Composition consumer and release must use the same source');
  assert.equal(manifest.generation, 'normal-prepack-then-metadata-and-license-only');
  assert.deepEqual(manifest.cohort.packages, ['client-wire', 'sdk', 'local-node', 'node']);
  const manifestSha256 = sha256(manifestWire);
  return {
    directory, manifest, manifestSha256,
    archives: manifest.packages.map(item => join(directory, item.file)),
    async verifyUnchanged() {
      assert.deepEqual(checkoutState(repository), source,
        'Composition source changed during installed acceptance');
      assert.equal(sha256(await readFile(join(directory, 'release.json'))), manifestSha256,
        'Original release manifest changed during acceptance');
      assert.deepEqual(await verifyPackageRelease(directory), manifest,
        'Original release artifacts changed during acceptance');
    },
  };
}
