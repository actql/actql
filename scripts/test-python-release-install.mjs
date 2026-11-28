// Fresh official-PyPI consumer for the existing fixed cohort and business
// fixture. No builder, publisher, injected runtime or old-state recovery.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, lstat, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {observeChildFds} from './release-install-child.mjs';
import {verifyReleaseSet} from './release-set.mjs';
import {observePythonReleaseTarget} from './release-registry.mjs';
import {pythonReleaseInstallSelection, pythonPublicConsumerEnvironment, pythonInstallCommand, pythonConsumerDestination,
  pythonUvConsumerEnvironment, pythonUvInstallCommand, pythonUvProject, pythonUvProjectParents, verifyPythonPublicReleaseBinding} from './release-public-install.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

async function uvToolIdentity(path) {
  const actual = await realpath(path), before = await lstat(actual);
  assert(before.isFile() && !before.isSymbolicLink() && (before.mode & 0o111) !== 0 && before.size <= 128 * 1024 * 1024);
  const bytes = await readFile(actual), after = await lstat(actual);
  const stamp = value => [value.dev, value.ino, value.size, value.mode, value.mtimeMs, value.ctimeMs];
  assert.deepEqual(stamp(after), stamp(before)); assert.equal(bytes.length, before.size);
  return {path, actual, stamp: stamp(before), sha256: sha(bytes)};
}

