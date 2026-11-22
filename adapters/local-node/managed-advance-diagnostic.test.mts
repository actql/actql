import {createClientDispatchCleanup} from '../host-node/client-dispatch-cleanup.mjs';
import {runtimeFailure} from '../host-common/compiler-binding.generated.mjs';
import {dispatchFailureSnapshot as snapshot, publicBudgetFailureMessage as publicBudgetMessage, retainedBudgetFailureMessage as retainedBudgetMessage} from '../host-node/client-dispatch-diagnostic.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import type {AnyNode, CallExpression, ClassDeclaration, ExportNamedDeclaration, Identifier, VariableDeclarator} from 'acorn';
import {checkedLocalManagedAdvance} from './managed-advance-diagnostic.mjs';

type OriginalFailure = Error & {primaryDiagnostic?: unknown};
type PublishedFailure = Readonly<{status: string; terminal_error: Readonly<{code: string; message: string}>}>;

type Projector = NonNullable<Parameters<typeof checkedLocalManagedAdvance>[0]['strategyModule_local_ManagedAdvanceCause']>;
type CauseDescription = NonNullable<Parameters<typeof publicBudgetMessage>[1]>;
type Reject<Actual, Port> = Actual extends Port ? false : true;
type Assert<Condition extends true> = Condition;
type _RejectAsyncProjector = Assert<Reject<(result: unknown) => Promise<string>, Projector>>;
type _RejectAsyncDescription = Assert<Reject<(cause: string) => PromiseLike<string>, CauseDescription>>;



test('managed advance resource diagnosis comes only from the original typed projector', () => {
  for (const dimension of ['retained_bytes', 'execution_bytes', undefined, 'memory', 5]) {
    const result = runtimeFailure({}), primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    const moon = {strategyModule_local_ManagedAdvanceResourceDimension(value: unknown) {
      assert.equal(this, moon); assert.equal(value, result); return dimension;
    }};
    assert.throws(() => checkedLocalManagedAdvance(moon, result, () => {throw primary;}, 44), error => error === primary);
    if (typeof dimension === 'string' && dimension.endsWith('_bytes')) {
      assert.deepEqual(snapshot(primary)!.primaryDiagnostic, {
        code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'resource', task: 44, dimension,
      });
    } else assert.equal(snapshot(primary)!.primaryDiagnostic, undefined);
  }
});

test('pending cleanup diagnostics retain only closed inert owner and phase DATA', () => {
  const data = {owner: 'local_managed', phase: 'refresh_cleanup', continuation: 'blocked'};
  const original = Object.assign(new Error('original'), {cleanupDiagnostic: data});
  assert.deepEqual(snapshot({primaryFailure: original})!.cleanupDiagnostic, data);
  assert.equal(snapshot({cleanupDiagnostic: {...data, phase: 'arbitrary_private_state'}})!.cleanupDiagnostic, undefined);
  assert.equal(snapshot({cleanupDiagnostic: {...data, owner: 'foreign_owner'}})!.cleanupDiagnostic, undefined);
  assert.equal(snapshot({cleanupDiagnostic: {...data, get continuation() {return assert.fail('no getter');}}})!.cleanupDiagnostic, undefined);
});

test('the existing Site failure wrapper preserves original resource DATA without traversing causes', () => {
  const text = readFileSync(new URL('../host-common/strategy.mjs', import.meta.url), 'utf8');
  const body = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body;
  const declaration = (body.find(value => value.type === 'ExportNamedDeclaration' && (value.declaration as ClassDeclaration | undefined)?.id?.name === 'StrategyHostError') as ExportNamedDeclaration).declaration!;
  const memberNode = body.flatMap(value => value.type === 'VariableDeclaration' ? value.declarations : []).find(value => (value.id as Identifier).name === 'failureMember')!;
  const factory = body.find(value => value.type === 'FunctionDeclaration' && value.id!.name === 'ownedStrategyFailure')!;
  const ErrorClass = Function('return (' + text.slice(declaration.start, declaration.end) + ');')();
  const member = Function('return (' + text.slice(memberNode.init!.start, memberNode.init!.end) + ');')();
  const wrap = Function('StrategyHostError', 'failureMember', 'return (' + text.slice(factory.start, factory.end) + ');')(ErrorClass, member);
  const diagnostic = Object.freeze({code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'resource', task: 44, dimension: 'retained_bytes'});
  const original = Object.assign(new Error('original'), {primaryDiagnostic: diagnostic});
  const middle = wrap(original, 'StrategyExecutionFailed');
  const outer = wrap(middle, 'StrategyExecutionFailed');
  assert.equal(outer.primaryFailure, middle);
  assert.equal(outer.primaryDiagnostic, diagnostic);
  assert.deepEqual(snapshot(outer)!.primaryDiagnostic, diagnostic);
});

