// dbt-to-ActQL compatibility probe (manual; not a CI job).
//
// Compiles probes/dbt-compat/project with pinned dbt-core and dbt-duckdb, then
// submits each compiled model, byte for byte as dbt wrote it, through the
// packed public ActQL Client on installed Local and HTTP. Evidence (original
// models, compiled SQL, manifest excerpt, commands, results, versions and
// digests) is written under _build/dbt-compat-evidence/ before the disposable
// environment (Python venv, ActQL installation) is removed. A failed run keeps
// both; ACTQL_TEST_PRESERVE_SCRATCH=1 keeps the environment after success.
//
// Requires Python 3.13 (ACTQL_PROBE_PYTHON, default `python3.13`), network
// access for the initial wheel installation, and a repository build that can
// pack the Client packages. dbt compile itself runs offline.
//
// Test only: ACTQL_DBT_PROBE_INJECT_RUN_FAILURE=<case>,... records those
// cases' successful Runs as Run failures (marked `injected`), to show that a
// Run failure fails the probe and keeps the evidence.
import {spawnSync} from 'node:child_process';
import {createHash, randomBytes} from 'node:crypto';
import {existsSync} from 'node:fs';
import {cp, mkdir, readdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join, relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {probeStatus} from './fixtures/dbt-compat-judge.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {CLIENT_PACKAGES, packedClientPackage, packedNpmCache} from
  './packed-client-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const probe = join(repository, 'probes', 'dbt-compat');
const build = join(repository, '_build');
const specification = JSON.parse(await readFile(join(probe, 'cases.json'),
  'utf8'));
const started = Date.now();
const evidence = join(build, 'dbt-compat-evidence',
  `${new Date(started).toISOString().replaceAll(':', '-')}-${
    randomBytes(3).toString('hex')}`);
await mkdir(evidence, {recursive: true});
console.log(`dbt compatibility probe evidence: ${evidence}`);

const scratch = await createOwnedScratch({parent: build, prefix: 'dbt-compat-',
  label: 'dbt compatibility probe',
  digests: () => CLIENT_PACKAGES.map(name =>
    join('install', `actql-${name}-0.0.0-development.tgz`))});
const root = scratch.path;

const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const commands = [];
const persistCommands = () => writeFile(join(evidence, 'commands.json'),
  JSON.stringify(commands, null, 2) + '\n');

// Run one command, keep its argv, exit, duration and streams as evidence,
// and fail the probe on an unexpected exit.
async function run(command, args, {cwd = root, env = process.env,
  timeout = 600_000, allowFailure = false} = {}) {
  const begin = performance.now();
  const result = spawnSync(command, args, {cwd, env, encoding: 'utf8',
    timeout, killSignal: 'SIGKILL', maxBuffer: 64 * 1024 * 1024});
  const id = String(commands.length + 1).padStart(3, '0');
  commands.push({id, command, args: args.map(value =>
    String(value).replaceAll(root, '<scratch>').replaceAll(repository,
      '<repository>/')), cwd: relative(root, cwd) || '.',
  status: result.status, signal: result.signal,
  elapsedMs: Math.round(performance.now() - begin),
  error: result.error?.code ?? null});
  await writeFile(join(evidence, `${id}.stdout.log`), result.stdout ?? '');
  await writeFile(join(evidence, `${id}.stderr.log`), result.stderr ?? '');
  await persistCommands();
  if (!allowFailure && (result.error || result.status !== 0)) {
    throw new Error(`${command} ${args.join(' ')} failed (${id}); see ${
      evidence}`, {cause: result.error});
  }
  return result;
}

// 1. Python and the pinned dbt installation (the only networked step).
const python = process.env.ACTQL_PROBE_PYTHON ?? 'python3.13';
const pythonVersion = (await run(python, ['--version'])).stdout.trim();
if (!/^Python 3\.13\.\d+$/u.test(pythonVersion)) {
  throw new Error(`requirements.txt is resolved for Python 3.13, not ${
    pythonVersion}`);
}
const venv = join(root, 'venv');
await run(python, ['-m', 'venv', venv]);
const pip = join(venv, 'bin', 'pip');
const pipEnv = {...process.env, PIP_DISABLE_PIP_VERSION_CHECK: '1',
  PIP_CACHE_DIR: join(root, 'pip-cache')};
await run(pip, ['install', '--require-hashes', '--only-binary', ':all:',
  '--no-deps', '-r', join(probe, 'requirements.txt')], {env: pipEnv});
await run(pip, ['list', '--format', 'json'], {env: pipEnv});
const versions = JSON.parse((await run(join(venv, 'bin', 'python'), ['-c',
  'import json, importlib.metadata as m, platform; print(json.dumps({' +
  '"python": platform.python_version(), ' +
  '"dbt-core": m.version("dbt-core"), "dbt-duckdb": m.version("dbt-duckdb"), ' +
  '"dbt-adapters": m.version("dbt-adapters"), ' +
  '"dbt-common": m.version("dbt-common"), "duckdb": m.version("duckdb")}))'
])).stdout);

// 2. dbt compile, offline, from copies of the projects (dbt writes target/
// and logs/ next to the project).
const projects = join(root, 'projects');
await cp(join(probe, 'project'), join(projects, 'project'), {recursive: true});
await mkdir(join(projects, 'project-default-quoting'));
await cp(join(probe, 'project-default-quoting', 'dbt_project.yml'),
  join(projects, 'project-default-quoting', 'dbt_project.yml'));
await cp(join(probe, 'project', 'profiles.yml'),
  join(projects, 'project-default-quoting', 'profiles.yml'));
await cp(join(probe, 'project', 'models'),
  join(projects, 'project-default-quoting', 'models'), {recursive: true});
await cp(join(probe, 'project'), join(evidence, 'source', 'project'),
  {recursive: true});
await cp(join(probe, 'project-default-quoting'),
  join(evidence, 'source', 'project-default-quoting'), {recursive: true});

const dbtEnv = {...process.env, DBT_SEND_ANONYMOUS_USAGE_STATS: 'false',
  DO_NOT_TRACK: '1', DBT_PARTIAL_PARSE: 'false'};
// On macOS the compile runs with all outbound network denied, so success also
// shows that it needed none. Elsewhere the run records that it was not
// isolated; the log and file checks below still apply.
const sandbox = existsSync('/usr/bin/sandbox-exec');
const isolation = sandbox
  ? 'sandbox-exec with (deny network-outbound)' : 'not network-isolated';
const compileChecks = {};
for (const project of ['project', 'project-default-quoting']) {
  const directory = join(projects, project);
  const dbtArgs = ['compile', '--no-populate-cache', '--profiles-dir', '.',
    '--target-path', 'target', '--log-path', 'logs', '--log-level-file',
    'debug'];
  const dbt = join(venv, 'bin', 'dbt');
  await run(sandbox ? '/usr/bin/sandbox-exec' : dbt, sandbox
    ? ['-p', '(version 1)(allow default)(deny network-outbound)', dbt,
      ...dbtArgs] : dbtArgs, {cwd: directory, env: dbtEnv});
  const log = await readFile(join(directory, 'logs', 'dbt.log'), 'utf8');
  await mkdir(join(evidence, 'dbt', project), {recursive: true});
  await writeFile(join(evidence, 'dbt', project, 'dbt.log'), log);
  const entries = await readdir(directory, {recursive: true});
  compileChecks[project] = {
    connectionOpens: (log.match(/Opening a new connection/gu) ?? []).length,
    duckdbFiles: entries.filter(name => /\.duckdb(\.wal)?$/u.test(name)),
    userFile: existsSync(join(directory, '.user.yml')),
    isolation,
  };
}

// 3. Compiled SQL exactly as written by dbt, with its manifest provenance.
const compiled = {};
const manifestExcerpt = {};
for (const item of specification.cases) {
  const directory = join(projects, item.project);
  const file = join(directory, 'target', 'compiled', 'actql_probe', 'models',
    'cases', `${item.model}.sql`);
  const bytes = await readFile(file);
  compiled[item.name] = bytes.toString('utf8');
  await mkdir(join(evidence, 'compiled'), {recursive: true});
  await writeFile(join(evidence, 'compiled', `${item.name}.sql`), bytes);
  const manifest = JSON.parse(await readFile(join(directory, 'target',
    'manifest.json'), 'utf8'));
  const node = manifest.nodes[`model.actql_probe.${item.model}`];
  manifestExcerpt[item.name] = {project: item.project,
    dbtVersion: manifest.metadata.dbt_version,
    adapterType: manifest.metadata.adapter_type, unique_id: node.unique_id,
    original_file_path: node.original_file_path, checksum: node.checksum,
    raw_code: node.raw_code, compiled_code: node.compiled_code,
    relation_name: node.relation_name, depends_on: node.depends_on,
    extra_ctes: node.extra_ctes, quoting: manifest.metadata.quoting ?? null,
    compiled_sha256: sha256(bytes)};
}
await writeFile(join(evidence, 'manifest-excerpt.json'),
  JSON.stringify(manifestExcerpt, null, 2) + '\n');

// 4. A clean ActQL installation from the packed public packages.
const install = join(root, 'install');
await mkdir(install);
const npmEnv = {...process.env, npm_config_cache: packedNpmCache(install)};
const tarballs = {};
for (const name of CLIENT_PACKAGES) {
  await packedClientPackage({repository, name, destination: install,
    pack: () => run('npm', ['pack', '--pack-destination', install, '--json'],
      {cwd: join(repository, 'packages', name), env: npmEnv})});
  const file = `actql-${name}-0.0.0-development.tgz`;
  tarballs[file] = sha256(await readFile(join(install, file)));
}
await writeFile(join(install, 'package.json'),
  '{"private":true,"type":"module"}\n');
await run('npm', ['install', '--ignore-scripts', '--no-save',
  ...CLIENT_PACKAGES.map(name => join(install,
    `actql-${name}-0.0.0-development.tgz`))], {cwd: install, env: npmEnv});
for (const [source, destination] of [
  ['scripts/fixtures/dbt-compat-acceptance.mjs', 'acceptance.mjs'],
  ['scripts/fixtures/dbt-compat-judge.mjs', 'dbt-compat-judge.mjs'],
  ['adapters/host-node/fixtures/query-amount-environment.json',
    'source-environment.json'],
  ['spec/local-check-environment.json', 'base-environment.json'],
]) {
  await cp(join(repository, source), join(install, destination));
}
await cp(join(probe, 'programs'), join(install, 'programs'), {recursive: true});
await cp(join(probe, 'cases.json'), join(install, 'cases.json'));
await writeFile(join(install, 'compiled.json'), JSON.stringify(compiled));
await run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: install});

