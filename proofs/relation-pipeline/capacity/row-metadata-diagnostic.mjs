// A narrow local diagnostic using the existing observation driver and oracle.
// It emits local correspondence evidence, never authenticated Actions receipts.
import assert from 'node:assert/strict';
import {copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {execute, closeExecutor, executions, root, toolchain} from '../execute.mjs';
import {hash, snapshot} from '../inventory.mjs';
import {fixedCorpus} from '../corpus.mjs';
import {registry} from '../registry.mjs';
import {registrations} from '../obligations.mjs';
import {compareSemantics} from '../evidence.mjs';
import {checkCensus} from './census.mjs';
import {inspectEvents} from './model.mjs';
import {inspectPipelineBacking} from './backing/pipeline.mjs';
import {generatedObservers, instrument, replacements, installGeneratedObservers,
  restoreGeneratedObservers} from './instrument.mjs';
const git = args => {
  const result = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
};
assert.equal(git(['status', '--porcelain']), '', 'Diagnostic requires a submitted clean source');
const revision = git(['rev-parse', 'HEAD']), source = snapshot(root);
checkCensus(root);
const corpus = fixedCorpus(registry, registrations).filter(c => c.steps.filter(s => s.op === 'distinct').length === 1);
const cases = [corpus.find(c => c.rows.length === 0), corpus.find(c => c.rows.length > 0)];
assert(cases.every(Boolean), 'Existing DISTINCT fixed cases missing');
const originals = Object.fromEntries(Object.keys(replacements).map(path => [path, readFileSync(join(root, path), 'utf8')]));
const overlays = Object.fromEntries(Object.entries(originals).map(([path, code]) => [path, instrument(path, code)]));
let observations, claims, execution;
try {
  installGeneratedObservers(root);
  for (const [path, code] of Object.entries(overlays)) writeFileSync(join(root, path), code);
  observations = execute(cases, registry, 'native', false, 'metadata-native');
  execution = executions.at(-1);
  assert.equal(execution.receipt.target, 'native');
  claims = observations.map((o, i) => {
    compareSemantics(cases[i], o, registry);
    inspectEvents(cases[i], o, registry);
    return inspectPipelineBacking(cases[i], o, registry, 'native', execution.receipt.target);
  });
} finally {
  closeExecutor();
  for (const [path, code] of Object.entries(originals)) {
    assert.equal(readFileSync(join(root, path), 'utf8'), overlays[path], 'Owned source overlay changed');
    writeFileSync(join(root, path), code);
  }
  restoreGeneratedObservers(root);
  assert.deepEqual(snapshot(root), source, 'Local diagnostic failed byte-for-byte restoration');
}
const directory = '.artifacts/relation-pipeline/row-metadata-diagnostic';
mkdirSync(join(root, directory), {recursive: true});
const archives = {};
for (const [path, digest] of Object.entries(execution.receipt.artifacts)) {
  const archive = `${directory}/binaries/${digest}`;
  mkdirSync(dirname(join(root, archive)), {recursive: true});
  if (!existsSync(join(root, archive))) copyFileSync(join(root, path), join(root, archive));
  assert.equal(hash(readFileSync(join(root, archive))), digest);
  archives[path] = archive;
}
const report = {version: 'actql-row-metadata-native-diagnostic/0.1', revision, source, toolchain,
  command: ['node', 'proofs/relation-pipeline/capacity/row-metadata-diagnostic.mjs'],
  authority: 'local-finite-correspondence', reuseAuthorized: false,
  overlays: Object.fromEntries(Object.entries({...overlays, ...generatedObservers}).map(([path, code]) => [path, hash(code)])),
  cases, observations, claims, execution, archives, restored: true,
  remaining: ['complete retained-state allocation union and lifetime overlap',
    'nonempty tuple/variant referents and metadata cursor record byte bounds',
    'chain preparation/callback captures and reservation custody']};
writeFileSync(join(root, directory, 'report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(`native: ${cases.length} existing DISTINCT cases; actual Map/Array descriptors, independent bounds and restored source`);