test('managed advance keeps the exact checked result receiver primary and cleanup while adding closed DATA', () => {
  const result = runtimeFailure({}), cleanupHandle = {};
  const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure', cleanupHandle});
  let projects = 0, checks = 0;
  const moon = {strategyModule_local_ManagedAdvanceControlWorkLimit(value: unknown) {
    assert.strictEqual(this, moon); assert.strictEqual(value, result); projects++; return 100000;
  }};
  assert.throws(() => checkedLocalManagedAdvance(moon, result, value => {
    checks++; assert.strictEqual(value, result); throw primary;
  }, 7), error => error === primary);
  assert.equal(checks, 1); assert.equal(projects, 1);
  assert.strictEqual(primary.cleanupHandle, cleanupHandle);
  assert.deepEqual((primary as OriginalFailure).primaryDiagnostic, {code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work', task: 7, controlWorkLimit: 100000});
  assert(Object.isFrozen((primary as OriginalFailure).primaryDiagnostic));
  assert.deepEqual(snapshot(primary)!.primaryDiagnostic, (primary as OriginalFailure).primaryDiagnostic);
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
      runtimeFailure({}), () => {throw primary;}, 0), error => error === primary);
    assert.equal((primary as OriginalFailure).primaryDiagnostic, undefined);
  }
  for (const task of [undefined, -1, 1.5, 2147483648]) {
    const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceControlWorkLimit() {return 100000;}},
      runtimeFailure({}), () => {throw primary;}, task), error => error === primary);
    assert.equal((primary as OriginalFailure).primaryDiagnostic, undefined);
  }
});

test('managed advance optional missing throwing or frozen diagnostics preserve every original thrown value', () => {
  for (const primary of [undefined, null, 7, new Error('untyped'),
    Object.freeze(Object.assign(new Error('frozen'), {code: 'MoonBitHostFailure'}))]) {
    for (const moon of [{}, {strategyModule_local_ManagedAdvanceControlWorkLimit() {throw new Error('optional');}},
      {strategyModule_local_ManagedAdvanceControlWorkLimit() {return 100000;}}]) {
      let threw = false;
      try {checkedLocalManagedAdvance(moon, runtimeFailure({}), () => {throw primary;}, 0);}
      catch (error) {threw = true; assert.strictEqual(error, primary);}
      assert.equal(threw, true);
    }
  }
});

test('managed advance never invokes an original thrown code accessor', () => {
  let reads = 0;
  const original = Object.defineProperty(new Error('original'), 'code', {get() {reads++; return 'MoonBitHostFailure';}});
  assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceControlWorkLimit() {return 100000;}},
    runtimeFailure({}), () => {throw original;}, 0), error => error === original);
  assert.equal(reads, 0); assert.equal((original as OriginalFailure).primaryDiagnostic, undefined);
});

