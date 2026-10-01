import { readFileSync, writeFileSync, unlinkSync, mkdirSync, existsSync, copyFileSync } from 'node:fs';
import { join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { program } from './engine.mjs';
import { snapshot } from './inventory.mjs';
import { artifacts } from '../bounded-session/evidence.mjs';
import { body, payload, inputVariable } from './fixture.mjs';
export const root = fileURLToPath(new URL('../../', import.meta.url));
export const fixture = 'src/query_integration/relation_pipeline_batch_wbtest.mbt';
export const digest = value => createHash('sha256').update(value).digest('hex');
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
export const environment = { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` };
export const moon = join(home, 'bin/moon');
export const toolchain = pin;
const compiler = spawnSync(join(home, 'bin/moonc'), ['-v'], { env: environment, encoding: 'utf8' });
if (compiler.status !== 0 || compiler.stdout.trim() !== pin.moonc) throw new Error('Wrong MoonBit compiler');
let serial = 0;
const invocation = `${Date.now()}-${process.pid}`;
export const executions = [];
let ownedFixture = false;
process.on('exit', () => {
  if (ownedFixture && existsSync(join(root, fixture))) {
    if (readFileSync(join(root, fixture), 'utf8') !== body) throw new Error('Owned fixture was changed');
    unlinkSync(join(root, fixture));
  }
});
export function execute(cases, registry, target, correspondence = false, label = 'probe') {
  if (!['js', 'wasm', 'native'].includes(target) || !cases.length) throw new Error('Bad execution request');
  const path = join(root, fixture);
  if (existsSync(path)) {
    if (!ownedFixture || readFileSync(path, 'utf8') !== body) throw new Error('Another pipeline batch owns the temporary fixture');
  } else { writeFileSync(path, body); ownedFixture = true; }
  const entries = cases.map((testCase, i) => ({ testCase, id: `${serial}:${i}:${testCase.id}`, program: program(testCase, registry) }));
  const source = snapshot(root);
  const inputs = payload(entries, correspondence);
  const directory = join(root, '.artifacts/relation-pipeline');
  mkdirSync(directory, { recursive: true });
  const sourcePath = `.artifacts/relation-pipeline/sources/${source.digest}.json`;
  mkdirSync(join(directory, 'sources'), { recursive: true });
  if (!existsSync(join(root, sourcePath))) writeFileSync(join(root, sourcePath), JSON.stringify(source, null, 2) + '\n');
  const prefix = `${invocation}-${String(serial++).padStart(4, '0')}-${label}-${target}`;
  const command = ['test', fixture, '--target', target, '--deny-warn'];
  writeFileSync(join(directory, `${prefix}.fixture.mbt`), body);
  writeFileSync(join(directory, `${prefix}.inputs.json`), inputs);
  const result = spawnSync(moon, command, { cwd: root,
    env: { ...environment, [inputVariable]: inputs }, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `${prefix}.log`), output);
  if (result.error || result.status !== 0) {
    process.stderr.write(output);
    throw result.error ?? new Error(`Generated observation execution failed: ${prefix}`);
  }
  const observations = [];
  let currentId;
  let faults = [];
  for (const line of output.split('\n')) {
    if (line.startsWith('ACTQL_PIPELINE_CASE:')) { currentId = JSON.parse(line.slice('ACTQL_PIPELINE_CASE:'.length)); faults = []; }
    if (line.startsWith('ACTQL_PIPELINE_FAULT:')) faults.push(JSON.parse(line.slice('ACTQL_PIPELINE_FAULT:'.length)));
    if (line.startsWith('ACTQL_PIPELINE:')) {
      const value = JSON.parse(line.slice('ACTQL_PIPELINE:'.length));
      if (value.id !== currentId) throw new Error('Unbound execution event');
      observations.push({ ...value, tableRows: value.rows,
        rows: value.wireRows.map(row => value.columns.map(field => row[field])), faults });
    }
  }
  if (observations.length !== entries.length) throw new Error(`Missing actual observations ${observations.length}/${entries.length}: ${prefix}`);
  observations.forEach((observation, i) => {
    if (observation.id !== entries[i].id || !observation.checked || !observation.registered) throw new Error('Execution identity mismatch');
  });
  if (snapshot(root).digest !== source.digest) throw new Error('Source changed during generated execution');
  const actualArtifacts = artifacts(root, target, 'query_integration');
  const archives = {};
  if (label === 'normal') {
    mkdirSync(join(directory, 'final-artifacts', target), { recursive: true });
    for (const [path, expected] of Object.entries(actualArtifacts)) {
      const archive = `.artifacts/relation-pipeline/final-artifacts/${target}/${basename(path)}`;
      copyFileSync(join(root, path), join(root, archive));
      if (digest(readFileSync(join(root, archive))) !== expected) throw new Error('Archive differs from executed artifact');
      archives[path] = archive;
    }
  }
  const receipt = { target, correspondence, compiler: compiler.stdout.trim(), sourceDigest: source.digest, sourcePath,
    command: ['moon', ...command], exit: result.status, fixtureDigest: digest(body),
    fixturePath: `.artifacts/relation-pipeline/${prefix}.fixture.mbt`,
    inputVariable, inputDigest: digest(inputs), inputPath: `.artifacts/relation-pipeline/${prefix}.inputs.json`,
    logPath: `.artifacts/relation-pipeline/${prefix}.log`,
    logDigest: digest(output), artifacts: actualArtifacts, archives,
    cases: entries.map((e, i) => ({ ...e, caseDigest: digest(JSON.stringify(e.testCase)), observation: observations[i] })) };
  writeFileSync(join(directory, `${prefix}.json`), JSON.stringify(receipt, null, 2) + '\n');
  executions.push({ path: `.artifacts/relation-pipeline/${prefix}.json`, digest: digest(JSON.stringify(receipt)), receipt });
  const recorded = JSON.parse(readFileSync(join(directory, `${prefix}.json`)));
  return recorded.cases.map(e => e.observation);
}
