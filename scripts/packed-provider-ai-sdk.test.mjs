import assert from 'node:assert/strict';
import test from 'node:test';
import {access, lstat, mkdtemp, mkdir, writeFile, readFile, copyFile, cp, rm, glob} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {basename, dirname, join} from 'node:path';
import {parse} from 'yaml';
import {CLIENT_PACKAGES, packClientPackages} from './packed-client-packages.mjs';
import {prepareHealthPackages} from './health-monitor-adapters.mjs';
import {runPackedProviderAI, checkPackedProviderObservation,
  registeredAuthorityAcceptanceCases, registeredProviderAcceptanceCases} from './test-packed-provider-ai-sdk.mjs';

import {observeEnteredCancellation} from './fixtures/normal-provider-diagnostics.fixture.mjs';

test('entered Model cancellation starts the concurrent wait only after original peer entry', async () => {
  const entered = Promise.withResolvers();
  const observed = Promise.withResolvers();
  const steps = [];
  const terminal = {status: 'needs_reconciliation'};
  const result = observeEnteredCancellation({
    awaitEntry: () => entered.promise,
    wait() {
      steps.push('wait');
      return observed.promise;
    },
    async cancel() {
      steps.push('cancel');
      observed.resolve(terminal);
    },
    record: stage => steps.push(stage),
  });
  assert.deepEqual(steps, ['entry_pending']);
  entered.resolve();
  assert.equal(await result, terminal);
  assert.deepEqual(steps, ['entry_pending', 'entered', 'wait', 'wait_started', 'cancel', 'wait_returned']);
});

test('missing Model peer entry does not start wait or issue cancellation', async () => {
  const failure = new Error('OriginalEnteredRequestUnavailable');
  const steps = [];
  await assert.rejects(observeEnteredCancellation({
    awaitEntry: async () => { throw failure; },
    wait: () => assert.fail('Unexpected wait'),
    cancel: () => assert.fail('Unexpected cancel'),
    record: stage => steps.push(stage),
  }), error => error === failure);
  assert.deepEqual(steps, ['entry_pending', 'entry_failed']);
});

test('entered Model cancellation retains the first failure while its other operation settles', async () => {
  const waitFailed = Object.assign(new Error('WaitTimeout'), {code: 'WaitTimeout'});
  const cancelFailed = new Error('CancelObservationFailed');
  const waitOnlySteps = [];
  await assert.rejects(observeEnteredCancellation({
    awaitEntry: async () => {},
    wait: async () => { throw waitFailed; },
    cancel: async () => {},
    record: stage => waitOnlySteps.push(stage),
  }), error => error === waitFailed);
  assert.deepEqual(waitOnlySteps, ['entry_pending', 'entered', 'wait_started', 'wait_failed']);

  for (const waitFirst of [true, false]) {
    const observed = Promise.withResolvers();
    const steps = [];
    const result = observeEnteredCancellation({
      awaitEntry: async () => {},
      wait: () => observed.promise,
      async cancel() {
        if (waitFirst) {
          observed.reject(waitFailed);
          await Promise.resolve();
        }
        throw cancelFailed;
      },
      record: stage => steps.push(stage),
    });
    await assert.rejects(result, error => error === (waitFirst ? waitFailed : cancelFailed));
    if (!waitFirst) {
      observed.reject(waitFailed);
      await Promise.resolve();
    }
    assert.deepEqual(steps, ['entry_pending', 'entered', 'wait_started',
      ...(waitFirst ? ['wait_failed', 'cancel_path_failed'] : ['cancel_path_failed', 'wait_failed'])]);
  }
});

function httpFailureObservation(status, pid, sends) {
  const cid = digit => 'sha256:' + digit.repeat(64);
  const evidence = Object.fromEntries(['model_attempt_accounting', 'model_attempt_outcome',
    'model_call_attempt', 'model_capture_bundle', 'model_dispatch_authority', 'model_slot_capture']
    .map((role, index) => [role, {cid: cid(String(index)), holdingCid: cid('a')}]));
  return {pid, httpStatus: status, terminalFailure: status === 429 ? 'rate_limit' : 'provider_error',
    originalRunDefinitionCid: cid('b'), originalModelStarts: sends, completedHttpFailures: sends,
    failureCredentialReads: sends, failureJournal: {
      state: 'SavedFailure', settled: true, settledAt: '2026-10-17T00:00:00.000Z',
      scopeCid: cid('c'), slotCid: cid('d'), attemptCid: cid('e'), providerBindingCid: cid('f'), evidence,
    }};
}

async function withFixtureGitHubSource(source, action) {
  const original = process.env.GITHUB_SHA;
  process.env.GITHUB_SHA = source;
  try {return await action();}
  finally {
    if (original === undefined) delete process.env.GITHUB_SHA;
    else process.env.GITHUB_SHA = original;
  }
}

// Real Git/tar/inventory acquisition; installs and business processes below are
// explicit command ports, not a Common, normal Host or provider acceptance run.
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-optional-provider-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const repository = join(root, 'source'), retained = join(root, 'original'), archives = join(root, 'archives');
  for (const dir of [repository, retained, archives]) await mkdir(dir);
  await writeFile(join(repository, 'package.json'), '{"private":true,"type":"module"}');
  for (const name of [...CLIENT_PACKAGES, 'provider-ai-sdk']) {
    const pkg = join(repository, 'packages', name); await mkdir(pkg, {recursive: true});
    await writeFile(join(pkg, 'package.json'), JSON.stringify({name: '@actql/' + name,
      version: '0.0.0-development', private: true, files: ['index.mjs', 'npm-shrinkwrap.json'],
      scripts: {prepack: 'node -e "process.stderr.write(\'original lifecycle\\n\')"'}}));
    await writeFile(join(pkg, 'index.mjs'), 'export const fixture = "' + name + '";\n');
    await writeFile(join(pkg, 'npm-shrinkwrap.json'), '{"lockfileVersion":3}');
    const stage = join(archives, name); await mkdir(stage);
    await cp(pkg, join(stage, 'package'), {recursive: true});
    execFileSync('tar', ['-czf', join(archives, 'actql-' + name + '-0.0.0-development.tgz'), '-C', stage, 'package']);
  }
  for (const file of ['normal-openai-installed.fixture.mjs', 'normal-provider-diagnostics.fixture.mjs', 'external-rest/conformance.mjs']) {
    await mkdir(join(repository, 'scripts/fixtures', file, '..'), {recursive: true});
    await copyFile(new URL('./fixtures/' + file, import.meta.url), join(repository, 'scripts/fixtures', file));
  }
  await mkdir(join(repository, 'adapters/host-node/fixtures'), {recursive: true});
  await copyFile(new URL('../adapters/host-node/fixtures/work-observation.fixture.mjs', import.meta.url),
    join(repository, 'adapters/host-node/fixtures/work-observation.fixture.mjs'));
  const git = args => execFileSync('git', args, {cwd: repository, encoding: 'utf8'}).trim();
  git(['init', '-q']); git(['add', '.']);
  git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture']);
  const source = {sha: git(['rev-parse', 'HEAD']), dirty: false};
  const pack = destination => name => copyFile(join(archives, 'actql-' + name + '-0.0.0-development.tgz'),
    join(destination, 'actql-' + name + '-0.0.0-development.tgz'));
  await packClientPackages({repository, destination: retained, pack: pack(retained)});
  const optional = join(retained, 'optional-provider');
  await packClientPackages({repository, destination: optional, names: ['provider-ai-sdk'], pack: pack(optional)});
  const phases = [], installs = [], preparations = [], phaseCalls = [];
  const command = async (cmd, args, options) => {
    // Exercise the same exclusive output rule as execute(), so reusing one
    // install-node raw filename across preparations is an actual fixture error.
    if (options.raw) await writeFile(join(options.raw, options.name + '.stdout'), '', {flag: 'wx'});
    if (cmd === 'npm') {
      installs.push(args);
      preparations.push({cwd: options.cwd, raw: options.raw});
      for (const name of [...CLIENT_PACKAGES, 'provider-ai-sdk']) {
        await cp(join(archives, name, 'package'), join(options.cwd, 'node_modules/@actql', name), {recursive: true});
      }
      return {stdout: '', pid: 70000};
    }
    const phase = args[1], caseId = basename(dirname(options.cwd)); phases.push(phase);
    assert(!Object.hasOwn(options.env, 'OPENAI_API_KEY'), 'Fixture must not inherit the operator credential');
    const modules = await lstat(join(options.cwd, 'node_modules'));
    assert(modules.isDirectory() && !modules.isSymbolicLink());
    const profilePath = join(options.cwd, 'case-profile.fixture.json');
    let profile;
    if (phase === 'cold') {
      await access(join(options.cwd, '.state'));
      profile = JSON.parse(await readFile(profilePath, 'utf8'));
    } else {
      await assert.rejects(access(join(options.cwd, '.state')), {code: 'ENOENT'}); await mkdir(join(options.cwd, '.state'));
      profile = {usage: phase === 'project-key' ? 'reported' : phase.startsWith('usage-') ? phase.slice(6) : null,
        timeout: phase.startsWith('timeout-') ? phase.slice(8) : null};
      await writeFile(profilePath, JSON.stringify(profile), {flag: 'wx'});
    }
    const pid = 70001 + phaseCalls.length;
    phaseCalls.push({case: caseId, phase, profile, cwd: options.cwd, raw: options.raw, modulesInode: modules.ino, pid});
    const sends = ['cold', 'missing-key'].includes(phase) ? 0 : phase === 'warm' ? 2 : 1;
    return {pid, stdout: JSON.stringify({phase,
      firstCloseReturned: true, aliveScopedFD0: true,
      ...(caseId === 'rate-limit' ? httpFailureObservation(429, pid, sends) : {}),
      ...(profile.usage === 'reported' ? {maxCalls: 1} : {}),
      calls: sends, registeredSdk: true, projectCredential: true, projectTlsConnects: sends,
      ...(phase === 'missing-key' ? {credentialRefused: true} : {}),
      ...(phase === 'warm' ? {tasks: 2, requests: 2} : phase === 'cold'
        ? {egressChecks: 0, ...(profile.timeout === null ? {originalSavedFirst: true} : {originalUnknown: true, zeroResend: true})}
        : {tasks: 1, requests: 1, ...(profile.usage === null ? {} : {usageMode: profile.usage, usageCaptures: 1})}),
      ...(profile.timeout === null ? {} : {timeoutMode: profile.timeout, preserveOriginalState: true}),
      ...(phase === 'timeout-call' ? {continuousWrites: 3, responseClosedBeforeFirstClose: true} : {})})};
  };
  return {root, repository, retained, optional, source, command, phases, installs, preparations, phaseCalls};
}