// 5. The compiled models through installed Local and HTTP.
const runtimeEnv = {...npmEnv, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
  NODE_EXTRA_CA_CERTS: join(install, 'remote.crt')};
for (const name of ['MOON_HOME', 'ACTQL_LOCAL_STATE_DIR',
  'ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE']) {
  delete runtimeEnv[name];
}
const resultsPath = join(evidence, 'results.json');
const acceptance = await run(process.execPath, ['acceptance.mjs',
  'cases.json', 'compiled.json', resultsPath], {cwd: install, env: runtimeEnv,
  timeout: 900_000, allowFailure: true});
const recorded = existsSync(resultsPath)
  ? JSON.parse(await readFile(resultsPath, 'utf8')) : {outcomes: []};
const results = recorded.outcomes;
// An acceptance that stopped without recording why is itself a fault.
const fault = recorded.fault ?? (acceptance.status === 0 ? undefined
  : {message: `acceptance exited ${acceptance.status ?? acceptance.signal
  } without recording a fault`});

// 6. Summary, written before the environment may be removed.
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: repository,
  encoding: 'utf8'}).stdout.trim();
const dirty = spawnSync('git', ['status', '--porcelain', '--untracked-files=no'],
  {cwd: repository, encoding: 'utf8'}).stdout.trim() !== '';
