// Controlled extraction comparison, never execution evidence or reuse authority.
import assert from 'node:assert/strict';
import processTools, {execFileSync} from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {join, resolve} from 'node:path';
import {readCatalog} from '../proofs/ci-evidence/actions.mjs';
import {actionInputs, gitTree, hash} from '../proofs/ci-evidence/inputs.mjs';

export const referenceRevision = '92fb7a94b1c9776ce13eb516723dd3471f6152f3';
const sourcePath = 'proofs/ci-evidence/inputs.mjs';
export async function loadReference(root, reference = referenceRevision) {
  assert(/^[a-f0-9]{40}$/u.test(reference), 'Use a full reference Git revision');
  const bytes = execFileSync('git', ['show', `${reference}:${sourcePath}`], {cwd: root});
  // Compare only the changed traversal. Keep registry/shared-input/parser
  // context equal so later legitimate obligations do not invalidate this
  // regression merely because the historical module's catalog was smaller.
  const candidate = readFileSync(join(root, sourcePath), 'utf8');
  const span = code => {
    const start = code.indexOf('export function packageSourceInputs(');
    const end = code.indexOf('export const mutationPackages', start);
    assert(start >= 0 && end > start && code.indexOf('export function packageSourceInputs(', start + 1) < 0,
      'Unexpected extractor boundary');
    return {start, end};
  };
  const previous = bytes.toString('utf8'), old = span(previous), current = span(candidate);
  let code = candidate.slice(0, current.start) + previous.slice(old.start, old.end) + candidate.slice(current.end);
  for (const [relative, path] of [['../bounded-session/action-inputs.mjs', 'proofs/bounded-session/action-inputs.mjs'],
    ['./package-configurations.mjs', 'proofs/ci-evidence/package-configurations.mjs']]) {
    const from = `from '${relative}'`;
    assert.equal(code.split(from).length, 2, 'Unexpected reference import');
    code = code.replace(from, `from '${pathToFileURL(join(root, path)).href}'`);
  }
  return {...await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`), referenceDigest: hash(bytes)};
}

async function profile(root, output, reference = referenceRevision) {
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  const clean = () => assert.equal(execFileSync('git', ['status', '--porcelain', '--untracked-files=no'], {cwd: root, encoding: 'utf8'}), '', 'Use a clean candidate');
  clean();
  const before = await loadReference(root, reference), catalog = readCatalog();
  const runtime = {profile: 'input-extractor-equivalence-only', unresolved: ['not runtime acceptance']};
  const extract = (implementation, counters = null) => {
    let tree = implementation.gitTree(root, revision);
    if (counters) {
      const original = tree.entries;
      const entries = new Proxy(original, {get(map, key) {
        if (key === 'keys') return function* () {
          counters.entryEnumerations++;
          for (const path of original.keys()) {counters.pathVisits++; yield path;}
        };
        const value = Reflect.get(map, key, map);
        return typeof value === 'function' ? value.bind(map) : value;
      }});
      tree = {...tree, entries};
    }
    return catalog.actions.map(action => implementation.actionInputs({tree, revision, action, runtime}));
  };
  const after = {gitTree, actionInputs};
  assert.deepEqual(extract(before), extract(after));
  // Count separately from timed pairs: both wrappers invoke the actual Git.
  const count = implementation => {
    const original = processTools.execFileSync; let batches = 0, objects = 0;
    processTools.execFileSync = (command, args, options) => {
      if (command === 'git' && args[0] === 'cat-file' && args[1] === '--batch') {
        batches++; objects += options.input.trim().split('\n').length;
      }
      return original(command, args, options);
    };
    syncBuiltinESMExports();
    const counters = {entryEnumerations: 0, pathVisits: 0};
    try { const inputs = extract(implementation, counters); return {batches, objects, ...counters, keys: inputs.map(input => input.key)}; }
    finally { processTools.execFileSync = original; syncBuiltinESMExports(); }
  };
  const counts = {before: count(before), after: count(after)};
  assert.deepEqual(counts.before.keys, counts.after.keys);
  for (let i = 0; i < 2; i++) { extract(before); extract(after); }
  const pairs = [];
  for (let i = 0; i < 9; i++) {
    const pair = {index: i, order: i % 2 ? ['after', 'before'] : ['before', 'after']};
    for (const role of pair.order) {
      const start = performance.now(); const inputs = extract(role === 'before' ? before : after);
      pair[`${role}Milliseconds`] = performance.now() - start;
      assert.deepEqual(inputs.map(input => input.key), counts.before.keys);
    }
    pair.savedMilliseconds = pair.beforeMilliseconds - pair.afterMilliseconds; pairs.push(pair);
  }
  clean(); assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim(), revision);
  const record = {authority: 'local-controlled-input-extraction', reuseAuthorized: false, candidate: revision,
    referenceRevision: reference, referenceDigest: before.referenceDigest, candidateExtractorDigest: hash(readFileSync(join(root, sourcePath))),
    conditions: {actions: catalog.actions.length, tree: 'fresh per invocation; immutable candidate Git blobs',
      warmupPairs: 2, measuredPairs: 9, caches: 'OS/filesystem warm; no closure cache across invocations',
      referenceImports: 'preceding package traversal in equal candidate context; two relative imports relocated',
      target: 'source extraction only; no Moon/Lean/compiler/Actions execution'}, counts, pairs,
    netRunnerSavingsMilliseconds: null};
  writeFileSync(output, `${JSON.stringify(record, null, 2)}\n`, {flag: 'wx'});
  console.log(JSON.stringify({output, candidate: revision, batchesBefore: counts.before.batches, batchesAfter: counts.after.batches,
    meanSavedMilliseconds: pairs.reduce((sum, pair) => sum + pair.savedMilliseconds, 0) / pairs.length}));
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert(process.argv.length === 3 || process.argv.length === 5 && process.argv[3] === '--reference',
    'Use profile-session-input-frontiers.mjs OUTPUT_JSON [--reference FULL_SHA]');
  await profile(fileURLToPath(new URL('../', import.meta.url)), process.argv[2], process.argv[4] ?? referenceRevision);
}