test('optional normal pack reuses lifecycle producer without changing required five', async t => {
  const f = await fixture(t);
  const required = await readFile(join(f.retained, 'packed-client-packages.json'));
  // Exercise the actual default npm callback on a tiny authored package only.
  const extra = join(f.root, 'actual-optional');
  await packClientPackages({repository: f.repository, destination: extra, names: ['provider-ai-sdk']});
  const original = JSON.parse(await readFile(join(extra, 'packed-client-packages.json')));
  assert.deepEqual(Object.keys(original.tarballs), ['provider-ai-sdk']);
  assert.equal(original.revision, f.source.sha);
  assert.deepEqual(Object.keys(JSON.parse(required).tarballs), CLIENT_PACKAGES);
  assert.deepEqual(await readFile(join(f.retained, 'packed-client-packages.json')), required);
});

test('optional usage consumers retain separate fresh installations and warm shares only its cold original', async t => {
  const f = await fixture(t), original = process.env.GITHUB_SHA;
  const result = await withFixtureGitHubSource(f.source.sha,
    () => runPackedProviderAI(join(f.root, 'consumer-case'), f));
  assert.equal(process.env.GITHUB_SHA, original);
  assert.equal(result.complete, true); assert(result.phases.every(row => row.status === 'passed'));
  const [warm, cold] = f.phaseCalls.filter(row => row.case === 'warm');
  const usage = f.phaseCalls.filter(row => row.phase.startsWith('usage-'));
  assert.equal(warm.cwd, cold.cwd); assert.notEqual(warm.pid, cold.pid);
  assert.equal(warm.modulesInode, cold.modulesInode);
  const [oneCall, savedOneCall] = f.phaseCalls.filter(row => row.case === 'usage-reported');
  assert.equal(oneCall.cwd, savedOneCall.cwd);
  assert.equal(oneCall.modulesInode, savedOneCall.modulesInode);
  assert.notEqual(oneCall.pid, savedOneCall.pid);
  for (const value of usage) {
    assert.notEqual(value.cwd, warm.cwd); assert.notEqual(value.modulesInode, warm.modulesInode);
    const mode = value.phase.slice(6), actual = result.phases.find(row => row.case === value.case && row.phase === value.phase).actual;
    assert.equal(actual.usageMode, mode); assert.equal(actual.usageCaptures, 1);
  }
  assert.equal(new Set(usage.map(row => row.cwd)).size, 3);
  assert.equal(new Set(usage.map(row => row.modulesInode)).size, 3);
  assert.equal(new Set(f.preparations.map(row => row.raw)).size, f.preparations.length);
  for (const args of f.installs) {
    assert(args.includes('--ignore-scripts=false')); assert(!args.includes('--offline'));
    assert.equal(args.filter(x => x.endsWith('.tgz')).length, CLIENT_PACKAGES.length + 1);
  }
  assert.equal(result.preparations.length, f.preparations.length);
});

function directObservation(caseId, phase) {
  const cold = phase === 'cold';
  const lost = caseId === 'direct-response-loss';
  const partial = caseId === 'direct-partial-raw';
  const unknown = lost || partial;
  const count = cold ? 0 : 1;
  const resolved = !cold && !lost ? 1 : 0;
  const originalRunDefinitionCid = 'sha256:' + (lost ? '1' : partial ? '0' : '2').repeat(64);
  const originalAuthorityScopeCid = 'sha256:' + '3'.repeat(64);
  const text = {type: 'string', nullable: false};
  const directResult = {ref: {namespaceId: 'local', authorityScopeCid: originalAuthorityScopeCid,
    runDefinitionCid: originalRunDefinitionCid}, resultName: 'answer',
    columns: [{name: 'id', contract: text}, {name: 'outcome', contract: text},
      {name: 'value', contract: {type: 'object', nullable: true, additional_properties: false,
        fields: {answer: {type: 'boolean', nullable: false}}}}],
    rows: [{id: 'original-text', outcome: 'ok', value: {answer: true}}]};
  return {phase, directHttp: true, calls: count, peerTcpAccepts: count, peerTlsHandshakes: count,
    peerSocketCloses: count, modelCredentialReads: count, originalModelStarts: count,
    directDnsStarted: resolved, directDnsCompleted: resolved, peerServerName: resolved === 1 ? 'localhost' : null,
    firstCloseReturned: true, aliveScopedFD0: true,
    directDependencyClosure: {packages: 12, sha256: 'b'.repeat(64)},
    originalRunDefinitionCid, originalAuthorityScopeCid,
    originalTerminalStatus: unknown ? 'needs_reconciliation' : 'succeeded',
    ...(unknown ? {directResultRefusal: 'ResultAccessDenied',
      ...(!cold ? {directPeerClosedBeforeFirstClose: true} : {})} : {directResult}),
    ...(lost ? {directRawAbsent: true} : {}),
    directJournal: {runId: '98765432-4321-1234-abcd-1234567890ab',
      scopeCid: 'sha256:' + '6'.repeat(64), slotCid: 'sha256:' + '7'.repeat(64),
      attemptCid: 'sha256:' + (lost ? '8' : partial ? 'a' : '9').repeat(64), state: unknown ? 'EnteredUnknown' : 'SavedSuccess'},
    ...(!lost ? {directRaw: {
      holdingCid: 'sha256:' + 'a'.repeat(64),
      descriptorCid: 'sha256:' + (partial ? 'b' : '4').repeat(64),
      contentCid: partial ? 'sha256:0e94b5b974cd7b4cab7cf2729e6996ad87ac3e3c8c5897b3300297549518a4c1'
        : 'sha256:' + 'c'.repeat(64),
      byteCount: partial ? 8 : 234, httpStatus: partial ? 503 : 200, transportEof: !partial,
      objectCids: ['sha256:' + 'd'.repeat(64), 'sha256:' + 'e'.repeat(64)],
    }} : {}),
    ...(cold ? {egressChecks: 0, ...(unknown ? {originalUnknown: true, zeroResend: true} : {originalSavedFirst: true})}
      : {checkedWithoutPhysicalWork: true,
        ...(unknown ? {} : {usageCaptures: 1, originalRawArtifactCid: 'sha256:' + '4'.repeat(64)})})};
}

