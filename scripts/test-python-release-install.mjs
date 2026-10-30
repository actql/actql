// Fresh official-PyPI consumer for the existing fixed cohort and business
// fixture. No builder, publisher, injected runtime or old-state recovery.
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, lstat, mkdir, readFile, readdir, readlink, writeFile} from 'node:fs/promises';
import {dirname, join, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyReleaseSet} from './release-set.mjs';
import {observePythonReleaseTarget} from './release-registry.mjs';
import {pythonReleaseInstallSelection, pythonPublicConsumerEnvironment, pythonInstallCommand, pythonConsumerDestination} from './release-public-install.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

export async function observeChildFds(child, state) {
  assert.equal(child.exitCode, null); assert.equal(child.signalCode, null);
  const original = await lstat(state); assert(original.isDirectory() && !original.isSymbolicLink());
  if (process.platform === 'darwin') {
    const args = ['-nP', '-a', '-p', String(child.pid), '+D', state, '-F', 'pfn'];
    const result = spawnSync('/usr/sbin/lsof', args, {encoding: 'utf8', timeout: 10_000, maxBuffer: 1024 * 1024});
    assert(result.status === 1 && result.stdout === '' && result.stderr === '' && !result.error,
      'Original still-live Python child has unavailable/nonempty scoped descriptor observation');
    assert.equal(child.exitCode, null); assert.equal(child.signalCode, null);
    return {pid: child.pid, aliveAfterClose: true, scopedStateFd0: true, command: ['/usr/sbin/lsof', ...args],
      exitCode: result.status, stdout: result.stdout, stderr: result.stderr};
  }
  // A future genuine Linux supplier still uses this own-child observation;
  // this branch cannot make the current macOS-only runtime accepted on Linux.
  assert.equal(process.platform, 'linux');
  const fdRoot = `/proc/${child.pid}/fd`, descriptors = await readdir(fdRoot); assert(descriptors.length <= 4096);
  const scoped = [];
  for (const fd of descriptors) {
    let target;
    try {target = await readlink(join(fdRoot, fd));} catch (failure) {if (failure.code === 'ENOENT') continue; throw failure;}
    const path = target.replace(/ \(deleted\)$/u, '');
    if (path === state || path.startsWith(`${state}${sep}`)) scoped.push({fd, target});
  }
  assert.deepEqual(scoped, []); assert.equal(child.exitCode, null); assert.equal(child.signalCode, null);
  return {pid: child.pid, aliveAfterClose: true, scopedStateFd0: true, descriptorCount: descriptors.length};
}

export async function runPythonReleaseInstall(args) {
  const selection = pythonReleaseInstallSelection(args), fixed = await verifyReleaseSet(selection.directory,
    {expectedSha256: selection.manifestSha256});
  const target = fixed.manifest.request.targets.find(value => value.id === selection.targetId);
  assert.equal(target?.ecosystem, 'pypi'); assert.equal(target.destination, 'https://upload.pypi.org/legacy/');
  assert.deepEqual(target.packages, ['actql-sdk', 'actql-local-runtime', 'actql']);
  const cohort = fixed.manifest.cohorts.find(value => value.targetId === target.id); assert.equal(cohort.kind, 'python-wheels');
  const actualPlatform = `${process.platform}-${process.arch}`;
  assert.equal(actualPlatform, 'darwin-arm64', 'No selected normal Linux/other-platform Python supplier or verifier');
  assert(target.platforms.includes(actualPlatform)); assert(target.profiles.includes('local'));
  const root = await pythonConsumerDestination(selection.consumer, [repository, selection.directory]);
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
  // Build-time verifier may use the existing shared Node version projection;
  // that environment is never passed to the installed consumer.
  await run(selection.python, [join(repository, 'scripts/python_release_cohort.py'), '--verify-directory',
    dirname(join(selection.directory, cohort.path)), '--source', fixed.manifest.request.source.commit,
    '--version', fixed.manifest.release.pythonVersion, '--frozen-layout'], root, process.env);
  const observe = () => observePythonReleaseTarget(selection.directory, fixed.sha256, target.id);
  const initial = await observe();
  await writeFile(join(root, 'public-before.json'), `${JSON.stringify(initial, null, 2)}\n`, {flag: 'wx', mode: 0o600});
  assert(initial.observations.every(value => value.state === 'present'), 'Every original Python wheel must be public with exact bytes');
  const plan = {manifestSha256: fixed.sha256, targetId: target.id,
    artifacts: fixed.manifest.artifacts.filter(value => value.targetId === target.id).map(value =>
      ({name: value.name, version: value.version, path: join(selection.directory, value.path), bytes: value.bytes, sha256: value.sha256}))};
  const planPath = join(root, 'install-plan.json'), planBytes = Buffer.from(`${JSON.stringify(plan, null, 2)}\n`);
  await writeFile(planPath, planBytes, {flag: 'wx', mode: 0o600});
  const audits = [];
  for (const entry of ['actql-sdk', 'actql']) {
    const consumer = join(root, entry); await mkdir(consumer, {mode: 0o700});
    await run(selection.python, ['-I', '-B', '-m', 'venv', join(consumer, 'venv')], root, setupEnv);
    const python = join(consumer, 'venv/bin/python'), env = pythonPublicConsumerEnvironment(process.env, consumer, python);
    for (const path of [env.HOME, env.TMPDIR]) await mkdir(path, {mode: 0o700});
    const report = join(consumer, 'pip-report.json');
    const verifyToolAbsence = () => run(python, ['-I', '-B', '-c', "import shutil;assert all(shutil.which(x) is None for x in ('node','npm','actql'))"], consumer, env);
    await verifyToolAbsence();
    await run(python, pythonInstallCommand(fixed.manifest.release.version, entry, report), consumer, env);
    await verifyToolAbsence();
    const audit = async () => {
      const result = await run(python, ['-I', '-B', auditor, '--audit-installed', planPath, '--pip-report', report, '--entry', entry], consumer, env);
      audits.push(JSON.parse(result.stdout));
    };
    await audit();
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
    await audit();
    await verifyToolAbsence();
  }
  const after = await observe();
  await writeFile(join(root, 'public-after.json'), `${JSON.stringify(after, null, 2)}\n`, {flag: 'wx', mode: 0o600});
  assert(after.observations.every(value => value.state === 'present'));
  await verifyReleaseSet(selection.directory, {expectedSha256: fixed.sha256});
  assert.deepEqual(await readFile(planPath), planBytes);
  const result = {schemaVersion: 'actql-python-public-install/0.1', manifestSha256: fixed.sha256, targetId: target.id,
    platform: actualPlatform, publicRegistry: 'https://pypi.org/simple', fixtureSha256: sha(await readFile(originalFixture)),
    nodeFreeConsumer: true, audits, records, qualification: 'Only the actually completed selected installed consumer/close scope; no approval or publication authority'};
  await writeFile(join(root, 'result.json'), `${JSON.stringify(result, null, 2)}\n`, {flag: 'wx', mode: 0o600});
  return result;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  console.log(JSON.stringify(await runPythonReleaseInstall(process.argv.slice(2)), null, 2));