test('dispatch snapshot refuses misleading local-work DATA and retains the existing full Model diagnostic', () => {
  const data = {code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work', task: 0, controlWorkLimit: 100000};
  for (const foreign of [{...data, kind: 'execution'}, {...data, controlWorkLimit: undefined}, {...data, controlWorkLimit: -1}, {...data, task: -1}, {...data, task: undefined},
    {...data, unit: 0}, {...data, unit: undefined}, {...data, step: 0}, {...data, code: 'Foreign'}]) {
    assert.equal(snapshot(Object.assign(new Error('original'), {primaryDiagnostic: foreign}))!.primaryDiagnostic, undefined);
  }
  const accessor = Object.defineProperty(new Error('original'), 'primaryDiagnostic', {get() {assert.fail('no getter');}});
  assert.equal(snapshot(accessor)!.primaryDiagnostic, undefined);
  const model = {code: 'MoonBitHostFailure', phase: 'original_model_acquired_effect_evidence',
    kind: 'original_sources.missing', task: 1, unit: 2, step: 3};
  assert.deepEqual(snapshot(Object.assign(new Error('original'), {primaryDiagnostic: model}))!.primaryDiagnostic, model);
});


test('managed advance retains exact value capture work cause step limit receiver and original error', () => {
  const result=runtimeFailure({}),cleanupHandle={},primary=Object.assign(new Error('original'),{code:'MoonBitHostFailure',cleanupHandle});
  let projects=0,checks=0;
  const moon={strategyModule_local_ManagedAdvanceControlWorkLimit(){return undefined;},
    strategyModule_local_ManagedAdvanceCaptureWork(value: unknown){assert.strictEqual(this,moon);assert.strictEqual(value,result);projects++;return Object.assign(Object.create({$tag:1}),{_0:[41,100000]});}};
  assert.throws(()=>checkedLocalManagedAdvance(moon,result,value=>{checks++;assert.strictEqual(value,result);throw primary;},41),error=>error===primary);
  assert.equal(checks,1);assert.equal(projects,1);assert.strictEqual(primary.cleanupHandle,cleanupHandle);
  assert.deepEqual((primary as OriginalFailure).primaryDiagnostic,{code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'value_capture_work',task:41,step:41,workLimit:100000});
  assert(Object.isFrozen((primary as OriginalFailure).primaryDiagnostic));
  assert.deepEqual(snapshot(primary)!.primaryDiagnostic,(primary as OriginalFailure).primaryDiagnostic);
});


test('managed advance capture diagnostic refuses generic malformed and foreign vectors without replacing original failure', () => {
  for(const capture of [undefined,null,[],[41],[41,100000,0],[-1,100000],[41,-1],[41,NaN],[41,'100000'],[2147483648,100000]]){
    const original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'});
    assert.throws(()=>checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCaptureWork(){return Object.assign(Object.create({$tag:1}),{_0:capture});}},runtimeFailure({}),()=>{throw original;},41),error=>error===original);
    assert.equal((original as OriginalFailure).primaryDiagnostic,undefined);
  }
  const accessor=Object.defineProperty([41,100000],'0',{get(){assert.fail('do not invoke capture vector accessors');}});
  const original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'});
  assert.throws(()=>checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCaptureWork(){return Object.assign(Object.create({$tag:1}),{_0:accessor});}},runtimeFailure({}),()=>{throw original;},41),error=>error===original);
  assert.equal((original as OriginalFailure).primaryDiagnostic,undefined);
  const data={code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'value_capture_work',task:41,step:41,workLimit:100000};
  for(const changed of [{...data,workLimit:-1},{...data,step:-1},{...data,unit:0},{...data,controlWorkLimit:100000}])assert.equal(snapshot(Object.assign(new Error('original'),{primaryDiagnostic:changed}))!.primaryDiagnostic,undefined);
});


test('capture work getter uses the actual pinned boxed Option and refuses an unboxed replacement', () => {
  // Exact boxed Some/None layout is witnessed at the original 7d1 export;
  // these are compiler DATA fixtures, not issued request or resource values.
  const boxed=Object.assign(Object.create({$tag:1}),{_0:[41,100000]}), result=runtimeFailure({});
  for(const [returned,expected]of [[boxed,true],[Object.create({$tag:0}),false],[[41,100000],false]]){
    const original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'});
    let calls=0;const moon={strategyModule_local_ManagedAdvanceCaptureWork(originalResult: unknown){assert.strictEqual(this,moon);assert.strictEqual(originalResult,result);calls++;return returned;}};
    assert.throws(()=>checkedLocalManagedAdvance(moon,result,()=>{throw original;},41),error=>error===original);
    assert.equal(calls,1);
    if(expected)assert.deepEqual((original as OriginalFailure).primaryDiagnostic,{code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'value_capture_work',task:41,step:41,workLimit:100000});
    else assert.equal((original as OriginalFailure).primaryDiagnostic,undefined);
  }
});