test('direct HTTPS reuses the standard Client tarballs and pairs each cold process with its own original', async t => {
  const f = await fixture(t);
  await rm(f.optional, {recursive: true});
  const cases = ['direct-project', 'direct-response-loss', 'direct-partial-raw'];
  const installed = [], child = [];
  let replacedScope, replacedAttempt, replacedDependencyClosure, replacedRaw;
  const command = async (cmd, args, options) => {
    if (cmd === 'npm') {
      assert(args.includes('--offline') && args.includes('--ignore-scripts=false'));
      assert.equal(args.filter(x => x.endsWith('.tgz')).length, CLIENT_PACKAGES.length);
      assert(!args.some(x => x.includes('provider-ai-sdk')));
      installed.push(options.cwd);
      for (const tar of args.filter(x => x.endsWith('.tgz'))) {
        const packageName = basename(tar).slice('actql-'.length, -'-0.0.0-development.tgz'.length);
        const destination = join(options.cwd, 'node_modules/@actql', packageName);
        await mkdir(destination, {recursive: true});
        execFileSync('tar', ['-xzf', tar, '--strip-components', '1', '-C', destination]);
      }
      return {stdout: '', pid: 70000};
    }
    assert.equal(cmd, process.execPath);
    assert.equal(args[0], 'fixture.mjs');
    const phase = args[1], caseId = basename(dirname(options.cwd)), pid = 70001 + child.length;
    const observation = directObservation(caseId, phase);
    if (phase === 'cold' && caseId === replacedScope) observation.originalAuthorityScopeCid = 'sha256:' + '5'.repeat(64);
    if (phase === 'cold' && caseId === replacedAttempt) observation.directJournal.attemptCid = 'sha256:' + 'a'.repeat(64);
    if (phase === 'cold' && caseId === replacedDependencyClosure) observation.directDependencyClosure.sha256 = 'c'.repeat(64);
    if (phase === 'cold' && caseId === replacedRaw) observation.directRaw.descriptorCid = 'sha256:' + 'f'.repeat(64);
    child.push({caseId, phase, pid, cwd: options.cwd});
    return {pid, stdout: JSON.stringify(observation)};
  };
  const execute = root => withFixtureGitHubSource(f.source.sha, () =>
    runPackedProviderAI(join(f.root, root), {...f, cases, command}));
  const result = await execute('direct');
  assert.equal(result.complete, true);
  assert.equal(new Set(installed).size, cases.length);
  for (const id of cases) {
    const [warm, cold] = child.filter(row => row.caseId === id);
    assert.equal(warm.phase, id); assert.equal(cold.phase, 'cold');
    assert.equal(warm.cwd, cold.cwd); assert.notEqual(warm.pid, cold.pid);
  }
  replacedScope = 'direct-response-loss';
  await assert.rejects(execute('replaced-scope'));
  const refused = JSON.parse(await readFile(join(f.root, 'replaced-scope/summary.json')));
  assert.equal(refused.complete, false);
  assert.equal(refused.phases.find(row => row.case === replacedScope && row.phase === 'cold').status, 'failed');
  replacedScope = undefined;
  replacedAttempt = 'direct-response-loss';
  await assert.rejects(execute('replaced-attempt'));
  const substituted = JSON.parse(await readFile(join(f.root, 'replaced-attempt/summary.json')));
  assert.equal(substituted.complete, false);
  assert.equal(substituted.phases.find(row => row.case === replacedAttempt && row.phase === 'cold').status, 'failed');
  replacedAttempt = undefined;
  replacedDependencyClosure = 'direct-project';
  await assert.rejects(execute('replaced-dependency-closure'));
  const changed = JSON.parse(await readFile(join(f.root, 'replaced-dependency-closure/summary.json')));
  assert.equal(changed.complete, false);
  assert.equal(changed.phases.find(row => row.case === replacedDependencyClosure && row.phase === 'cold').status, 'failed');
  replacedDependencyClosure = undefined;
  replacedRaw = 'direct-partial-raw';
  await assert.rejects(execute('replaced-raw'));
  const foreign = JSON.parse(await readFile(join(f.root, 'replaced-raw/summary.json')));
  assert.equal(foreign.complete, false);
  assert.equal(foreign.phases.find(row => row.case === replacedRaw && row.phase === 'cold').status, 'failed');
});

test('direct HTTPS evidence refuses missing Raw or retirement, cold credentials and the wrong terminal state', () => {
  for (const [caseId, phase, change] of [
    ['direct-project', 'direct-project', {originalRawArtifactCid: null}],
    ['direct-project', 'direct-project', {peerSocketCloses: 0}],
    ['direct-project', 'direct-project', {checkedWithoutPhysicalWork: false}],
    ['direct-project', 'direct-project', {directDependencyClosure: undefined}],
    ['direct-project', 'direct-project', {directRaw: undefined}],
    ['direct-project', 'direct-project', {directDnsCompleted: 0}],
    ['direct-project', 'direct-project', {peerServerName: null}],
    ['direct-project', 'cold', {modelCredentialReads: 1}],
    ['direct-project', 'cold', {directDnsStarted: 1}],
    ['direct-project', 'cold', {directResult: undefined}],
    ['direct-project', 'cold', {directResult: {...directObservation('direct-project', 'cold').directResult,
      rows: [{id: 'original-text', outcome: 'ok', value: {answer: 'true'}}]}}],
    ['direct-project', 'cold', {directResult: {...directObservation('direct-project', 'cold').directResult,
      columns: directObservation('direct-project', 'cold').directResult.columns.toReversed()}}],
    ['direct-response-loss', 'cold', {directResult: directObservation('direct-project', 'cold').directResult}],
    ['direct-response-loss', 'direct-response-loss', {directDnsStarted: 1}],
    ['direct-response-loss', 'cold', {calls: 1}],
    ['direct-response-loss', 'cold', {originalTerminalStatus: 'succeeded'}],
    ['direct-response-loss', 'cold', {originalSavedFirst: true}],
    ['direct-response-loss', 'cold', {firstCloseReturned: false}],
    ['direct-response-loss', 'cold', {directJournal: undefined}],
    ['direct-response-loss', 'cold', {directJournal: directObservation('direct-project', 'cold').directJournal}],
    ['direct-response-loss', 'cold', {directRaw: directObservation('direct-partial-raw', 'cold').directRaw}],
    ['direct-response-loss', 'cold', {directResultRefusal: undefined}],
    ['direct-response-loss', 'cold', {directRawAbsent: undefined}],
    ['direct-partial-raw', 'direct-partial-raw', {directPeerClosedBeforeFirstClose: undefined}],
    ['direct-partial-raw', 'cold', {directRaw: directObservation('direct-project', 'cold').directRaw}],
    ['direct-partial-raw', 'cold', {directRaw: undefined}],
  ]) {
    const observation = directObservation(caseId, phase);
    const selected = {caseId, phase, originalPid: 1, pid: 2};
    checkPackedProviderObservation({...selected, observation});
    assert.throws(() => checkPackedProviderObservation({...selected, observation: {...observation, ...change}}));
  }
});