const compileProblems = Object.entries(compileChecks).filter(([, check]) =>
  check.connectionOpens !== 0 || check.duckdbFiles.length !== 0 ||
  check.userFile);
const {status, failures} = probeStatus({outcomes: results, compileProblems,
  fault});
const injected = process.env.ACTQL_DBT_PROBE_INJECT_RUN_FAILURE;
const summary = {
  version: 'actql-dbt-compat-evidence/0.1',
  status,
  ...(fault === undefined ? {} : {fault}),
  ...(injected ? {injectedRunFailures: injected.split(',')} : {}),
  startedAt: new Date(started).toISOString(),
  elapsedMs: Date.now() - started,
  platform: `${process.platform}-${process.arch}`,
  node: process.version,
  actql: {revision, trackedChanges: dirty, tarballs},
  dbt: {...versions, requirementsSha256: sha256(await readFile(join(probe,
    'requirements.txt'))), compileChecks},
  outcomes: results.map(({case: name, transport, stage, verdict, code,
    problems, injected}) => ({case: name, transport, stage, verdict,
    ...(code === undefined ? {} : {code}),
    ...(injected === undefined ? {} : {injected}),
    ...(problems === undefined ? {} : {problems})})),
};
await writeFile(join(evidence, 'summary.json'),
  JSON.stringify(summary, null, 2) + '\n');
for (const item of summary.outcomes) {
  console.log(`${item.transport}\t${item.case}\t${item.stage}\t${
    item.verdict}${item.code ? '\t' + item.code : ''}`);
}
console.log(`dbt compatibility probe ${summary.status} in ${
  Math.round(summary.elapsedMs / 1000)} s; evidence: ${evidence}`);
if (summary.status !== 'passed') {
  for (const [project, check] of compileProblems) {
    console.error(`dbt compile check failed for ${project}: ${
      JSON.stringify(check)}`);
  }
  for (const item of failures) console.error(JSON.stringify(item));
  if (fault !== undefined) console.error(`fault: ${JSON.stringify(fault)}`);
  process.exitCode = 1;
} else {
  // Every process this probe started has exited (spawnSync) and the
  // evidence above is written.
  scratch.passed();
}
