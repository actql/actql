// Argument/environment preparation only; no public HTTP, venv, product or build.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync, spawn} from 'node:child_process';
import {mkdtemp, mkdir, rm, symlink, realpath, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename, join, resolve} from 'node:path';
import {pythonReleaseInstallSelection, pythonPublicConsumerEnvironment, pythonInstallCommand, pythonConsumerDestination,
  pythonUvConsumerEnvironment, pythonUvInstallCommand, pythonUvProject, pythonUvProjectParents, verifyPythonPublicReleaseBinding} from './release-public-install.mjs';
import {runPythonReleaseInstall} from './test-python-release-install.mjs';
import {observeChildFds} from './release-install-child.mjs';
import {freezeReleaseSet} from './release-set.mjs';
import {writeInertPairedPythonReleaseCohort} from './fixtures/release-python-wheels.mjs';

test('Python public consumer: fixed digest, target, absolute interpreter and new destination are explicit', () => {
  const value = pythonReleaseInstallSelection(['fixed', 'a'.repeat(64), 'python', '/selected/python', '/new/consumer']);
  assert.equal(value.kind, 'public-pypi'); assert.equal(value.python, '/selected/python');
  for (const args of [[], ['fixed'], ['fixed', 'HEAD', 'python', '/selected/python', '/new/consumer'],
    ['fixed', 'a'.repeat(64), 'python', 'python', '/new/consumer'],
    ['fixed', 'a'.repeat(64), 'python', '/selected/python', '/new/consumer', '--fallback']])
    assert.throws(() => pythonReleaseInstallSelection(args));
});

test('Python public consumer: fresh process environment has no Node path, source injection or publisher credentials', () => {
  const env = pythonPublicConsumerEnvironment({PATH: '/old/node:/usr/bin', HOME: '/old', PYTHONPATH: '/source',
    PYTHONHOME: '/old-python', PYTHONSTARTUP: '/old-startup', PIP_INDEX_URL: 'https://owner:secret@private',
    PIP_EXTRA_INDEX_URL: 'https://private', TWINE_PASSWORD: 'secret', HTTPS_PROXY: 'http://private',
    ACTQL_LOCAL_SOURCE_PROFILE: '/old-profile', NODE_OPTIONS: '--require old-code', LANG: 'C'}, '/new/consumer', '/new/consumer/venv/bin/python');
  assert.equal(env.PATH, '/new/consumer/venv/bin'); assert.equal(env.HOME, '/new/consumer/home');
  assert.equal(env.PIP_CONFIG_FILE, '/dev/null');
  assert.deepEqual(Object.keys(env).sort(), ['HOME', 'LANG', 'PATH', 'PIP_CONFIG_FILE', 'TEMP', 'TMP', 'TMPDIR'].sort());
});

test('Python public consumer: pip requests only the exact public entry using the shared version projection and no source builds', () => {
  const command = pythonInstallCommand('0.0.7-rc.1', 'actql', '/new/report.json');
  assert.deepEqual(command, ['-I', '-B', '-m', 'pip', '--isolated', 'install', '--index-url', 'https://pypi.org/simple',
    '--only-binary=:all:', '--no-cache-dir', '--no-compile', '--disable-pip-version-check', '--no-input',
    '--report', '/new/report.json', 'actql==0.0.7rc1']);
  assert.equal(pythonInstallCommand('0.0.7', 'actql-sdk', '/new/report.json').at(-1), 'actql-sdk==0.0.7');
  for (const version of ['patch', '0.0.7rc1', '0.0.7\n']) assert.throws(() => pythonInstallCommand(version, 'actql', '/report'));
  assert.throws(() => pythonInstallCommand('0.0.7', 'actql-local-runtime', '/report'));
});

test('Python public consumer: invalid launcher input stops before registry, installation or business execution', async () => {
  await assert.rejects(runPythonReleaseInstall([]), /usage:/u);
});