test('optional timeout originals retain independent installations and same-profile cold Unknown without resend', async t => {
  const f = await fixture(t), result = await withFixtureGitHubSource(f.source.sha,
    () => runPackedProviderAI(join(f.root, 'timeouts'), f));
  const required = [['warm', ['warm', 'cold']], ['missing-key', ['missing-key']], ['project-key', ['project-key', 'cold']],
    ['rate-limit', ['rate-limit', 'cold']],
    ['usage-reported', ['usage-reported', 'cold']],
    ['usage-zero', ['usage-zero']], ['usage-absent', ['usage-absent']],
    ['timeout-headers', ['timeout-headers', 'cold']], ['timeout-body', ['timeout-body', 'cold']],
    ['timeout-call', ['timeout-call', 'cold']]];
  assert.deepEqual(result.phases.map(row => `${row.case}/${row.phase}`).sort(),
    required.flatMap(([id, phases]) => phases.map(phase => `${id}/${phase}`)).sort());
  assert.equal(result.complete, true);assert(result.phases.every(row => row.status === 'passed'));
  assert.deepEqual(result.preparations.map(row => row.case).sort(), required.map(([id]) => id).sort());
  assert.equal(new Set(f.preparations.map(row => row.cwd)).size, required.length);
  assert.equal(new Set(f.preparations.map(row => row.raw)).size, required.length);
  const modules = new Set();
  for (const prepared of result.preparations) {
    assert.equal(prepared.manifest.sourceSha, f.source.sha);
    assert.deepEqual(prepared.manifest.packages.map(row => row.name).sort(),
      [...CLIENT_PACKAGES, 'provider-ai-sdk'].map(name => '@actql/' + name).sort());
    for (const pkg of prepared.manifest.packages) {
      assert.match(pkg.sha256, /^[a-f0-9]{64}$/u);assert.match(pkg.integrity, /^sha512-/u);
    }
    modules.add((await lstat(join(prepared.consumer, 'node_modules'))).ino);
  }
  assert.equal(modules.size, required.length);
  for (const mode of ['headers', 'body', 'call']) {
    const id = 'timeout-' + mode, calls = f.phaseCalls.filter(row => row.case === id);
    assert.deepEqual(calls.map(row => row.phase), [id, 'cold']);
    assert.equal(calls[0].cwd, calls[1].cwd);assert.equal(calls[0].raw, calls[1].raw);
    assert.equal(calls[0].modulesInode, calls[1].modulesInode);assert.notEqual(calls[0].pid, calls[1].pid);
    assert.deepEqual(calls[0].profile, {usage: null, timeout: mode});assert.deepEqual(calls[1].profile, calls[0].profile);
    const cold = result.phases.find(row => row.case === id && row.phase === 'cold');
    assert.equal(cold.actual.timeoutMode, mode);assert.equal(cold.actual.preserveOriginalState, true);
    assert.equal(cold.actual.originalUnknown, true);assert.equal(cold.actual.zeroResend, true);
    assert.equal(cold.actual.calls, 0);assert.equal(cold.actual.egressChecks, 0);
    assert.equal(cold.actual.originalSavedFirst, undefined);
    if (mode === 'call') {
      const original = result.phases.find(row => row.case === id && row.phase === id);
      assert.equal(original.actual.continuousWrites, 3);
      assert.equal(original.actual.responseClosedBeforeFirstClose, true);
    }
  }
});

test('whole-call timeout observation requires continuous body writes and peer close before public close', () => {
  const originalPid = 70001, pid = 70002;
  const observation = {phase:'timeout-call', calls:1, tasks:1, requests:1,
    registeredSdk:true, projectCredential:true, projectTlsConnects:1,
    firstCloseReturned:true, aliveScopedFD0:true, timeoutMode:'call', preserveOriginalState:true,
    continuousWrites:3, responseClosedBeforeFirstClose:true};
  checkPackedProviderObservation({caseId:'timeout-call', phase:'timeout-call', pid:originalPid,
    observation});
  for (const change of [
    ...[undefined, 0, 1, 128, 1.5, '3'].map(continuousWrites => ({continuousWrites})),
    {responseClosedBeforeFirstClose:false}, {responseClosedBeforeFirstClose:undefined},
  ]) assert.throws(() => checkPackedProviderObservation({caseId:'timeout-call', phase:'timeout-call',
    pid:originalPid, observation:{...observation, ...change}}));
  const cold = {phase:'cold', calls:0, egressChecks:0, firstCloseReturned:true, aliveScopedFD0:true,
    registeredSdk:true, projectCredential:true, projectTlsConnects:0,
    timeoutMode:'call', preserveOriginalState:true, originalUnknown:true, zeroResend:true};
  checkPackedProviderObservation({caseId:'timeout-call', phase:'cold', pid, originalPid, observation:cold});
  for (const change of [{originalUnknown:false}, {zeroResend:false}, {timeoutMode:'body'},
    {calls:1}, {egressChecks:1}, {projectTlsConnects:1}, {registeredSdk:false}, {originalSavedFirst:true}]) {
    assert.throws(() => checkPackedProviderObservation({caseId:'timeout-call', phase:'cold', pid,
      originalPid, observation:{...cold, ...change}}));
  }
});

test('optional timeout cold completion refuses mismatched Unknown, resend, profile, process and close evidence', async t => {
  const originalPid = 70001, pid = 70002;
  const observation = mode => ({phase: 'cold', calls: 0, egressChecks: 0, firstCloseReturned: true,
    aliveScopedFD0: true, registeredSdk: true, projectCredential: true, projectTlsConnects: 0,
    timeoutMode: mode, preserveOriginalState: true, originalUnknown: true, zeroResend: true});
  for (const mode of ['headers', 'body', 'call'])
    checkPackedProviderObservation({caseId: 'timeout-' + mode, phase: 'cold', pid, originalPid, observation: observation(mode)});
  // Reuse the actual imported DATA guard for independent invalid fields rather
  // than repacking/reinstalling every unchanged case for each assertion.
  for (const [mode, change, samePid] of [
    ['headers', {originalUnknown: false}], ['body', {zeroResend: false}],
    ['headers', {calls: 1}], ['body', {egressChecks: 1}], ['headers', {timeoutMode: 'body'}],
    ['body', {preserveOriginalState: false}], ['headers', {firstCloseReturned: false}],
    ['body', {aliveScopedFD0: false}], ['headers', {}, true],
  ]) {
    assert.throws(() => checkPackedProviderObservation({caseId: 'timeout-' + mode, phase: 'cold',
      pid: samePid ? originalPid : pid, originalPid, observation: {...observation(mode), ...change}}));
  }
  const f = await fixture(t), root = join(f.root, 'invalid'), id = 'timeout-body';
  await assert.rejects(withFixtureGitHubSource(f.source.sha, () => runPackedProviderAI(root, {...f, command: async (cmd, args, options) => {
    const result = await f.command(cmd, args, options);
    return args[1] === 'cold' && basename(dirname(options.cwd)) === id
      ? {...result, stdout: JSON.stringify({...JSON.parse(result.stdout), zeroResend: false})} : result;
  }})));
  const report = JSON.parse(await readFile(join(root, 'summary.json')));
  assert.equal(report.complete, false);
  assert.equal(report.phases.find(row => row.case === id && row.phase === 'cold').status, 'failed');
  assert(report.phases.filter(row => row.case !== id).every(row => row.status === 'passed'));
});

