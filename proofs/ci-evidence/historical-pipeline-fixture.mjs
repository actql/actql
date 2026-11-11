// Test-only replay consumers for three independently pinned local originals.
// No production collector, acquisition or final consumer imports this module.
import assert from 'node:assert/strict';
import {after} from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {gitTree} from './inputs.mjs';

const revisions = Object.freeze([
  '346f9274cccb5d617d48c99ad1efc4576cad29e2',
  'f2a191b51fd6ecd7b70486c6e8fa33204fa8964e',
  'b7a6926588b03251d95df2f2f049dc7901355163',
]);
// Reviewed literal import/resource closure. Missing modules fail import; no
// current-code overlay, archive-supplied code or permissive import resolver.
const paths = Object.freeze([
  "proofs/bounded-session/action-inputs.mjs",
  "proofs/bounded-session/evidence.mjs",
  "proofs/ci-evidence/inputs.mjs",
  "proofs/ci-evidence/isolated-contract.mjs",
  "proofs/ci-evidence/isolated-execution.mjs",
  "proofs/ci-evidence/isolated-runtime.mjs",
  "proofs/ci-evidence/isolation.mjs",
  "proofs/ci-evidence/local-isolated-acceptance.mjs",
  "proofs/ci-evidence/mutation-inventory.mjs",
  "proofs/ci-evidence/mutation-observation.mjs",
  "proofs/ci-evidence/package-configurations.mjs",
  "proofs/ci-evidence/runtime.mjs",
  "proofs/relation-chain/evidence.mjs",
  "proofs/relation-pipeline/corpus.mjs",
  "proofs/relation-pipeline/distinct-acceptance.mjs",
  "proofs/relation-pipeline/distinct-mutations.mjs",
  "proofs/relation-pipeline/distinct.mjs",
  "proofs/relation-pipeline/engine.mjs",
  "proofs/relation-pipeline/evidence.mjs",
  "proofs/relation-pipeline/execute.mjs",
  "proofs/relation-pipeline/execution-names.mjs",
  "proofs/relation-pipeline/execution-original.mjs",
  "proofs/relation-pipeline/exploration-impact.mjs",
  "proofs/relation-pipeline/filter.mjs",
  "proofs/relation-pipeline/fixed-js-replay.mjs",
  "proofs/relation-pipeline/fixed-js-scope.mjs",
  "proofs/relation-pipeline/fixture.mjs",
  "proofs/relation-pipeline/inventory.mjs",
  "proofs/relation-pipeline/mismatch.mjs",
  "proofs/relation-pipeline/mutation-parts.mjs",
  "proofs/relation-pipeline/mutation-registry.mjs",
  "proofs/relation-pipeline/mutations.mjs",
  "proofs/relation-pipeline/obligations.mjs",
  "proofs/relation-pipeline/pristine-replay.mjs",
  "proofs/relation-pipeline/proof-parts.mjs",
  "proofs/relation-pipeline/registry.mjs",
  "proofs/relation-pipeline/rename-mutations.mjs",
  "proofs/relation-pipeline/rename.mjs",
  "proofs/relation-pipeline/select.mjs",
  "proofs/relation-pipeline/sites.mjs",
  "proofs/relation-pipeline/sort.mjs",
  "proofs/relation-pipeline/take.mjs",
  "proofs/relation-pipeline/workspaces.mjs",
  "scripts/local-checks-guard.mjs",
  "scripts/owned-scratch.mjs",
  "proofs/bounded-session/nest-obligations.json",
  "proofs/relation-pipeline/harness.mbt",
  "proofs/relation-pipeline/regressions.json"
]);
export async function historicalPipelineFixture(root, revision) {
  assert(revisions.includes(revision), 'Unregistered historical pipeline revision');
  // The first pristine record preceded the strengthened original consumer.
  // Its later pinned consumer preserves these scientific inputs and adds exact
  // requested-Program checking. Require identical Git bytes/modes rather than
  // adding a permissive historical branch to the production validator.
  const consumerRevision = revision === revisions[0] ? revisions[1] : revision;
  const tree = gitTree(root, consumerRevision);
  if (consumerRevision !== revision) {
    const original = gitTree(root, revision);
    for (const path of ['proofs/relation-pipeline/harness.mbt', 'proofs/relation-pipeline/fixture.mjs',
      'proofs/relation-pipeline/engine.mjs', 'proofs/relation-pipeline/registry.mjs',
      'proofs/relation-pipeline/regressions.json', 'proofs/relation-pipeline/proof-parts.mjs']) {
      assert.equal(original.entries.get(path)?.mode, tree.entries.get(path)?.mode);
      assert(original.read(path).equals(tree.read(path)), 'Changed historical scientific input');
    }
  }
  const directory = mkdtempSync(join(tmpdir(), 'actql-historical-pipeline-fixture-'));
  let retained = false;
  try {
    // The fixed campaign modules did not exist for the two pristine originals.
    const selected = paths.filter(path => tree.entries.has(path));
    tree.prefetch(selected);
    for (const path of selected) {
      assert.equal(tree.entries.get(path).mode, '100644', 'Unexpected historical module/resource mode');
      const file = join(directory, path);
      mkdirSync(dirname(file), {recursive: true});
      writeFileSync(file, tree.read(path), {flag: 'wx'});
    }
    const load = path => import(pathToFileURL(join(directory, path)).href);
    const [execution, pristine, acceptance, runtime, isolation] = await Promise.all([
      load('proofs/ci-evidence/isolated-execution.mjs'),
      load('proofs/relation-pipeline/pristine-replay.mjs'),
      load('proofs/ci-evidence/local-isolated-acceptance.mjs'),
      load('proofs/ci-evidence/isolated-runtime.mjs'),
      load('proofs/ci-evidence/isolation.mjs'),
    ]);
    const fixed = revision === revisions[2] ? await load('proofs/relation-pipeline/fixed-js-replay.mjs') : null;
    // Return only pure replay consumers. Execution/image builder entry points
    // are never exposed or called; imports alone do not acquire any authority.
    after(() => rmSync(directory, {recursive: true, force: true}));
    retained = true;
    return {
      validatePipelinePristineOriginal: execution.validatePipelinePristineOriginal,
      checkPipelinePristineResult: execution.checkPipelinePristineResult,
      checkPipelineFixedJsResult: execution.checkPipelineFixedJsResult,
      validatePristineReport: pristine.validatePristineReport,
      validateFixedJsReport: fixed?.validateFixedJsReport,
      verifyPristineTamperRefusals: acceptance.verifyPristineTamperRefusals,
      verifyFixedJsTamperRefusals: acceptance.verifyFixedJsTamperRefusals,
      checkIsolatedInputs: runtime.checkIsolatedInputs,
      imageRuntime: runtime.imageRuntime,
      pipelinePristineSourcePaths: isolation.pipelinePristineSourcePaths,
      pipelineFixedJsSourcePaths: isolation.pipelineFixedJsSourcePaths,
      snapshotFromGit: runtime.snapshotFromGit,
    };
  } finally {
    if (!retained) rmSync(directory, {recursive: true, force: true});
  }
}
