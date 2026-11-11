// Controlled consumer copies of real healthy originals. These are not actual
// mutation executions, image observations, or an Actions trust witness.
// Copies bind the current consumer fixture; archived originals stay unchanged.
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {fileURLToPath} from 'node:url';
import {hash, gitTree} from '../../ci-evidence/inputs.mjs';
import {pipelinePristineSourcePaths} from '../../ci-evidence/isolation.mjs';
import {checkCurrentSource, snapshot} from '../inventory.mjs';
import {mutationPart} from '../mutation-parts.mjs';
import {variants} from '../mutation-registry.mjs';
import {applyMutation} from '../sites.mjs';
import {fixedJsAction} from '../fixed-js-scope.mjs';
import {body, boundFixture, payload as executionPayload} from '../fixture.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
// Only these controlled DATA copies bind current sources; the captured archive
// remains an unchanged historical input, never a current execution receipt.
const revision = checkCurrentSource(root);
const bytes = gunzipSync(readFileSync(new URL('../../../docs/reviews/evidence/2026-10-08-pipeline-pristine-normal-f2a191b51.json.gz', import.meta.url)), {maxOutputLength: 4 * 1024 * 1024});
if (hash(bytes) !== '0a81ea5af7e6c061696c486a3615262a512d67d8edd3c3d9d9c1e304bbbef68f') throw new Error('Changed fixture original');
const original = JSON.parse(bytes), tree = gitTree(root, revision);
tree.prefetch(pipelinePristineSourcePaths(tree));
const digest = value => hash(JSON.stringify(value));
export function controlledFixedJsOriginal() {
  const source = snapshot(root), files = {};
  const workspaces = {mutable: {id: 'controlled-mutable', root: '/controlled/mutable'},
    pristine: {id: 'controlled-pristine', root: '/controlled/pristine'}};
  const restorationOwner = {id: 'controlled-new-owner', root: workspaces.mutable.root};
  const regressions = JSON.parse(tree.read('proofs/relation-pipeline/regressions.json'));
  const results = original.report.observations.map(({name, testCase, observed}, index) => {
    const variant = variants.find(v => v.name === name), fixed = regressions.find(r => r.name === name);
    const mutated = applyMutation(tree.read(variant.path).toString(), variant);
    const changedSources = {...source.sources, [variant.path]: hash(mutated)};
    const changed = {sources: changedSources, digest: digest(changedSources)};
    function execution(phase, owner, phaseSource, correspondence) {
      const originalExecution = original.report.receipts[index], run = structuredClone(originalExecution.receipt);
      const value = structuredClone(observed); value.id = `${name}:${phase}`;
      if (!correspondence) {
        value.correspondence = false;
        if (index === 0) {value.kind = 'failed'; value.faults = [{kind: 'wrong checked handoff port', receiver: 1, expectedPort: 0, usedPort: 1}];}
        else if (index === 1) {value.wireRows.reverse(); value.rows.reverse();}
        else for (const contract of ['checked', 'kernel']) {
          value.contracts[0][contract][fixed.anchor.field][fixed.anchor.property] = fixed.anchor.wrong;
        }
      }
      run.boundary = {...run.boundary, workspace: owner.id, root: owner.root,
        role: phase === 'pristine' ? 'pristine' : 'mutable', sourceDigest: phaseSource.digest,
        fixtureDigest: hash(body)};
      run.buildIdentity = digest(run.boundary); run.sourceDigest = phaseSource.digest; run.correspondence = correspondence;
      run.sourcePath = `.artifacts/relation-pipeline/sources/${phaseSource.digest}.json`;
      files[run.sourcePath] = `${JSON.stringify(phaseSource,null,2)}\n`;
      const prefix = `.artifacts/relation-pipeline/controlled-${name}-${phase}`;
      run.logPath = `${prefix}.log`; run.inputPath = `${prefix}.inputs.json`; run.fixturePath = `${prefix}.fixture.mbt`;
      run.cases[0] = {...run.cases[0], id: value.id, observation: value};
      files[run.inputPath] = executionPayload(run.cases, correspondence); run.inputDigest = hash(files[run.inputPath]);
      files[run.fixturePath] = boundFixture(run.boundary); run.fixtureDigest = hash(files[run.fixturePath]);
      const {rows: _rows, tableRows, faults, ...raw} = value;
      files[run.logPath] = [`ACTQL_PIPELINE_BUILD:${run.buildIdentity}`, `ACTQL_PIPELINE_CASE:${JSON.stringify(value.id)}`,
        ...faults.map(fault => `ACTQL_PIPELINE_FAULT:${JSON.stringify(fault)}`),
        `ACTQL_PIPELINE:${JSON.stringify({...raw, rows: tableRows})}`, 'Total tests: 1, passed: 1, failed: 0', ''].join('\n');
      run.logDigest = hash(files[run.logPath]);
      const entry = {path: `${prefix}.json`, digest: digest(run), receipt: run};
      files[entry.path] = `${JSON.stringify(run,null,2)}\n`; return entry;
    }
    const mutant = execution('mutated', workspaces.mutable, changed, false),
      pristine = execution('pristine', workspaces.pristine, source, true),
      restored = execution('post-restore', restorationOwner, source, true);
    return {owner: 'L-M0', name, site: variant.path, originalDigest: source.sources[variant.path], mutatedDigest: hash(mutated),
      source: changed, anchor: fixed.anchor, original: testCase, minimal: testCase, localMinimal: false, killed: true,
      executions: [mutant], replay: {js: mutant.receipt.cases[0].observation},
      healthyExecutions: [pristine], healthy: {js: pristine.receipt.cases[0].observation},
      postRestore: {executions: [restored], observations: {js: restored.receipt.cases[0].observation}}};
  });
  const report = {version: 'actql-pipeline-fixed-js-campaign/0.1', action: fixedJsAction,
    part: mutationPart('L-M0'), reuseAuthorized: false, source, workspaces, restorationOwner,
    closure: {mutable:true, pristine:true, restoration:true, sourceRestored:true},
    revision, decision:{revision,localOnly:true}, toolchain: JSON.parse(tree.read('toolchain.json')),
    mode:'fixed', seed:null, explorationTarget:null, results};
  return {payload: {report, files}, context: {source, revision, readSource: path => tree.read(path)}};
}