test('failed timeout original retains primary and cannot start a replacement cold case', async t => {
  const f = await fixture(t), root = join(f.root, 'failed'), primary = new Error('OriginalTimeoutFixtureFailed');
  await assert.rejects(withFixtureGitHubSource(f.source.sha, () => runPackedProviderAI(root, {...f, command: async (cmd, args, options) => {
    if (cmd !== 'npm' && args[1] === 'timeout-headers') throw primary;
    return f.command(cmd, args, options);
  }})), actual => actual === primary);
  const report = JSON.parse(await readFile(join(root, 'summary.json')));
  assert.equal(report.complete, false);
  assert.equal(report.phases.find(row => row.case === 'timeout-headers' && row.phase === 'timeout-headers').status, 'failed');
  assert.equal(report.phases.find(row => row.case === 'timeout-headers' && row.phase === 'cold').status, 'unexecuted');
  assert(!f.phaseCalls.some(row => row.case === 'timeout-headers' && row.phase === 'cold'));
  assert(report.phases.filter(row => row.case !== 'timeout-headers').every(row => row.status === 'passed'));
});

test('optional timeout completion rechecks every independent installed package inventory', async t => {
  const f = await fixture(t), root = join(f.root, 'changed');
  const packages = [...CLIENT_PACKAGES, 'provider-ai-sdk'], changed = new Set(), consumers = new Set();
  await assert.rejects(withFixtureGitHubSource(f.source.sha, () => runPackedProviderAI(root, {...f, command: async (cmd, args, options) => {
    const result = await f.command(cmd, args, options);
    if (args[1] === 'cold' || ['missing-key', 'usage-zero', 'usage-absent'].includes(args[1])) {
      const index = f.preparations.findIndex(prepared => prepared.cwd === options.cwd);
      assert(index >= 0); assert(!consumers.has(options.cwd)); consumers.add(options.cwd);
      const name = packages[index % packages.length]; changed.add(name);
      await writeFile(join(options.cwd, 'node_modules/@actql', name, 'index.mjs'), 'changed original package\n');
    }
    return result;
  }})), /OptionalProviderSoftwareChanged/u);
  assert.deepEqual([...changed].sort(), packages.sort(), 'Exercise every original package type across the independent installations');
  assert.deepEqual([...consumers].sort(), f.preparations.map(value => value.cwd).sort());
  const report = JSON.parse(await readFile(join(root, 'summary.json')));
  assert.equal(report.complete, false);assert(report.phases.every(row => row.status === 'passed'));
  assert.equal(report.cleanup.length, f.preparations.length);
});

test('required-five consumers remain offline and never discover optional siblings', async t => {
  const f = await fixture(t), root = join(f.root, 'required-only'); await mkdir(root);
  await writeFile(join(f.optional, 'packed-client-packages.json'), 'invalid optional input');
  const prepared = await prepareHealthPackages({...f, root, normalLifecycle: true});
  assert.deepEqual(prepared.manifest.packages.map(row => row.name), CLIENT_PACKAGES.map(name => '@actql/' + name));
  assert(f.installs[0].includes('--offline'));
  assert.equal(f.installs[0].filter(x => x.endsWith('.tgz')).length, CLIENT_PACKAGES.length);
});

test('optional source, selection and changed archive refuse before any install', async t => {
  for (const mode of ['source', 'extra', 'bytes']) {
    const f = await fixture(t), file = join(f.optional, 'packed-client-packages.json');
    const manifest = JSON.parse(await readFile(file));
    if (mode === 'source') manifest.revision = 'f'.repeat(40);
    if (mode === 'extra') manifest.tarballs.sdk = 'a'.repeat(64);
    await writeFile(file, JSON.stringify(manifest));
    if (mode === 'bytes') await writeFile(join(f.optional, 'actql-provider-ai-sdk-0.0.0-development.tgz'), 'changed');
    const root = join(f.root, 'refusal'); await mkdir(root);
    await assert.rejects(prepareHealthPackages({...f, root, optionalProvider: f.optional, normalLifecycle: true}));
    assert.deepEqual(f.installs, []);
  }
});

test('optional consumer refuses a foreign hosted SHA before output or installation and restores the caller environment', async t => {
  const f = await fixture(t), original = process.env.GITHUB_SHA, destination = join(f.root, 'foreign-source');
  const foreign = (f.source.sha[0] === '0' ? '1' : '0') + f.source.sha.slice(1);
  await withFixtureGitHubSource(foreign, () => assert.rejects(runPackedProviderAI(destination, f),
    error => error.code === 'ERR_ASSERTION' && error.actual === f.source.sha && error.expected === foreign));
  assert.equal(process.env.GITHUB_SHA, original);
  assert.deepEqual(f.installs, []); assert.deepEqual(f.phases, []);
  await assert.rejects(access(destination), {code: 'ENOENT'});
});

test('warm failure preserves primary and cannot start a cold replacement port', async t => {
  const f = await fixture(t), primary = new Error('OriginalWarmFailure');
  const original = process.env.GITHUB_SHA;
  await assert.rejects(withFixtureGitHubSource(f.source.sha, () => runPackedProviderAI(join(f.root, 'failed'), {...f,
    command: async (cmd, args, options) => {
      if (cmd !== 'npm' && args[1] === 'warm') {f.phases.push(args[1]); throw primary;}
      return f.command(cmd, args, options);
    }})), actual => actual === primary);
  assert.equal(process.env.GITHUB_SHA, original);
  assert(!f.phaseCalls.some(row => row.case === 'warm' && row.phase === 'cold'));
  const report = JSON.parse(await readFile(join(f.root, 'failed/summary.json')));
  assert.equal(report.complete, false);
  assert.equal(report.phases.find(row => row.case === 'warm' && row.phase === 'warm').status, 'failed');
  assert.equal(report.phases.find(row => row.case === 'warm' && row.phase === 'cold').status, 'unexecuted');
  assert(report.phases.filter(row => row.phase.startsWith('usage-')).every(row => row.status === 'passed'));
});

test('optional usage completion refuses mismatched evidence and retained close or FD failures', async t => {
  for (const change of [{usageCaptures: 0}, {calls: 0}, {usageMode: 'reported'}, {aliveScopedFD0: false}]) {
    const f = await fixture(t);
    const root = join(f.root, 'invalid');
    await assert.rejects(withFixtureGitHubSource(f.source.sha, () => runPackedProviderAI(root, {...f, command: async (cmd, args, options) => {
      const result = await f.command(cmd, args, options);
      return args[1] === 'usage-zero' ? {...result, stdout: JSON.stringify({...JSON.parse(result.stdout), ...change})} : result;
    }})));
    const report = JSON.parse(await readFile(join(root, 'summary.json')));
    assert.equal(report.complete, false);
    assert.equal(report.phases.find(row => row.case === 'usage-zero' && row.phase === 'usage-zero').status, 'failed');
    assert.equal(report.phases.find(row => row.case === 'usage-absent' && row.phase === 'usage-absent').status, 'passed');
  }
});

