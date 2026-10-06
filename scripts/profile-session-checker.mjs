// One frozen full-catalog plan, three serial alternating-order pairs. No
// Actions authority, physical execution, cache authorization or net CI claim.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {join, resolve} from 'node:path';
import {hash} from '../proofs/ci-evidence/inputs.mjs';
import {checkPlan, leanInput} from '../proofs/ci-evidence/check.mjs';
import {completeCheckerFixture, planRevision} from '../proofs/ci-evidence/checker-plan-fixture.mjs';

const root = fileURLToPath(new URL('../', import.meta.url)), sourcePath = 'proofs/ci-evidence/check.mjs';
const git = args => execFileSync('git', args, {cwd: root});
const revision = () => git(['rev-parse', 'HEAD']).toString().trim();
const clean = () => assert.equal(git(['status', '--porcelain', '--untracked-files=no']).toString(), '', 'Use a clean profile source');

export async function loadPreviousChecker() {
  const original = git(['show', `${planRevision}:${sourcePath}`]);
  for (const path of ['proofs/ci-evidence/Reuse.lean', 'proofs/ci-evidence/Claims.lean', 'proofs/bounded-session/lean-toolchain'])
    assert(git(['show', `${planRevision}:${path}`]).equals(readFileSync(join(root, path))), 'Different model/claim/pin invalidates method-only comparison');
  // Relocate only module resolution; the original encoder and checker execute.
  let source = original.toString();
  assert.equal(source.split("from './inputs.mjs'").length, 2);
  source = source.replace("from './inputs.mjs'", `from '${pathToFileURL(join(root, 'proofs/ci-evidence/inputs.mjs')).href}'`)
    .replaceAll('import.meta.url', JSON.stringify(pathToFileURL(join(root, sourcePath)).href));
  return {...await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`), sourceDigest: hash(original)};
}

async function profile(output) {
  clean(); const candidate = revision(), fixture = completeCheckerFixture(root), previous = await loadPreviousChecker();
  const declarations = source => source.slice(0, source.lastIndexOf('example : IncrementalEvidence.check submittedRequirements'));
  assert.equal(declarations(previous.leanInput(fixture.required, fixture.applications)), declarations(leanInput(fixture.required, fixture.applications)),
    'Proof strategy cannot replace model, audit, requirements or applications');
  const pairs = [];
  for (let index = 0; index < 3; index++) {
    const pair = {index, order: index % 2 ? ['after', 'before'] : ['before', 'after']};
    for (const role of pair.order) {
      const start = performance.now();
      try {
        const result = (role === 'before' ? previous.checkPlan : checkPlan)(fixture.required, fixture.applications);
        pair[role] = {status: 'accepted', milliseconds: performance.now() - start,
          inputDigest: result.inputDigest, outputDigest: result.outputDigest, theoremCount: result.theoremCount, toolchain: result.toolchain};
      } catch (error) {
        pair[role] = {status: error.code === 'ETIMEDOUT' ? 'timeout' : 'rejected', milliseconds: performance.now() - start,
          error: {name: error.name, code: error.code ?? null}};
      }
    }
    pair.savedMilliseconds = pair.before.status === 'accepted' && pair.after.status === 'accepted'
      ? pair.before.milliseconds - pair.after.milliseconds : null;
    pairs.push(pair);
  }
  clean(); assert.equal(revision(), candidate);
  const record = {authority: 'local-controlled-checker-comparison', reuseAuthorized: false, candidate,
    referenceRevision: planRevision, referenceDigest: previous.sourceDigest, candidateDigest: hash(readFileSync(join(root, sourcePath))),
    fixture: {sourceRevision: fixture.sourceRevision, dataDigest: fixture.dataDigest, catalogDigest: fixture.catalogDigest,
      requirements: fixture.required.length, applications: fixture.applications.length},
    conditions: {pairs: 3, warmup: 0, order: 'alternating', execution: 'serial real pinned Lean, production 30s limit',
      interval: 'JS generation, version subprocess, model/claim/axiom and candidate proof checking',
      excluded: ['Git/source fixture preparation', 'Actions authentication', 'artifact transfer', 'physical execution'],
      interpretation: 'local one-plan cost; timeouts retained and never counted as accepted or exact savings'},
    pairs, netRunnerSavingsMilliseconds: null};
  writeFileSync(output, `${JSON.stringify(record, null, 2)}\n`, {flag: 'wx'});
  console.log(JSON.stringify({output, candidate, pairs: pairs.map(pair => ({index: pair.index, before: pair.before.status,
    after: pair.after.status, savedMilliseconds: pair.savedMilliseconds}))}));
  assert(pairs.every(pair => pair.after.status === 'accepted'), 'The new checker did not accept every complete-plan trial');
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'Use profile-session-checker.mjs OUTPUT_JSON');
  await profile(process.argv[2]);
}
