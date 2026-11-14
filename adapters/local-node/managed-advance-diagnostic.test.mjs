import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checkedLocalManagedAdvance} from './managed-advance-diagnostic.mjs';

const source = readFileSync(new URL('../host-node/client-dispatch-owner.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const node = tree.body.find(value => value.type === 'FunctionDeclaration' && value.id.name === 'dispatchFailureSnapshot');
const snapshot = Function(`return (${source.slice(node.start, node.end)});`)();

test('managed advance resource diagnosis comes only from the original typed projector', () => {
  for (const dimension of ['retained_bytes', 'execution_bytes', undefined, 'memory', 5]) {
    const result = {}, primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    const moon = {strategyModule_local_ManagedAdvanceResourceDimension(value) {
      assert.equal(this, moon); assert.equal(value, result); return dimension;
    }};
    assert.throws(() => checkedLocalManagedAdvance(moon, result, () => {throw primary;}, 44), error => error === primary);
    if (typeof dimension === 'string' && dimension.endsWith('_bytes')) {
      assert.deepEqual(snapshot(primary).primaryDiagnostic, {
        code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'resource', task: 44, dimension,
      });
    } else assert.equal(snapshot(primary).primaryDiagnostic, undefined);
  }
});

test('pending cleanup diagnostics retain only closed inert owner and phase DATA', () => {
  const data = {owner: 'local_managed', phase: 'refresh_cleanup', continuation: 'blocked'};
  const original = Object.assign(new Error('original'), {cleanupDiagnostic: data});
  assert.deepEqual(snapshot({primaryFailure: original}).cleanupDiagnostic, data);
  assert.equal(snapshot({cleanupDiagnostic: {...data, phase: 'arbitrary_private_state'}}).cleanupDiagnostic, undefined);
  assert.equal(snapshot({cleanupDiagnostic: {...data, owner: 'foreign_owner'}}).cleanupDiagnostic, undefined);
  assert.equal(snapshot({cleanupDiagnostic: {...data, get continuation() {assert.fail('no getter');}}}).cleanupDiagnostic, undefined);
});

test('the existing Site failure wrapper preserves original resource DATA without traversing causes', () => {
  const text = readFileSync(new URL('../host-common/strategy.mjs', import.meta.url), 'utf8');
  const body = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body;
  const declaration = body.find(value => value.type === 'ExportNamedDeclaration' && value.declaration?.id?.name === 'StrategyHostError').declaration;
  const memberNode = body.flatMap(value => value.type === 'VariableDeclaration' ? value.declarations : []).find(value => value.id.name === 'failureMember');
  const factory = body.find(value => value.type === 'FunctionDeclaration' && value.id.name === 'ownedStrategyFailure');
  const ErrorClass = Function('return (' + text.slice(declaration.start, declaration.end) + ');')();
  const member = Function('return (' + text.slice(memberNode.init.start, memberNode.init.end) + ');')();
  const wrap = Function('StrategyHostError', 'failureMember', 'return (' + text.slice(factory.start, factory.end) + ');')(ErrorClass, member);
  const diagnostic = Object.freeze({code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'resource', task: 44, dimension: 'retained_bytes'});
  const original = Object.assign(new Error('original'), {primaryDiagnostic: diagnostic});
  const middle = wrap(original, 'StrategyExecutionFailed');
  const outer = wrap(middle, 'StrategyExecutionFailed');
  assert.equal(outer.primaryFailure, middle);
  assert.equal(outer.primaryDiagnostic, diagnostic);
  assert.deepEqual(snapshot(outer).primaryDiagnostic, diagnostic);
});

test('managed advance keeps the exact checked result receiver primary and cleanup while adding closed DATA', () => {
  const result = {}, cleanupHandle = {};
  const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure', cleanupHandle});
  let projects = 0, checks = 0;
  const moon = {strategyModule_local_ManagedAdvanceControlWorkLimit(value) {
    assert.strictEqual(this, moon); assert.strictEqual(value, result); projects++; return 100000;
  }};
  assert.throws(() => checkedLocalManagedAdvance(moon, result, value => {
    checks++; assert.strictEqual(value, result); throw primary;
  }, 7), error => error === primary);
  assert.equal(checks, 1); assert.equal(projects, 1);
  assert.strictEqual(primary.cleanupHandle, cleanupHandle);
  assert.deepEqual(primary.primaryDiagnostic, {code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work', task: 7, controlWorkLimit: 100000});
  assert(Object.isFrozen(primary.primaryDiagnostic));
  assert.deepEqual(snapshot(primary).primaryDiagnostic, primary.primaryDiagnostic);
});

test('managed advance success does not invoke a failure projector or create diagnostic DATA', () => {
  const result = {}, value = {};
  assert.strictEqual(checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceControlWorkLimit() {
    assert.fail('successful yield or completion is not work refusal');
  }}, result, original => {assert.strictEqual(original, result); return value;}, 0), value);
});

test('managed advance refuses unclassified physical row workspace and foreign diagnostic reasons', () => {
  for (const kind of [undefined, -1, 1.5, 2147483648, NaN, 'control_work', 'execution', 'ExecutionLimit', 'retention', 'row', 'workspace', 'control_work.extra']) {
    const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceControlWorkLimit() {return kind;}},
      {}, () => {throw primary;}, 0), error => error === primary);
    assert.equal(primary.primaryDiagnostic, undefined);
  }
  for (const task of [undefined, -1, 1.5, 2147483648]) {
    const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceControlWorkLimit() {return 100000;}},
      {}, () => {throw primary;}, task), error => error === primary);
    assert.equal(primary.primaryDiagnostic, undefined);
  }
});

