import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {hash} from '../inventory.mjs';
import {adoptedConstructionReview, retainedConstructionRead}
  from '../capacity/parent-control/provider-construction-adopted-review.mjs';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const sources = new Map();
const retainedProviders = JSON.parse(readFileSync(
  new URL('../capacity/parent-control/provider-construction.json', import.meta.url))).providers;
// Test only: construct the archived adapter inputs from its already pinned
// complete preimages. These bytes are never current Source or Native evidence.
export function adoptedConstructionFixtureRead(path) {
  const entry = adoptedConstructionReview.sources.find(entry => entry.path === path);
  const provider = retainedProviders.find(provider => provider.path === path);
  if (!entry && !provider) return readFileSync(new URL('../../../' + path, import.meta.url));
  if (!sources.has(path)) {
    let source = execFileSync('git', ['--no-replace-objects', 'show',
      `${adoptedConstructionReview.previousRevision}:${path}`], {cwd: root}).toString();
    assert.equal(hash(source), entry?.previousSha256 ?? provider.sourceDigest);
    for (const {before, after} of entry?.hunks ?? []) {
      assert.equal(source.split(before).length, 2, 'Changed archived fixture preimage');
      source = source.replace(before, after);
    }
    assert.equal(hash(source), entry?.currentSha256 ?? provider.sourceDigest);
    sources.set(path, Buffer.from(source));
  }
  return sources.get(path);
}

export const retainedConstructionFixtureRead = retainedConstructionRead(adoptedConstructionFixtureRead);