test('Project acceptance requires the original environment credential path and no TLS on reopen', () => {
  const original = {phase: 'project-key', firstCloseReturned: true, aliveScopedFD0: true, projectCredential: true,
    calls: 1, projectTlsConnects: 1, maxCalls: 1, tasks: 1, requests: 1, usageMode: 'reported', usageCaptures: 1,
    registeredSdk: true};
  const saved = {phase: 'cold', firstCloseReturned: true, aliveScopedFD0: true, projectCredential: true,
    calls: 0, projectTlsConnects: 0, maxCalls: 1, egressChecks: 0, originalSavedFirst: true, registeredSdk: true};
  checkPackedProviderObservation({caseId: 'project-key', phase: 'project-key', pid: 1, observation: original});
  checkPackedProviderObservation({caseId: 'project-key', phase: 'cold', pid: 2, originalPid: 1, observation: saved});
  for (const [observation, pid, originalPid] of [
    [{...original, projectCredential: false}, 1, undefined],
    [{...original, projectTlsConnects: 0}, 1, undefined],
    [{...saved, projectTlsConnects: 1}, 2, 1],
  ]) {
    assert.throws(() => checkPackedProviderObservation({
      caseId: 'project-key', phase: observation.phase, pid, originalPid, observation,
    }));
  }
});

test('a registered Responses Task over its Host ceiling must refuse before any Model work', () => {
  const phase = 'registered-openai-responses-over-limit';
  const observation = {phase, rejected: 'MoonBitHostFailure', credentialReads: 0,
    tlsAttempts: 0, peerConnections: 0, calls: 0, modelStarts: 0, modelScopes: 0, modelAttempts: 0,
    aliveScopedFD0: true, usageCaptures: 0};
  const verify = value => checkPackedProviderObservation({caseId: phase, phase, pid: 70001, observation: value});
  assert.doesNotThrow(() => verify(observation));
  for (const [key, value] of Object.entries({rejected: 'OtherRefusal', credentialReads: 1,
    tlsAttempts: 1, peerConnections: 1, calls: 1, modelStarts: 1, modelScopes: 1, modelAttempts: 1,
    aliveScopedFD0: false, usageCaptures: 1})) {
    assert.throws(() => verify({...observation, [key]: value}));
  }
});

test('registered terminal failures require original Saved in a distinct zero-egress process', () => {
  const shared = {firstCloseReturned: true, aliveScopedFD0: true, registeredSdk: true,
    projectCredential: true, maxCalls: 1, originalRunDefinitionCid: 'sha256:' + 'd'.repeat(64)};
  for (const [caseId, terminalFailure] of [
    ['registered-length', 'truncated'], ['registered-refusal', 'refusal'],
    ['registered-openai-filter', 'safety_rejected'], ['registered-google-recitation', 'safety_rejected'],
    ['registered-google-blocklist', 'safety_rejected'],
  ]) {
    const warm = {...shared, terminalFailure, phase: caseId, tasks: 1, requests: 1,
      calls: 1, projectTlsConnects: 1, originalModelStarts: 1};
    const cold = {...shared, terminalFailure, phase: 'cold', calls: 0, projectTlsConnects: 0,
      originalModelStarts: 0, egressChecks: 0, originalSavedFirst: true};
    checkPackedProviderObservation({caseId, phase: caseId, pid: 1, observation: warm});
    checkPackedProviderObservation({caseId, phase: 'cold', pid: 2, originalPid: 1, observation: cold});
    for (const [pid, observation] of [[1, cold], [2, {...cold, originalSavedFirst: false}],
      [2, {...cold, originalModelStarts: 1}], [2, {...cold, egressChecks: 1}],
      [2, {...cold, terminalFailure: 'schema_invalid'}]]) {
      assert.throws(() => checkPackedProviderObservation({caseId, phase: 'cold', pid, originalPid: 1, observation}));
    }
  }
});

test('external duplicate fetch refuses before transport and keeps the same failed Run cold', () => {
  const caseId = 'registered-external-double';
  const cid = 'sha256:' + 'd'.repeat(64);
  const shared = {firstCloseReturned: true, aliveScopedFD0: true, registeredSdk: true, calls: 0,
    projectTlsConnects: 0, externalTcp: 0, externalCredentialReads: 0, originalModelStarts: 0,
    usageCaptures: 0, usageAuthorizations: 0, externalTerminal: 'failed', externalResultIssue: 'ResultAccessDenied',
    externalAdapterCid: cid, externalLockCid: cid, originalRunDefinitionCid: cid};
  const warm = {...shared, phase: caseId, interceptedFetches: 2, additionalIssue: 'SdkAdditionalRequestRefused'};
  const cold = {...shared, phase: 'cold', interceptedFetches: 0, egressChecks: 0, originalFailureObserved: true};
  checkPackedProviderObservation({caseId, phase: caseId, pid: 1, observation: warm});
  checkPackedProviderObservation({caseId, phase: 'cold', pid: 2, originalPid: 1, observation: cold});
  for (const observation of [{...warm, interceptedFetches: 1}, {...warm, externalTcp: 1},
    {...warm, externalCredentialReads: 1}, {...warm, externalResultIssue: 'ProviderError'}]) {
    assert.throws(() => checkPackedProviderObservation({caseId, phase: caseId, pid: 1, observation}));
  }
  for (const [pid, observation] of [[1, cold], [2, {...cold, originalFailureObserved: false}],
    [2, {...cold, calls: 1}], [2, {...cold, usageCaptures: 1}]]) {
    assert.throws(() => checkPackedProviderObservation({caseId, phase: 'cold', pid, originalPid: 1, observation}));
  }
});

test('optional diagnostic selection retains nested inventories and bounded usage evidence without keys or state', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-provider-diagnostic-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const ci = parse(await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const upload = ci.jobs['client-model-packed'].steps.find(step => step.with?.path?.includes('/optional-provider/summary.json'));
  const prefix = '${{ runner.temp }}/client-model-packed/optional-provider/';
  const patterns = upload.with.path.split('\n').filter(path => path.startsWith(prefix)).map(path => path.slice(prefix.length));
  const expected = ['summary.json'];
  const privateFiles = [];
  for (const name of ['warm', 'missing-key', 'project-key', 'rate-limit', 'usage-reported', 'usage-zero', 'usage-absent',
    'timeout-headers', 'timeout-body', 'timeout-call']) {
    expected.push(`cases/${name}/packages/ordinary-operation-packages.json`,
      `cases/${name}/packages/optional-provider-packages.json`, `raw/${name}/install-node.stdout`);
    if (name.startsWith('usage-') || name === 'project-key') {
      for (const file of ['usage-original.json', 'usage-receipt.json']) expected.push(`cases/${name}/consumer/${file}`);
    }
    for (const file of ['operator-private.fixture', 'api-key.fixture', 'provider-credential.fixture', 'provider.key', '.state/private.db'])
      privateFiles.push(`cases/${name}/consumer/${file}`);
  }
  for (const path of [...expected, ...privateFiles]) {await mkdir(join(root, path, '..'), {recursive: true}); await writeFile(join(root, path), 'fixture');}
  const selected = [];
  for (const pattern of patterns) for await (const path of glob(pattern, {cwd: root})) selected.push(path);
  assert.deepEqual(selected.sort(), expected.sort());
});

