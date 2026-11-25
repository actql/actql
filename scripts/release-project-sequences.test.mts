import assert from 'node:assert/strict';
import test, {after} from 'node:test';
import {createHash} from 'node:crypto';
import {runReleaseProjectSequences, assertProjectSequenceRows, assertTemplateStatic, assertProjectNodeWork,
  assertProjectResultDescription, projectCliExpectedExit} from './release-project-sequences.mjs';
import {mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';
import {requireNativeMockWork} from './native-cli-mock-scenario.mjs';
import {observeNativeMockHarnessPhase, type NativeMockHarnessRecord} from './native-approval-performance.mjs';

type ReleasePorts = Parameters<typeof runReleaseProjectSequences>[0];
type Label = Parameters<ReleasePorts['cli']>[2];
type ActionRequest = Parameters<ReleasePorts['node']>[0];
type CaseRecord = Awaited<ReturnType<typeof runReleaseProjectSequences>>[number];
type TemplateSnapshot = Parameters<typeof assertProjectSequenceRows>[2];
type ProjectDescription = Parameters<typeof assertProjectResultDescription>[1];
type ProjectPlan = Parameters<typeof assertTemplateStatic>[1];
type BindingEvent = Parameters<typeof requireNativeMockWork>[1];
type ResultReadObservation = (work: unknown, request: {kind: 'result'}, rows: number) => void;
type FixtureData = ReturnType<typeof sourceData> & {unrelated?: string};
type FixtureOriginal = CaseRecord['runs'][number]['original'];
type Decision = 'approved' | 'rejected';
type FixtureRun = {original: FixtureOriginal; before: FixtureData;
  status: 'waiting_checkpoint' | 'succeeded' | 'cancelled'};
type FixtureProject = {template: string; data: FixtureData; generation: number; runs: FixtureRun[]};
type ObservedCall = Label & {project: string; args?: readonly string[]; kind?: ActionRequest['kind']};
type WorkCounts = {sourceAcquisitionStarts: number; modelCallStarts: number; effectReplacementReturns: number};
type FixtureExit = {code: number; signal: string | null; stdout: string; pid: number;
  acceptance?: {modelAttempts: unknown[]; writes: unknown[]}};
type ColumnContract = {type: string; nullable: boolean; additional_properties?: boolean;
  fields?: Record<string, ColumnContract>; enum?: string[]; media_type?: string};
type FixtureDescription = {ref: FixtureOriginal['ref']; resultName: string;
  columns: {name: string; contract: ColumnContract}[];
  programDefinitionCid: string; resultDefinitionCid: string; resultSchemaCid: string; resultArtifactCid: string};
type FixtureReply = {pid: number; firstClose: {attempted: boolean; returned: boolean};
  workObservation: WorkCounts & {totals: WorkCounts; complete: boolean};
  original?: FixtureOriginal; state?: Record<string, unknown>; rows?: unknown[];
  description?: FixtureDescription; check?: unknown; plan?: unknown; staticChecks?: unknown[]};
type FixturePorts = {root: string;
  snapshot(project: string): Promise<{bytes: string; generation: number}>;
  persist(record: CaseRecord): Promise<void>;
  cli(args: readonly string[], project: string, label: Label): Promise<FixtureExit>;
  node(request: ActionRequest, project: string, label: Label): Promise<FixtureReply>};
type HarnessPhase = 'release-project-sequences' | 'original-mock-regressions';
type PhaseRecord = NativeMockHarnessRecord<HarnessPhase>;

// The original fixture ports supply independently authored observations and
// timestamps. The runner itself checks slot and payload requirements.
const runWithFixture = runReleaseProjectSequences as unknown as
  (ports: FixturePorts) => ReturnType<typeof runReleaseProjectSequences>;

// Independently authored port DATA, not a Native/SQLite/installed execution.
const sourceData = (template: string) => template === 'churn-risk-mock' ? {
  salesforce: {Account: {key: ['id'], rows: [
    {id: '001Acme', name: 'Acme Corp', description: 'Acme notes', Churn_Risk__c: 'low', Risk_Reason__c: null},
    {id: '001Globex', name: 'Globex Inc', description: 'Globex notes', Churn_Risk__c: 'medium', Risk_Reason__c: null},
  ]}}, snowflake: {usage_30d: {rows: [
    {account_id: '001Acme', active_users: 4, trend: 'down'}, {account_id: '001Globex', active_users: 12, trend: 'flat'},
  ]}},
} : {salesforce: {Opportunity: {key: ['id'], rows: [
  {id: '006Acme', name: 'Acme renewal', StageName: 'Proposal', NextStep: null},
  {id: '006Globex', name: 'Globex expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
]}}, drive: {files: {rows: [
  {name: 'Acme renewal', content_utf8: 'Independent Acme notes\n'},
  {name: 'Globex expansion', content_utf8: 'Independent Globex notes\n'},
]}}};

// Independently authored descriptions for explicit ports, not compiler output.
function describedColumns(template: string): FixtureDescription['columns'] {
  const string = {type: 'string', nullable: false};
  const key = {type: 'object', nullable: false, additional_properties: false, fields: {id: string}};
  if (template === 'churn-risk-mock') return [
    {name: 'id', contract: string}, {name: 'notes', contract: string},
    {name: 'active_users', contract: {type: 'int64', nullable: false}}, {name: 'trend', contract: string},
    {name: 'risk', contract: {type: 'object', nullable: false, additional_properties: false, fields: {
      input_key: key, outcome: string,
      value: {type: 'object', nullable: false, additional_properties: false, fields: {
        level: {type: 'string', nullable: false, enum: ['low', 'medium', 'high']}, reason: string,
      }},
    }}},
  ];
  return [
    {name: 'id', contract: string}, {name: 'StageName', contract: string},
    {name: 'NextStep', contract: {type: 'string', nullable: true}},
    {name: 'notes', contract: {type: 'content_ref', nullable: false, media_type: 'text/plain'}},
    {name: 'review', contract: {type: 'object', nullable: false, additional_properties: false, fields: {
      input_key: key, outcome: string,
      value: {type: 'object', nullable: false, additional_properties: false, fields: {
        changed: {type: 'boolean', nullable: false}, stage: string, next_step: string,
      }},
    }}},
  ];
}

function fixture({failApproval = false, replaceRun = false, mutateSavedRows = false, mutateUnrelated = false,
  mutateInitialContract = false, missingStaticControls = false} = {}) {
  const root = mkdtempSync(join(tmpdir(), 'actql-rc-sequence-ports-'));
  after(() => rmSync(root, {recursive: true, force: true}));
  const projects = new Map<string, FixtureProject>(), records: CaseRecord[] = [], calls: ObservedCall[] = [], failure = new Error('original Unknown approval');
  let ordinal = 0, pid = 100;
  const plan = {version: 'actql-effectful-static-plan-view/0.1', observation: 'static', provider_io: 0,
    computation: {plan_view: {logical_map: {steps: [{operator: 'join'}, {operator: 'infer'}]}}},
    effect_set: {members: [{effect_kind: 'update', input: {kind: 'result', result_name: 'aql_private_update'}}]}};
  const check = {outcome: 'completed', report: {verdict: 'verified', runnable: {verdict: 'yes', reasons: []}}};
  const current = (run: FixtureRun) => ({version: 'actql-run-state/0.1', run_id: run.original.runId, status: run.status,
    checkpoint: {id: run.original.checkpointId, checkpoint_id: run.original.checkpointId,
      checkpoint_cid: run.original.checkpointCid}});
  function start(project: string) {
    const value = projects.get(project)!, n = ++ordinal;
    const original = {runId: 'run-' + n, checkpointId: 'checkpoint-' + n,
      checkpointCid: 'sha256:' + n.toString(16).padStart(64, '0'),
      ref: {namespaceId: 'same-project', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
        runDefinitionCid: 'sha256:' + (n + 100).toString(16).padStart(64, '0')}};
    const run: FixtureRun = {original, before: structuredClone(value.data), status: 'waiting_checkpoint'};
    value.runs.push(run); return run;
  }
  function resolve(value: FixtureProject, run: FixtureRun, decision: Decision, label: Label) {
    if (failApproval && label.family === 'native-after-approve' && label.ordinal === 2) throw failure;
    run.status = decision === 'approved' ? 'succeeded' : 'cancelled';
    if (decision === 'approved') {
      const resource = value.template === 'churn-risk-mock' ? 'Account' : 'Opportunity';
      for (const row of value.data.salesforce[resource]!.rows) {
        const first = row.id.endsWith('Acme');
        Object.assign(row, resource === 'Account' ? {Churn_Risk__c: 'high', Risk_Reason__c: first
          ? 'falling usage and a competitor evaluation' : 'support tickets about pricing'}
          : {StageName: first ? 'Negotiation' : 'Closed Lost', NextStep: first
            ? 'Send revised pricing by Friday' : 'Revisit next fiscal year'});
      }
      if (mutateUnrelated) value.data.unrelated = 'unexpected write';
      value.generation++;
    }
  }
  function rows(value: FixtureProject, run: FixtureRun) {
    const before = mutateSavedRows ? value.data : run.before;
    if (value.template === 'churn-risk-mock') return before.salesforce.Account!.rows.map((row, i) => ({
      id: row.id, notes: row.description, active_users: String(before.snowflake!.usage_30d.rows[i].active_users),
      trend: before.snowflake!.usage_30d.rows[i].trend, risk: {input_key: {id: row.id}, outcome: 'ok', value: {level: 'high', reason: i === 0
        ? 'falling usage and a competitor evaluation' : 'support tickets about pricing'}},
    }));
    return before.salesforce.Opportunity!.rows.map((row, i) => {
      const notes = before.drive!.files.rows[i].content_utf8;
      return {id: row.id, StageName: row.StageName, NextStep: row.NextStep,
        notes: {$actql_ref: 'content', media_type: 'text/plain', metadata: {
          content_cid: 'sha256:' + createHash('sha256').update(notes).digest('hex'),
          size_bytes: Buffer.byteLength(notes), truncated: false}},
        review: {input_key: {id: row.id}, outcome: 'ok', value: {changed: true, stage: i === 0 ? 'Negotiation' : 'Closed Lost',
          next_step: i === 0 ? 'Send revised pricing by Friday' : 'Revisit next fiscal year'}}};
    });
  }
  return {projects, records, calls, failure, options: {root,
    async snapshot(project) {const p = projects.get(project)!; return {bytes: JSON.stringify(p.data), generation: p.generation};},
    async persist(record) {records.push(structuredClone(record));},
    async cli(args, project, label) {
      calls.push({surface: 'cli', args, project, ...(label as Omit<Label, 'surface'>)});
      if (args[0] === 'init') {
        assert(!projects.has(project), 'Never scaffold/reset an existing sequence project');
        mkdirSync(project);
        const program = args[2].slice(0, -5) + '.aql';
        writeFileSync(join(project, program), projectTemplateFiles(args[2])[program], {flag: 'wx'});
        projects.set(project, {template: args[2], data: sourceData(args[2]), generation: 0, runs: []});
        return {code: 0, signal: null, stdout: '', pid: ++pid};
      }
      const value = projects.get(project)!; let reply: unknown;
      if (args[0] === 'check' && label.staticCheckControl) {
        assert.equal(value.runs.length, 0, 'CLI controls precede the first Run');
        const invalid = label.staticCheckControl === 'known-outcome-type-error';
        const original = projectTemplateFiles(value.template)[value.template.slice(0, -5) + '.aql'];
        const variable = value.template === 'churn-risk-mock' ? 'risk' : 'review';
        assert.equal(readFileSync(join(project, args[1]), 'utf8'), invalid
          ? original.replace(variable + ".outcome = 'ok'", variable + '.outcome = 1')
          : 'SELECT 1 AS id |> RESULT out |> EFFECT UPDATE private.unknown FROM RESULT out ID id SET (Name = 1)');
        reply = {version: 'actql-check-outcome/0.1', outcome: 'completed', report: {scope: {kind: 'bound_input'},
          inputs: [{document_id: 'source', kind: 'text', byte_length: Buffer.byteLength(readFileSync(join(project, args[1]))),
            revision: 'rev:' + '1'.repeat(64)}],
          verdict: invalid ? 'invalid' : 'undetermined', requirements: [],
          reasons: invalid ? [{code: 'expression_domain_mismatch', facts: {domain: 'key_comparable_operands'}}] : [],
          coverage: {limits: invalid ? [] : [{code: 'unresolved_protected'}]}}};
        return {code: invalid ? 1 : 0, signal: null, pid: ++pid, stdout: JSON.stringify(reply),
          acceptance: {modelAttempts: [], writes: []}};
      } else if (args[0] === 'check') reply = check;
      else if (args[0] === 'explain' && args[1] !== '--run') reply = plan;
      else if (args[0] === 'explain') {
        const run = value.runs.find(run => run.original.runId === args[2]); assert(run);
        reply = {version: 'actql-run-plan-view/0.1', run_ref: run.original.ref};
      } else if (args[0] === 'run') {
        const run = replaceRun && value.runs.length ? value.runs[0] : start(project); reply = current(run);
      } else if (args[0] === 'approve' || args[0] === 'reject') {
        const run = value.runs.find(run => run.original.checkpointId === args[1]); assert(run);
        resolve(value, run, args[0] === 'approve' ? 'approved' : 'rejected', label); reply = {};
      } else {
        const run = value.runs.find(run => run.original.runId === args[1]); assert(run);
        if (args[0] === 'result') return {code: 0, signal: null, pid: ++pid,
          stdout: rows(value, run).map(row => JSON.stringify(row)).join('\n') + '\n'};
        assert.equal(args[0], 'status'); reply = current(run);
      }
      return {code: 0, signal: null, pid: ++pid, stdout: JSON.stringify(reply)};
    },
    async node(request, project, label) {
      assert.equal(label.family, 'node-sequential', 'Node never opens a Native family Store');
      calls.push({surface: 'node', kind: request.kind, project, ...(label as Omit<Label, 'surface'>)});
      const counts = {sourceAcquisitionStarts: request.kind === 'start' ? 2 : 0,
        modelCallStarts: request.kind === 'start' ? 2 : 0, effectReplacementReturns: request.decision === 'approved' ? 2 : 0};
      const value = projects.get(project)!, base = {pid: ++pid, firstClose: {attempted: true, returned: true},
        workObservation: {...counts, totals: {...counts}, complete: true}};
      if (request.kind === 'static') {
        assert.equal(value.runs.length, 0, 'Node check/plan precedes its first Run');
        const staticChecks = [
          {name: 'known-outcome-type-error', check: {outcome: 'completed', report: {
            scope: {kind: 'bound_input'}, verdict: 'invalid', requirements: [],
            reasons: [{code: 'expression_domain_mismatch', facts: {domain: 'key_comparable_operands'}}]}}},
          {name: 'unknown-update-target', check: {outcome: 'completed', report: {
            scope: {kind: 'bound_input'}, verdict: 'undetermined',
            coverage: {limits: [{code: 'unresolved_protected'}]}}}},
        ];
        return {...base, check, plan, ...(missingStaticControls ? {} : {staticChecks})};
      }
      let run;
      if (request.kind === 'start') {
        run = start(project);
        if (request.decision) resolve(value, run, request.decision, label);
      } else {run = value.runs.find(run => run.original.runId === request.original!.runId); assert(run);}
      if (request.kind === 'resolve') resolve(value, run, request.decision!, label);
      const result: FixtureReply = {...base, original: run.original, state: current(run)};
      if (request.kind === 'result') {
        result.rows = rows(value, run);
        result.description = {ref: run.original.ref, resultName: 'updates',
          columns: describedColumns(value.template), programDefinitionCid: 'sha256:' + '1'.repeat(64),
          resultDefinitionCid: 'sha256:' + '2'.repeat(64), resultSchemaCid: 'sha256:' + '3'.repeat(64),
          resultArtifactCid: run.original.ref.runDefinitionCid};
        if (mutateInitialContract) result.description.columns[0].contract = {type: 'string', nullable: true};
      }
      return result;
    },
  } satisfies FixturePorts};
}

test('RC CLI static controls use the original template once before Run1 without changing the selection', async () => {
  const f = fixture(), cases = await runWithFixture(f.options);
  assert.equal(cases.length, 8);
  assert.equal(cases.reduce((sum, entry) => sum + entry.runs.length, 0), 24);
  const controls = f.calls.filter(value => value.staticCheckControl);
  assert.equal(controls.length, 4);
  for (const template of ['churn-risk-mock', 'deal-review-mock']) {
    const selected = controls.filter(value => value.template === template);
    assert.deepEqual(selected.map(value => value.staticCheckControl), ['known-outcome-type-error', 'unknown-update-target']);
    for (const call of selected) {
      assert.equal(call.family, 'native-while-waiting'); assert.equal(call.ordinal, 0);
      assert.equal(call.args![0], 'check'); assert.equal(call.args![2], '--json');
      assert(f.calls.indexOf(call) < f.calls.findIndex(value => value.project === call.project && value.args?.[0] === 'run'));
    }
    const program = template.slice(0, -5) + '.aql';
    assert.equal(readFileSync(join(selected[0].project, program), 'utf8'), projectTemplateFiles(template)[program]);
  }
  assert.equal(f.calls.filter(value => value.surface === 'node' && value.kind === 'static').length, 2);
});

test('RC CLI expected invalid exit cannot bypass another command or control label', () => {
  const args = ['check', 'stage2-known-outcome-type-error.aql', '--json'];
  const label: Label = {template: 'churn-risk-mock', family: 'native-while-waiting', ordinal: 0,
    phase: 'check', surface: 'cli', staticCheckControl: 'known-outcome-type-error'};
  assert.equal(projectCliExpectedExit(args, label), 1);
  assert.equal(projectCliExpectedExit(['check', 'stage2-unknown-update-target.aql', '--json'],
    {...label, staticCheckControl: 'unknown-update-target'}), 0);
  assert.equal(projectCliExpectedExit(args, {...label, staticCheckControl: undefined}), 0);
  for (const wrong of [{template: 'foreign'}, {family: 'node-sequential'}, {ordinal: 1},
    {phase: 'run'}, {surface: 'node'}, {staticCheckControl: 'foreign'}, {staticCheckControl: 'toString'}])
    assert.throws(() => projectCliExpectedExit(args, {...label, ...wrong} as Label));
  for (const wrong of [['run', ...args.slice(1)], ['check', 'original.aql', '--json'],
    ['check', '../stage2-known-outcome-type-error.aql', '--json'], [...args, '--other']])
    assert.throws(() => projectCliExpectedExit(wrong, label));
});

test('RC CLI static controls refuse foreign generic unclassified exit and work substitutions', async () => {
  type CheckReply = {version: string; outcome: string; report:
    {reasons: {code: string; facts: {domain: string}}[]; requirements: {code: string}[]; inputs: {byte_length: number}[]}};
  const changes: ((value: FixtureExit, reply: CheckReply) => void)[] = [
    value => {value.code = 0;},
    value => {value.code = 2;},
    value => {value.signal = 'SIGTERM';},
    (_, reply) => {reply.version = 'actql-run-state/0.1';},
    (_, reply) => {reply.outcome = 'failed';},
    (_, reply) => {reply.report.reasons[0].code = 'generic_error';},
    (_, reply) => {reply.report.reasons[0].facts.domain = 'foreign';},
    (_, reply) => {reply.report.reasons[0].code = 'check_unclassified';},
    (_, reply) => {reply.report.requirements = [{code: 'fabricated'}];},
    (_, reply) => {reply.report.inputs[0].byte_length++;},
    value => {delete value.acceptance;},
    value => {value.acceptance!.modelAttempts.push('unexpected');},
    value => {value.acceptance!.writes.push('unexpected');},
  ];
  for (const change of changes) {
    const f = fixture(), cli = f.options.cli;
    f.options.cli = async (args, project, label) => {
      const value = await cli(args, project, label);
      if (label.staticCheckControl === 'known-outcome-type-error') {
        const reply = JSON.parse(value.stdout); change(value, reply); value.stdout = JSON.stringify(reply);
      }
      return value;
    };
    await assert.rejects(runWithFixture(f.options), AggregateError);
    for (const entry of f.records.filter(value => value.family === 'native-while-waiting')) {
      assert.equal(entry.complete, false); assert.equal(entry.failedPhase, 'check'); assert.equal(entry.runs.length, 0);
    }
  }
  const f = fixture(), cli = f.options.cli;
  f.options.cli = async (args, project, label) => {
    const value = await cli(args, project, label);
    if (label.staticCheckControl === 'unknown-update-target') value.code = 1;
    return value;
  };
  await assert.rejects(runWithFixture(f.options), AggregateError);
});

test('RC CLI controls preserve original files and targets and refuse occupied sidecars', async () => {
  for (const mutation of ['occupied', 'program', 'control', 'target', 'root']) {
    const f = fixture(), cli = f.options.cli;
    f.options.cli = async (args, project, label) => {
      const value = await cli(args, project, label);
      if (mutation === 'occupied' && args[0] === 'init' && label.family === 'native-while-waiting')
        writeFileSync(join(project, 'stage2-known-outcome-type-error.aql'), 'original occupant', {flag: 'wx'});
      if (label.staticCheckControl === 'known-outcome-type-error') {
        if (mutation === 'program') writeFileSync(join(project, label.template.slice(0, -5) + '.aql'), 'changed');
        if (mutation === 'control') writeFileSync(join(project, args[1]), 'changed');
        if (mutation === 'target') f.projects.get(project)!.generation++;
        if (mutation === 'root') {
          const program = label.template.slice(0, -5) + '.aql';
          const original = readFileSync(join(project, program)), control = readFileSync(join(project, args[1]));
          renameSync(project, project + '.original'); mkdirSync(project);
          writeFileSync(join(project, program), original); writeFileSync(join(project, args[1]), control);
        }
      }
      return value;
    };
    await assert.rejects(runWithFixture(f.options), AggregateError);
    for (const entry of f.records.filter(value => value.family === 'native-while-waiting')) {
      assert.equal(entry.runs.length, 0);
      if (mutation === 'occupied') assert.equal(readFileSync(join(entry.project,
        'stage2-known-outcome-type-error.aql'), 'utf8'), 'original occupant');
    }
  }
});

test('RC sequences retain independent owner-local projects for check/plan and new Run2/3', async () => {
  const f = fixture(), cases = await runWithFixture(f.options);
  for (const template of ['churn-risk-mock', 'deal-review-mock']) for (const family of [
    'native-while-waiting', 'native-after-approve', 'native-after-reject', 'node-sequential']) {
    const entry = cases.find(row => row.template === template && row.family === family); assert(entry?.complete);
    const calls = f.calls.filter(row => row.project === entry.project);
    assert.equal(calls.filter(row => row.args?.[0] === 'init').length, 1);
    assert.equal(new Set(entry.runs.map(run => run.original.runId)).size, entry.runs.length);
    if (family.startsWith('native-')) assert.equal(entry.runs.length, 3);
    if (family === 'node-sequential') {
      assert.equal(entry.runs.length, 3);
      assert(calls.filter(row => row.surface === 'cli').every(row => row.args![0] === 'init'));
      const staticAt = calls.findIndex(row => row.kind === 'static');
      assert(staticAt >= 0 && staticAt < calls.findIndex(row => row.kind === 'start'));
    } else {
      assert(!calls.some(row => row.surface === 'node'));
    }
    assert(entry.phases.some(row => row.phase === 'result') || family.includes('reject') || family.includes('waiting'));
  }
  assert(f.records.every(row => row.complete));
  assert(!cases.some(row => row.family === 'exclusive-cli-node-roundtrip'), 'Deferred interoperability is unselected');
});

test('RC Node static controls must be present before the first original Run', async () => {
  const f = fixture({missingStaticControls: true});
  await assert.rejects(runWithFixture(f.options), AggregateError);
  for (const entry of f.records.filter(row => row.family === 'node-sequential')) {
    assert.equal(entry.complete, false); assert.equal(entry.failedPhase, 'static');
    assert.equal(entry.runs.length, 0);
    assert(!f.calls.some(row => row.project === entry.project && row.kind === 'start'));
  }
});

test('RC first Result description requires independently authored ordered complete contracts', () => {
  const ref = {namespaceId: 'original', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
    runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
  for (const template of ['churn-risk-mock', 'deal-review-mock']) {
    const description = {ref, resultName: 'updates', columns: describedColumns(template),
      programDefinitionCid: 'sha256:' + '1'.repeat(64), resultDefinitionCid: 'sha256:' + '2'.repeat(64),
      resultArtifactCid: 'sha256:' + '3'.repeat(64), resultSchemaCid: 'sha256:' + '4'.repeat(64)};
    assert.doesNotThrow(() => assertProjectResultDescription(template as Label['template'], description as unknown as ProjectDescription, ref));
    for (const change of [
      value => value.columns.reverse(),
      value => {value.columns[0].contract.nullable = true;},
      value => {delete value.columns.at(-1)!.contract.fields!.input_key;},
      value => {value.columns.at(-1)!.contract.fields!.value.nullable = true;},
      value => {value.resultArtifactCid = 'not-an-original-cid';},
    ] as ((value: FixtureDescription) => void)[]) {
      const wrong = structuredClone(description); change(wrong);
      assert.throws(() => assertProjectResultDescription(template as Label['template'], wrong as unknown as ProjectDescription, ref));
    }
  }
});

test('RC initial wrong schema cannot become an oracle merely by repeating on Saved reads', async () => {
  const f = fixture({mutateInitialContract: true});
  await assert.rejects(runWithFixture(f.options), AggregateError);
  for (const entry of f.records.filter(row => row.family === 'node-sequential')) {
    assert.equal(entry.complete, false);
    assert.equal(f.calls.filter(row => row.project === entry.project && row.kind === 'result').length, 1);
  }
});

test('RC uncertain approval stops that project without replay or hiding independent case failures', async () => {
  const f = fixture({failApproval: true});
  await assert.rejects(runWithFixture(f.options), (error: Error) => error.cause === f.failure);
  for (const entry of f.records.filter(row => row.family === 'native-after-approve')) {
    assert.equal(entry.complete, false);
    const calls = f.calls.filter(row => row.project === entry.project);
    assert.equal(calls.filter(row => row.args?.[0] === 'run').length, 2);
    assert.equal(calls.filter(row => row.args?.[0] === 'approve' && row.ordinal === 2).length, 1);
  }
  assert(f.records.some(row => row.complete && row.family === 'native-after-reject'));
});

for (const [name, options] of [['reused Run', {replaceRun: true}], ['latest target as old Result', {mutateSavedRows: true}],
  ['unrelated target change', {mutateUnrelated: true}]] as const) test(`RC independent original/target oracle refuses ${name}`, async () => {
  const f = fixture(options);
  await assert.rejects(runWithFixture(f.options), AggregateError);
  assert(f.records.some(row => !row.complete));
});

test('RC Result oracle rejects missing whole fields and changed Model values', () => {
  const before = {bytes: JSON.stringify(sourceData('churn-risk-mock'))};
  assert.throws(() => assertProjectSequenceRows('churn-risk-mock', [{id: '001Acme'}, {id: '001Globex'}], before as TemplateSnapshot));
  const rows = [
    {id: '001Acme', notes: 'Acme notes', active_users: '4', trend: 'down', risk: {outcome: 'ok', value: {
      level: 'high', reason: 'falling usage and a competitor evaluation'}}},
    {id: '001Globex', notes: 'Globex notes', active_users: '12', trend: 'flat', risk: {outcome: 'ok', value: {
      level: 'high', reason: 'support tickets about pricing'}}},
  ];
  assert.doesNotThrow(() => assertProjectSequenceRows('churn-risk-mock', rows, before as TemplateSnapshot));
  rows[0].risk.value.level = 'low';
  assert.throws(() => assertProjectSequenceRows('churn-risk-mock', rows, before as TemplateSnapshot));
});

test('RC Int64 Result oracle requires exact canonical decimal Strings without numeric coercion', () => {
  const before = {bytes: JSON.stringify(sourceData('churn-risk-mock'))};
  const rows = [
    {id: '001Acme', notes: 'Acme notes', active_users: '4', trend: 'down', risk: {outcome: 'ok', value: {
      level: 'high', reason: 'falling usage and a competitor evaluation'}}},
    {id: '001Globex', notes: 'Globex notes', active_users: '12', trend: 'flat', risk: {outcome: 'ok', value: {
      level: 'high', reason: 'support tickets about pricing'}}},
  ];
  assert.doesNotThrow(() => assertProjectSequenceRows('churn-risk-mock', rows, before as TemplateSnapshot));
  for (const value of [4, '04', '+4', '-0', '4.0', '4e0', ' 4', '5', null]) {
    const changed = structuredClone(rows); (changed[0] as {active_users: unknown}).active_users = value;
    assert.throws(() => assertProjectSequenceRows('churn-risk-mock', changed, before as TemplateSnapshot));
  }
  const unsafe = sourceData('churn-risk-mock'); unsafe.snowflake!.usage_30d.rows[0].active_users = 9007199254740992;
  const rounded = structuredClone(rows); rounded[0].active_users = '9007199254740992';
  assert.throws(() => assertProjectSequenceRows('churn-risk-mock', rounded, {bytes: JSON.stringify(unsafe)} as TemplateSnapshot));
});

test('RC template check uses the actual typed runnable verdict and refuses a boolean substitute', () => {
  const check = JSON.parse(readFileSync(new URL('../packages/client-wire/fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
  const plan = {version: 'actql-effectful-static-plan-view/0.1', observation: 'static', provider_io: 0,
    computation: {plan_view: {logical_map: {steps: [{operator: 'infer'}, {operator: 'join'}]}}},
    effect_set: {members: [{effect_kind: 'update', input: {kind: 'result', result_name: 'aql_private_update'}}]}};
  assert.doesNotThrow(() => assertTemplateStatic(check, plan as unknown as ProjectPlan));
  // Both templates lower SET fields into this checked private carrier. The
  // separately exported updates Result is still checked by full row/schema
  // and same-original Saved assertions; it cannot replace the Effect input.
  for (const input of [undefined, {kind: 'result', result_name: 'updates'},
    {kind: 'result', result_name: ''}, {kind: 'result', result_name: 'foreign'},
    {kind: 'table', table_name: 'aql_private_update'}, {kind: 'none'}]) {
    const changed = structuredClone(plan); (changed.effect_set.members[0] as {input: unknown}).input = input;
    assert.throws(() => assertTemplateStatic(check, changed as unknown as ProjectPlan));
  }
  for (const runnable of [true, {verdict: 'no', reasons: []}, {verdict: 'unknown', reasons: []}])
    assert.throws(() => assertTemplateStatic({...check, report: {...check.report, runnable}}, plan as unknown as ProjectPlan));
  assert.throws(() => assertTemplateStatic(check, {...plan, provider_io: 1} as unknown as ProjectPlan));
  assert.throws(() => assertTemplateStatic({...check, report: {...check.report, verdict: 'undetermined'}}, plan as unknown as ProjectPlan));
});

test('RC zero-work and reuse claims require complete same-Run observations', () => {
  const empty = {sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0};
  const work = {...empty, totals: {...empty}, complete: true};
  assert.doesNotThrow(() => (assertProjectNodeWork as unknown as ResultReadObservation)(work, {kind: 'result'}, 2));
  for (const changed of [undefined, {...work, complete: false}, {...work, modelCallStarts: 1},
    {...work, totals: {...empty, modelCallStarts: 1}}])
    assert.throws(() => (assertProjectNodeWork as unknown as ResultReadObservation)(changed, {kind: 'result'}, 2));
  const template = 'churn-risk-mock', changed = sourceData(template), same = sourceData(template);
  Object.assign(same.salesforce.Account!.rows[0], {Churn_Risk__c: 'high',
    Risk_Reason__c: 'falling usage and a competitor evaluation'});
  Object.assign(same.salesforce.Account!.rows[1], {Churn_Risk__c: 'high',
    Risk_Reason__c: 'support tickets about pricing'});
  const request = (before: FixtureData): ActionRequest & {beforeBytes: string} =>
    ({kind: 'resolve', decision: 'approved', beforeBytes: JSON.stringify(before)});
  assert.doesNotThrow(() => assertProjectNodeWork(work, request(same), 2, template),
    'An approved same-value no-op is not required to perform another replacement');
  assert.throws(() => assertProjectNodeWork(work, request(changed), 2, template),
    'An initial changed target requires actual replacements');
  const observed = (count: number) => ({...work, effectReplacementReturns: count,
    totals: {...empty, effectReplacementReturns: count}});
  assert.throws(() => assertProjectNodeWork(observed(1), request(changed), 2, template));
  assert.doesNotThrow(() => assertProjectNodeWork(observed(2), request(changed), 2, template));
  same.salesforce.Account!.rows[1].Churn_Risk__c = 'medium';
  assert.throws(() => assertProjectNodeWork(work, request(same), 2, template));
  assert.doesNotThrow(() => assertProjectNodeWork(observed(1), request(same), 2, template));
  assert.throws(() => assertProjectNodeWork(work, {kind: 'resolve', decision: 'approved'}, 2, template),
    'Missing original before DATA cannot prove a no-op');
});

test('RC sequence phase uses the existing observer and preserves an original failed action', async () => {
  for (const phase of ['release-project-sequences', 'original-mock-regressions'] as const) {
    const records: PhaseRecord[] = [], primary = new Error('original RC failure'), result = {};
    assert.equal(await observeNativeMockHarnessPhase(records, phase, async () => result), result);
    await assert.rejects(observeNativeMockHarnessPhase(records, phase, async () => {throw primary;}),
      value => value === primary);
    assert.deepEqual(records.map(({phase, state}) => [phase, state]), [[phase, 'completed'], [phase, 'failed']]);
    assert(records.every(({wallNs}) => Number.isSafeInteger(wallNs) && wallNs! >= 0));
  }
});

test('RC same-value Native approval keeps original trace validation without requiring a redundant replacement', () => {
  assert.throws(() => requireNativeMockWork(['approve'], [{events: []}], 2));
  assert.deepEqual(requireNativeMockWork(['approve'], [{events: []}], 2, {minimumWrites: 0}).writes, []);
  assert.throws(() => requireNativeMockWork(['run'], [{events: []}], 2, {minimumWrites: 0}));
  assert.throws(() => requireNativeMockWork(['status'], [{events: [{tag: 0, ordinal: 0, identity: 'unexpected'}]}] as unknown as BindingEvent, 2));
});
