import {runInNewContext} from 'node:vm';
// These are acceptance-harness unit tests with explicit doubles. A green result
// here does not establish that the Native mock workflow is implemented.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, readFile, rm, stat, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeMockAcceptanceObservations, scaffoldProject} from '../packages/native-cli/lib/project-scaffold.mjs';
import {captureNativeMockCommand, mockTemplates, nativeLauncherEnvelope, runNativeCliMockScenario}
  from './native-cli-mock-scenario.mjs';
import {observeNativeJournalExhaustion, requireNativeJournalCapacityRefusal}
  from './test-native-cli-source-free-install.mjs';

test('installed Mock acceptance requires both complete same-cohort public templates without skips', async () => {
  assert.deepEqual(mockTemplates, ['deal-review-mock', 'churn-risk-mock']);
  const installed = await readFile(new URL('./test-native-cli-mock-install.mjs', import.meta.url), 'utf8');
  for (const requirement of ['await verifyNativeCliRelease(directory)',
    "assert.equal(source.revision, manifest.sourceSha",
    'assert(expectedArtifact?.localRuntime',
    'for (const template of mockTemplates) scenarios.push(await runNativeCliMockScenario',
    "assert.equal(scenarios.length, 2, 'Both README and Quickstart must finish without skips')",
    "run(process.execPath, [launcher, ...args], cwd)",
    "records.push(record)", "await writeFile(join(root, 'commands.json')"]) {
    assert(installed.includes(requirement), requirement);
  }
  assert.equal(installed.indexOf('await registry.close()') < installed.indexOf('await writeFile(receiptFile'), true);
});

function observation(pid, events = []) {
  return 'ACTQL_NATIVE_TIMINGS ' + JSON.stringify({pid, origin:'first_hook',elapsed_ns:1,clock_current:true,nested_inclusive:true,
    child_process_counters:false,phase_slots:39,counter_slots:70,initializing_drops:0,invalid_tags:0,invalid_amounts:0,clock_failures:0,overflow:false,stack_overflows:0,parallel_observed:false}) + '\n' +
    Array.from({length:39},(_,tag)=>'ACTQL_NATIVE_PHASE '+JSON.stringify({tag,name:['startup','config_auth','preparation','execution','save','close','saved_result','journal'][tag] ?? {32:'approval_material_complete',33:'approval_reviewer_sign',34:'approval_host_sign',35:'approval_resolution_commit',36:'approval_apply',37:'approval_publish',38:'approval_checkpoint_restore'}[tag] ?? 'private_phase',begins:0,ends:0,inclusive_ns:0,exclusive_ns:0,active:0,overlap:0,unmatched_end:0,sql_prepares:0,current_calls:0})+'\n').join('') +
    Array.from({length:70},(_,tag)=>'ACTQL_NATIVE_COUNTER '+JSON.stringify({tag,name:({0:'sqlite_open_calls',1:'sqlite_prepare_calls',2:'sqlite_step_calls',3:'sqlite_exec_calls',16:'member_hash_calls',17:'parse_check_calls',18:'current_calls',19:'account_auth_calls',20:'run_record_save_calls',22:'host_authorize_calls',23:'captured_read_authorize_calls',24:'publisher_authorize_calls',25:'run_record_read_calls',26:'adoption_digest_calls',46:'backing_allocated_bytes',47:'backing_explicit_zeroed_bytes',64:'signing_full_boundary_calls',65:'signing_helper_revalidation_calls',66:'request_query_parse_calls',67:'request_query_lower_calls',68:'request_semantic_check_calls',69:'request_program_compile_calls'})[tag] ?? 'private_counter',count:0})+'\n').join('') +
    'ACTQL_NATIVE_ACCEPTANCE_BEGIN ' + JSON.stringify({pid, count: events.length, limit: 32, complete: true}) + '\n' +
    events.map((event, seq) => 'ACTQL_NATIVE_ACCEPTANCE_EVENT ' + JSON.stringify({pid, seq, ...event}) + '\n').join('') +
    'ACTQL_NATIVE_ACCEPTANCE_END ' + JSON.stringify({pid, count: events.length}) + '\n';
}
const observedCid = digit => 'sha256:' + digit.repeat(64);

function journalCapacityRefusal({unknown = false, cause = 5001, closed = true} = {}) {
  const diagnostic = observation(1701).trimEnd().split('\n').map(line => {
    const index = line.indexOf(' '), prefix = line.slice(0, index);
    const value = JSON.parse(line.slice(index + 1));
    if (prefix === 'ACTQL_NATIVE_COUNTER') value.count =
      ({8: 1, 10: 7, 11: cause, 14: unknown ? 1 : 0})[value.tag] ?? 0;
    if (prefix === 'ACTQL_NATIVE_PHASE' && value.tag === 5) {
      value.begins = 1; value.ends = closed ? 1 : 0; value.active = closed ? 0 : 1;
    }
    return prefix + ' ' + JSON.stringify(value);
  }).join('\n') + '\n';
  return {code: 1, signal: null, stdout: '', stderr:
    `actql-native-client: LocalSubmissionAcceptance${unknown ? 'Unknown' : 'Unavailable'}` +
    ` originalSubmissionRequestId=${observedCid('a')} originalOperationAttemptId=cli-${'b'.repeat(64)}` +
    ' (reconcile with lookup-request; do not resend this operation)\n' +
    diagnostic + 'ACTQL_NATIVE_LAUNCHER_TIMINGS ' +
    JSON.stringify({units: 'nanoseconds', preparation: 1, child: 1, total: 2}) + '\n'};
}