test('required Node Model consumers share one producer and retain the original authority cases', async () => {
  assert.deepEqual(registeredProviderAcceptanceCases, [
    'registered-project', 'registered-anthropic', 'registered-google', 'registered-mixed',
    'registered-mistral', 'registered-openai-responses',
    'registered-length', 'registered-refusal', 'registered-too-late', 'registered-invalid',
    'registered-credential-reference', 'registered-credential-header', 'registered-foreign-model', 'registered-missing-routes',
  ]);
  assert.deepEqual(registeredAuthorityAcceptanceCases, [
    'registered-capabilities', 'registered-openai-responses-over-limit', 'registered-checkpoint',
    'registered-checkpoint-raw-denied', 'registered-checkpoint-changed-route',
    'registered-checkpoint-missing-binding', 'registered-checkpoint-stale-lease',
    'registered-response-loss', 'registered-entered-cancel', 'registered-http-401', 'registered-http-503',
  ]);
  const ci = parse(await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const producer = ci.jobs['client-packages'];
  const optional = producer.steps.filter(step => step.run?.includes("names: ['provider-ai-sdk']"));
  assert.equal(optional.length, 1);
  const upload = producer.steps.find(step => step.id === 'packages');
  assert(producer.steps.indexOf(optional[0]) < producer.steps.indexOf(upload));
  const model = ci.jobs['client-model-packed'];
  assert.deepEqual(model.needs, ['select-targets', 'client-packages']);
  assert(ci.jobs.client.needs.includes('client-model-packed'));
  assert.deepEqual(model.strategy, {'fail-fast': false, matrix: {node: ['22.22.0', '24']}});
  const setup = model.steps.find(step => step.uses?.startsWith('actions/setup-node@'));
  assert.equal(setup.with['node-version'], "${{ matrix.node == '24' && '24.21.0' || matrix.node }}");
  const input = model.steps.find(step => step.id === 'client-inputs');
  assert.equal(input.uses, './.github/actions/download-client-packages');
  assert.equal(input.with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  const cases = model.steps.filter(step => step.run?.includes('node scripts/test-packed-provider-ai-sdk.mjs '));
  assert.deepEqual(cases.map(step => step.run.trim().split('\n').at(-1)), [
    'node scripts/test-packed-provider-ai-sdk.mjs "$RUNNER_TEMP/client-model-packed/optional-provider"',
    'node scripts/test-packed-provider-ai-sdk.mjs "$RUNNER_TEMP/client-model-packed/registered-provider" --registered-only',
    'node scripts/test-packed-provider-ai-sdk.mjs "$RUNNER_TEMP/client-model-packed/model-authority" --registered-authority-only',
  ]);
  for (const step of cases) {
    assert(model.steps.indexOf(input) < model.steps.indexOf(step));
    assert.equal(step.if, "${{ !cancelled() && steps.client-inputs.outcome == 'success' }}");
    assert.equal(step['continue-on-error'], undefined);
  }
  assert(cases[0].run.indexOf('command -v lsof') < cases[0].run.indexOf('node scripts/'));
  assert(!model.steps.some(step => /npm pack|moon build|test-packed-readme/u.test(step.run ?? '')));
  assert(!ci.jobs['client-readme-packed'].steps.some(step => step.run?.includes('test-packed-provider-ai-sdk')));
  const diagnostics = model.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(diagnostics.if, 'always()');
  assert.equal(diagnostics.with['if-no-files-found'], 'error');
  assert(diagnostics.with.path.includes('/model-authority/summary.json'));
  assert(diagnostics.with.path.includes('/model-authority/raw/*/*'));
  const guard = ci.jobs.lint.steps.filter(step => step.run?.includes('scripts/packed-provider-ai-sdk.test.mjs'));
  assert.equal(guard.length, 1);
  const direct = ci.jobs['client-direct-model'];
  assert.deepEqual(direct.needs, ['select-targets', 'client-packages']);
  assert.deepEqual(direct.strategy, {'fail-fast': false, matrix: {node: ['22.22.0', '24.21.0']}});
  assert(direct.if.includes("needs.select-targets.outputs.profile == 'full'"));
  assert(direct.if.includes('!inputs.performance_matrix') && direct.if.includes('!inputs.packed_query_evidence_probe'));
  assert(ci.jobs.check.needs.includes('client-direct-model'));
  const downloader = direct.steps.filter(step => step.uses === './.github/actions/download-client-packages');
  assert.equal(downloader.length, 1);
  assert.equal(downloader[0].with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  const directStep = direct.steps.find(step => step.run?.includes('--direct-only'));
  assert(directStep);
  assert(direct.steps.indexOf(downloader[0]) < direct.steps.indexOf(directStep));
  assert.equal(ci.jobs['client-readme-packed']['timeout-minutes'], 15);
  assert(!ci.jobs['client-readme-packed'].steps.some(step => step.run?.includes('--direct-only')));
  assert(!direct.steps.some(step => /npm (?:pack|run build)|packClientPackages/u.test(step.run ?? '')));
  const receipt = direct.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert(receipt.if.includes('always()'));
  for (const original of ['/summary.json', '/raw/*/*', '/consumer/terminal-0.json',
    '/direct-project/consumer/usage-original.json', '/direct-project/consumer/usage-receipt.json']) {
    assert(receipt.with.path.includes(original));
  }
});

test('registered Checkpoint acceptance binds one approval send and requires a fresh process to read Saved', () => {
  const cid = digit => 'sha256:' + digit.repeat(64);
  const caseId = 'registered-checkpoint';
  const reference = {runDefinitionCid: cid('1'), authorityScopeCid: cid('4')};
  const settlement = {slotCid: cid('2'), attemptCid: cid('3')};
  const taskCid = cid('5');
  const usage = {input_tokens: 2, output_tokens: 3, observation_origin: 'reported',
    model_task_contract_cid: taskCid, model_call_slot_cid: settlement.slotCid, raw_response_artifact_cid: cid('6')};
  const raw = {manifest_cid: cid('6'), holding_cid: cid('7'),
    objects: [{cid: cid('8'), byte_count: 100}, {cid: cid('9'), byte_count: 50}]};
  const receipt = {subject: reference, target: 'inferred', manifest: {kind: 'usage', status: 'complete',
    subject: reference, target: 'inferred',
    items: [{modelCallSlotCid: settlement.slotCid, attemptCid: settlement.attemptCid, status: 'complete'}]}};
  const usageEvidence = {usage, receipt, raw};
  const approved = {caseId, phase: 'approve', pid: 42, reference, settlement, taskCid, usageEvidence,
    usageCounts: {authorize: 1, capture: 1, record: 1},
    approval: {runDefinitionCid: reference.runDefinitionCid}, firstClose: 'closed', scopedStateFd0: true,
    tlsAttempts: 1, peerConnections: 1, posts: 1, credentialReads: 1,
    attempts: [{attempt_cid: settlement.attemptCid, state: 'SavedSuccess'}],
    typedResult: [{id: 'original-text', outcome: 'ok', value: {answer: true}}]};
  const check = (phase, pid, observation) =>
    checkPackedProviderObservation({caseId, phase, pid, originalPid: 41, observation});
  check('approve', 42, approved);
  const saved = {...approved, phase: 'cold', pid: 43, approval: undefined,
    usageCounts: {authorize: 0, capture: 0, record: 0},
    tlsAttempts: 0, peerConnections: 0, posts: 0, credentialReads: 0};
  check('cold', 43, saved);
  for (const wrong of [{posts: 1}, {credentialReads: 1}, {firstClose: 'ClientCleanupPending'},
    {settlement: {...settlement, attemptCid: cid('4')}}, {typedResult: []},
    {usageCounts: approved.usageCounts}, {usageEvidence: {...usageEvidence, raw: {...raw, manifest_cid: cid('a')}}},
    {usageEvidence: {...usageEvidence, receipt: {...receipt, subject: {...reference, authorityScopeCid: cid('a')}}}}]) {
    assert.throws(() => check('cold', 43, {...saved, ...wrong}), {code: 'ERR_ASSERTION'});
  }
  assert.throws(() => check('cold', 41, {...saved, pid: 41}), {code: 'ERR_ASSERTION'});
});

test('registered interruptions distinguish response loss from accepted cancellation and require the original cold Unknown', () => {
  const cid = digit => 'sha256:' + digit.repeat(64);
  for (const [caseId, interruption] of [['registered-response-loss', 'response-loss'],
    ['registered-entered-cancel', 'entered-cancel']]) {
    const cancelled = interruption === 'entered-cancel';
    const originalRunDefinitionCid = cid('1');
    const unknownJournal = {scopeCid: cid('2'), slotCid: cid('3'), attemptCid: cid('4'),
      providerBindingCid: cid('5'), state: 'EnteredUnknown', settled: false};
    const unknownControl = {revision: 4, cancellation_requested: cancelled, physical_stop: 'confirmed'};
    const cancellation = cancelled ? {kind: 'accepted', revision: 3,
      cancelRef: {runDefinitionCid: originalRunDefinitionCid, expectedRevision: 2}} : undefined;
    const warm = {phase: caseId, pid: 15, interruption, originalRunDefinitionCid, unknownJournal, unknownControl, cancellation,
      firstCloseReturned: true, aliveScopedFD0: true, registeredSdk: true, projectCredential: true,
      calls: 1, projectTlsConnects: 1, originalModelStarts: 1, interruptionCredentialReads: 1,
      tasks: 1, requests: 1, responseClosedBeforeFirstClose: true};
    checkPackedProviderObservation({caseId, phase: caseId, pid: 15, observation: warm});
    const cold = {...warm, phase: 'cold', pid: 16, calls: 0, projectTlsConnects: 0, originalModelStarts: 0,
      interruptionCredentialReads: 0, originalUnknown: true, zeroResend: true, egressChecks: 0,
      responseClosedBeforeFirstClose: undefined};
    const checkCold = observation => checkPackedProviderObservation({caseId, phase: 'cold', pid: 16,
      originalPid: 15, observation});
    checkCold(cold);
    for (const altered of [{projectTlsConnects: 1}, {interruptionCredentialReads: 1}, {originalSavedFirst: true},
      {unknownJournal: {...unknownJournal, settled: true}},
      {unknownControl: {...unknownControl, physical_stop: 'unconfirmed'}},
      {unknownControl: {...unknownControl, cancellation_requested: !cancelled}}]) {
      assert.throws(() => checkCold({...cold, ...altered}), {code: 'ERR_ASSERTION'});
    }
  }
});

test('registered binding startup refuses before credentials, original entry or transport and retires state', () => {
  const evidence = {pid: 21, credentialReads: 0, tlsAttempts: 0, peerConnections: 0, calls: 0,
    modelStarts: 0, modelScopes: 0, modelAttempts: 0, aliveScopedFD0: true, usageCaptures: 0,
    bindingProjections: 1, egressChecks: 0, usageAuthorizations: 0};
  for (const [phase, failure] of [
    ['registered-foreign-model', {rejected: 'MoonBitHostFailure', bindingIssue: 'ForeignConfiguration'}],
    ['registered-missing-routes', {rejected: 'InvalidInstalledModelSdkInstallation'}],
  ]) {
    const observation = {...evidence, ...failure, phase};
    const check = value => checkPackedProviderObservation({caseId: phase, phase, pid: 21, observation: value});
    check(observation);
    for (const wrong of [{pid: 22}, {bindingProjections: 0}, {credentialReads: 1}, {modelAttempts: 1},
      {peerConnections: 1}, {calls: 1}, {aliveScopedFD0: false}, {rejected: 'UnrelatedRefusal'}]) {
      assert.throws(() => check({...observation, ...wrong}), {code: 'ERR_ASSERTION'});
    }
  }
});

test('registered checkpoint without a selected binding cannot resume the original attempt', () => {
  const cid = digit => 'sha256:' + digit.repeat(64);
  const caseId = 'registered-checkpoint-missing-binding';
  const reference = {runDefinitionCid: cid('1'), authorityScopeCid: cid('2')};
  const approval = {runDefinitionCid: reference.runDefinitionCid};
  const missingBindingEvidence = {originalSha256: cid('3'), admittedSha256: cid('4')};
  const observation = {caseId, phase: 'approve', pid: 22, firstClose: 'closed', scopedStateFd0: true,
    reference, approval, taskCid: cid('5'), terminalCause: 'ClientModelProviderSelectionUnavailable',
    tlsAttempts: 0, peerConnections: 0, posts: 0, credentialReads: 0, attempts: [],
    usageCounts: {authorize: 0, capture: 0, record: 0}, missingBindingEvidence};
  const check = value => checkPackedProviderObservation({
    caseId, phase: 'approve', pid: 22, originalPid: 21, observation: value,
  });
  check(observation);
  for (const wrong of [{missingBindingEvidence: undefined},
    {missingBindingEvidence: {...missingBindingEvidence, admittedSha256: missingBindingEvidence.originalSha256}},
    {terminalCause: 'ClientModelProviderSelectionChanged'}, {posts: 1}, {credentialReads: 1},
    {attempts: [{state: 'EnteredUnknown'}]}, {approval: {runDefinitionCid: cid('6')}}]) {
    assert.throws(() => check({...observation, ...wrong}), {code: 'ERR_ASSERTION'});
  }
});

test('retained original without a selected binding remains readable and refuses execution replay', () => {
  const cid = digit => 'sha256:' + digit.repeat(64);
  const observation = {phase: 'retained-unbound', firstCloseReturned: true, aliveScopedFD0: true,
    projectCredential: true, registeredSdk: true, capabilityRoutes: ['fixture-chat', 'fixture-unsupported'],
    originalRunDefinitionCid: cid('1'), capabilityJournal: {supported: {
      providerBindingCid: cid('2'), savedAttempts: 1, attemptCid: cid('3'), entrySha256: cid('4'), settlementSha256: cid('5'),
    }}, calls: 0, projectTlsConnects: 0, originalModelStarts: 0, capabilityCredentialReads: 0,
    deniedCredentialReads: 0, historicalSavedAfterChange: true, changedIssue: 'SubmissionRefused',
    changedReason: 'model_provider_selection_unavailable', savedEgressChecks: 0, egressChecks: 1,
    missingBindingEvidence: {originalSha256: cid('6'), admittedSha256: cid('7')}};
  const check = (value, pid = 22) => checkPackedProviderObservation({caseId: 'registered-capabilities',
    phase: 'retained-unbound', pid, originalPid: 21, observation: value});
  check(observation);
  for (const wrong of [{historicalSavedAfterChange: false}, {changedIssue: 'SubmissionConflict'}, {changedReason: 'model_provider_selection'},
    {savedEgressChecks: 1}, {calls: 1}, {originalModelStarts: 1}, {capabilityCredentialReads: 1}, {missingBindingEvidence: undefined},
    {capabilityJournal: {supported: {...observation.capabilityJournal.supported, settlementSha256: 'missing'}}}]) {
    assert.throws(() => check({...observation, ...wrong}), {code: 'ERR_ASSERTION'});
  }
  assert.throws(() => check(observation, 21), {code: 'ERR_ASSERTION'});
});

test('registered HTTP failures preserve the selected status and settled original in a separate Saved process', () => {
  for (const [caseId, status] of [['registered-http-401', 401], ['rate-limit', 429], ['registered-http-503', 503]]) {
    const common = {firstCloseReturned: true, aliveScopedFD0: true, registeredSdk: true, projectCredential: true};
    const warm = {...common, ...httpFailureObservation(status, 21, 1),
      phase: caseId, calls: 1, projectTlsConnects: 1, tasks: 1, requests: 1};
    checkPackedProviderObservation({caseId, phase: caseId, pid: 21, observation: warm});
    const cold = {...common, ...httpFailureObservation(status, 22, 0),
      phase: 'cold', calls: 0, projectTlsConnects: 0, originalSavedFirst: true, egressChecks: 0};
    const checkCold = observation => checkPackedProviderObservation({
      caseId, phase: 'cold', pid: 22, originalPid: 21, observation,
    });
    checkCold(cold);
    for (const altered of [{failureCredentialReads: 1}, {httpStatus: 400}, {originalUnknown: true},
      {failureJournal: {...cold.failureJournal, settled: false}},
      {failureJournal: {...cold.failureJournal, evidence: {}}}]) {
      assert.throws(() => checkCold({...cold, ...altered}), {code: 'ERR_ASSERTION'});
    }
  }
});
