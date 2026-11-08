// Adapt the existing exact-checkout packed input gate for an installed
// consumer. This neither packs a package nor manufactures release metadata.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, readFile} from 'node:fs/promises';
import {isAbsolute, join, resolve} from 'node:path';
import {CLIENT_PACKAGES, checkoutState, packedClientPackage} from './packed-client-packages.mjs';
import {inventory, unpack} from './package-release.mjs';

const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

export async function admitRecordApprovalCIInput({repository, destination}) {
  const directory = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  assert(typeof directory === 'string' && isAbsolute(directory),
    'CI record approval requires explicit ACTQL_PACKED_CLIENT_PACKAGES; no packing fallback');
  assert.notEqual(resolve(directory), resolve(destination), 'Retain original archives outside the copied input');
  const before = checkoutState(repository);
  assert(before.clean, 'CI record approval requires clean source');
  const manifestPath = join(directory, 'packed-client-packages.json');
  const wire = await readFile(manifestPath), manifest = JSON.parse(wire);
  assert.equal(manifest.revision, before.revision, 'CI record approval requires the exact packed source');
  assert.deepEqual(Object.keys(manifest.tarballs ?? {}).sort(), [...CLIENT_PACKAGES].sort(),
    'CI record approval requires the complete five-package input');
  await mkdir(destination, {recursive: true});
  const packages = [];
  for (const name of CLIENT_PACKAGES) {
    await packedClientPackage({repository, name, destination,
      pack() {throw new Error('RecordApprovalCannotProducePackages');}});
    const file = `actql-${name}-0.0.0-development.tgz`;
    const payload = await unpack(join(destination, file), join(destination, 'payload', name));
    const metadata = JSON.parse(await readFile(join(payload, 'package.json')));
    assert.equal(metadata.name, '@actql/' + name, 'The archive must contain its original named package');
    packages.push({name: metadata.name, file, files: await inventory(payload)});
  }
  const admitted = {kind: 'ci-packed-client-packages', directory,
    manifestSha256: sha256(wire), manifest: {sourceSha: before.revision, packages},
    archives: packages.map(item => join(destination, item.file)),
    async verifyUnchanged() {
      assert.deepEqual(checkoutState(repository), before, 'Packed source changed during record approval');
      assert.deepEqual(await readFile(manifestPath), wire, 'Original packed manifest changed');
      for (const [index, name] of CLIENT_PACKAGES.entries()) {
        const file = packages[index].file, expected = manifest.tarballs[name];
        assert.equal(sha256(await readFile(join(directory, file))), expected, 'Original packed archive changed');
        assert.equal(sha256(await readFile(join(destination, file))), expected, 'Copied packed archive changed');
      }
    }};
  await admitted.verifyUnchanged();
  return admitted;
}