test('managed failure snapshot preserves original diagnostic through the existing owned primary wrapper only', () => {
  const source=readFileSync(new URL('../host-common/managed-failure.mjs',import.meta.url),'utf8');
  const body=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body;
  const memberNode=body.flatMap(value=>value.type==='VariableDeclaration'?value.declarations:[]).find(value=>(value.id as Identifier).name==='member')!;
  const factory=body.find(value=>value.type==='FunctionDeclaration'&&value.id!.name==='ownedFailure')!;
  const member=Function('return ('+source.slice(memberNode.init!.start,memberNode.init!.end)+');')();
  const owned=Function('member','return ('+source.slice(factory.start,factory.end)+');')(member);
  const original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'}),result=runtimeFailure({});
  assert.throws(()=>checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCaptureWork(){return Object.assign(Object.create({$tag:1}),{_0:[41,100000]});}},result,()=>{throw original;},41),error=>error===original);
  const wrapper=owned(original,'ManagedExecutionFailed'),cleanupHandle={original:'same-cleanup'};
  wrapper.cleanupHandle=cleanupHandle;
  assert.notStrictEqual(wrapper,original);assert.strictEqual(wrapper.primaryFailure,original);assert.strictEqual(wrapper.cause,original);
  assert.deepEqual(snapshot(wrapper)!.primaryDiagnostic,(original as OriginalFailure).primaryDiagnostic);
  assert.strictEqual(wrapper.cleanupHandle,cleanupHandle);assert.equal(wrapper.code,original.code);assert.deepEqual(wrapper.cleanupErrors,[]);
});

test('managed failure diagnostic wrapper lookup never traverses getters cause chains or recursive primary slots', () => {
  const data=Object.freeze({code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'value_capture_work',task:41,step:41,workLimit:100000});
  const original=Object.defineProperty(new Error('original'),'primaryDiagnostic',{value:data});
  const self: {primaryFailure?: object}={};self.primaryFailure=self;
  for(const value of [self,{cause:original},{primaryFailure:{primaryFailure:original}},
    Object.defineProperty({},'primaryFailure',{get(){assert.fail('no primary getter');}}),
    {primaryFailure:Object.defineProperty({},'primaryDiagnostic',{get(){assert.fail('no diagnostic getter');}})},
    Object.defineProperty({primaryFailure:original},'primaryDiagnostic',{get(){assert.fail('no outer getter or fallback');}})])assert.equal(snapshot(value)!.primaryDiagnostic,undefined);
  assert.equal(snapshot({primaryFailure:undefined})!.primaryDiagnostic,undefined);
});

const some = (value: unknown) => Object.assign(Object.create({$tag: 1}), {_0: value});
// Explicit test-port DATA; the separate compiled Core test qualifies the ABI.
const budgetTuple = (fields: readonly unknown[]) => Object.fromEntries(fields.map((value, index) => [`_${index}`, value]));

test('original managed budget quantities reach the existing public message with the correct setting and units', () => {
  for (const dimension of ['retained_bytes', 'execution_bytes', 'value_capture_work']) {
    const result = runtimeFailure({}), primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    const work = dimension === 'value_capture_work';
    const moon = {
      strategyModule_local_ManagedAdvanceResourceDimension: () => work ? undefined : dimension,
      strategyModule_local_ManagedAdvanceCaptureWork: () => some([41, 100]),
      strategyModule_local_ManagedAdvanceBudget(value: unknown) {
        assert.strictEqual(this, moon); assert.strictEqual(value, result);
        return budgetTuple([dimension, !work, 8n, 7n, 100n]);
      },
    };
    assert.throws(() => checkedLocalManagedAdvance(moon, result, value => {
      assert.strictEqual(value, result); throw primary;
    }, 41), error => error === primary);
    const selected = snapshot(primary)!.primaryDiagnostic!;
    assert.deepEqual(selected.budget, {requested: '8', remaining: '7', policy: '100', requestedIsLowerBound: work});
    const message = publicBudgetMessage(primary)!;
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
    }, runtimeFailure({}), () => {throw primary;}, 4), error => error === primary);
    assert.equal(snapshot(primary)!.primaryDiagnostic!.budget, undefined);
    const message = publicBudgetMessage(primary)!;
    assert(message.includes('requested_delta=unavailable; remaining=unavailable; policy=unavailable;'));
    assert(!message.includes('private'));
  }
  const invalid = Object.assign(new Error('original'), {primaryDiagnostic: {
    code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'resource', task: 4,
    dimension: 'retained_bytes', budget: {get requested() {return assert.fail('no getter');},
      remaining: '0', policy: '100', requestedIsLowerBound: false},
  }});
  assert.equal(snapshot(invalid)!.primaryDiagnostic!.budget, undefined);
});