test('managed advance optional missing throwing or frozen diagnostics preserve every original thrown value', () => {
  for (const primary of [undefined, null, 7, new Error('untyped'),
    Object.freeze(Object.assign(new Error('frozen'), {code: 'MoonBitHostFailure'}))]) {
    for (const moon of [{}, {strategyModule_local_ManagedAdvanceControlWorkLimit() {throw new Error('optional');}},
      {strategyModule_local_ManagedAdvanceControlWorkLimit() {return 100000;}}]) {
      let threw = false;
      try {checkedLocalManagedAdvance(moon, {}, () => {throw primary;}, 0);}
      catch (error) {threw = true; assert.strictEqual(error, primary);}
      assert.equal(threw, true);
    }
  }
});

test('managed advance never invokes an original thrown code accessor', () => {
  let reads = 0;
  const original = Object.defineProperty(new Error('original'), 'code', {get() {reads++; return 'MoonBitHostFailure';}});
  assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceControlWorkLimit() {return 100000;}},
    {}, () => {throw original;}, 0), error => error === original);
  assert.equal(reads, 0); assert.equal(original.primaryDiagnostic, undefined);
});

test('dispatch snapshot refuses misleading local-work DATA and retains the existing full Model diagnostic', () => {
  const data = {code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work', task: 0, controlWorkLimit: 100000};
  for (const foreign of [{...data, kind: 'execution'}, {...data, controlWorkLimit: undefined}, {...data, controlWorkLimit: -1}, {...data, task: -1}, {...data, task: undefined},
    {...data, unit: 0}, {...data, unit: undefined}, {...data, step: 0}, {...data, code: 'Foreign'}]) {
    assert.equal(snapshot(Object.assign(new Error('original'), {primaryDiagnostic: foreign})).primaryDiagnostic, undefined);
  }
  const accessor = Object.defineProperty(new Error('original'), 'primaryDiagnostic', {get() {assert.fail('no getter');}});
  assert.equal(snapshot(accessor).primaryDiagnostic, undefined);
  const model = {code: 'MoonBitHostFailure', phase: 'original_model_acquired_effect_evidence',
    kind: 'original_sources.missing', task: 1, unit: 2, step: 3};
  assert.deepEqual(snapshot(Object.assign(new Error('original'), {primaryDiagnostic: model})).primaryDiagnostic, model);
});


test('managed advance retains exact value capture work cause step limit receiver and original error', () => {
  const result={},cleanupHandle={},primary=Object.assign(new Error('original'),{code:'MoonBitHostFailure',cleanupHandle});
  let projects=0,checks=0;
  const moon={strategyModule_local_ManagedAdvanceControlWorkLimit(){return undefined;},
    strategyModule_local_ManagedAdvanceCaptureWork(value){assert.strictEqual(this,moon);assert.strictEqual(value,result);projects++;return Object.assign(Object.create({$tag:1}),{_0:[41,100000]});}};
  assert.throws(()=>checkedLocalManagedAdvance(moon,result,value=>{checks++;assert.strictEqual(value,result);throw primary;},41),error=>error===primary);
  assert.equal(checks,1);assert.equal(projects,1);assert.strictEqual(primary.cleanupHandle,cleanupHandle);
  assert.deepEqual(primary.primaryDiagnostic,{code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'value_capture_work',task:41,step:41,workLimit:100000});
  assert(Object.isFrozen(primary.primaryDiagnostic));
  assert.deepEqual(snapshot(primary).primaryDiagnostic,primary.primaryDiagnostic);
});


test('managed advance capture diagnostic refuses generic malformed and foreign vectors without replacing original failure', () => {
  for(const capture of [undefined,null,[],[41],[41,100000,0],[-1,100000],[41,-1],[41,NaN],[41,'100000'],[2147483648,100000]]){
    const original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'});
    assert.throws(()=>checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCaptureWork(){return Object.assign(Object.create({$tag:1}),{_0:capture});}},{},()=>{throw original;},41),error=>error===original);
    assert.equal(original.primaryDiagnostic,undefined);
  }
  const accessor=Object.defineProperty([41,100000],'0',{get(){assert.fail('do not invoke capture vector accessors');}});
  const original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'});
  assert.throws(()=>checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCaptureWork(){return Object.assign(Object.create({$tag:1}),{_0:accessor});}},{},()=>{throw original;},41),error=>error===original);
  assert.equal(original.primaryDiagnostic,undefined);
  const data={code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'value_capture_work',task:41,step:41,workLimit:100000};
  for(const changed of [{...data,workLimit:-1},{...data,step:-1},{...data,unit:0},{...data,controlWorkLimit:100000}])assert.equal(snapshot(Object.assign(new Error('original'),{primaryDiagnostic:changed})).primaryDiagnostic,undefined);
});