test('Native Journal fresh refusal retains the original reconciliation context', () => {
  const original = journalCapacityRefusal();
  const observed = requireNativeJournalCapacityRefusal(original);
  assert.equal(observed.originalCause, 'Journal.CapacityExceeded');
  assert.equal(observed.firstCommandCleanupObserved, true);
  assert.equal(observed.independentPhysicalAck, false);
  assert(original.stderr.includes(`originalSubmissionRequestId=${observedCid('a')}`));
  assert(original.stderr.includes(`originalOperationAttemptId=cli-${'b'.repeat(64)}`));
});

test('Native Journal fresh refusal rejects missing malformed or extra reconciliation context', () => {
  const original = journalCapacityRefusal();
  for (const stderr of [
    original.stderr.replace(/ originalSubmissionRequestId=[^\n]+/u, ''),
    original.stderr.replace(observedCid('a'), 'sha256:wrong'),
    original.stderr.replace(`cli-${'b'.repeat(64)}`, 'cli-short'),
    original.stderr.replace('do not resend this operation', 'resend this operation'),
    original.stderr.replace(')\n', ') extra\n'),
    'unexpected error\n' + original.stderr,
  ]) assert.throws(() => requireNativeJournalCapacityRefusal({...original, stderr}),
    {code: 'ERR_ASSERTION'});
});

test('Native Journal shared Read counter cannot become a failed acceptance count', () => {
  const original = journalCapacityRefusal();
  const stderr = original.stderr.split('\n').map(line => {
    const prefix = 'ACTQL_NATIVE_COUNTER ';
    if (!line.startsWith(prefix)) return line;
    const value = JSON.parse(line.slice(prefix.length));
    if (value.tag === 8) value.count = 2424833;
    return prefix + JSON.stringify(value);
  }).join('\n');
  const record = {...original, stderr};
  const observed = requireNativeJournalCapacityRefusal(record);
  assert.deepEqual(observed.nativeFailedAcceptanceCount,
    {status: 'unavailable', counterTag: 8, reason: 'shared-with-original-read-inventory'});
  assert.equal(observed.originalCause, 'Journal.CapacityExceeded');
  assert.equal(record.stderr, stderr, 'Keep the original Read observation without subtraction');
});

test('Native Journal refuses transaction tags after overlapping Compute observations', () => {
  const original = journalCapacityRefusal();
  for (const overlap of ['phase', 'inventory']) {
    const stderr = original.stderr.split('\n').map(line => {
      const index = line.indexOf(' '), prefix = line.slice(0, index);
      if (prefix !== 'ACTQL_NATIVE_PHASE' && prefix !== 'ACTQL_NATIVE_COUNTER') return line;
      const value = JSON.parse(line.slice(index + 1));
      if (overlap === 'phase' && prefix === 'ACTQL_NATIVE_PHASE' && value.tag === 3) {
        value.begins = 1; value.ends = 1;
      }
      if (overlap === 'inventory' && prefix === 'ACTQL_NATIVE_COUNTER' && value.tag === 60)
        value.count = 1;
      return prefix + ' ' + JSON.stringify(value);
    }).join('\n');
    assert.throws(() => requireNativeJournalCapacityRefusal({...original, stderr}),
      {code: 'ERR_ASSERTION'});
  }
});