test('same failed Run and exact control frame retain the first budget message without granting state or cleanup', () => {
  const primary = {primaryDiagnostic: {code: 'MoonBitHostFailure', phase: 'local_managed_advance',
    kind: 'resource', task: 4, dimension: 'retained_bytes',
    budget: {requested: '19', remaining: '7', policy: '512', requestedIsLowerBound: false}}};
  const message = publicBudgetMessage(primary)!;
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

test('original failed retirement publishes only after cleanup and fences callback reentry before returning the parent', () => {
  for (const callback of ['reenter', 'new-pending', 'replace-entry']) {
    let parentReturns = 0, publications = 0;
    const ref = {runDefinitionCid: 'original'};
    const frame = {physicalCloseConfirmed: true, observedTerminalOutcome: 'failed',
      runDefinition: {}, resultNames: ['answer'], dispatchReserved: true, preDispatchFailureConfirmed: false};
    type Entry = Parameters<ReturnType<typeof createClientDispatchCleanup<typeof ref, typeof frame>>['retire']>[0];
    const entry: Entry = {ref, settled: true, physicalStarted: true, stopObserved: true,
      primaryFailure: {primaryDiagnostic: {code: 'MoonBitHostFailure', phase: 'local_managed_advance',
        kind: 'resource', task: 4, dimension: 'retained_bytes'}},
      retirePreparation() {parentReturns++;}};
    const entries = new Map<string, Entry>([['original', entry]]);
    const unused = () => assert.fail('Retirement cannot perform new physical work');
    const {retire} = createClientDispatchCleanup({
      entries, keyOf: value => value.runDefinitionCid,
      control: {runDefinitionRunId: () => 'original-run'},
      now: () => '2026-11-14T00:00:00.000Z',
      moon: {strategyHostStop: unused, strategyHostCloseOutputs: unused,
        strategyHostUsage: unused, strategyHostRun: unused,
        clientProgramIssueControlledUnpublishedRunState: () => ({
          $tag: 1, _0: JSON.stringify({status: 'failed',
            terminal_error: {code: 'ACTQL_E_UNPUBLISHED_RUN', message: 'Run ended before publication'}}),
        })},
      journal: {markPreDispatchFailure: unused,
        lookupRunDefinition(value) {assert.strictEqual(value, ref); return frame;},
        publishRunState(original, state) {
          publications++; assert.strictEqual(original, frame);
          assert.equal(state.status, 'failed'); assert.equal(state.terminal_error?.code, 'ACTQL_E_UNPUBLISHED_RUN');
          assert(typeof state.terminal_error?.message === 'string');
          assert(state.terminal_error.message.includes('dimension=retained_bytes'));
          retire(entry); assert.equal(parentReturns, 0, 'No parent return inside the diagnostic callback');
          if (callback === 'new-pending') entry.cleanupOwner = {close: unused, cleanup: unused, cleanupPending: unused};
          if (callback === 'replace-entry') entries.set('original', {ref});
        }},
      async observeStop() {unused();},
      diagnostic: unused, resourceUsage: unused,
    });
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
const hostInstaller = embeddedTree.body.find(value => value.type === 'FunctionDeclaration' && value.id!.name === 'openInstalledHost');
const findObserve = (value: unknown): AnyNode | null | undefined => {
  if (!value || typeof value !== 'object') return undefined;
  if ((value as VariableDeclarator).type === 'VariableDeclarator' && ((value as VariableDeclarator).id as Identifier | undefined)?.name === 'observeRun') return (value as VariableDeclarator).init;
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
      lookupRunDefinition(value: unknown) {assert.strictEqual(value, ref); attempts++; return frame;},
      observeRunCancellation(value: unknown, originalMoon: unknown, originalControl: unknown, retained: unknown) {
        assert.strictEqual(value, ref); assert.strictEqual(retained, frame);
        return () => ({revision: mode === 'changed-frame' && attempts === 1 ? 5 : 4});
      },
      publishRunState(retained: unknown, state: PublishedFailure) {
        assert.strictEqual(retained, frame); projections++;
        const expected = mode === 'failed' || mode === 'changed-frame' ? message : originalState.terminal_error.message;
        assert.equal(state.terminal_error.message, expected);
        assert.equal(state.status, status);
        return JSON.stringify(state);
      },
    };
    const observe: (input: {ref: typeof ref; principalId: string}) => Promise<PublishedFailure> = Function('principalId', 'namespaceId', 'authorityScopeCid', 'journal', 'moon', 'control',
      'observeAuthorizedRunState', 'stateService', 'checkpoints', 'dispatchOwner', 'modelResumeFlights',
      'issueInstalledUnpublishedRunState', 'now', 'projectRunObservation', 'clientOperationError',
      `return (${embeddedSource.slice(observeNode.start, observeNode.end)});`)(
      'principal', 'namespace', 'authority', journal, {}, {runDefinitionRunId: () => 'run'},
      async () => undefined, {}, undefined, {
        live: () => mode === 'running',
        credentialRefusalPending(value: unknown) {assert.strictEqual(value, ref); return false;},
        failureMessage(value: unknown) {assert.strictEqual(value, ref); diagnosticReads++; return mode === 'retired-entry' ? undefined : message;},
      }, new Map(), () => ({...originalState}), () => 'now', () => {}, (code: string) => new Error(code));
    const observed = await observe({ref, principalId: 'principal'});
    assert.equal(observed.status, status); assert.equal(projections, 1);
    assert.equal(attempts, mode === 'changed-frame' ? 2 : 1);
    assert.equal(diagnosticReads, ['failed', 'changed-frame', 'retired-entry'].includes(mode) ? 1 : 0);
    await assert.rejects(observe({ref, principalId: 'foreign'}), /RunStateAccessDenied/u);
  }
});

test('Relation snapshot errors use the same failed-result budget projector and preserve the original Unit failure',()=>{
  const text=readFileSync(new URL('./strategy-bundle.mjs',import.meta.url),'utf8');
  const parsed=parse(text,{ecmaVersion:'latest',sourceType:'module'});let call!: CallExpression;
  const visit=(node: unknown)=>{if(!node||typeof node!=='object')return;
    if((node as CallExpression).type==='CallExpression'&&((node as CallExpression).callee as Identifier | undefined)?.name==='prepareLocalRelationSnapshot')call=node as CallExpression;
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(visit);else visit(value);
  };visit(parsed);assert(call);const callback=call.arguments[2];
  assert.equal(callback.type,'ArrowFunctionExpression');
  const unitFailure=Object.freeze(runtimeFailure({original:'same failed Unit result'}));
  const primary=Object.assign(new Error('original reload refusal'),{code:'MoonBitHostFailure'});
  const moon={strategyModule_local_ManagedAdvanceResourceDimension(result: unknown){
    assert.strictEqual(result,unitFailure);return 'execution_bytes';
  },strategyModule_local_ManagedAdvanceBudget(result: unknown){
    assert.strictEqual(result,unitFailure);return budgetTuple(['execution_bytes',true,268840096n,268840095n,1073741824n]);
  }};
  const observed=Function('checkedLocalManagedAdvance','moon','checked','prepared',
    `return (${text.slice(callback.start,callback.end)});`)(checkedLocalManagedAdvance,moon,
      (result: unknown)=>{assert.strictEqual(result,unitFailure);throw primary;},{task:41});
  assert.throws(()=>observed(unitFailure),error=>error===primary);
  assert.match(publicBudgetMessage(primary)!,/requested_delta=268840096; remaining=268840095; policy=1073741824;/u);
  assert.match(publicBudgetMessage(primary)!,/setting=installation.requestMemory.executionBytes/u);
});


test('managed original nonrow cause copies only Core DATA and preserves the original checked failure', () => {
  const result = runtimeFailure({}), cleanup = {}, primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure', cleanup});
  let checks = 0, causes = 0, steps = 0;
  const moon = {
    strategyModule_local_ManagedAdvanceCause(value: unknown) {assert.strictEqual(this, moon); assert.strictEqual(value, result); causes++; return 'sequence.input_limit';},
    strategyModule_local_ManagedAdvanceRowStep(value: unknown) {assert.strictEqual(this, moon); assert.strictEqual(value, result); steps++; return -1;},
  };
  assert.throws(() => checkedLocalManagedAdvance(moon, result, value => {assert.strictEqual(value, result); checks++; throw primary;}, 42), error => error === primary);
  assert.equal(checks, 1); assert.equal(causes, 1); assert.equal(steps, 1); assert.strictEqual(primary.cleanup, cleanup);
  assert.deepEqual(snapshot(primary)!.primaryDiagnostic, {code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'local_issue', task: 42, cause: 'sequence.input_limit'});
  assert.equal(publicBudgetMessage(primary), 'Execution failed: phase=local_managed_advance; task=42; cause=sequence.input_limit. Original execution failure; resource quantities were not retained.');
});

test('managed original nonrow cause never overrides preferred row resource or work DATA', () => {
  for (const [project, expected] of [
    [{strategyModule_local_ManagedAdvanceResourceDimension: () => 'execution_bytes'}, 'resource'],
    [{strategyModule_local_ManagedAdvanceControlWorkLimit: () => 100}, 'control_work'],
  ] as const) {
    const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({...project,
      strategyModule_local_ManagedAdvanceCause() {assert.fail('preferred original diagnostic');},
      strategyModule_local_ManagedAdvanceRowStep: () => -1}, runtimeFailure({}), () => {throw primary;}, 42), error => error === primary);
    assert.equal(snapshot(primary)!.primaryDiagnostic!.kind, expected);
  }
  const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
  assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCause: () => 'rows.row_limit',
    strategyModule_local_ManagedAdvanceRowStep: () => 9}, runtimeFailure({}), () => {throw primary;}, 42), error => error === primary);
  assert.equal(snapshot(primary)!.primaryDiagnostic!.kind, 'row_failure');
  assert.equal(snapshot(primary)!.primaryDiagnostic!.step, 9);
});