test('capture work getter uses the actual pinned boxed Option and refuses an unboxed replacement', () => {
  // Exact boxed Some/None layout is witnessed at the original 7d1 export;
  // these are compiler DATA fixtures, not issued request or resource values.
  const boxed=Object.assign(Object.create({$tag:1}),{_0:[41,100000]});
  for(const [returned,expected]of [[boxed,true],[Object.create({$tag:0}),false],[[41,100000],false]]){
    const original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'});
    let calls=0;const moon={strategyModule_local_ManagedAdvanceCaptureWork(result){assert.strictEqual(this,moon);assert.strictEqual(result,boxed);calls++;return returned;}};
    assert.throws(()=>checkedLocalManagedAdvance(moon,boxed,()=>{throw original;},41),error=>error===original);
    assert.equal(calls,1);
    if(expected)assert.deepEqual(original.primaryDiagnostic,{code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'value_capture_work',task:41,step:41,workLimit:100000});
    else assert.equal(original.primaryDiagnostic,undefined);
  }
});


test('managed failure snapshot preserves original diagnostic through the existing owned primary wrapper only', () => {
  const source=readFileSync(new URL('../host-common/managed-failure.mjs',import.meta.url),'utf8');
  const body=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body;
  const memberNode=body.flatMap(value=>value.type==='VariableDeclaration'?value.declarations:[]).find(value=>value.id.name==='member');
  const factory=body.find(value=>value.type==='FunctionDeclaration'&&value.id.name==='ownedFailure');
  const member=Function('return ('+source.slice(memberNode.init.start,memberNode.init.end)+');')();
  const owned=Function('member','return ('+source.slice(factory.start,factory.end)+');')(member);
  const original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'}),result={};
  assert.throws(()=>checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCaptureWork(){return Object.assign(Object.create({$tag:1}),{_0:[41,100000]});}},result,()=>{throw original;},41),error=>error===original);
  const wrapper=owned(original,'ManagedExecutionFailed'),cleanupHandle={original:'same-cleanup'};
  wrapper.cleanupHandle=cleanupHandle;
  assert.notStrictEqual(wrapper,original);assert.strictEqual(wrapper.primaryFailure,original);assert.strictEqual(wrapper.cause,original);
  assert.deepEqual(snapshot(wrapper).primaryDiagnostic,original.primaryDiagnostic);
  assert.strictEqual(wrapper.cleanupHandle,cleanupHandle);assert.equal(wrapper.code,original.code);assert.deepEqual(wrapper.cleanupErrors,[]);
});

test('managed failure diagnostic wrapper lookup never traverses getters cause chains or recursive primary slots', () => {
  const data=Object.freeze({code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'value_capture_work',task:41,step:41,workLimit:100000});
  const original=Object.defineProperty(new Error('original'),'primaryDiagnostic',{value:data});
  const self={};self.primaryFailure=self;
  for(const value of [self,{cause:original},{primaryFailure:{primaryFailure:original}},
    Object.defineProperty({},'primaryFailure',{get(){assert.fail('no primary getter');}}),
    {primaryFailure:Object.defineProperty({},'primaryDiagnostic',{get(){assert.fail('no diagnostic getter');}})},
    Object.defineProperty({primaryFailure:original},'primaryDiagnostic',{get(){assert.fail('no outer getter or fallback');}})])assert.equal(snapshot(value).primaryDiagnostic,undefined);
  assert.equal(snapshot({primaryFailure:undefined}).primaryDiagnostic,undefined);
});