async function journalFixture(t, fault) {
  const project = await mkdtemp(join(tmpdir(), 'native-journal-exhaustion-oracle-'));
  t.after(() => rm(project, {recursive: true, force: true}));
  const hosts = new Map(), calls = [], environment = {ACTQL_NATIVE_TIMINGS: 'prior'};
  const cli = async (args, cwd, expectedCode = 0) => {
    const operation = args.slice(6);
    assert.deepEqual(args.slice(0, 6), ['--mode', 'local', '--config-root', cwd,
      '--config-file', 'operator.json']);
    calls.push({cwd, args: operation});
    if (operation[0] === 'adopt') {
      assert(!hosts.has(cwd), 'Never replace a project or re-adopt after refusal');
      const configuration = JSON.parse(await readFile(join(cwd, 'operator.json'), 'utf8'));
      const local = configuration.native.local;
      assert([1, 2].includes(local.journal_record_limit));
      assert.equal(local.journal_snapshot_bytes, 8388608);
      assert.equal(local.state_parent, cwd);
      hosts.set(cwd, {limit: local.journal_record_limit, originals: new Map(), attempts: 0});
      return {code: 0, signal: null, stdout: '{"kind":"local_host_adopted"}'};
    }
    const host = hosts.get(cwd); assert(host);
    if (operation[0] === 'run') {
      host.attempts++;
      const document = JSON.parse(await readFile(join(cwd, operation[1]), 'utf8'));
      if (host.originals.size === host.limit) {
        assert.equal(expectedCode, 1);
        assert.equal(host.attempts, host.limit + 1, 'Exactly one failed fresh submission');
        assert.equal(environment.ACTQL_NATIVE_TIMINGS, '1');
        assert.equal(environment.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS, '1');
        return fault === 'missing' ? {code: 1, signal: null, stdout: '', stderr: ''}
          : journalCapacityRefusal();
      }
      assert.equal(expectedCode, 0);
      const runId = `${host.limit}-${host.originals.size}`;
      host.originals.set(runId, {rows: document.stages[0].steps[0].values.rows, file: operation[1]});
      return {code: 0, signal: null, stdout: JSON.stringify({status: 'succeeded', run_id: runId})};
    }
    assert.equal(operation[0], 'result');
    assert.equal(expectedCode, 0); assert.equal(host.attempts, host.limit + 1);
    const original = host.originals.get(operation[1]); assert(original);
    await assert.rejects(readFile(join(cwd, original.file)), {code: 'ENOENT'});
    return {code: 0, signal: null, stdout: (fault === 'saved' ? [{id: 999}] : original.rows)
      .map(row => JSON.stringify(row)).join('\n') + '\n'};
  };
  return {project: join(project, 'cases'), cli, environment, hosts, calls,
    assets: {environment: JSON.stringify({host_policy_profile: {capacity: {}}}),
      'result-policy': '{"version":"explicit-test-policy"}',
      registry: '{}', values: '{}', fragment: '{}', ordered: '{}'},
    libraries: {sqlite: '/explicit-port-not-loaded-sqlite.dylib',
      crypto: '/explicit-port-not-loaded-crypto.dylib'}, runtimeWire: '{}'};
}

test('Native Journal explicit limits precede adopt and all old Saved survive one failed fresh intent', async t => {
  const fixture = await journalFixture(t), before = {...fixture.environment};
  const observed = await observeNativeJournalExhaustion(fixture);
  assert.deepEqual(observed.observations.map(row => row.limit), [1, 2]);
  assert.deepEqual(observed.observations.map(row => row.acceptedSubmissions), [1, 2]);
  assert(observed.observations.every(row => row.allOriginalSavedAfterRefusal));
  assert.equal(fixture.hosts.size, 2);
  assert.deepEqual([...fixture.hosts.values()].map(row => row.attempts), [2, 3]);
  assert.deepEqual(fixture.environment, before);
});

test('Native Journal refusal oracle rejects Unknown foreign cause and unfinished first cleanup', () => {
  assert.equal(requireNativeJournalCapacityRefusal(journalCapacityRefusal()).originalCause,
    'Journal.CapacityExceeded');
  for (const input of [{unknown: true}, {cause: 5002}, {closed: false}])
    assert.throws(() => requireNativeJournalCapacityRefusal(journalCapacityRefusal(input)), {code: 'ERR_ASSERTION'});
});

