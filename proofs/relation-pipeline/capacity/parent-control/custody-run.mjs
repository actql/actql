import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, existsSync, unlinkSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { root, environment, moon, toolchain } from '../../execute.mjs';
import { registry } from '../../registry.mjs';
import { registrations } from '../../obligations.mjs';
import { fixedCorpus } from '../../corpus.mjs';
import { program } from '../../engine.mjs';
import { snapshot, hash } from '../../inventory.mjs';
import { artifacts } from '../../../bounded-session/evidence.mjs';
import { replacements, generatedObservers, instrument, installGeneratedObservers,
  restoreGeneratedObservers } from '../instrument.mjs';

const target = process.argv[2] ?? 'js';
assert(['js', 'wasm', 'native'].includes(target));
const case_ = fixedCorpus(registry, registrations).find(c => c.id === 'pair:distinct/filter');
assert(case_ && case_.steps.length === 2);
const pipeline = program(case_, registry);
const input = {
  version: 'actql/0.1', id: 'p', params: { minimum: { type: 'number', nullable: false } },
  stages: [
    { id: 'a', inputs: { remote: { connector: 'crm/main', resource: 'r' } },
      steps: [{ filter: 'id > $minimum', as: 'filtered' }, { select: ['id'], as: 'captured' }],
      results: { r: { from: 'captured', fields: ['id'] } } },
    { id: 'compute_a', inputs: {}, steps: JSON.parse(pipeline.source),
      results: { r: { from: 'seed', fields: Object.keys(pipeline.states[0].schema) } } },
    { id: 'compute_b', inputs: { prior: { result: { stage: 'compute_a', result: 'r' } } },
      steps: JSON.parse(pipeline.steps),
      results: { r: { from: 's1', fields: pipeline.states.at(-1).fields } } },
  ], results: { source: { from: { stage: 'a', result: 'r' } } },
};
const source = snapshot(root);
const read = path => readFileSync(join(root, path));
const query = 'src/query_integration/query_checked_program_wbtest.mbt';
const fixture = 'src/query_integration/relation_pipeline_custody_wbtest.mbt';
const originals = Object.fromEntries([...Object.keys(replacements), query].map(p => [p, read(p)]));
const overlay = Object.fromEntries(Object.entries(originals).map(([p, text]) =>
  [p, replacements[p] ? instrument(p, text.toString()) : text.toString()]));
const anchor = '    Some(kind) => local_values_unary_program(kind)';
assert.equal(overlay[query].split(anchor).length, 2);
const variable = 'ACTQL_RELATION_PIPELINE_CUSTODY_PROGRAM';
overlay[query] = overlay[query].replace(anchor,
  `    Some(kind) => if kind == "capacity-custody-probe" { @env.get_env_var("${variable}").unwrap() } else { local_values_unary_program(kind) }`);
overlay[fixture] = readFileSync(new URL('./custody-fixture.mbt', import.meta.url), 'utf8');
assert(!existsSync(join(root, fixture)), 'Foreign custody fixture');
assert(Object.keys(generatedObservers).every(p => !existsSync(join(root, p))), 'Foreign generated observer');
const directory = '.artifacts/relation-pipeline/capacity/custody';
mkdirSync(join(root, directory), { recursive: true });
const prefix = `${directory}/${Date.now()}-${process.pid}-${target}`;
const command = ['test', fixture, '--target', target, '--deny-warn'];
let ownsFixture = false;
try {
  installGeneratedObservers(root);
  writeFileSync(join(root, fixture), overlay[fixture], { flag: 'wx' }); ownsFixture = true;
  for (const p of Object.keys(originals)) writeFileSync(join(root, p), overlay[p]);
  const executedSource = snapshot(root);
  writeFileSync(join(root, `${prefix}.source.json`), JSON.stringify(executedSource, null, 2) + '\n');
  writeFileSync(join(root, `${prefix}.fixture.mbt`), overlay[fixture]);
  writeFileSync(join(root, `${prefix}.input.json`), JSON.stringify({ case: case_, program: input }, null, 2) + '\n');
  const result = spawnSync(moon, command, { cwd: root, env: { ...environment,
    [variable]: JSON.stringify(input) }, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const log = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(root, `${prefix}.log`), log);
  if (result.status !== 0) { process.stderr.write(log); throw result.error ?? new Error(`Custody diagnostic exit ${result.status}`); }
  const rows = log.split('\n').filter(l => l.startsWith('ACTQL_CUSTODY:')).map(l => JSON.parse(l.slice(14)));
  assert.equal(rows.length, 1);
  const observed = rows[0];
  const after = log.indexOf('ACTQL_CUSTODY_STAGE:after-settlement-before-cleanup');
  const cleanup = log.indexOf('"event":"before-cleanup"', after);
  assert(after >= 0 && cleanup > after, 'No actual child cleanup observed after settlement');
  const executedArtifacts = artifacts(root, target, 'query_integration');
  const archives = {};
  mkdirSync(join(root, directory, 'binaries'), { recursive: true });
  for (const [path, digest] of Object.entries(executedArtifacts)) {
    const archive = `${directory}/binaries/${digest}`;
    if (!existsSync(join(root, archive))) copyFileSync(join(root, path), join(root, archive));
    assert.equal(hash(read(archive)), digest); archives[path] = archive;
  }
  const receipt = { target, toolchain, source, executedSource, command: ['moon', ...command],
    exit: result.status, inputVariable: variable, inputDigest: hash(JSON.stringify(input)),
    logPath: `${prefix}.log`, logDigest: hash(log),
    overlays: Object.fromEntries(Object.entries({ ...generatedObservers, ...overlay }).map(([p, text]) => [p, hash(text)])),
    artifacts: executedArtifacts, archives, observation: observed,
    prematureReleaseCandidate: BigInt(observed.before) - BigInt(observed.after) === BigInt(observed.executionCapacity),
    physicalGcCompletion: false, completeAllocationUpper: false };
  writeFileSync(join(root, `${prefix}.receipt.json`), JSON.stringify(receipt, null, 2) + '\n');
  console.log(JSON.stringify({ path: `${prefix}.receipt.json`, observation: observed,
    prematureReleaseCandidate: receipt.prematureReleaseCandidate }));
} finally {
  for (const [p, text] of Object.entries(originals)) writeFileSync(join(root, p), text);
  if (ownsFixture) unlinkSync(join(root, fixture));
  restoreGeneratedObservers(root);
  assert.equal(snapshot(root).digest, source.digest, 'Custody diagnostic source restoration failed');
}