test('Python uv consumer: explicit tool, exact entry and isolated no-cache wheel-only command', () => {
  const args = ['fixed', 'a'.repeat(64), 'python', '/selected/python', '/new/consumer'];
  assert.equal(pythonReleaseInstallSelection(args).manager, 'pip');
  assert.equal(pythonReleaseInstallSelection([...args, '--uv', '/selected/uv']).uv, '/selected/uv');
  assert.throws(() => pythonReleaseInstallSelection([...args, '--uv', 'uv']));
  assert.throws(() => pythonReleaseInstallSelection([...args, '--uv', '/selected/uv', '--index', '/old']));
  assert.deepEqual(pythonUvInstallCommand('0.0.7-rc.1', 'actql', '/selected/python'),
    ['add', '--python', '/selected/python', '--no-managed-python', '--no-python-downloads', '--no-config',
      '--default-index', 'https://pypi.org/simple', '--no-build', '--no-sources', '--no-cache', '--link-mode', 'copy',
      '--no-install-project', '--no-workspace', '--bounds', 'exact', '--keyring-provider', 'disabled', 'actql==0.0.7rc1']);
  assert.throws(() => pythonUvInstallCommand('patch', 'actql', '/selected/python'));
  assert.throws(() => pythonUvInstallCommand('0.0.7', 'actql-local-runtime', '/selected/python'));
});

test('Python uv consumer: actual fresh project and environment exclude shared caches, active venv and injected sources', () => {
  const env = pythonUvConsumerEnvironment({PATH: '/old', HOME: '/old', UV_CACHE_DIR: '/shared',
    UV_INDEX: 'https://private', UV_PROJECT_ENVIRONMENT: '/old/venv', VIRTUAL_ENV: '/old/venv',
    UV_PYTHON: '/other/python', UV_CONFIG_FILE: '/old/uv.toml', LANG: 'C'}, '/fresh');
  assert.equal(env.PATH, ''); assert.equal(env.HOME, '/fresh/home'); assert.equal(env.UV_CACHE_DIR, '/fresh/uv-cache');
  assert.deepEqual(Object.keys(env).sort(), ['HOME', 'LANG', 'PATH', 'PIP_CONFIG_FILE', 'TEMP', 'TMP', 'TMPDIR', 'UV_CACHE_DIR'].sort());
  assert.equal(pythonUvProject('3.12'), '[project]\nname = "release-consumer-check"\nversion = "0.0.0"\nrequires-python = "==3.12.*"\ndependencies = []\n');
  assert.throws(() => pythonUvProject('3.12\n[tool.uv.sources]'));
});

test('Python uv consumer: enclosing workspace refuses before the new manager can mutate it', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-uv-ancestor-')); t.after(() => rm(root, {recursive: true}));
  await pythonUvProjectParents(join(root, 'new-consumer'));
  await writeFile(join(root, 'pyproject.toml'), '[tool.uv.workspace]\nmembers=["*"]\n');
  await assert.rejects(pythonUvProjectParents(join(root, 'new-consumer')), /enclosing project/u);
});

test('Python public consumer: actual own-child state descriptor observation distinguishes closed and still-held files', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-python-close-observer-')); t.after(() => rm(root, {recursive: true}));
  for (const held of [false, true]) {
    const child = spawn(process.execPath, ['-e',
      "const fs=require('node:fs');const fd=fs.openSync(process.argv[1],'w');if(process.argv[2]==='closed')fs.closeSync(fd);console.log('ready');process.stdin.once('data',()=>{if(process.argv[2]==='held')fs.closeSync(fd);process.stdin.destroy();});",
      join(root, 'state.db'), held ? 'held' : 'closed'], {stdio: ['pipe', 'pipe', 'pipe']});
    const terminal = new Promise((resolve, reject) => {child.once('error', reject); child.once('close', code => resolve(code));});
    t.after(() => child.stdin.end('done\n'));
    await new Promise((resolve, reject) => {child.stdout.once('data', resolve); child.once('error', reject);});
    if (held) await assert.rejects(observeChildFds(child, root));
    else assert.equal((await observeChildFds(child, root)).scopedStateFd0, true);
    child.stdin.end('done\n'); assert.equal(await terminal, 0);
  }
});