test('Native Journal refuses changed old Saved without a new Host or repeated failed submission', async t => {
  const fixture = await journalFixture(t, 'saved');
  await assert.rejects(observeNativeJournalExhaustion(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.hosts.size, 1);
  assert.equal([...fixture.hosts.values()][0].attempts, 2);
});

test('Native Journal missing observations fail without retry and restore original flags', async t => {
  const fixture = await journalFixture(t, 'missing'), before = {...fixture.environment};
  await assert.rejects(observeNativeJournalExhaustion(fixture), /timing trailer missing/u);
  assert.equal(fixture.hosts.size, 1);
  assert.equal([...fixture.hosts.values()][0].attempts, 2);
  assert.deepEqual(fixture.environment, before);
});

function commandObservations(command, pid) {
  const events = [];
  for (let ordinal = 0; ordinal < 2; ordinal++) {
    if (command === 'run') for (const tag of [0, 1, 2]) events.push({tag, ordinal, identity: observedCid(String(ordinal + 1))});
    if (command === 'approve') for (const tag of [5, 6, 7, 8, 9, 10, 11]) events.push({tag,
      ordinal: tag === 6 || tag === 7 ? -1 : ordinal,
      identity: tag === 6 || tag === 7 ? '' : observedCid(String(ordinal + (tag === 9 ? 5 : tag === 10 ? 7 : tag === 11 ? 9 : 3)).replace('10', 'a'))});
  }
  return observation(pid, events) + (command === 'init' ? observation(pid + 1) : '');
}

async function fixture(t, template, mutate = () => {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-mock-scenario-unit-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const file = join(root, template, 'mock/data.json');
  let approved = false, reads = 0;
  const updates = template === 'deal-review-mock' ? [
    {id: '006Acme', StageName: 'Negotiation', NextStep: 'Send revised pricing by Friday'},
    {id: '006Globex', StageName: 'Closed Lost', NextStep: 'Revisit next fiscal year'},
  ] : [
    {id: '001Acme', Churn_Risk__c: 'high', Risk_Reason__c: 'falling usage and a competitor evaluation'},
    {id: '001Globex', Churn_Risk__c: 'high', Risk_Reason__c: 'support tickets about pricing'},
  ];
  const calls = [];
  const run = async (args, cwd) => {
    calls.push({args: [...args], cwd});
    let value;
    if (args[0] === 'init') scaffoldProject(args[3], args[2]);
    else if (args[0] === 'run' || args[0] === 'status') {
      value = {version: 'actql-run-state/0.1', run_id: 'unit-original-run',
        status: approved ? 'succeeded' : 'waiting_checkpoint',
        ...(approved ? {} : {checkpoint: {checkpoint_id: 'unit-original-checkpoint',
          checkpoint_cid: `sha256:${'a'.repeat(64)}`}})};
    } else if (args[0] === 'approve') {
      approved = true;
      const data = JSON.parse(await readFile(file, 'utf8'));
      if (template === 'deal-review-mock') {
        Object.assign(data.salesforce.Opportunity.rows[0],
          {StageName: 'Negotiation', NextStep: 'Send revised pricing by Friday'});
        Object.assign(data.salesforce.Opportunity.rows[1],
          {StageName: 'Closed Lost', NextStep: 'Revisit next fiscal year'});
      } else {
        Object.assign(data.salesforce.Account.rows[0],
          {Churn_Risk__c: 'high', Risk_Reason__c: 'falling usage and a competitor evaluation'});
        Object.assign(data.salesforce.Account.rows[1],
          {Churn_Risk__c: 'high', Risk_Reason__c: 'support tickets about pricing'});
      }
      await writeFile(file, JSON.stringify(data));
      value = {resolved: true};
    }
    const record = {code: 0, signal: null, stderr: commandObservations(args[0], 100 + calls.length * 2), stdout: value ? JSON.stringify(value) : ''};
    if (args[0] === 'status' && !args.includes('--json')) {
      assert.equal(approved, false);
      const resource = template === 'deal-review-mock' ? 'Opportunity' : 'Account';
      const originals = JSON.parse(await readFile(file, 'utf8')).salesforce[resource].rows;
      record.stdout = ['Run: "unit-original-run"', 'State: "waiting_checkpoint"',
        'Checkpoint: "unit-original-checkpoint"', `  Original CID: "sha256:${'a'.repeat(64)}"`,
        'Stored Effect Preview (read-only; not approval):',
        `  Effect: "update"  Target: "connector://salesforce/${resource}"`, '  Items: 2',
        '  Preview strength: "full_diff"', '  Changes:', ...updates.flatMap(update => [
          '    Row: ' + JSON.stringify(update.id),
          '      Before: ' + JSON.stringify({state: 'present', value: originals.find(row => row.id === update.id)}),
          '      After: ' + JSON.stringify({state: 'present', value:
            Object.fromEntries(Object.entries(update).filter(([name]) => name !== 'id'))}),
        ])].join('\n') + '\n';
    }
    if (args[0] === 'result') {
      reads++;
      const ids = template === 'deal-review-mock' ? ['006Acme', '006Globex'] : ['001Acme', '001Globex'];
      const values = template === 'deal-review-mock' ? [
        {id: ids[0], StageName: 'Proposal', NextStep: null, review: {outcome: 'ok', value:
          {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'}}},
        {id: ids[1], StageName: 'Negotiation', NextStep: 'Legal review', review: {outcome: 'ok', value:
          {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'}}},
      ] : [
        {id: ids[0], risk: {outcome: 'ok', value: {level: 'high', reason: 'falling usage and a competitor evaluation'}}},
        {id: ids[1], risk: {outcome: 'ok', value: {level: 'high', reason: 'support tickets about pricing'}}},
      ];
      record.stdout = values.map(value => JSON.stringify(value)).join('\n') + '\n';
    }
    await mutate({args, record, file, reads});
    return record;
  };
  return {root, template, run, calls};
}

for (const template of mockTemplates) test(`harness requires the public ${template} approval and retained reread sequence`, async t => {
  const options = await fixture(t, template);
  const receipt = await runNativeCliMockScenario(options);
  assert.equal(receipt.runId, 'unit-original-run');
  assert.equal(receipt.resultRows, 2);
  assert.deepEqual(options.calls.map(({args}) => args[0]),
    ['init', 'run', 'status', 'status', 'approve', 'status', 'result', 'status', 'result']);
  assert.equal(options.calls.filter(({args}) => args[0] === 'run').length, 1);
  assert.equal(options.calls.filter(({args}) => args[0] === 'approve').length, 1);
  assert.deepEqual(receipt.humanWaiting, {runId: 'unit-original-run', checkpointId: 'unit-original-checkpoint',
    checkpointCid: `sha256:${'a'.repeat(64)}`, rows: 2});
  assert.deepEqual(options.calls.filter(({args}) => args[0] === 'status' && !args.includes('--json'))
    .map(({args}) => args), [['status', 'unit-original-run']]);
});

for (const [name, mutate, pattern] of [
  ['unavailable bindings', ({args, record}) => {
    if (args[0] === 'run') Object.assign(record, {code: 1, stderr: 'LocalProjectBindingsUnavailable'});
  }, /LocalProjectBindingsUnavailable/u],
  ['success receipt without Run state', ({args, record}) => {
    if (args[0] === 'run') record.stdout = '{"kind":"prepared"}';
  }, /command receipt/u],
  ['changed recovered Run', ({args, record}) => {
    if (args[0] === 'status') record.stdout = record.stdout.replace('unit-original-run', 'replacement-run');
  }, /original Run/u],
  ['changed recovered preview', ({args, record}) => {
    if (args[0] === 'status') record.stdout = record.stdout.replace('a'.repeat(64), 'b'.repeat(64));
  }, /strictly equal/u],
  ['write before approval', async ({args, file}) => {
    if (args[0] === 'run') await writeFile(file, '{}');
  }, /before approval/u],
  ['unrelated changes on approval', async ({args, file}) => {
    if (args[0] === 'approve') {
      const data = JSON.parse(await readFile(file, 'utf8')); data.unrequested = true;
      await writeFile(file, JSON.stringify(data));
    }
  }, /expected target fields/u],
  ['missing Result row', ({args, record}) => {
    if (args[0] === 'result') record.stdout = '{"id":"006Acme"}\n';
  }, /expected updates/u],
  ['missing retained Model outcome', ({args, record}) => {
    if (args[0] === 'result') record.stdout = '{"id":"006Acme"}\n{"id":"006Globex"}\n';
  }, /Model outcome/u],
  ['replacement post-write Source result', ({args, record}) => {
    if (args[0] === 'result') record.stdout = record.stdout.replace('"StageName":"Proposal"', '"StageName":"Negotiation"');
  }, /pre-write Source/u],
  ['changed retained Result', ({args, record, reads}) => {
    if (args[0] === 'result' && reads === 2) record.stdout += '\n';
  }, /original bytes/u],
  ['same-byte Effect replay during reread', async ({args, file, reads}) => {
    if (args[0] === 'result' && reads === 2) await writeFile(file, await readFile(file));
  }, /rewrite the target/u],
]) test(`harness refuses ${name} instead of counting a skip or acceptance`, async t => {
  const options = await fixture(t, 'deal-review-mock', mutate);
  await assert.rejects(runNativeCliMockScenario(options), pattern);
});


test('harness refuses deferring the approved Effect until status', async t => {
  let before, deferred;
  const options = await fixture(t, 'deal-review-mock', async ({args, file}) => {
    if (args[0] === 'run') before = await readFile(file);
    if (args[0] === 'approve') {
      deferred = await readFile(file);
      await writeFile(file, before);
    } else if (args[0] === 'status' && deferred) {
      await writeFile(file, deferred);
    }
  });
  await assert.rejects(runNativeCliMockScenario(options), /expected target fields/u);
});

test('harness refuses same-byte Effect replay during completed status', async t => {
  const options = await fixture(t, 'deal-review-mock', async ({args, record, file}) => {
    if (args[0] === 'status' && args.includes('--json') && JSON.parse(record.stdout).status === 'succeeded') {
      await writeFile(file, await readFile(file));
    }
  });
  await assert.rejects(runNativeCliMockScenario(options), /Completed status must not rewrite/u);
});


for (const operation of ['approve', 'result']) {
  test(`harness refuses consulting Model answers during ${operation} recovery`, async t => {
    const options = await fixture(t, 'deal-review-mock', async ({args, file}) => {
      if (args[0] === operation) {
        await readFile(join(file, '..', 'deal-review.v1.answers.yaml'));
      }
    });
    await assert.rejects(runNativeCliMockScenario(options), {code: 'ENOENT'});
  });
}


for (const [name, mutate, pattern] of [
  ['State-only output without the stored Preview', ({record}) => {
    record.stdout = record.stdout.split('Stored Effect Preview')[0];
  }, /Human waiting Preview/u],
  ['a replacement Run in human output', ({record}) => {
    record.stdout = record.stdout.replace('unit-original-run', 'replacement-run');
  }, /Human waiting Preview/u],
  ['a replacement Checkpoint in human output', ({record}) => {
    record.stdout = record.stdout.replace('a'.repeat(64), 'b'.repeat(64));
  }, /Human waiting Preview/u],
  ['a Program alias instead of the original target URI', ({record}) => {
    record.stdout = record.stdout.replace('connector://salesforce/Opportunity', 'salesforce.Opportunity');
  }, /Human waiting Preview/u],
  ['a different connector target resource', ({record}) => {
    record.stdout = record.stdout.replace('connector://salesforce/Opportunity', 'connector://salesforce/Account');
  }, /Human waiting Preview/u],
  ['incorrect displayed before evidence', ({record}) => {
    record.stdout = record.stdout.replace('"StageName":"Proposal"', '"StageName":"Other"');
  }, /original before StageName/u],
  ['incorrect displayed intended changes', ({record}) => {
    record.stdout = record.stdout.replace('"StageName":"Negotiation"', '"StageName":"Other"');
  }, /intended after fields/u],
]) test(`harness refuses ${name}`, async t => {
  const options = await fixture(t, 'deal-review-mock', context => {
    if (context.args[0] === 'status' && !context.args.includes('--json')) mutate(context);
  });
  await assert.rejects(runNativeCliMockScenario(options), pattern);
});

test('harness rejects restricted Preview contents added to canonical JSON state', async t => {
  const options = await fixture(t, 'deal-review-mock', ({args, record}) => {
    if (args[0] === 'run') record.stdout = JSON.stringify({...JSON.parse(record.stdout),
      effect_preview: {before: 'restricted original'}});
  });
  await assert.rejects(runNativeCliMockScenario(options), /JSON Run state must not embed restricted Preview/u);
});

for (const [name, mutate, pattern] of [
  ['missing diagnostics', record => { record.stderr = ''; }, /Missing complete Native observations/u],
  ['truncated diagnostics', record => { record.stderr = record.stderr.replace(/ACTQL_NATIVE_ACCEPTANCE_END[^\n]*\n/gu, ''); }, /Missing complete Native observations/u],
  ['overflow or failed recording', record => { record.stderr = record.stderr.replace('"complete":true', '"complete":false'); }, /Incomplete Native observations/u],
  ['foreign process', record => { record.stderr = record.stderr.replace('"pid":104,"seq":0', '"pid":999,"seq":0'); }, /Foreign or extra Native event/u],
  ['wrong attempt identity', record => { record.stderr = record.stderr.replace('"tag":1,"ordinal":0,"identity":"sha256:' + '1'.repeat(64), '"tag":1,"ordinal":0,"identity":"sha256:' + '2'.repeat(64)); }, /Changed original Model attempt/u],
  ['same-byte Effect replay', record => { record.stderr = commandObservations('approve', 900); }, /replayed Model or Effect work/u],
]) test(`Native acceptance refuses ${name} instead of claiming zero replay`, async t => {
  const options = await fixture(t, 'deal-review-mock', ({args, record}) => {
    if (args[0] === (name === 'same-byte Effect replay' ? 'status' : 'run')) mutate(record);
  });
  await assert.rejects(runNativeCliMockScenario(options), pattern);
});

for (const [name, edit, pattern] of [
  ['foreign dispatch ACK', text => text.replace('"tag":8,"ordinal":0,"identity":"sha256:'+'3'.repeat(64), '"tag":8,"ordinal":0,"identity":"sha256:'+'4'.repeat(64)), /Changed original Effect dispatch key/u],
  ['rename attempt confused with success', text => text.replace('"seq":2,"tag":7', '"seq":2,"tag":6'), /retain attempt, rename, final ACK/u],
  ['repeated original operation', text => text.replaceAll('sha256:'+'4'.repeat(64), 'sha256:'+'3'.repeat(64)), /Repeated Effect operation/u],
  ['repeated file receipt', text => text.replaceAll('sha256:'+'8'.repeat(64), 'sha256:'+'7'.repeat(64)), /Repeated Effect operation/u],
]) test(`Native acceptance refuses ${name}`, async t => {
  const options = await fixture(t, 'deal-review-mock', ({args, record}) => {
    if (args[0] === 'approve') record.stderr = edit(record.stderr);
  });
  await assert.rejects(runNativeCliMockScenario(options), pattern);
});

test('fresh command observation groups do not treat an OS PID as an operation identity', async t => {
  const options = await fixture(t, 'deal-review-mock', ({args, record}) => {
    if (args[0] !== 'init') record.stderr = record.stderr.replace(/"pid":\d+/gu,'"pid":999');
  });
  const receipt = await runNativeCliMockScenario(options);
  assert.equal(receipt.resultRows,2);
});

test('unrelated timing precision does not replace acceptance event completeness', async t => {
  const options = await fixture(t, 'deal-review-mock', ({record}) => {
    record.stderr = record.stderr.replaceAll('"clock_current":true','"clock_current":false')
      .replaceAll('"clock_failures":0','"clock_failures":1')
      .replaceAll('"overflow":false','"overflow":true')
      .replaceAll('"stack_overflows":0','"stack_overflows":1')
      .replaceAll('"parallel_observed":false','"parallel_observed":true');
  });
  assert.equal((await runNativeCliMockScenario(options)).resultRows,2);
});

test('different attempts cannot replace the original two Model slots', async t => {
  const options = await fixture(t, 'deal-review-mock', ({args,record}) => {
    if (args[0] === 'run') record.stderr = record.stderr.replaceAll('"ordinal":1','"ordinal":0');
  });
  await assert.rejects(runNativeCliMockScenario(options),/Changed original Model slots/u);
});

const launcherTimingTrailer = value => 'ACTQL_NATIVE_LAUNCHER_TIMINGS ' + JSON.stringify({units:'nanoseconds',preparation:12,child:30,total:42,...value}) + '\n';

test('Node launcher acceptance unwraps its canonical final trailer without changing Native observations or raw stderr', async t => {
  const raw = [];
  const options = await fixture(t, 'deal-review-mock', ({record}) => {
    record.stderr += launcherTimingTrailer(); raw.push(record.stderr);
  });
  options.launcherTimings = 'required';
  const receipt = await runNativeCliMockScenario(options);
  assert.equal(receipt.resultRows,2);
  assert.deepEqual(receipt.commands.map(command=>command.stderr),raw);
  assert(receipt.commands.every(command=>command.launcherTiming.units==='nanoseconds' && command.launcherTiming.total===42));
  assert.equal(receipt.commands.find(command=>command.args[0]==='run').acceptance.modelAttempts.length,2);
  assert.equal(receipt.commands.find(command=>command.args[0]==='approve').acceptance.writes.length,2);
});

test('the actual Node launcher timing statement remains compatible with the required harness envelope', async t => {
  const source = await readFile(new URL('../packages/native-cli/bin/actql.mjs',import.meta.url),'utf8');
  const start = source.indexOf("      writeSync(2, 'ACTQL_NATIVE_LAUNCHER_TIMINGS '");
  const end = source.indexOf('\n    } catch {}',start);
  assert(start>=0 && end>start);
  let trailer;
  runInNewContext(source.slice(start,end),{childStart:30n,timingStart:12n,finish:42n,
    writeSync(fd,value){assert.equal(fd,2);trailer=value;}});
  const options = await fixture(t,'deal-review-mock',({record})=>{record.stderr+=trailer;});
  options.launcherTimings='required';
  const receipt = await runNativeCliMockScenario(options);
  assert(receipt.commands.every(command=>command.launcherTiming.total===30));
});

test('the required Node caller cannot silently become a direct Native caller', async t => {
  const options = await fixture(t,'deal-review-mock'); options.launcherTimings='required';
  await assert.rejects(runNativeCliMockScenario(options),/Required Node launcher timing trailer missing/u);
  const installed = await readFile(new URL('./test-native-cli-mock-install.mjs',import.meta.url),'utf8');
  assert(installed.includes("runNativeCliMockScenario({root, template, launcherTimings: 'required'"));
});

for (const [name, envelope] of [
  ['duplicate trailer', text=>text+launcherTimingTrailer()+launcherTimingTrailer()],
  ['out of order trailer', text=>launcherTimingTrailer()+text],
  ['truncated trailer', text=>text+launcherTimingTrailer().slice(0,-1)],
  ['unknown trailing record', text=>text+launcherTimingTrailer()+'ACTQL_NATIVE_UNKNOWN {}\n'],
  ['ordinary error before trailer', text=>text+'PRIVATE error\n'+launcherTimingTrailer()],
  ['ordinary error after trailer', text=>text+launcherTimingTrailer()+'PRIVATE error\n'],
  ['PID field', text=>text+launcherTimingTrailer({pid:123})],
  ['unknown field', text=>text+launcherTimingTrailer({error:'PRIVATE'})],
  ['wrong units', text=>text+launcherTimingTrailer({units:'milliseconds'})],
  ['negative amount', text=>text+launcherTimingTrailer({preparation:-1,total:29})],
  ['fractional amount', text=>text+launcherTimingTrailer({child:0.5,total:12.5})],
  ['unsafe amount', text=>text+launcherTimingTrailer({preparation:9007199254740992,child:0,total:9007199254740992})],
  ['unsafe sum', text=>text+launcherTimingTrailer({preparation:Number.MAX_SAFE_INTEGER,child:1,total:Number.MAX_SAFE_INTEGER})],
  ['incorrect sum', text=>text+launcherTimingTrailer({total:41})],
  ['negative zero spelling', text=>text+launcherTimingTrailer().replace('"preparation":12','"preparation":-0')],
  ['duplicate field', text=>text+launcherTimingTrailer().replace('"child":30','"child":30,"child":30')],
  ['alternate field order', text=>text+'ACTQL_NATIVE_LAUNCHER_TIMINGS {"preparation":12,"units":"nanoseconds","child":30,"total":42}\n'],
  ['noncanonical whitespace', text=>text+launcherTimingTrailer().replace('{','{ ')],
  ['unknown launcher prefix', text=>text+launcherTimingTrailer().replace('LAUNCHER_TIMINGS','LAUNCHER_ERROR')],
]) test(`launcher observations refuse ${name} without laundering Native errors`, async t => {
  const options=await fixture(t,'deal-review-mock',({record})=>{record.stderr=envelope(record.stderr);});
  options.launcherTimings='required';
  await assert.rejects(runNativeCliMockScenario(options));
});

test('Native mock command capture preserves complete diagnostics on an owned regular stderr file', async t => {
  const root = await mkdtemp(join(tmpdir(), 'native-mock-stderr-'));
  t.after(() => rm(root, {recursive:true, force:true}));
  const server = createServer((_request, response) => response.end('original registry is responsive'));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const events = [0,1].flatMap(ordinal => [0,1,2].map(tag =>
    ({tag,ordinal,identity:observedCid(String(ordinal + 1))})));
  const native = observation(901, events) + observation(902), original = native + launcherTimingTrailer();
  assert(Buffer.byteLength(original) > 16 * 1024, 'Exercise more than a small pipe window');
  const payload = join(root, 'original.txt'), stderrPath = join(root, 'command.stderr');
  await writeFile(payload, original);
  const source = `import assert from 'node:assert/strict';
    import {fstatSync,readFileSync,writeSync} from 'node:fs';
    assert(fstatSync(2).isFile());
    const reply=await fetch(process.argv[2]);
    assert.equal(await reply.text(),'original registry is responsive');
    const body=readFileSync(process.argv[1]);
    for(let offset=0;offset<body.length;offset+=512)
      assert.equal(writeSync(2,body.subarray(offset,offset+512)),Math.min(512,body.length-offset));
    writeSync(1,'complete original child\\n');`;
  const result = await captureNativeMockCommand(process.execPath,
    ['--input-type=module','-e',source,payload,`http://127.0.0.1:${server.address().port}`],
    {cwd:root, env:process.env, stderrPath, timeout:5000});
  assert.equal(result.stdout, 'complete original child\n');
  assert.equal(result.stderr, original);
  assert.equal(await readFile(stderrPath, 'utf8'), original);
  assert.equal((await stat(stderrPath)).mode & 0o777, 0o600);
  const envelope = nativeLauncherEnvelope(result.stderr, 'required');
  assert.equal(envelope.native, native);
  assert.equal(nativeMockAcceptanceObservations(envelope.native)[0].events.length, 6);
  await assert.rejects(captureNativeMockCommand(process.execPath, ['-e','process.exit(99)'],
    {cwd:root,env:process.env,stderrPath,timeout:5000}), {code:'EEXIST'});
  assert.equal(await readFile(stderrPath, 'utf8'), original, 'Never overwrite the original diagnostic file');
});

test('Native mock command capture retains original failures and bounded reads', async t => {
  const root = await mkdtemp(join(tmpdir(), 'native-mock-capture-failures-'));
  t.after(() => rm(root, {recursive:true, force:true}));
  for (const [name, source, options, expected] of [
    ['nonzero', "process.stderr.write('original error\\n');process.exitCode=7", {}, {code:7,exitCode:7,signal:null,stderr:'original error\n'}],
    ['signal', "process.kill(process.pid,'SIGTERM')", {}, {code:null,exitCode:null,signal:'SIGTERM'}],
    ['timeout', 'setInterval(()=>{},1000)', {timeout:100}, {code:'ETIMEDOUT',signal:'SIGKILL',killed:true}],
    ['stdout', "require('node:fs').writeSync(1,Buffer.alloc(4096,120))", {maxBuffer:32}, {code:'ERR_CHILD_PROCESS_STDIO_MAXBUFFER'}],
    ['stderr', "require('node:fs').writeSync(2,Buffer.alloc(4096,120))", {maxBuffer:32}, {code:'ERR_CHILD_PROCESS_STDIO_MAXBUFFER',exitCode:0,signal:null,killed:false}],
  ]) {
    await assert.rejects(captureNativeMockCommand(process.execPath, ['-e',source],
      {cwd:root,env:process.env,stderrPath:join(root,name+'.stderr'),timeout:5000,...options}), error => {
      for (const [key,value] of Object.entries(expected)) assert.equal(error[key],value,name+': '+key);
      assert(Buffer.byteLength(error.stdout) <= (options.maxBuffer ?? 8 * 1024 * 1024));
      assert(Buffer.byteLength(error.stderr) <= (options.maxBuffer ?? 8 * 1024 * 1024));
      return true;
    });
  }
});

test('Native mock command capture cannot launder incomplete or foreign diagnostic rows', async t => {
  const root = await mkdtemp(join(tmpdir(), 'native-mock-capture-refusals-'));
  t.after(() => rm(root, {recursive:true, force:true}));
  const native = observation(902);
  for (const [index, original] of [
    native+'ACTQL_NATIVE_ACCEPTANCE_EVEN'+launcherTimingTrailer(),
    native+launcherTimingTrailer()+launcherTimingTrailer(),
    native+launcherTimingTrailer()+'unknown trailing garbage\n',
    'original Native error\n'+native+launcherTimingTrailer(),
    native,
  ].entries()) {
    const payload = join(root,index+'.txt'); await writeFile(payload,original);
    const result = await captureNativeMockCommand(process.execPath,
      ['-e',"require('node:fs').writeSync(2,require('node:fs').readFileSync(process.argv[1]))",payload],
      {cwd:root,env:process.env,stderrPath:join(root,index+'.stderr'),timeout:5000});
    assert.equal(result.stderr,original);
    assert.throws(() => nativeMockAcceptanceObservations(nativeLauncherEnvelope(result.stderr,'required').native));
  }
});

test('Native mock command capture stops continuous stderr growth before timeout', async t => {
  const root = await mkdtemp(join(tmpdir(), 'native-mock-live-limit-'));
  t.after(() => rm(root, {recursive:true, force:true}));
  await assert.rejects(captureNativeMockCommand(process.execPath,
    ['-e',"setInterval(()=>require('node:fs').writeSync(2,Buffer.alloc(1024,120)),2)"],
    {cwd:root,env:process.env,stderrPath:join(root,'live.stderr'),timeout:3000,maxBuffer:4096}), error => {
    assert.equal(error.code,'ERR_CHILD_PROCESS_STDIO_MAXBUFFER');
    assert.equal(error.signal,'SIGKILL');
    assert.equal(error.killed,true);
    assert(Buffer.byteLength(error.stderr)<=4096);
    return true;
  });
});
