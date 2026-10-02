import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';
export const hash = value => createHash('sha256').update(value).digest('hex');
function files(path) {
  return readdirSync(path, { withFileTypes: true }).flatMap(e => e.isDirectory()
    ? files(join(path, e.name)) : e.isFile() ? [join(path, e.name)] : []);
}
export function snapshot(root) {
  const paths = ['src', 'proofs/bounded-session', 'proofs/relation-chain', 'proofs/relation-capacity', 'proofs/relation-pipeline']
    .flatMap(p => files(join(root, p)))
    .concat(['toolchain.json', 'moon.mod', 'package.json', 'package-lock.json', '.github/workflows/ci.yml', 'docs/spec/language.md', 'docs/spec/execution.md'].map(p => join(root, p)))
    .filter(p => relative(root, p) !== 'src/query_integration/relation_pipeline_batch_wbtest.mbt').sort();
  const sources = Object.fromEntries(paths.map(p => [relative(root, p), hash(readFileSync(p))]));
  return { sources, digest: hash(JSON.stringify(sources)) };
}
export function checkBaseline(root) {
  const baseline = JSON.parse(readFileSync(join(root, 'proofs/relation-pipeline/baseline.json')));
  for (const [path, expected] of Object.entries(baseline.unchangedCommon)) {
    if (hash(readFileSync(join(root, path))) !== expected) throw new Error(`Changed common proof/history: ${path}`);
  }
  for (const item of baseline.existingGroup) {
    if (!readFileSync(join(root, item.path), 'utf8').includes(`test "${item.test}"`)) throw new Error(`Missing retained fixture ${item.test}`);
  }
  return baseline;
}