const publicBudgetNode = tree.body.find(value => value.type === 'FunctionDeclaration' && value.id.name === 'publicBudgetFailureMessage');
const publicBudgetMessage = Function('dispatchFailureSnapshot', `return (${source.slice(publicBudgetNode.start, publicBudgetNode.end)});`)(snapshot);
const journalSource = readFileSync(new URL('../host-node/client-request-journal.mjs', import.meta.url), 'utf8');
const journalTree = parse(journalSource, {ecmaVersion: 'latest', sourceType: 'module'});
const retainedBudgetNode = journalTree.body.find(value => value.type === 'FunctionDeclaration' && value.id.name === 'retainedBudgetFailureMessage');
const retainedBudgetMessage = Function(`return (${journalSource.slice(retainedBudgetNode.start, retainedBudgetNode.end)});`)();
const some = value => Object.assign(Object.create({$tag: 1}), {_0: value});
// Explicit test-port DATA; the separate compiled Core test qualifies the ABI.
const budgetTuple = fields => Object.fromEntries(fields.map((value, index) => [`_${index}`, value]));

test('original managed budget quantities reach the existing public message with the correct setting and units', () => {
  for (const dimension of ['retained_bytes', 'execution_bytes', 'value_capture_work']) {
    const result = {}, primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    const work = dimension === 'value_capture_work';
    const moon = {
      strategyModule_local_ManagedAdvanceResourceDimension: () => work ? undefined : dimension,
      strategyModule_local_ManagedAdvanceCaptureWork: () => some([41, 100]),
      strategyModule_local_ManagedAdvanceBudget(value) {
        assert.strictEqual(this, moon); assert.strictEqual(value, result);
        return budgetTuple([dimension, !work, 8n, 7n, 100n]);
      },
    };
    assert.throws(() => checkedLocalManagedAdvance(moon, result, value => {
      assert.strictEqual(value, result); throw primary;
    }, 41), error => error === primary);
    const selected = snapshot(primary).primaryDiagnostic;
    assert.deepEqual(selected.budget, {requested: '8', remaining: '7', policy: '100', requestedIsLowerBound: work});
    const message = publicBudgetMessage(primary);
    assert(message.includes(`dimension=${dimension};`));
    assert(message.includes(`requested_delta=${work ? '>=' : ''}8; remaining=7; policy=100;`));
    assert(message.includes(work ? 'setting=installation.sourceFreeMaxWork.'
      : `setting=installation.requestMemory.${dimension === 'retained_bytes' ? 'retainedBytes' : 'executionBytes'}.`));
    assert(message.includes(work ? 'not Program parsing/checking' : 'not process RSS'));
    assert.equal(primary.message, 'original');
  }
});