test('managed nonrow optional projections preserve malformed foreign frozen and absent originals', () => {
  for (const [cause, step] of [[undefined, -1], ['private input', -1], ['x'.repeat(97), -1], ['compute.invalid_limits', -2], ['compute.invalid_limits', undefined]]) {
    const primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCause: () => cause,
      strategyModule_local_ManagedAdvanceRowStep: () => step}, runtimeFailure({}), () => {throw primary;}, 42), error => error === primary);
    assert.equal(snapshot(primary)!.primaryDiagnostic, undefined);
  }
  for (const primary of [undefined, new Error('foreign'), Object.freeze(Object.assign(new Error('frozen'), {code: 'MoonBitHostFailure'}))]) {
    for (const project of [() => 'compute.invalid_limits', () => {throw new Error('optional');}]) {
      let threw = false;
      try {checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceCause: project,
        strategyModule_local_ManagedAdvanceRowStep: () => -1}, runtimeFailure({}), () => {throw primary;}, 42);}
      catch (error) {threw = true; assert.strictEqual(error, primary);}
      assert.equal(threw, true);
    }
  }
});

test('managed nonrow retained message stays bound to the original failed confirmed-stop Journal frame', () => {
  const message = 'Execution failed: phase=local_managed_advance; task=42; cause=capture.capture_limit. Original execution failure; resource quantities were not retained.';
  const control = {physical_stop: 'confirmed', revision: 1};
  const state = {run_id: 'original', status: 'failed', result_available: false, next_action: {kind: 'none'},
    terminal_error: {code: 'ACTQL_E_UNPUBLISHED_RUN', message}, control};
  const key = JSON.stringify(state);
  assert.equal(retainedBudgetMessage(key, state, 'original', control), message);
  for (const changed of [{...control, physical_stop: 'unknown'}, {...control, revision: 2}]) assert.equal(retainedBudgetMessage(key, state, 'original', changed), undefined);
  assert.equal(retainedBudgetMessage(key, {...state, status: 'running'}, 'original', control), undefined);
  assert.equal(retainedBudgetMessage(key, state, 'foreign', control), undefined);
  for (const bad of [message + ' private', message.replace('task=42', 'task=2147483648'), message.replace('capture.capture_limit', 'private input')]) {
    assert.equal(retainedBudgetMessage(JSON.stringify({...state, terminal_error: {...state.terminal_error, message: bad}}), state, 'original', control), undefined);
  }
  const data = {code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'local_issue', task: 42, cause: 'sequence.input_limit'};
  for (const extra of [{step: -1}, {dimension: 'execution_bytes'}, {budget: {}}, {get cause() {return assert.fail('no getter');}}]) {
    const invalid = Object.defineProperties({...data}, Object.getOwnPropertyDescriptors(extra));
    assert.equal(snapshot({primaryDiagnostic: invalid})!.primaryDiagnostic, undefined);
  }
});

