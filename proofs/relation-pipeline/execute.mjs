import { accessSync, constants, readFileSync, readdirSync, statSync, realpathSync, writeFileSync, unlinkSync, mkdirSync, existsSync, copyFileSync } from 'node:fs';
import { join, dirname, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { program } from './engine.mjs';
import { artifacts } from '../bounded-session/evidence.mjs';
import { body, boundFixture, executionCommand, fixturePath, payload, inputVariable } from './fixture.mjs';
import assert from 'node:assert/strict';
import { workspaceIdentity } from './workspaces.mjs';
export const root = fileURLToPath(new URL('../../', import.meta.url));
export const fixture = fixturePath;
export const digest = value => createHash('sha256').update(value).digest('hex');
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
export const environment = Object.freeze({ ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` });
export const moon = join(home, 'bin/moon');
export const toolchain = pin;
const compiler = spawnSync(join(home, 'bin/moonc'), ['-v'], { env: environment, encoding: 'utf8' });
if (compiler.status !== 0 || compiler.stdout.trim() !== pin.moonc) throw new Error('Wrong MoonBit compiler');
let serial = 0;
const invocation = `${Date.now()}-${process.pid}`;
export const executions = [];
// All contexts share only receipt storage and serial IDs, never source/build trees.
export function createExecutor(workspace = workspaceIdentity(root, 'normal')) {
  const workspaceRoot = workspace.root;
  const built = new Map();
  let ownedFixture = null;
  let closed = false;
  const path = join(workspaceRoot, fixture);
  const resolveTool = name => {
    const candidates = isAbsolute(name) ? [name] : environment.PATH.split(':').map(directory => join(directory, name));
    const path = candidates.find(path => {
      try { accessSync(path, constants.X_OK); return statSync(path).isFile(); } catch { return false; }
    });
    assert(path, `Missing execution tool ${name}`);
    return realpathSync(path);
  };
  const toolIdentity = () => {
    const inputs = [...['moon', 'moonc', 'moonrun'].map(name => join(home, 'bin', name)),
      ...[...new Set(['node', 'cc', 'c++', 'ar', environment.CC ?? 'cc', environment.CXX ?? 'c++', environment.AR ?? 'ar'])].map(resolveTool)];
    const files = directory => readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))
      .flatMap(entry => { const path = join(directory, entry.name);
        if (entry.isSymbolicLink()) {
          assert(realpathSync(path).startsWith(realpathSync(home) + '/') && statSync(path).isFile(),
            'External or directory-linked Moon toolchain input');
          return [path];
        }
        return entry.isDirectory() ? files(path) : entry.isFile() ? [path] : [];
      });
    for (const directory of ['lib/core', 'lib/runtime', 'include']) inputs.push(...files(join(home, directory)));
    return digest(JSON.stringify(inputs.map(path => [path, realpathSync(path), digest(readFileSync(path))])));
  };
  const expectedTools = toolIdentity();
  const environmentDigest = digest(JSON.stringify(Object.entries(environment).sort(([a], [b]) => a.localeCompare(b))));
  const close = () => {
    if (ownedFixture !== null) {
      assert(existsSync(path), 'Owned fixture was removed');
      assert.equal(readFileSync(path, 'utf8'), ownedFixture, 'Owned fixture was changed');
      unlinkSync(path);
      assert(!existsSync(path), 'Owned fixture cleanup failed');
      ownedFixture = null;
    }
    closed = true;
    process.removeListener('exit', close);
  };
  process.once('exit', close);
  function execute(cases, registry, target, correspondence = false, label = 'probe') {
    assert(!closed, 'Execution workspace is closed');
    if (!['js', 'wasm', 'native'].includes(target) || !cases.length) throw new Error('Bad execution request');
    const source = workspace.check();
    assert.equal(toolIdentity(), expectedTools, 'Execution toolchain changed');
    const boundary = { version: 'actql-pipeline-execution-boundary/0.1', workspace: workspace.id,
      root: workspaceRoot, role: workspace.role, sourceDigest: source.digest,
      toolchainDigest: expectedTools, environmentDigest, fixtureDigest: digest(body), target, command: executionCommand(target) };
    const buildIdentity = digest(JSON.stringify(boundary));
    const fixtureBody = boundFixture(boundary);
    if (existsSync(path)) {
      assert(ownedFixture !== null && readFileSync(path, 'utf8') === ownedFixture,
        'Another pipeline batch owns the temporary fixture');
    }
    if (ownedFixture !== fixtureBody) { writeFileSync(path, fixtureBody); ownedFixture = fixtureBody; }
    const prior = built.get(target);
    if (prior?.buildIdentity === buildIdentity) {
      assert.deepEqual(artifacts(workspaceRoot, target, 'query_integration'), prior.artifacts,
        'Previously built execution artifacts changed');
    }
    const entries = cases.map((testCase, i) => ({ testCase, id: `${invocation}:${serial}:${i}:${testCase.id}`, program: program(testCase, registry) }));
    const inputs = payload(entries, correspondence);
    const directory = join(root, '.artifacts/relation-pipeline');
    mkdirSync(directory, { recursive: true });
    const sourcePath = `.artifacts/relation-pipeline/sources/${source.digest}.json`;
    mkdirSync(join(directory, 'sources'), { recursive: true });
    if (!existsSync(join(root, sourcePath))) writeFileSync(join(root, sourcePath), JSON.stringify(source, null, 2) + '\n');
    const prefix = `${invocation}-${String(serial++).padStart(4, '0')}-${label}-${target}`;
    const command = executionCommand(target).slice(1);
    writeFileSync(join(directory, `${prefix}.fixture.mbt`), fixtureBody);
    writeFileSync(join(directory, `${prefix}.inputs.json`), inputs);
    const result = spawnSync(moon, command, { cwd: workspaceRoot,
      env: { ...environment, [inputVariable]: inputs }, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
    const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
    writeFileSync(join(directory, `${prefix}.log`), output);
    if (result.error || result.status !== 0) {
      process.stderr.write(output);
      throw result.error ?? new Error(`Generated observation execution failed: ${prefix}`);
    }
    assert.equal(toolIdentity(), expectedTools, 'Execution toolchain changed');
    assert.equal(readFileSync(path, 'utf8'), fixtureBody, 'Execution fixture changed');
    const markers = output.split('\n').filter(line => line.startsWith('ACTQL_PIPELINE_BUILD:'));
    assert.deepEqual(markers, [`ACTQL_PIPELINE_BUILD:${buildIdentity}`], 'Executed binary/source/workspace identity mismatch');
    assert.match(output, /Total tests: 1, passed: 1, failed: 0/, 'Observation fixture did not pass exactly once');
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
    if (workspace.check().digest !== source.digest) throw new Error('Source changed during generated execution');
    const actualArtifacts = artifacts(workspaceRoot, target, 'query_integration');
    if (prior?.buildIdentity === buildIdentity) assert.deepEqual(actualArtifacts, prior.artifacts, 'Unchanged-source execution artifacts changed');
    built.set(target, { buildIdentity, artifacts: actualArtifacts });
    const archives = {};
    if (label === 'normal') {
      mkdirSync(join(directory, 'final-artifacts', target), { recursive: true });
      for (const [path, expected] of Object.entries(actualArtifacts)) {
        const suffix = path.slice(`_build/${target}/debug/test/query_integration/`.length);
        const archive = `.artifacts/relation-pipeline/final-artifacts/${target}/${suffix}`;
        mkdirSync(dirname(join(root, archive)), { recursive: true });
        copyFileSync(join(workspaceRoot, path), join(root, archive));
        if (digest(readFileSync(join(root, archive))) !== expected) throw new Error('Archive differs from executed artifact');
        archives[path] = archive;
      }
    }
    const receipt = { target, correspondence, boundary, buildIdentity, compiler: compiler.stdout.trim(), sourceDigest: source.digest, sourcePath,
      command: ['moon', ...command], exit: result.status, fixtureDigest: digest(fixtureBody),
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

  return Object.freeze({ execute, close });
}
const normal = createExecutor();
export const execute = normal.execute;