test('missing or malformed budget projection never invents quantities or replaces the original failure', () => {
  for (const project of [() => undefined, () => {throw new Error('private');},
    () => budgetTuple(['retained_bytes', true, 7n, 7n, 100n]),
    () => budgetTuple(['execution_bytes', true, 8n, 7n, 100n]),
    () => budgetTuple(['retained_bytes', false, 8n, 7n, 100n]),
    () => budgetTuple(['retained_bytes', true, 8n, 7n, 6n])]) {
    const primary = Object.assign(new Error('private'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({
      strategyModule_local_ManagedAdvanceResourceDimension: () => 'retained_bytes',
      strategyModule_local_ManagedAdvanceBudget: project,
    }, {}, () => {throw primary;}, 4), error => error === primary);
    assert.equal(snapshot(primary).primaryDiagnostic.budget, undefined);
    const message = publicBudgetMessage(primary);
    assert(message.includes('requested_delta=unavailable; remaining=unavailable; policy=unavailable;'));
    assert(!message.includes('private'));
  }
  const invalid = Object.assign(new Error('original'), {primaryDiagnostic: {
    code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'resource', task: 4,
    dimension: 'retained_bytes', budget: {get requested() {assert.fail('no getter');},
      remaining: '0', policy: '100', requestedIsLowerBound: false},
  }});
  assert.equal(snapshot(invalid).primaryDiagnostic.budget, undefined);
});

test('same failed Run and exact control frame retain the first budget message without granting state or cleanup', () => {
  const primary = {primaryDiagnostic: {code: 'MoonBitHostFailure', phase: 'local_managed_advance',
    kind: 'resource', task: 4, dimension: 'retained_bytes',
    budget: {requested: '19', remaining: '7', policy: '512', requestedIsLowerBound: false}}};
  const message = publicBudgetMessage(primary);
  const control = {revision: 4, physical_stop: 'confirmed', cancellation_requested: false};
  const state = {run_id: 'original-run', status: 'failed', result_available: false,
    next_action: {kind: 'none'}, terminal_error: {code: 'ACTQL_E_UNPUBLISHED_RUN', message}, control};
  const key = JSON.stringify(state);
  assert.equal(retainedBudgetMessage(key, state, 'original-run', control), message);
  assert.equal(retainedBudgetMessage(key, {...state, terminal_error: {...state.terminal_error, message: 'later cause'}}, 'original-run', control), message);
  for (const status of ['running', 'preparing', 'needs_reconciliation', 'cancelled', 'succeeded']) {
    assert.equal(retainedBudgetMessage(key, {...state, status}, 'original-run', control), undefined);
  }
  for (const changed of [{...control, revision: 5}, {...control, physical_stop: 'unknown'},
    {...control, cancellation_requested: true}]) {
    assert.equal(retainedBudgetMessage(key, state, 'original-run', changed), undefined);
  }
  assert.equal(retainedBudgetMessage(key, state, 'foreign-run', control), undefined);
  assert.equal(retainedBudgetMessage(JSON.stringify({...state, terminal_error: {...state.terminal_error, message: message + ' private'}}), state, 'original-run', control), undefined);
  assert.equal(retainedBudgetMessage('not json', state, 'original-run', control), undefined);
});

const installerNode = tree.body.find(value => value.type === 'ExportNamedDeclaration' && value.declaration?.id?.name === 'installNodeClientDispatchOwner').declaration;
const retirementSource = ['retirementReady', 'retainBudgetFailureObservation', 'retire'].map(name => {
  const value = installerNode.body.body.find(value => value.type === 'FunctionDeclaration' && value.id.name === name);
  assert(value, name); return source.slice(value.start, value.end);
}).join('\n');

test('original failed retirement publishes only after cleanup and fences callback reentry before returning the parent', () => {
  for (const callback of ['reenter', 'new-pending', 'replace-entry']) {
    let parentReturns = 0, publications = 0, retire;
    const ref = {runDefinitionCid: 'original'};
    const entry = {ref, settled: true, physicalStarted: true, stopObserved: true,
      primaryFailure: {primaryDiagnostic: {code: 'MoonBitHostFailure', phase: 'local_managed_advance',
        kind: 'resource', task: 4, dimension: 'retained_bytes'}},
      retirePreparation() {parentReturns++;}};
    const entries = new Map([['original', entry]]);
    const frame = {physicalCloseConfirmed: true, observedTerminalOutcome: 'failed',
      runDefinition: {}, resultNames: ['answer'], dispatchReserved: true, preDispatchFailureConfirmed: false};
    const journal = {lookupRunDefinition(value) {assert.strictEqual(value, ref); return frame;},
      publishRunState(original, state) {
        publications++; assert.strictEqual(original, frame);
        assert.equal(state.status, 'failed'); assert.equal(state.terminal_error.code, 'ACTQL_E_UNPUBLISHED_RUN');
        assert(state.terminal_error.message.includes('dimension=retained_bytes'));
        retire(entry); assert.equal(parentReturns, 0, 'No parent return inside the diagnostic callback');
        if (callback === 'new-pending') entry.cleanupOwner = {};
        if (callback === 'replace-entry') entries.set('original', {});
      }};
    retire = Function('publicBudgetFailureMessage', 'journal', 'moon', 'control', 'now',
      'issueInstalledUnpublishedRunState', 'entries', 'keyOf', 'diagnostic', 'resourceUsage',
      retirementSource + '\nreturn retire;')(publicBudgetMessage, journal, {},
      {runDefinitionRunId: () => 'original-run'}, () => '2026-11-14T00:00:00.000Z',
      () => ({status: 'failed', terminal_error: {code: 'ACTQL_E_UNPUBLISHED_RUN', message: 'Run ended before publication'}}),
      entries, value => value.runDefinitionCid, () => {}, () => {});
    retire(entry);
    assert.equal(publications, 1);
    if (callback === 'reenter') {
      assert.equal(parentReturns, 1); assert.equal(entries.size, 0);
    } else {
      assert.equal(parentReturns, 0); assert.equal(entry.retirePreparation instanceof Function, true);
      if (callback === 'new-pending') {
        entry.cleanupOwner = undefined; retire(entry);
        assert.equal(parentReturns, 1); assert.equal(publications, 1, 'Original diagnostic duty is spent once');
      }
    }
  }
});


// Execute the actual observation closure with explicit original Store/journal
// ports. This is a caller/currentness regression, not packed Host acceptance.
const embeddedSource = readFileSync(new URL('../host-node/embedded-local.mjs', import.meta.url), 'utf8');
const embeddedTree = parse(embeddedSource, {ecmaVersion: 'latest', sourceType: 'module'});
const hostInstaller = embeddedTree.body.find(value => value.type === 'FunctionDeclaration' && value.id.name === 'openInstalledHost');
const findObserve = value => {
  if (!value || typeof value !== 'object') return undefined;
  if (value.type === 'VariableDeclarator' && value.id?.name === 'observeRun') return value.init;
  for (const child of Object.values(value)) {
    const found = Array.isArray(child) ? child.map(findObserve).find(Boolean) : findObserve(child);
    if (found) return found;
  }
};
const observeNode = findObserve(hostInstaller);
assert(observeNode, 'Actual installed Host observation closure');

test('original revision-stable observation joins budget DATA only after actual failed stop and retries changed frames', async () => {
  for (const mode of ['failed', 'pending-stop', 'unknown', 'running', 'cancelled', 'changed-frame', 'retired-entry']) {
    const ref = {namespaceId: 'namespace', authorityScopeCid: 'authority', runDefinitionCid: 'definition'};
    let attempts = 0, projections = 0, diagnosticReads = 0;
    const frame = {runDefinition: {}, revision: 4, resultNames: ['answer'], dispatchReserved: true,
      physicalStartReserved: true, preDispatchFailureConfirmed: false,
      physicalCloseConfirmed: mode !== 'pending-stop',
      observedTerminalOutcome: mode === 'unknown' ? null : 'failed'};
    const status = ['running', 'cancelled'].includes(mode) ? mode : mode === 'unknown' ? 'needs_reconciliation' : 'failed';
    const originalState = {status, terminal_error: {code: 'ACTQL_E_UNPUBLISHED_RUN', message: 'original placeholder'}};
    const message = 'original closed budget message';
    const journal = {
      lookupRunDefinition(value) {assert.strictEqual(value, ref); attempts++; return frame;},
      observeRunCancellation(value, originalMoon, originalControl, retained) {
        assert.strictEqual(value, ref); assert.strictEqual(retained, frame);
        return () => ({revision: mode === 'changed-frame' && attempts === 1 ? 5 : 4});
      },
      publishRunState(retained, state) {
        assert.strictEqual(retained, frame); projections++;
        const expected = mode === 'failed' || mode === 'changed-frame' ? message : originalState.terminal_error.message;
        assert.equal(state.terminal_error.message, expected);
        assert.equal(state.status, status);
        return JSON.stringify(state);
      },
    };
    const observe = Function('principalId', 'namespaceId', 'authorityScopeCid', 'journal', 'moon', 'control',
      'observeAuthorizedRunState', 'stateService', 'checkpoints', 'dispatchOwner', 'modelResumeFlights',
      'issueInstalledUnpublishedRunState', 'now', 'projectRunObservation', 'clientOperationError',
      `return (${embeddedSource.slice(observeNode.start, observeNode.end)});`)(
      'principal', 'namespace', 'authority', journal, {}, {runDefinitionRunId: () => 'run'},
      async () => undefined, {}, undefined, {
        live: () => mode === 'running',
        failureMessage(value) {assert.strictEqual(value, ref); diagnosticReads++; return mode === 'retired-entry' ? undefined : message;},
      }, new Map(), () => ({...originalState}), () => 'now', () => {}, code => new Error(code));
    const observed = await observe({ref, principalId: 'principal'});
    assert.equal(observed.status, status); assert.equal(projections, 1);
    assert.equal(attempts, mode === 'changed-frame' ? 2 : 1);
    assert.equal(diagnosticReads, ['failed', 'changed-frame', 'retired-entry'].includes(mode) ? 1 : 0);
    await assert.rejects(observe({ref, principalId: 'foreign'}), /RunStateAccessDenied/u);
  }
});