export async function runPythonReleaseInstall(args) {
  const selection = pythonReleaseInstallSelection(args);
  const actualPlatform = `${process.platform}-${process.arch}`;
  const {fixed, target, cohort, original, plan} = await verifyPythonPublicReleaseBinding(selection, actualPlatform);
  const root = await pythonConsumerDestination(selection.consumer, [repository, selection.directory]);
  if (selection.manager === 'uv') await pythonUvProjectParents(root);
  await mkdir(root, {mode: 0o700}); // Fresh or fail, never restore an earlier Run.
  const records = [], originalFixture = join(repository, 'scripts/fixtures/python-product-installed.py');
  const auditor = join(root, 'python_release_cohort.py'); await copyFile(join(repository, 'scripts/python_release_cohort.py'), auditor);
  const run = async (command, args, cwd, env, {state = null} = {}) => {
    let record;
    await new Promise((resolveRun, rejectRun) => {
      const child = spawn(command, args, {cwd, env, stdio: ['pipe', 'pipe', 'pipe']});
      record = {command, args, pid: child.pid, startedAt: new Date().toISOString(), stdout: '', stderr: '', code: null};
      records.push(record); let bytes = 0, lines = '', observing = false, observation = Promise.resolve();
      child.stdin.on('error', failure => {record.stdinFailure = failure.message;});
      const timer = setTimeout(() => {record.terminationReason = 'original-child-timeout'; child.kill('SIGTERM');}, 180_000);
      child.stdout.on('data', chunk => {
        bytes += chunk.length; if (bytes > 8 * 1024 * 1024) {record.terminationReason = 'output-limit'; child.kill('SIGTERM'); return;}
        record.stdout += chunk.toString(); lines += chunk.toString();
        let end;
        while ((end = lines.indexOf('\n')) !== -1) {
          const line = lines.slice(0, end); lines = lines.slice(end + 1);
          if (!state) continue;
          let body; try {body = JSON.parse(line);} catch {continue;}
          if (body.stage === 'close-observation-ack') {
            record.closeObservationAcknowledged = body.pid === child.pid; continue;
          }
          if (observing) continue;
          if (body.stage !== 'closed') continue;
          observing = true;
          observation = (async () => {
            assert.equal(body.pid, child.pid); record.close = await observeChildFds(child, state);
            child.stdin.end('observed\n');
          })().catch(failure => {record.closeObservationFailure = failure.message; child.stdin.end('unobserved\n');});
        }
      });
      child.stderr.on('data', chunk => {
        bytes += chunk.length; if (bytes > 8 * 1024 * 1024) {record.terminationReason = 'output-limit'; child.kill('SIGTERM');}
        else record.stderr += chunk.toString();
      });
      child.once('error', failure => {record.spawnFailure = failure.message;});
      child.once('close', async (code, signal) => {
        clearTimeout(timer); await observation; Object.assign(record, {code, signal, endedAt: new Date().toISOString()});
        try {
          await writeFile(join(root, `command-${records.length}.json`), `${JSON.stringify(record, null, 2)}\n`, {flag: 'wx', mode: 0o600});
          assert.equal(code, 0, record.stderr); assert(!record.terminationReason && !record.spawnFailure);
          if (state) {
            assert.equal(record.close?.scopedStateFd0, true, 'First close/live descriptor observation unproven');
            assert.equal(record.closeObservationAcknowledged, true, 'Original child did not acknowledge the completed live observation');
            assert(!record.stdinFailure);
          }
          resolveRun();
        } catch (failure) {rejectRun(failure);}
      });
      if (!state) child.stdin.end();
    });
    return record;
  };
  const setupEnv = pythonPublicConsumerEnvironment(process.env, root, selection.python);
  for (const path of [setupEnv.HOME, setupEnv.TMPDIR]) await mkdir(path, {mode: 0o700});
  let uvTool = null, uvMinor = null;
  if (selection.manager === 'uv') {
    uvTool = await uvToolIdentity(selection.uv);
    const version = await run(selection.uv, ['--version'], root, pythonUvConsumerEnvironment(process.env, root));
    assert.match(version.stdout, /^uv [0-9]+\.[0-9]+\.[0-9]+(?: \([^\r\n]+\))?\n$/u); assert.equal(version.stderr, '');
    uvTool.version = version.stdout.trim();
    const minor = await run(selection.python, ['-I', '-B', '-c',
      "import sys;print(str(sys.version_info.major)+'.'+str(sys.version_info.minor))"], root, setupEnv);
    uvMinor = minor.stdout.trim(); pythonUvProject(uvMinor);
  }
  const platform = await run(selection.python, ['-I', '-B', '-c',
    "import platform,sys;print({('darwin','arm64'):'darwin-arm64',('linux','x86_64'):'linux-x64'}.get((sys.platform,platform.machine()),'unsupported'))"],
  root, setupEnv);
  assert.equal(platform.stdout, actualPlatform + '\n', 'Selected Python interpreter differs from the actual consumer platform');
  // Build-time verifier may use the existing shared Node version projection;
  // that environment is never passed to the installed consumer.
  const verification = await run(selection.python, [join(repository, 'scripts/python_release_cohort.py'), '--verify-directory',
    dirname(join(selection.directory, original.path)), '--source', fixed.manifest.request.source.commit,
    '--version', fixed.manifest.release.pythonVersion, '--frozen-layout',
    ...(cohort.kind === 'python-wheel-pair' ? ['--frozen-wheels', dirname(join(selection.directory, cohort.path))] : [])],
  root, process.env);
  const verified = JSON.parse(verification.stdout);
  assert.equal(verified.manifest_sha256, original.sha256);
  assert.equal(verified.cohort.platform, actualPlatform);
  const observe = () => observePythonReleaseTarget(selection.directory, fixed.sha256, target.id);
  const initial = await observe();
  await writeFile(join(root, 'public-before.json'), `${JSON.stringify(initial, null, 2)}\n`, {flag: 'wx', mode: 0o600});
  assert(initial.observations.every(value => value.state === 'present'), 'Every original Python wheel must be public with exact bytes');
  const planPath = join(root, 'install-plan.json'), planBytes = Buffer.from(`${JSON.stringify(plan, null, 2)}\n`);
  await writeFile(planPath, planBytes, {flag: 'wx', mode: 0o600});
  const audits = [];
  for (const entry of ['actql-sdk', 'actql']) {
    const consumer = join(root, entry); await mkdir(consumer, {mode: 0o700});
    const uv = selection.manager === 'uv';
    if (!uv) await run(selection.python, ['-I', '-B', '-m', 'venv', join(consumer, 'venv')], root, setupEnv);
    const python = join(consumer, uv ? '.venv/bin/python' : 'venv/bin/python');
    const env = pythonPublicConsumerEnvironment(process.env, consumer, python);
    for (const path of [env.HOME, env.TMPDIR]) await mkdir(path, {mode: 0o700});
    const report = join(consumer, uv ? 'uv.lock' : 'pip-report.json'), project = join(consumer, 'pyproject.toml');
    const verifyToolAbsence = () => run(python, ['-I', '-B', '-c', "import shutil;assert all(shutil.which(x) is None for x in ('node','npm','actql'))"], consumer, env);
    if (uv) {
      await writeFile(project, pythonUvProject(uvMinor), {flag: 'wx', mode: 0o600});
      await run(selection.uv, pythonUvInstallCommand(fixed.manifest.release.version, entry, selection.python), consumer,
        pythonUvConsumerEnvironment(process.env, consumer));
    } else {
      await verifyToolAbsence();
      await run(python, pythonInstallCommand(fixed.manifest.release.version, entry, report), consumer, env);
    }
    await verifyToolAbsence();
    const audit = async () => {
      const result = await run(python, ['-I', '-B', auditor, '--audit-installed', planPath,
        ...(uv ? ['--uv-lock', report, '--uv-project', project] : ['--pip-report', report]), '--entry', entry], consumer, env);
      const value = JSON.parse(result.stdout); audits.push(value); return value;
    };
    const originalAudit = await audit();
    const fixture = join(consumer, 'installed.py'); await copyFile(originalFixture, fixture);
    if (entry === 'actql-sdk') await run(python, ['-I', '-B', fixture, '--version', fixed.manifest.release.pythonVersion, '--mode', 'sdk-only'], consumer, env);
    else for (const facade of ['sync', 'async']) {
      const app = join(consumer, facade); await mkdir(app, {mode: 0o700});
      const appEnv = pythonPublicConsumerEnvironment(process.env, app, python);
      for (const path of [appEnv.HOME, appEnv.TMPDIR]) await mkdir(path, {mode: 0o700});
      const receipt = join(app, 'original.json');
      for (const phase of ['initial', 'resume']) await run(python, ['-I', '-B', fixture, '--version', fixed.manifest.release.pythonVersion,
        '--mode', 'local', '--facade', facade, '--phase', phase, '--receipt', receipt, '--await-close-observation'], app, appEnv,
      {state: appEnv.HOME});
    }
    assert.deepEqual(await audit(), originalAudit, 'Original manager evidence or installed payload changed during consumption');
    await verifyToolAbsence();
  }
  const after = await observe();
  await writeFile(join(root, 'public-after.json'), `${JSON.stringify(after, null, 2)}\n`, {flag: 'wx', mode: 0o600});
  assert(after.observations.every(value => value.state === 'present'));
  await verifyReleaseSet(selection.directory, {expectedSha256: fixed.sha256});
  assert.deepEqual(await readFile(planPath), planBytes);
  if (uvTool) {
    const {version, ...identity} = uvTool;
    assert.deepEqual(await uvToolIdentity(selection.uv), identity, 'Selected uv executable changed');
  }
  const result = {schemaVersion: 'actql-python-public-install/0.1', manifestSha256: fixed.sha256, targetId: target.id,
    ...(cohort.kind === 'python-wheel-pair' ? {sourceSha: fixed.manifest.request.source.commit,
      packageVersion: fixed.manifest.release.version, cohortManifestSha256: cohort.sha256,
      platformManifestSha256: original.sha256} : {}),
    manager: selection.manager, uvTool,
    platform: actualPlatform, publicRegistry: 'https://pypi.org/simple', fixtureSha256: sha(await readFile(originalFixture)),
    nodeFreeConsumer: true, audits, records, qualification: 'Only the actually completed selected installed consumer/close scope; no approval or publication authority'};
  await writeFile(join(root, 'result.json'), `${JSON.stringify(result, null, 2)}\n`, {flag: 'wx', mode: 0o600});
  return result;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  console.log(JSON.stringify(await runPythonReleaseInstall(process.argv.slice(2)), null, 2));
