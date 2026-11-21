import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {createHostObservationConnection, installHostObservation, projectEffectPreflightFailure} from '../host-common/observation.mjs';
import {DatabaseSync} from 'node:sqlite';
import {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
import {openClientObservationStorage} from './client-observation-journal.mjs';
import {workflowWorkObservation, workflowObservationComplete} from './fixtures/work-observation.fixture.mjs';
import {mockProjectWorkflowChecks, startMockProjectSource} from './fixtures/mock-project-effect-protocol.fixture.mjs';
import {multipleTargetMockProjectFiles, multipleTargetMockExpectedBytes, multipleTargetMockWriteCount} from './fixtures/mock-multiple-targets.fixture.mjs';
import {terminalMockScenario, checkTerminalMockRows, checkTerminalMockSavedRows, assertTerminalMockObservation,
  runTerminalMockWorkflow, terminalMockFailureDiagnostic} from './fixtures/mock-project-terminal-public.mjs';
import {createDiagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import * as terminalFs from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';

const terminalRiskRows = [
  {id: '001Acme', risk: {input_key: {id: '001Acme'}, outcome: 'ok', value: {level: 'high', reason: 'falling usage and a competitor evaluation'}}},
  {id: '001Globex', risk: {input_key: {id: '001Globex'}, outcome: 'ok', value: {level: 'high', reason: 'support tickets about pricing'}}},
];

test('terminal Mock declarations and independent rows cannot substitute an Effect or another output', () => {
  const infer = terminalMockScenario('terminal-infer');
  assert.equal(infer.format, 'aql');assert.match(infer.source, /RESULT updates;/u);
  assert(!infer.source.includes('EFFECT'));assert.deepEqual([infer.sourceStarts, infer.modelStarts], [2, 2]);
  const program = JSON.parse(terminalMockScenario('terminal-content').source), stage = program.stages[0];
  assert.deepEqual(stage.inputs, {});assert.equal(stage.effects, undefined);
  assert.deepEqual(stage.steps[0].values.rows, [{id: 1}, {id: 2}]);
  assert.deepEqual(stage.steps[1].serialize, {format: 'jsonl', fields: ['id'], name: 'two.jsonl',
    preserve_order: true, bounds: {max_rows: 2, max_bytes: 64}});
  checkTerminalMockRows('terminal-infer', terminalRiskRows);
  assert.throws(() => checkTerminalMockRows('terminal-infer', terminalRiskRows.slice(1)));
  const foreign = structuredClone(terminalRiskRows);foreign[1].risk.value.reason = 'other original';
  assert.throws(() => checkTerminalMockRows('terminal-infer', foreign));
  const wrongKey = structuredClone(terminalRiskRows);wrongKey[0].risk.input_key.id = '001Globex';
  assert.throws(() => checkTerminalMockRows('terminal-infer', wrongKey));
  const missingKey = structuredClone(terminalRiskRows);delete missingKey[0].risk.input_key;
  assert.throws(() => checkTerminalMockRows('terminal-infer', missingKey));
  assert.throws(() => terminalMockScenario('unknown'));
});

test('terminal Content oracle checks byte-derived metadata and full original Saved equality separately', () => {
  // A synthetic response DTO for checking the oracle, NOT an issued reference,
  // permission, Store fixture or real product completion.
  const contentCid = 'sha256:' + createHash('sha256').update('{"id":1}\n{"id":2}\n').digest('hex');
  const row = {name: 'two.jsonl', media_type: 'application/x-ndjson', size_bytes: 18, row_count: 2,
    content: {$actql_ref: 'content', version: 'actql-content-ref/0.1', content_ref_cid: 'sha256:' + 'a'.repeat(64),
      media_type: 'application/x-ndjson', metadata: {content_cid: contentCid, size_bytes: 18,
        media_type: 'application/x-ndjson', truncated: false,
        issuer_evidence: {version: 'actql-content-issuer-evidence/0.1', issuer_kind: 'content_derivation', content_cid: contentCid}}}};
  checkTerminalMockRows('terminal-content', [row]);
  checkTerminalMockSavedRows('terminal-content', [structuredClone(row)], [row]);
  const otherEnvelope = structuredClone(row);otherEnvelope.content.content_ref_cid = 'sha256:' + 'b'.repeat(64);
  checkTerminalMockRows('terminal-content', [otherEnvelope]);
  assert.throws(() => checkTerminalMockSavedRows('terminal-content', [otherEnvelope], [row]));
  for (const mutate of [r => {r.size_bytes++;}, r => {r.row_count++;},
    r => {r.content.metadata.content_cid = 'sha256:' + 'b'.repeat(64);},
    r => {r.content.metadata.truncated = true;}, r => {delete r.content.content_ref_cid;}]) {
    const changed = structuredClone(row);mutate(changed);
    assert.throws(() => checkTerminalMockRows('terminal-content', [changed]));
  }
});

test('terminal original observation refuses repeats, unknown, same process and incomplete close', () => {
  const actual = {phase: 'recover', variant: 'terminal-infer', pid: 202,
    status: 'passed', complete: true, submits: 0, resultReads: 1, lookupOriginal: true,
    savedFirst: true, originalRefBeforeWait: false, originalInputsAbsent: true,
    firstClose: {attempted: true, returned: true, calls: 1}, aliveScopedFD: {before: 0, after: 0, pid: 202},
    workObservation: {complete: true, sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0}};
  const expected = {phase: 'recover', variant: 'terminal-infer', pid: 202, capturedPid: 101};
  assertTerminalMockObservation(actual, expected);
  const started = {...actual, recoveryOrigin: 'started', originalRowsCompared: false, normalCaptureComplete: false};
  assertTerminalMockObservation(started, {...expected, fromStarted: true});
  assert.throws(() => assertTerminalMockObservation(started, expected));
  assert.throws(() => assertTerminalMockObservation(actual, {...expected, capturedPid: 202}));
  for (const mutate of [v => {v.savedFirst = false;}, v => {v.submits++;}, v => {v.status = 'needs_reconciliation';},
    v => {v.workObservation.sourceAcquisitionStarts++;}, v => {v.workObservation.modelCallStarts++;},
    v => {v.workObservation.complete = false;}, v => {v.firstClose.returned = false;},
    v => {v.firstClose.calls++;}, v => {v.aliveScopedFD.after++;}]) {
    const changed = structuredClone(actual);mutate(changed);
    assert.throws(() => assertTerminalMockObservation(changed, expected));
  }
});

async function terminalScratch(t) {
  const root = await terminalFs.mkdtemp(join(tmpdir(), 'actql-terminal-consumer-component-'));
  // Only authored files and explicit public-port observations, no product DB,
  // key, runtime, pending business state or installed normal software is made.
  t.after(() => terminalFs.rm(root, {recursive: true, force: true}));
  await terminalFs.mkdir(join(root, 'mock'));
  return root;
}

test('terminal explicit operator Content selects only its authored finite Account and unchanged Program', async t => {
  const root = await terminalScratch(t), primary = new Error('Stop before product initialization');
  const program = terminalMockScenario('terminal-content');
  await terminalFs.writeFile(join(root,program.path),program.source);
  let connections = 0;
  const connect = async ({mode,profile,installation}) => {
    connections++;assert.equal(mode,'local');assert.equal(profile,'mock');
    assert.equal(installation.authorization.siteKey,'local-mock');
    assert.deepEqual(Object.keys(installation.authorization).sort(),['accountConfiguration','observe','siteKey']);
    assert.equal(typeof installation.authorization.observe,'function');
    const configuration = JSON.parse(installation.authorization.accountConfiguration);
    assert.deepEqual(Object.keys(configuration).sort(),['account_id','entries','version']);
    assert.equal(configuration.version,'actql-execution-account-config/0.1');
    assert.equal(configuration.account_id,'terminal-content-explicit-operator');
    assert.deepEqual(configuration.entries.map(entry => entry.entry_id),
      ['operator-request','operator-result-file','operator-run']);
    assert.deepEqual(configuration.entries.map(entry => [entry.resource.any_of,entry.operation.any_of]),[
      [['installed-multi-acquired'],['write']],[['result/file'],['read']],
      [['run'],['cancel','publish','read','resolve','submit']],
    ]);
    for (const entry of configuration.entries) {
      assert.deepEqual(Object.keys(entry).sort(),
        ['connection','entry_id','exclusions','operation','outcome','principal','resource']);
      assert.equal(entry.outcome,'allow');assert.deepEqual(entry.principal,{any_of:[userInfo().username]});
      assert.deepEqual(entry.connection,{any_of:['local-mock']});assert.deepEqual(entry.exclusions,[]);
      assert.equal(JSON.stringify(entry).includes('"all"'),false);
    }
    assert.equal(await terminalFs.readFile(join(root,program.path),'utf8'),program.source);
    throw primary;
  };
  const options = {phase:'capture',variant:'terminal-content',accountScenario:'explicit-operator-content',
    handoffPath:join(root,'handoff.json'),directory:root,connect,
    observeDescriptors:async () => ({pid:process.pid,openPaths:[]}),
    createWorkObservation:() => ({connection:{},snapshot:() => ({complete:true,
      sourceAcquisitionStarts:0,modelCallStarts:0,effectReplacementReturns:0})})};
  await assert.rejects(runTerminalMockWorkflow(options),error => error.cause === primary &&
    error.observation.accountScenario === 'explicit-operator-content');
  await assert.rejects(runTerminalMockWorkflow({...options,variant:'terminal-infer'}),{code:'ERR_ASSERTION'});
  await assert.rejects(runTerminalMockWorkflow({...options,accountScenario:'unsupported'}),{code:'ERR_ASSERTION'});
  assert.equal(connections,1);
  const {accountScenario, ...omitted} = options;
  assert.equal(accountScenario,'explicit-operator-content');
  await assert.rejects(runTerminalMockWorkflow({...omitted,directory:await terminalScratch(t),
    async connect({mode,profile,installation}) {
      connections++;assert.equal(mode,'local');assert.equal(profile,'mock');
      assert.deepEqual(Object.keys(installation.authorization),['observe']);
      assert.equal(typeof installation.authorization.observe,'function');throw primary;
    }}),error => error.cause === primary && !Object.hasOwn(error.observation,'accountScenario'));
  assert.equal(connections,2);
});

test('terminal preparation failure projection accepts only closed source locations and original capacity scalars', () => {
  const sites = 'adapters/host-common/runtime-result.mjs:8:25\nadapters/host-node/embedded-local.mjs:5500:9';
  const capacity = {phase: 'request_snapshot', dimension: 'execution', requiredRetentionBytes: '7',
    requiredExecutionBytes: '19', availableRetentionBytes: '8', availableExecutionBytes: '18'};
  let touched = 0;
  const detail = {boundary: 'request_admission', available: true,
    primaryDiagnostic: {phase: 'dispatch', kind: 'code_site', message: sites}, capacity};
  Object.defineProperty(detail, 'cause', {get() {touched++;throw Error('Do not inspect causes');}});
  assert.deepEqual(terminalMockFailureDiagnostic('preparation_failed', detail), {
    event: 'preparation_failed', available: true, boundary: 'request_admission',
    primary: {phase: 'dispatch', kind: 'code_site'}, sites, capacity});
  for (const message of ['private prompt/key', '/private/state/request:1:2', 'adapters/../private.mjs:1:2', sites.repeat(200)]) {
    const result = terminalMockFailureDiagnostic('preparation_failed', {
      ...detail, primaryDiagnostic: {kind: 'code_site', message}});
    assert.equal(Object.hasOwn(result, 'sites'), false);
  }
  assert.equal(touched, 0);
  assert.deepEqual(terminalMockFailureDiagnostic('preparation_failed', {boundary: 'request_admission', available: false}),
    {event: 'preparation_failed', available: false, boundary: 'request_admission'});
});

test('terminal Content existing authorization callback retains only bounded original failure scalars before first close', async t => {
  const root = await terminalScratch(t), path = join(root, 'handoff.json');
  await terminalFs.writeFile(join(root, 'terminal.program.json'), terminalMockScenario('terminal-content').source);
  const primary = Object.assign(Error('private public error text'), {code: 'SubmissionUnknown'});
  let getterCalls = 0, delivery, starts = 0, closes = 0;
  const cause = {$tag: 7, _0: {$tag: 3}};
  Object.defineProperty(cause, 'message', {get() {getterCalls++;throw Error('Private getter');}});
  const detail = {code: 'MoonBitHostFailure', boundary: 'task_compilation', cause,
    primaryDiagnostic: {phase: 'dispatch', kind: 'code_site', message: 'private prompt and key'},
    reference: 'private-original', body: 'private-input'};
  const expected = {event: 'content_preparation_rejected', code: 'MoonBitHostFailure', boundary: 'task_compilation',
    primary: {phase: 'dispatch', kind: 'code_site'}, issueTag: 7, nestedIssueTag: 3};
  assert.deepEqual(terminalMockFailureDiagnostic('content_preparation_rejected', detail), expected);
  assert.equal(terminalMockFailureDiagnostic('authorization_allowed', detail), undefined);
  const ports = {phase: 'capture', variant: 'terminal-content', directory: root, handoffPath: path,
    observeDescriptors: async () => ({pid: process.pid, openPaths: []}),
    createWorkObservation: () => ({connection: {}, snapshot: () => ({complete: true,
      sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0})}),
    async connect({installation}) {
      delivery = createDiagnosticObserver(installation.authorization.observe);
      return {newSubmission: () => ({request: 'original-before-start'}),
        async startSource() {starts++;delivery('content_preparation_rejected', detail);throw primary;},
        async close() {
          closes++;
          const original = JSON.parse(await terminalFs.readFile(join(root, 'capture.primary.json'), 'utf8'));
          assert.deepEqual(original, {publicCode: 'SubmissionUnknown', thrownUndefined: false, originalDiagnostics: [expected]});
          delivery.close();
        }};
    }};
  await assert.rejects(runTerminalMockWorkflow(ports), error => error.cause === primary);
  assert.equal(starts, 1); assert.equal(closes, 1); assert.equal(getterCalls, 0);
  const original = JSON.parse(await terminalFs.readFile(join(root, 'capture.pending.json'), 'utf8'));
  assert.deepEqual(original.originalDiagnostics, [expected]);
  assert.deepEqual(original.firstClose, {attempted: true, returned: true, calls: 1});
  await assert.rejects(terminalFs.access(path + '.started'), {code: 'ENOENT'});
});

test('terminal imported consumer preserves ref before wait, Saved first and thrown undefined at first close', async t => {
  for (const phase of ['capture', 'recover', 'from-started', 'unknown-start', 'failure']) {
    const root = await terminalScratch(t), path = join(root, 'handoff.json'), events = [];
    const ref = {runDefinitionCid: 'sha256:' + 'a'.repeat(64)}, submissionRef = {request: 'authored-port'};
    const recovering = phase === 'recover' || phase === 'from-started';
    if (!recovering) await terminalFs.writeFile(join(root, 'terminal.aql'), terminalMockScenario('terminal-infer').source);
    else await terminalFs.writeFile(path + (phase === 'from-started' ? '.started' : ''), JSON.stringify({variant: 'terminal-infer', ref, submissionRef,
      ...(phase === 'recover' ? {rows: terminalRiskRows} : {}), pid: process.pid + 1}));
    const run = {ref, async wait() {
      events.push('wait');const saved = JSON.parse(await terminalFs.readFile(path + '.started', 'utf8'));
      assert.deepEqual(saved.ref, ref);
      if (phase === 'failure') throw undefined;
      return {status: 'succeeded'};
    }, result() {events.push('result');return {all: async () => terminalRiskRows};},
    async status() {events.push('status');return {status: 'succeeded'};}};
    let closes = 0;
    const ports = {phase: recovering ? 'recover' : 'capture', fromStarted: phase === 'from-started',
      variant: 'terminal-infer', directory: root, handoffPath: path,
      observeDescriptors: async () => ({pid: process.pid, openPaths: []}),
      createWorkObservation: () => ({connection: {}, snapshot: () => ({complete: true,
        sourceAcquisitionStarts: recovering ? 0 : 2, modelCallStarts: recovering ? 0 : 2, effectReplacementReturns: 0})}),
      connect: async () => ({newSubmission() {events.push('new');return submissionRef;},
        async startSource() {
          events.push('start');assert.equal(recovering, false);
          const submitted = JSON.parse(await terminalFs.readFile(path + '.submission', 'utf8'));
          assert.deepEqual(submitted.submissionRef, submissionRef);
          if (phase === 'unknown-start') throw Object.assign(Error('OriginalUnknown'), {code: 'SubmissionUnknown'});
          return run;
        },
        async attach(actual) {events.push('attach');assert.deepEqual(actual, ref);return run;},
        async lookupSubmission(actual) {events.push('lookup');assert.deepEqual(actual, submissionRef);return {kind: 'ready', admission: {ref}};},
        async close() {closes++;events.push('close');if (phase === 'failure') throw Error('LaterCloseFailure');}})};
    if (phase === 'unknown-start') {
      await assert.rejects(runTerminalMockWorkflow(ports), error => error.cause.code === 'SubmissionUnknown');
      assert.deepEqual(events, ['new', 'start', 'close']);
      await assert.rejects(terminalFs.access(path + '.started'), {code: 'ENOENT'});
      assert.deepEqual(JSON.parse(await terminalFs.readFile(path + '.submission', 'utf8')).submissionRef, submissionRef);
    } else if (phase === 'failure') {
      await assert.rejects(runTerminalMockWorkflow(ports), error => error.cause === undefined &&
        error.observation.status === 'failed' && error.observation.firstClose.returned === false);
      assert.deepEqual(events, ['new', 'start', 'wait', 'close']);
    } else {
      const observation = await runTerminalMockWorkflow(ports);assert.equal(observation.complete, true);
      assert.deepEqual(events, phase === 'capture' ? ['new', 'start', 'wait', 'result', 'lookup', 'close']
        : ['attach', 'result', 'status', 'lookup', 'close']);
      if (phase === 'from-started') {
        assert.equal(observation.recoveryOrigin, 'started');assert.equal(observation.originalRowsCompared, false);
        assert.equal(observation.normalCaptureComplete, false);
        await assert.rejects(terminalFs.access(path), {code: 'ENOENT'});
      }
    }
    assert.equal(closes, 1);
  }
});

test('plural Mock fixture authors one document and two exact same-Run UPDATE members without a Model',()=>{
  const files=multipleTargetMockProjectFiles(),config=JSON.parse(files['actql.config.json']);
  assert.equal(config.mock.data,'./mock/data.json');
  assert.deepEqual(JSON.parse(files['model-tasks.json']).tasks,{});
  const source=JSON.parse(files['mock/catalog.json']).connections.salesforce;
  assert.deepEqual(source.data.map(value=>value.items_path),[
    ['salesforce','Account','rows'],['salesforce','Contact','rows']]);
  assert.deepEqual(source.writes.map(value=>value.resource),['Account','Contact']);
  assert.deepEqual(source.writes.map(value=>[value.permission,value.observe_permission]),[
    ['salesforce:record:update','salesforce:record:observe'],
    ['salesforce:contact:update','salesforce:contact:observe']]);
  const program=JSON.parse(files['multiple-targets.program.json']);
  assert.equal(program.stages.length,1);const stage=program.stages[0];
  assert.deepEqual(stage.inputs,{accounts:{connector:'salesforce',resource:'Account'},
    contacts:{connector:'salesforce',resource:'Contact'}});
  assert.deepEqual(stage.effects,{
    account:{update:{target:'connector://salesforce/Account',mapping:'mapping:salesforce/Account/update-cd4d1d065cc201b7.v1',
      from:{result:'rows'},id:'account_id',set:{value:{field:'account_next'}}}},
    contact:{update:{target:'connector://salesforce/Contact',mapping:'mapping:salesforce/Contact/update-bfab525c7c063542.v1',
      from:{result:'rows'},id:'contact_id',set:{value:{field:'contact_next'}}}},
  });
  assert.equal(multipleTargetMockWriteCount,2);
});

test('plural Mock fixture byte oracle preserves both control rows and rejects a changed starting document',()=>{
  const before=multipleTargetMockProjectFiles()['mock/data.json'];
  const expected=multipleTargetMockExpectedBytes(before),parsed=JSON.parse(expected);
  assert.deepEqual(parsed.salesforce.Account.rows,[{id:'a1',group:'selected',value:'A-new'},
    {id:'a-control',group:'account-control',value:'keep-account'}]);
  assert.deepEqual(parsed.salesforce.Contact.rows,[{id:'c1',group:'selected',value:'C-new'},
    {id:'c-control',group:'contact-control',value:'keep-contact'}]);
  assert.deepEqual(parsed.control,{unchanged:'keep-physical-document'});
  assert.equal(expected.replace('A-new','A-old').replace('C-new','C-old'),before);
  assert.throws(()=>multipleTargetMockExpectedBytes(before.replace('keep-contact','foreign-change')));
});

test('plural Mock fixture oracles require both exact logical targets rather than one successful member',async()=>{
  // Public projection DATA only: these oracles issue no actual Review, Run,
  // checkpoint, authorization, claim, version or physical cleanup receipt.
  const checks=await mockProjectWorkflowChecks({template:'churn-risk-mock',variant:'multiple-targets'});
  const rows=[{account_id:'a1',contact_id:'c1',account_before:'A-old',contact_before:'C-old',
    account_next:'A-new',contact_next:'C-new'}];
  checks.checkRows(rows);assert.throws(()=>checks.checkRows([]));
  const cid=letter=>'sha256:'+letter.repeat(64);
  const summary={reviewProjectionCid:cid('a'),requiredArtifact:{cid:cid('b')},requirements:[]};
  const ref={authorityScopeCid:cid('c')};
  const review={version:'actql-review-projection/0.1',review_projection_cid:cid('a'),
    effect_preview_cid:cid('b'),authority_scope_cid:cid('c'),approval_claims:[],
    authoring_context_cid:cid('d'),redaction_policy_cid:cid('e'),sensitivity:'restricted',
    retention_class:'approval-evidence',encryption_required:true,displayed_authoring_context:{},
    displayed_permissions:[],displayed_scope:{effects:[
    {kind:'update',target:'connector://salesforce/Contact',count:1},
    {kind:'update',target:'connector://salesforce/Account',count:1}]},displayed_rows:[
    ['a1','A-old','A-new'],['c1','C-old','C-new']].map(([id,prior,next])=>({target_row_identity:id,
      row_preview_cid:'sha256:'+'a'.repeat(64),preview_strength:'full_diff',
      target_guard:{state:'version',version_cid:'sha256:'+'b'.repeat(64)},
      before:{state:'present',value:{group:'selected',id,value:prior}},
      intended_changes:{state:'present',value:{value:next}},after:{state:'present',value:{value:next}}}))};
  checks.checkReview(review,summary,ref);
  const missing=structuredClone(review);missing.displayed_scope.effects.pop();
  assert.throws(()=>checks.checkReview(missing,summary,ref));
  const foreign=structuredClone(review);foreign.displayed_rows[1].before.value.id='a1';
  assert.throws(()=>checks.checkReview(foreign,summary,ref));
});

// Execute the fixture's actual capture branch with explicit SDK/filesystem
// ports. This is no installed SDK, Model, business Run or close acceptance.
const text = readFileSync(new URL('./fixtures/mock-project-effect-public.mjs', import.meta.url), 'utf8');
const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => {
  const node = ast.body.map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .find(node => node?.type === 'FunctionDeclaration' && node.id.name === name);
  assert.ok(node);
  return text.slice(node.start, node.end);
};
const observe = new Function(`${declaration('publicRunObservation')};return publicRunObservation;`)();
const main = ast.body.find(node => node.type === 'TryStatement');
const branch = main.block.body.find(node => node.type === 'IfStatement');
const captureBody = text.slice(branch.consequent.start, branch.consequent.end);

test('workflow completeness allows suppressed Owner facts but refuses actual loss or unfinished cleanup', () => {
  const complete = workflowObservationComplete;
  const status = () => ({closed: true, cleanupPending: false, repeated: 31, dropped: 0,
    budgetUnavailable: 0, queueOverflow: 0, deliveryFailed: 0, limited: 0,
    queued: 0, active: 0, activeSegments: 0, loss: {}});
  for (const repeated of [0, 1, 31, Number.MAX_SAFE_INTEGER]) assert.equal(complete({...status(), repeated}), true);
  for (const repeated of [undefined, -1, NaN, Infinity, 0.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.equal(complete({...status(), repeated}), false);
  }
  for (const name of ['dropped', 'budgetUnavailable', 'queueOverflow', 'deliveryFailed',
    'limited', 'queued', 'active', 'activeSegments']) {
    assert.equal(complete({...status(), [name]: 1}), false, name);
    const missing = status(); delete missing[name]; assert.equal(complete(missing), false, name);
  }
  for (const changed of [undefined, null, {...status(), closed: false}, {...status(), cleanupPending: true},
    {...status(), loss: {delivery_failed: 1}}, {...status(), loss: undefined}, {...status(), loss: null}]) {
    assert.equal(complete(changed), false);
  }
});

test('authored README Source and Model call bounds reject duplicated and missing starts', () => {
  const check = new Function('assert', `${declaration('checkWorkflowWork')};return checkWorkflowWork;`)(assert);
  for (const models of [1, 2]) {
    const work = {complete: true, sourceAcquisitionStarts: 2, modelCallStarts: 2 * models,
      effectReplacementReturns: 0};
    check(work, 'capture', 2, models);
    for (const sourceAcquisitionStarts of [1, 3]) {
      assert.throws(() => check({...work, sourceAcquisitionStarts}, 'capture', 2, models));
    }
    for (const modelCallStarts of [2 * models - 1, 2 * models + 1]) {
      assert.throws(() => check({...work, modelCallStarts}, 'capture', 2, models));
    }
    assert.throws(() => check({...work, effectReplacementReturns: 1}, 'capture', 2, models));
  }
});

test('work collector selects needed facts without requesting Run rows or repeated Owner facts', async () => {
  const make = options => workflowWorkObservation({...options, createObservation: createHostObservationConnection});
  const work = make(), seen = new Set(), ref = {namespaceId: 'fixture',
    authorityScopeCid: `sha256:${'a'.repeat(64)}`, runDefinitionCid: `sha256:${'b'.repeat(64)}`};
  const observer = installHostObservation(work.connection, {journal: {observationStorage: () => ({consume(value) {
    if (value.ownerFactKey === undefined) return {accepted: true};
    if (seen.has(value.ownerFactKey)) return {accepted: false, repeated: true};
    seen.add(value.ownerFactKey); return {accepted: true};
  }})}});
  observer.diagnostic('selected_rows_observed', Object.defineProperty({}, 'rowOwner', {
    get() {assert.fail('Unselected row DATA must not be read');},
  }));
  for (let i = 0; i < 2; i++) {
    observer.diagnostic('acquisition_started', {}); observer.diagnostic('model_call_entered', {});
    observer.emit('run', 'owner_observed', {ref, outcome: 'succeeded'}, {ownerFactKey: 'same-original'});
  }
  await observer.close();
  const actual = work.snapshot();
  assert.equal(actual.sourceAcquisitionStarts, 2); assert.equal(actual.modelCallStarts, 2);
  assert.equal(actual.status.repeated, 0); assert.equal(actual.status.dropped, 0);
  assert.deepEqual(actual.status.loss, {}); assert.equal(actual.complete, true);
});

test('normal control capture establishes the original observer revision before acceptance without resetting custody', async () => {
  const make = options => workflowWorkObservation({...options, createObservation: createHostObservationConnection});
  const initializer = ast.body.filter(node => node.type === 'VariableDeclaration')
    .flatMap(node => node.declarations).find(node => node.id.name === 'workObservation').init;
  const captureFor = new Function('workflowWorkObservation', 'workPurpose',
    `return (${text.slice(initializer.start, initializer.end)});`);
  const original = {namespaceId: 'fixture', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${'b'.repeat(64)}`};
  for (const purpose of ['original-run-control', 'workflow']) {
    const db = new DatabaseSync(':memory:');
    try {
      db.exec(`CREATE TABLE client_requests (namespace_id TEXT, authority_scope_cid TEXT,
        run_definition_cid TEXT, caller_request_id TEXT) STRICT;`);
      db.prepare('INSERT INTO client_requests VALUES (?, ?, ?, ?)').run(original.namespaceId,
        original.authorityScopeCid, original.runDefinitionCid, 'original');
      const storage = openClientObservationStorage(db, createSqliteTransaction(db, 'Fixture'));
      const install = work => installHostObservation(work.connection,
        {journal: {observationStorage: () => storage}, runId: () => 'unit-original'});
      const capture = captureFor(make, purpose), accepted = install(capture);
      accepted.accepted({ref: original, inserted: true}, 'original');
      await accepted.close();
      const initial = db.prepare('SELECT * FROM client_observation_runs').get();
      const work = make({trackOriginal: true}), observer = install(work);
      for (let n = 0; n < 4; n++) observer.diagnostic('effect_application_observed',
        {ref: original, outcome: 'waiting_checkpoint'});
      await observer.close();
      const actual = work.forOriginal(original), matching = purpose === 'original-run-control';
      assert.equal(actual.complete, matching);
      assert.equal(actual.status.budgetUnavailable, matching ? 0 : 4);
      assert.equal(actual.status.dropped, matching ? 0 : 4);
      assert.equal(capture.connection.configuration().revision === work.connection.configuration().revision, matching);
      const retained = db.prepare('SELECT * FROM client_observation_runs').get();
      assert.equal(retained.configuration_revision, initial.configuration_revision);
      assert.equal(retained.records, matching ? 4 : 0);
      assert.equal(db.prepare('SELECT count(*) AS n FROM client_observation_runs').get().n, 1);
      assert.equal(db.prepare('SELECT count(*) AS n FROM client_requests').get().n, 1);
      assert.throws(() => storage.initialize({ref: original, requestId: 'original', scope: 'local',
        revision: work.connection.configuration().revision}));
      assert.deepEqual(actual.totals, {sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0});
    } finally {db.close();}
  }
});

test('workflow primary failure stays with its actual original Run instead of another verification Run', async () => {
  const make = options => workflowWorkObservation({...options, createObservation: createHostObservationConnection});
  const ref = value => ({namespaceId: 'fixture', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${value.repeat(64)}`});
  const original = ref('1'), verification = ref('2'), work = make({trackOriginal: true});
  const observer = installHostObservation(work.connection, {runId: () => 'same-host-fixture',
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  const failure = {code: 'MoonBitHostFailure', phase: 'original_model_acquired_effect_evidence',
    kind: 'invocation.foreign_captured_input', task: 4, unit: 2, step: 5};
  observer.diagnostic('dispatch_failed', {ref: verification, primaryDiagnostic: {...failure, kind: 'dependency'}});
  observer.diagnostic('dispatch_failed', {ref: original, primaryDiagnostic: failure});
  observer.diagnostic('dispatch_failed', {ref: original, primaryDiagnostic: {...failure, kind: 'relation'}});
  await observer.close();
  assert.deepEqual(work.forOriginal(original).primaryFailure, {available: true,
    code: failure.code, phase: failure.phase, kind: failure.kind, occurrence: {task: 4, unit: 2, step: 5}});
  assert.equal(work.forOriginal(verification).primaryFailure.kind, 'dependency');
  assert.deepEqual(work.forOriginal(ref('3')).primaryFailure, {available: false});
  assert.deepEqual(work.forOriginal(undefined).primaryFailure, {available: false});
  assert.equal(work.forOriginal(original).complete, true);
  assert.equal(JSON.stringify(work.forOriginal(original)).includes('sha256:'), false);
});

test('workflow missing or lost primary delivery remains unavailable instead of becoming a fabricated cause', async () => {
  const make = createObservation => options => workflowWorkObservation({...options, createObservation});
  for (const lose of [false, true]) {
    const work = make(options => createHostObservationConnection({...options,
      ...(lose ? {limits: {queueRecords: 1}} : {})}))();
    const observer = installHostObservation(work.connection);
    if (lose) observer.diagnostic('model_call_entered', {});
    observer.diagnostic('dispatch_failed', lose ? {primaryDiagnostic: {
      code: 'MoonBitHostFailure', phase: 'original_model_acquired_effect_evidence',
      kind: 'relation', task: 4, unit: 2, step: 5}} : {});
    await observer.close();
    assert.deepEqual(work.snapshot().primaryFailure, {available: false});
    if (lose) {assert.equal(work.snapshot().complete, false); assert(work.snapshot().status.dropped > 0);}
  }
});

test('workflow operation timers keep actual intervals and original failures even when logging fails', async () => {
  const make = new Function('ports', `
    const {console,process}=ports,phase='capture',stepDiagnosticFailures=ports.failures;
    let activeStep,firstFailedStep;
    ${declaration('step')}
    return step;
  `);
  for (const fails of [false, true]) for (const logFails of [false, true]) {
    const failures = [], rows = [], primary = new Error('OriginalOperationRefusal');
    const step = make({process, failures, console: {log(line) {
      rows.push(JSON.parse(line)); if (logFails) throw new Error('OriginalDiagnosticFailure');
    }}});
    let release, called = 0;
    const waiting = new Promise(resolve => {release = resolve;});
    const result = step('original public wait', async () => {called++; await waiting;
      if (fails) throw primary;return 'original';});
    const observed = fails ? assert.rejects(result, error => error === primary) : result;
    assert.equal(rows.length, 0, 'A pending operation must not acquire a completed timer');
    release(); await observed;
    assert.equal(called, 1); assert.equal(rows.length, 1);
    assert.equal(rows[0].status, fails ? 'failed' : 'passed');
    assert.equal(rows[0].step, 'original public wait');
    assert(rows[0].timing.wallNs > 0 && Number.isSafeInteger(rows[0].timing.wallNs));
    for (const name of ['cpuUserUs', 'cpuSystemUs']) assert(Number.isSafeInteger(rows[0].timing[name]) && rows[0].timing[name] >= 0);
    assert.equal(failures.length, logFails ? 1 : 0);
  }
});

test('workflow actual observation counts Source Model and physical writes with loss-aware phase controls', async () => {
  const make = options => workflowWorkObservation({...options, createObservation: createHostObservationConnection});
  const check = new Function('assert', `${declaration('checkWorkflowWork')};return checkWorkflowWork;`)(assert);
  for (const phase of ['capture', 'approve', 'recover']) for (const models of [1, 2]) {
    const work = make(), observer = installHostObservation(work.connection, {});
    assert.equal(work.snapshot().complete, false, 'Pending delivery is not zero work');
    if (phase === 'capture') {
      observer.diagnostic('acquisition_started', {}); observer.diagnostic('acquisition_started', {});
      for (let i = 0; i < 2 * models; i++) observer.diagnostic('model_call_entered', {});
    } else if (phase === 'approve') {
      observer.diagnostic('effect_write_observed', {}); observer.diagnostic('effect_write_observed', {});
    }
    observer.diagnostic('effect_application_observed', {outcome: 'succeeded'});
    await observer.close();
    const actual = work.snapshot(); check(actual, phase, 2, models);
    assert.equal(actual.sourceAcquisitionStarts, phase === 'capture' ? 2 : 0);
    assert.equal(actual.modelCallStarts, phase === 'capture' ? 2 * models : 0);
    assert.equal(actual.effectReplacementReturns, phase === 'approve' ? 2 : 0);
    assert.throws(() => check({...actual, complete: false}, phase, 2, models));
    assert.throws(() => check({...actual, effectReplacementReturns: 3}, phase, 2, models));
    if (phase !== 'capture') {
      assert.throws(() => check({...actual, sourceAcquisitionStarts: 1}, phase, 2, models));
      assert.throws(() => check({...actual, modelCallStarts: 1}, phase, 2, models));
    }
  }
  const limited = workflowWorkObservation({createObservation:
    options => createHostObservationConnection({...options, limits: {queueRecords: 1}})});
  const observer = installHostObservation(limited.connection, {});
  for (let n = 0; n < 10; n++) observer.diagnostic('model_call_entered', {});
  await observer.close();
  assert.equal(limited.snapshot().complete, false);
  assert(limited.snapshot().status.dropped > 0);
});

test('original Run work separates fresh verification reads and refuses unbound or over-limit scope', async () => {
  const make = options => workflowWorkObservation({...options, createObservation: createHostObservationConnection});
  const ref = value => ({namespaceId: 'fixture', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${value.repeat(64)}`});
  const original = ref('1'), verification = ref('2');
  const install = work => installHostObservation(work.connection, {runId: () => 'same-host-fixture',
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  for (const phase of ['approve', 'saved']) {
    const work = make({trackOriginal: true}), observer = install(work);
    if (phase === 'approve') {
      observer.diagnostic('effect_write_observed', {ref: original});
      observer.diagnostic('acquisition_started', {ref: verification});
    }
    await observer.close();
    const actual = work.forOriginal(original);
    assert.equal(actual.complete, true); assert.equal(actual.sourceAcquisitionStarts, 0);
    assert.equal(actual.modelCallStarts, 0);
    assert.equal(actual.effectReplacementReturns, phase === 'approve' ? 1 : 0);
    assert.equal(actual.totals.sourceAcquisitionStarts, phase === 'approve' ? 1 : 0);
    assert.equal(JSON.stringify(actual).includes('sha256:'), false);
    assert.equal(work.forOriginal(undefined).complete, false);
  }
  for (const event of ['acquisition_started', 'model_call_entered', 'effect_write_observed']) {
    const work = make({trackOriginal: true}), observer = install(work);
    observer.diagnostic(event, {}); await observer.close();
    assert.equal(work.forOriginal(original).complete, false, 'Unbound work cannot become original zero');
  }
  const ambient = make({trackOriginal: true}), selected = install(ambient);
  await selected.run('resolve', undefined, () => {
    selected.accepted({ref: original, inserted: false}, 'fixture-request');
    selected.diagnostic('effect_write_observed', {ref: {}});
  });
  await selected.close();
  assert.equal(ambient.forOriginal(original).complete, false, 'Unknown physical original cannot borrow caller correlation');
  assert.equal(ambient.forOriginal(original).totals.effectReplacementReturns, 1);
  const work = make({trackOriginal: true}), observer = install(work);
  for (let n = 1; n <= 9; n++) observer.diagnostic('acquisition_started', {ref: ref(String(n))});
  await observer.close(); assert.equal(work.forOriginal(original).complete, false);
});

test('write attribution borrows the existing exact Mock original and keeps unreadable identity unbound', () => {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let callback, installationCall, installationMethod;
  const declarations = new Map();
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id.type === 'Identifier') {
      assert(!declarations.has(node.id.name) || node.id.name !== 'observeMockEffectWrite');
      declarations.set(node.id.name, node.init);
    }
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.object.name === 'preparation' && node.callee.property.name === 'installMockEffects') {
      assert.equal(installationCall, undefined); installationCall = node;
    }
    if (node.type === 'Property' && !node.computed && node.key.name === 'installMockEffects' &&
        node.value.type === 'FunctionExpression') {
      assert.equal(installationMethod, undefined); installationMethod = node.value;
    }
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(visit);
      else if (child && typeof child === 'object') visit(child);
    }
  }
  visit(ast);
  assert(installationCall && installationMethod, 'Require the actual Mock installation call and implementation');
  const forwarded = name => {
    const index = installationMethod.params.findIndex(parameter => parameter.type === 'Identifier' && parameter.name === name);
    assert.notEqual(index, -1, `Missing Mock installation parameter: ${name}`);
    return installationCall.arguments[index];
  };
  for (const name of ['sourceProfile', 'installationServices']) {
    assert.equal(forwarded(name)?.type, 'Identifier');
    assert.equal(forwarded(name).name, name, `Forward the same original ${name}`);
  }
  callback = forwarded('observeWrite');
  if (callback?.type === 'Identifier') {
    assert.equal(callback.name, 'observeMockEffectWrite');
    callback = declarations.get(callback.name);
  }
  assert.equal(callback?.type, 'ArrowFunctionExpression');
  const original = Object.freeze({}), definition = Object.freeze({}), entries = new WeakMap();
  entries.set(original, {original, definition});
  const events = []; let calls = 0, unreadable = false;
  const observe = Function('mockEffectOriginals', 'diagnostic', 'namespaceId', 'authorityScopeCid', 'moon',
    `return (${source.slice(callback.start, callback.end)});`)(entries,
    (event, detail) => events.push({event, ...detail}), 'same-host', `sha256:${'a'.repeat(64)}`,
    {strategyPublicationContractIdentity(value) {
      assert.strictEqual(value, definition);calls++;
      if (unreadable) throw new Error('OriginalIdentityUnavailable');
      return `sha256:${'b'.repeat(64)}`;
    }});
  observe(original); observe(Object.freeze({})); unreadable = true; observe(original);
  assert.equal(calls, 2); assert.equal(events.length, 3);
  assert.deepEqual(events[0], {event: 'effect_write_observed', ref: {namespaceId: 'same-host',
    authorityScopeCid: `sha256:${'a'.repeat(64)}`, runDefinitionCid: `sha256:${'b'.repeat(64)}`}});
  assert.deepEqual(events[1].ref, {}); assert.deepEqual(events[2].ref, {});
});

function capture({saveFailure, state = {status: 'failed', terminal_error: {code: 'OriginalSourceFailure'}}} = {}) {
  const events = [], originalRef = Object.freeze({run: 'fixture-private-original'});
  let saved;
  const ports = {
    console: {log() {}},
    client: {async startSource() {
      events.push('submit');return {ref: originalRef, async wait() {
        events.push('wait');assert.strictEqual(saved.ref, originalRef);return state;
      }};
    }},
    targetState: async () => ({bytes: '{}'}), readFile: async () => 'original Source',
    save: async (path, value) => {
      events.push('save-reference');assert.equal(path, 'fixture-handoff.started');
      if (saveFailure !== undefined) throw saveFailure;
      saved = value;
    },
  };
  const make = new Function('ports', 'assert', 'startMockProjectSource', `
    const {client,targetState,readFile,save,console}=ports;
    const phase='capture',twoModels=false,dealReview=false,handoffPath='fixture-handoff';
    const template='churn-risk-mock',variant='readme';
    let activeStep,firstFailedStep,runObservation;const stepDiagnosticFailures=[];
    ${declaration('step')}
    ${declaration('publicRunObservation')}
    return async()=>{try ${captureBody} catch(cause) {
      return {cause,firstFailedStep,runObservation};
    }};
  `);
  return {invoke: make(ports, assert, startMockProjectSource), events, saved: () => saved, originalRef};
}

test('actual capture retains the original accepted reference before its first failed wait', async () => {
  const f = capture(), result = await f.invoke();
  assert.deepEqual(f.events, ['submit', 'save-reference', 'wait']);
  assert.strictEqual(f.saved().ref, f.originalRef);
  assert.equal(result.firstFailedStep, 'wait for original Checkpoint');
  assert.equal(result.cause.code, 'ERR_ASSERTION', 'keep the fixture oracle failure distinct');
  assert.deepEqual(result.runObservation, {available: true, status: 'failed', terminalCode: 'OriginalSourceFailure'});
});

test('reference persistence failure retains its exact cause and does not enter wait or resubmit', async () => {
  const failure = new Error('OriginalReferenceWriteRefused'), f = capture({saveFailure: failure});
  const result = await f.invoke();
  assert.strictEqual(result.cause, failure);
  assert.equal(result.firstFailedStep, 'retain original accepted reference before wait');
  assert.deepEqual(f.events, ['submit', 'save-reference']);
  assert.equal(result.runObservation, undefined);
});

test('public wait observation separates terminal DATA from uncertain stop and excludes private material', () => {
  const value = observe({status: 'needs_reconciliation', run_id: 'private-run',
    terminal_error: {code: 'OriginalSourceFailure', message: 'private rows and Source material'},
    next_action: {kind: 'reconcile_run', reason: 'execution_unknown'},
    control: {physical_stop: 'unknown', cancellation_requested: true, revision: 23}});
  assert.deepEqual(value, {available: true, status: 'needs_reconciliation',
    terminalCode: 'OriginalSourceFailure', nextAction: 'reconcile_run',
    physicalStop: 'unknown', cancellationRequested: true});
  assert.equal(JSON.stringify(value).includes('private'), false);
  assert.deepEqual(observe({status: 'failed', terminal_error: {code: 'x'.repeat(129)}}),
    {available: true, status: 'failed'});
  assert.deepEqual(observe({status: 'failed', get terminal_error() {throw new Error('unavailable');}}),
    {available: false});
});

test('actual first close reports its return separately and never replaces the original primary', async () => {
  const start = text.indexOf('let closeFailure, closeFailed');
  const end = text.indexOf('if (failed) throw primary;', start);
  assert.ok(start > 0 && end > start);
  const make = new Function('ports', `
    let {client,primary}=ports;const phase='capture',failed=true;
    const process={pid:123},writeFile=async()=>{};
    const workObservation={snapshot:()=>({complete:false})};const stepDiagnosticFailures=[];
    let firstFailedStep='wait for original Checkpoint',checkDiagnostic,runObservation;
    const console={log:line=>ports.summary(JSON.parse(line))};
    return async()=>{${text.slice(start,end)}};
  `);
  for (const cleanupFails of [false, true]) {
    const primary = Object.assign(new Error('original oracle'), {code: 'ERR_ASSERTION'});
    const cleanup = Object.assign(new Error('actual original cleanup'), {code: 'ClientCleanupPending'});
    let closes = 0, result;
    await make({primary, client: {async close() {closes++;if (cleanupFails) throw cleanup;}},
      summary(value) {result = value;}})();
    assert.equal(closes, 1);
    assert.equal(result.status, 'failed');assert.equal(result.code, primary.code);
    assert.equal(result.firstFailedStep, 'wait for original Checkpoint');
    assert.deepEqual(result.firstClose, {attempted: true, returned: !cleanupFails});
    assert.equal(result.cleanupCode, cleanupFails ? cleanup.code : undefined);
    assert.equal(result.physicalStop, undefined, 'a close return does not invent whole-Run stop');
  }
});

test('workflow persists the original primary before pending close even when diagnostic writes fail', async () => {
  const start = text.indexOf('let closeFailure, closeFailed');
  const make = new Function('ports', `
    const {client,primary,writeFile,process,console}=ports;const phase='capture',failed=true;
    const workObservation={snapshot:()=>({complete:false})};const stepDiagnosticFailures=[];
    let firstFailedStep='wait for original Checkpoint',checkDiagnostic,runObservation;
    return async()=>{${text.slice(start)}};
  `);
  for (const writeFails of [false, true]) {
    const primary = Object.assign(new Error('OriginalWaitRefusal'), {code: 'OriginalWaitRefusal'});
    const events = [], observations = [];
    let release, entered, summary;
    const closing = new Promise(resolve => {release = resolve;});
    const started = new Promise(resolve => {entered = resolve;});
    const result = make({primary, process: {pid: 123}, console: {log(value) {summary = JSON.parse(value);}},
      client: {async close() {events.push('close'); entered(); await closing;}},
      async writeFile(path, value) {
        events.push('save'); observations.push({path, value: JSON.parse(value)});
        if (writeFails) throw Object.assign(new Error('DiagnosticWriteRefused'), {code: 'EACCES'});
      }})();
    const rejected = assert.rejects(result, error => error === primary);
    await started;
    assert.deepEqual(events, ['save', 'close']);
    assert.equal(observations[0].path, 'capture.pending.json');
    assert.equal(observations[0].value.code, primary.code);
    assert.equal(observations[0].value.firstFailedStep, 'wait for original Checkpoint');
    assert.deepEqual(observations[0].value.firstClose, {attempted: true, returned: false, state: 'pending'});
    release(); await rejected;
    assert.deepEqual(observations[1].value.firstClose, {attempted: true, returned: true, state: 'returned'});
    assert.equal(summary.status, 'failed'); assert.equal(summary.code, primary.code);
    assert.equal(summary.diagnosticFailures?.length ?? 0, writeFails ? 2 : 0);
  }
});

test('actual cold recovery consumes the same Saved Result before status and preserves its first refusal', async () => {
  const approve = branch.alternate.body.find(node => node.type === 'IfStatement');
  assert.equal(approve.test.left.name, 'phase');assert.equal(approve.test.right.value, 'approve');
  const recoverBody = text.slice(approve.alternate.start, approve.alternate.end);
  const make = new Function('ports', 'assert', `
    const {execution,readFile,targetState,checkRows,console}=ports;
    const phase='recover',template='churn-risk-mock',variant='readme',wholeProducer=false,handoffPath='fixture-handoff';
    let activeStep,firstFailedStep;const stepDiagnosticFailures=[];
    ${declaration('step')}
    return async()=>${recoverBody};
  `);
  for (const fails of [false, true]) {
    const events = [], rows = [['original-result']], ref = {run: 'fixture-original'};
    const failure = new Error('OriginalSavedResultRefused');
    const approved = {ref, runId: 'same-original-run', rows, after: {bytes: 'original-target'}};
    const invoke = make({console: {log() {}},
      readFile: async () => JSON.stringify(approved), checkRows: actual => assert.deepEqual(actual, rows),
      targetState: async () => {events.push('target');return approved.after;},
      execution: {ref, result(name) {
        assert.equal(name, 'updates');return {async all() {
          events.push('saved');if (fails) throw failure;return rows;
        }};
      }, async status() {
        assert.deepEqual(events, ['saved'], 'status cannot precede the Saved read');
        events.push('status');return {status: 'succeeded', run_id: approved.runId};
      }},
    }, assert);
    if (fails) {
      await assert.rejects(invoke, error => error === failure);
      assert.deepEqual(events, ['saved']);
    } else {
      await invoke();assert.deepEqual(events, ['saved', 'status', 'target']);
    }
  }
});

test('work collector binds typed preflight failure only to the same original Run and never invents its cause', async () => {
  const make = options => workflowWorkObservation({...options, createObservation: createHostObservationConnection});
  const work = make({trackOriginal: true});
  const projection = installHostObservation(work.connection, {
    journal: {observationStorage: () => ({consume: () => ({accepted: true})})}, runId: () => 'unit-original'});
  const ref = {namespaceId: 'local', authorityScopeCid: 'sha256:' + 'a'.repeat(64), runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
  const foreign = {...ref, runDefinitionCid: 'sha256:' + 'c'.repeat(64)};
  const failure = {code: 'EffectTargetVersionMismatch', kind: 'target_version_mismatch', phase: 'effect_apply_preflight'};
  projectEffectPreflightFailure(projection, foreign, failure);
  projectEffectPreflightFailure(projection, ref, {...failure, kind: 'unknown'});
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(work.forOriginal(ref).effectPreflightFailure, undefined);
  projectEffectPreflightFailure(projection, ref, failure);
  await projection.close();
  const observed = work.forOriginal(ref);
  assert.equal(observed.complete, true);
  assert.deepEqual(observed.effectPreflightFailure, {available: true, ...failure});
  assert.deepEqual(observed.totals, {sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0});
  assert.equal(work.forOriginal({...ref, runDefinitionCid: 'sha256:' + 'd'.repeat(64)}).effectPreflightFailure, undefined);
});


test('workflow observes pre-Model Source Unit export failure without reporting Model work or private payload', async () => {
  const make = createObservation => options => workflowWorkObservation({...options, createObservation});
  const work = make(createHostObservationConnection)();
  const observer = installHostObservation(work.connection);
  observer.diagnostic('dispatch_failed', {primaryDiagnostic: {
    code: 'MoonBitHostFailure', phase: 'original_effect_source_unit_result_export',
    kind: 'export.completed.unavailable', task: 4, unit: 2, step: 5},
    message: 'private message', body: 'private body'});
  await observer.close();
  const actual = work.snapshot();
  assert.equal(actual.complete, true);
  assert.equal(actual.modelCallStarts, 0);
  assert.deepEqual(actual.primaryFailure, {available: true, code: 'MoonBitHostFailure',
    phase: 'original_effect_source_unit_result_export', kind: 'export.completed.unavailable',
    occurrence: {task: 4, unit: 2, step: 5}});
  assert.equal(JSON.stringify(actual).includes('private'), false);
});


test('workflow observes pre-Model Source Unit artifact failure without reporting Model work or private payload', async () => {
  const make = createObservation => options => workflowWorkObservation({...options, createObservation});
  const work = make(createHostObservationConnection)();
  const observer = installHostObservation(work.connection);
  observer.diagnostic('dispatch_failed', {primaryDiagnostic: {
    code: 'MoonBitHostFailure', phase: 'original_effect_source_unit_artifact',
    kind: 'run.foreign_original', task: 4, unit: 2, step: 5},
    message: 'private message', body: 'private body'});
  await observer.close();
  const actual = work.snapshot();
  assert.equal(actual.complete, true);
  assert.equal(actual.modelCallStarts, 0);
  assert.deepEqual(actual.primaryFailure, {available: true, code: 'MoonBitHostFailure',
    phase: 'original_effect_source_unit_artifact', kind: 'run.foreign_original',
    occurrence: {task: 4, unit: 2, step: 5}});
  assert.equal(JSON.stringify(actual).includes('private'), false);
});

test('workflow observes actual Model component call-scope failure without reporting Model work or private payload', async () => {
  const make = createObservation => options => workflowWorkObservation({...options, createObservation});
  const work = make(createHostObservationConnection)();
  const observer = installHostObservation(work.connection);
  observer.diagnostic('dispatch_failed', {primaryDiagnostic: {
    code: 'MoonBitHostFailure', phase: 'original_infer_component',
    kind: 'call_scope.foreign_input', task: 4, unit: 2, step: 5},
    message: 'private message', body: 'private body'});
  await observer.close();
  const actual = work.snapshot();
  assert.equal(actual.complete, true);
  assert.equal(actual.modelCallStarts, 0);
  assert.deepEqual(actual.primaryFailure, {available: true, code: 'MoonBitHostFailure',
    phase: 'original_infer_component', kind: 'call_scope.foreign_input',
    occurrence: {task: 4, unit: 2, step: 5}});
  assert.equal(JSON.stringify(actual).includes('private'), false);
});