test('Python public consumer: physical destination refuses a source-parent alias or any existing state', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-python-consumer-path-')); t.after(() => rm(root, {recursive: true}));
  const source = join(root, 'source'), outside = join(root, 'outside'); await mkdir(source); await mkdir(outside);
  const alias = join(root, 'source-alias'); await symlink(source, alias);
  await assert.rejects(pythonConsumerDestination(join(alias, 'new-state'), [source]), /physically outside/u);
  await assert.rejects(pythonConsumerDestination(source, [source]), /physically outside/u);
  await assert.rejects(pythonConsumerDestination(outside, [source]), /already exists/u);
  assert.equal(await pythonConsumerDestination(join(outside, 'fresh'), [source]), join(await realpath(outside), 'fresh'));
});

test('Python public pair selects one original runtime per host and preserves all four approved identities', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-python-public-pair-')); t.after(() => rm(root, {recursive: true}));
  const pair = await writeInertPairedPythonReleaseCohort(join(root, 'original'), 'python3');
  const request = {schemaVersion: 'actql-release-request/0.1', releaseId: 'synthetic-public-pair', version: '0.0.3',
    source: {repository: 'https://github.com/actql/actql', commit: 'a'.repeat(40), branch: 'main'},
    targets: [{id: 'python', ecosystem: 'pypi', packages: ['actql-sdk', 'actql-local-runtime', 'actql'],
      platforms: ['linux-x64', 'darwin-arm64'], profiles: ['local'], destination: 'https://upload.pypi.org/legacy/', channels: []}],
    notes: {summary: 'Inert public binding test', breakingChanges: [], migration: [], knownLimitations: []}};
  const policy = {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0'], publicationAuthority: 'external-owner-approval-required'};
  const directory = join(root, 'fixed');
  const fixed = await freezeReleaseSet({request, policy, cohorts: [pair], destination: directory});
  const selection = {directory, manifestSha256: fixed.sha256, targetId: 'python'};
  const linux = await verifyPythonPublicReleaseBinding(selection, 'linux-x64');
  const darwin = await verifyPythonPublicReleaseBinding(selection, 'darwin-arm64');
  assert.deepEqual(linux.plan.approvedArtifacts, darwin.plan.approvedArtifacts);
  assert.equal(linux.plan.approvedArtifacts.length, 4);
  assert.equal(linux.plan.manifestSha256, darwin.plan.manifestSha256);
  assert.equal(linux.original.path, 'python/linux-x64/cohort.json');
  assert.equal(darwin.original.path, 'python/darwin-arm64/cohort.json');
  assert.deepEqual(linux.plan.artifacts[0], darwin.plan.artifacts[0]);
  assert.deepEqual(linux.plan.artifacts[2], darwin.plan.artifacts[2]);
  assert.match(linux.plan.artifacts[1].path, /manylinux_2_28_x86_64\.whl$/u);
  assert.match(darwin.plan.artifacts[1].path, /macosx_11_0_arm64\.whl$/u);
  await assert.rejects(verifyPythonPublicReleaseBinding(selection, 'darwin-x64'));
  await assert.rejects(verifyPythonPublicReleaseBinding({...selection, manifestSha256: '0'.repeat(64)}, 'darwin-arm64'));

  const actual = `${process.platform}-${process.arch}`;
  const selected = actual === 'darwin-arm64' ? darwin : linux, foreign = actual === 'darwin-arm64' ? linux : darwin;
  assert.equal(selected.plan.platform, actual);
  const plan = join(root, 'plan.json'), project = join(root, 'project.toml'), lock = join(root, 'uv.lock'), site = join(root, 'site');
  const writePlan = value => writeFile(plan, JSON.stringify(value));
  const python = execFileSync('python3', ['-I', '-B', '-c', 'import sys;print(sys.executable)'], {encoding: 'utf8'}).trim();
  const minor = execFileSync(python, ['-I', '-B', '-c', 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")'],
    {encoding: 'utf8'}).trim(), requiresPython = `==${minor}.*`;
  await writeFile(project, pythonUvProject(minor).replace('dependencies = []', 'dependencies = ["actql==0.0.3"]'));
  await writePlan(selected.plan);
  const body = files => {
    const runtime = selected.plan.artifacts[1].name;
    const packages = selected.plan.artifacts.flatMap(item => [
      '[[package]]', `name = "${item.name}"`, 'version = "0.0.3"', 'source = { registry = "https://pypi.org/simple" }',
      'wheels = [' + (item.name === runtime ? files : [item]).map(file =>
        `{ url = "https://files.pythonhosted.org/packages/aa/${basename(file.path)}", hash = "sha256:${file.sha256}", size = ${file.bytes} }`).join(', ') + ']',
    ]);
    return ['version = 1', 'revision = 3', `requires-python = "${requiresPython}"`,
      '[[package]]', 'name = "release-consumer-check"', 'version = "0.0.0"', 'source = { virtual = "." }',
      'dependencies = [{ name = "actql" }]', '[package.metadata]',
      'requires-dist = [{ name = "actql", specifier = "==0.0.3" }]', ...packages].join('\n') + '\n';
  };
  const audit = () => execFileSync(python, ['-I', '-B', '-c', [
    'import importlib.util,json,sys', 'from pathlib import Path',
    'spec=importlib.util.spec_from_file_location("audit",sys.argv[1])',
    'module=importlib.util.module_from_spec(spec)', 'spec.loader.exec_module(module)',
    'plan,lock,project,site=map(Path,sys.argv[2:])',
    'print(json.dumps(module.verify_installed_release(json.loads(plan.read_bytes()),lock,"actql",site,manager="uv",project_path=project)))',
  ].join('\n'), resolve('scripts/python_release_cohort.py'), plan, lock, project, site], {encoding: 'utf8', stdio: 'pipe'});
  const installed = (plan, site) => execFileSync(python, ['-I', '-B', '-c', [
    'import csv, json, stat, sys, zipfile', 'from pathlib import Path',
    'plan,root=map(Path,sys.argv[1:])', 'root.mkdir()',
    'for wheel in json.loads(plan.read_bytes())["artifacts"]:',
    '    with zipfile.ZipFile(wheel["path"]) as source:',
    '        names=[]',
    '        for entry in source.infolist():',
    '            name=entry.filename; names.append(name); path=root/name',
    '            path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(source.read(entry))',
    '            path.chmod(stat.S_IMODE(entry.external_attr>>16))',
    '        directory=next(name.split("/")[0] for name in names if name.endswith(".dist-info/METADATA"))',
    '        for name,value in (("INSTALLER",b"uv"),("REQUESTED",b"")):',
    '            path=directory+"/"+name; (root/path).write_bytes(value); names.append(path)',
    '        with (root/directory/"RECORD").open("w",newline="") as record:',
    '            csv.writer(record).writerows((name,"","") for name in names)',
  ].join('\n'), plan, site], {encoding: 'utf8', stdio: 'pipe'});
  const selectedRuntime = selected.plan.artifacts[1], sibling = foreign.plan.artifacts[1];
  await writeFile(lock, body([sibling, selectedRuntime]));
  installed(plan, site);
  const verified = JSON.parse(audit());
  assert.equal(verified.payloads[1].sha256, selectedRuntime.sha256);
  await writeFile(lock, body([sibling]));
  assert.throws(audit, error => error.stderr.includes('omits the selected original platform wheel'));
  await writeFile(lock, body([selectedRuntime, {...sibling, sha256: 'f'.repeat(64)}]));
  assert.throws(audit, error => error.stderr.includes('differs from the fixed original wheel'));
  await writeFile(lock, body([sibling, selectedRuntime]));
  await writePlan({...selected.plan, artifacts: foreign.plan.artifacts});
  assert.throws(audit, error => error.stderr.includes('differs from the installed interpreter platform'));
});