test('logical work keeps Core selected policy and setting through the same failure and cold observation', () => {
  for (const [policy, setting] of [[20000000n, 'installation.sourceFreeMaxWork'], [10000000n, 'unavailable'], [20000000n, 'unavailable']]) {
    const result = runtimeFailure({}), primary = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    let calls = 0;
    const moon = {strategyModule_local_ManagedAdvanceLogicalWorkPolicy(value: unknown) {
      calls++; assert.strictEqual(this, moon); assert.strictEqual(value, result);
      return budgetTuple([43, policy, setting]);
    }};
    assert.throws(() => checkedLocalManagedAdvance(moon, result, () => {throw primary;}, 43), error => error === primary);
    assert.equal(calls, 1);
    assert.deepEqual(snapshot(primary)!.primaryDiagnostic, {code:'MoonBitHostFailure',phase:'local_managed_advance',kind:'logical_work',task:43,step:43,workLimit:String(policy),setting});
    const message = publicBudgetMessage(primary)!;
    assert(message.includes(`dimension=logical_work; requested_delta=unavailable; remaining=unavailable; policy=${policy}; unit=work_units; setting=${setting}.`));
    const state = {status:'failed',terminal_error:{code:'ACTQL_E_UNPUBLISHED_RUN',message}};
    const control = {physical_stop:'confirmed'};
    const key = JSON.stringify({...state,run_id:'original',result_available:false,next_action:{kind:'none'},control});
    assert.equal(retainedBudgetMessage(key, state, 'original', control), message);
    assert.equal(retainedBudgetMessage(key, state, 'other', control), undefined);
    assert.equal(retainedBudgetMessage(key, state, 'original', {physical_stop:'unknown'}), undefined);
  }
});

test('logical work optional malformed frozen and throwing projections preserve the original error', () => {
  for (const project of [undefined, () => {throw new Error('projection');},
    () => budgetTuple([-1, 20n, 'installation.sourceFreeMaxWork']),
    () => budgetTuple([43, -1n, 'installation.sourceFreeMaxWork']),
    () => budgetTuple([43, 20n, 'invented.setting']),
    () => budgetTuple([43, 9223372036854775808n, 'unavailable'])]) {
    for (const frozen of [false, true]) {
      const result=runtimeFailure({}), original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'});
      if(frozen)Object.freeze(original);
      assert.throws(()=>checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceLogicalWorkPolicy:project},result,()=>{throw original;},43),error=>error===original);
      assert.equal((original as OriginalFailure).primaryDiagnostic,undefined);
    }
  }
  const result=runtimeFailure({}), original=Object.assign(new Error('original'),{code:'MoonBitHostFailure'});
  const moon={strategyModule_local_ManagedAdvanceResourceDimension:()=> 'retained_bytes',
    strategyModule_local_ManagedAdvanceLogicalWorkPolicy(){assert.fail('Original resource diagnostic has priority');}};
  assert.throws(()=>checkedLocalManagedAdvance(moon,result,()=>{throw original;},43),error=>error===original);
  assert.equal(snapshot(original)!.primaryDiagnostic!.dimension,'retained_bytes');
});
