// Scheduling contract for the split Client gate. These are the existing
// acceptance commands, not a replacement acceptance oracle.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {types as nodeTypes} from 'node:util';
import './two-source-optional-effect.test.mjs';
import './composition-release-input.test.mjs';
import './table-ctas-result-controls.test.mjs';
import './packed-original-submission-callers.test.mjs';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {optionalEffectCases} from './fixtures/two-source-optional-effect.mjs';
import {compositionProgram, compositionTemplate, compositionExpectations, compositionText, compositionTextTemplate,
  publicFixtureEnvironment} from
  './fixtures/composed-infer-effect-input.mjs';
import {configuration as inferConfiguration, canonical as inferCanonical, cid as inferCid} from
  './fixtures/installed-infer-fixture.mjs';
import {selectInstalledHostEnvironment, selectInstalledLocalMaterializationEnvironment} from
  '../adapters/host-node/installed-host-policy.mjs';
import {composeInstalledCheckEnvironment} from '../adapters/host-node/installed-check-environment.mjs';
import {contentCid} from '../adapters/host-node/local-account-config.mjs';
import {inferPreparationFailureData} from './fixtures/packed-infer-preparation-diagnostic.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const {jobs} = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const normal = "${{ github.event.repository.visibility == 'public' && toJSON(github.event.repository.private) == 'false' && !inputs.performance_matrix && !inputs.packed_query_evidence_probe && needs.select-targets.outputs.profile == 'full' }}";
const groups = ['client-packages', 'client-distribution', 'client-distribution-callers', 'client-distribution-mutations', 'client-distribution-packed', 'client-distribution-native', 'client-packed', 'client-packed-composition', 'client-salesforce'];
const consumers = ['client-distribution', 'client-distribution-callers',
  'client-distribution-mutations', 'client-distribution-packed', 'client-packed', 'client-packed-composition'];
const runs = name => jobs[name].steps.filter(step => step.run).map(step => step.run.trim());
const run = (script, env) => spawnSync('bash', ['-eo', 'pipefail', '-c', script], {
  cwd: root, env: {...process.env, ...env}, encoding: 'utf8',
});

test('packed INFER original preparation evidence excludes opaque values getters and proxy traps', () => {
  const project = inferPreparationFailureData;
  let getterReads = 0;
  const cause = {$tag: 3};
  Object.defineProperty(cause, 'message', {get() {getterReads++; throw new Error('private');}});
  const detail = {boundary: 'model_execution', code: 'MoonBitHostFailure', typedCause: 'InvalidInput',
    cause, privateInput: 'never disclose'};
  assert.deepEqual(project(detail), {boundary: 'model_execution', code: 'MoonBitHostFailure',
    typedCause: 'InvalidInput', issueTag: 3});
  assert(Object.isFrozen(project(detail)));
  const accessor = {boundary: 'model_provider'};
  for (const key of ['code', 'typedCause', 'cause']) Object.defineProperty(accessor, key,
    {get() {getterReads++; throw new Error('private');}});
  assert.deepEqual(project(accessor), {boundary: 'model_provider'});
  const proxy = new Proxy({}, {get() {getterReads++; throw new Error('private');},
    getOwnPropertyDescriptor() {getterReads++; throw new Error('private');}});
  assert.equal(project(proxy), undefined);
  assert.deepEqual(project({boundary: 'model_provider', cause: proxy}), {boundary: 'model_provider'});
  assert.equal(project({boundary: 'private-business-input'}), undefined);
  assert.deepEqual(project({boundary: 'model_execution', code: 'not a typed code',
    typedCause: 'x'.repeat(129), cause: {$tag: -1}}), {boundary: 'model_execution'});
  assert.equal(getterReads, 0);
});

test('packed INFER dispatch evidence retains only original code and tags without observing opaque fields', () => {
  const script = readFileSync(new URL('./fixtures/packed-single-infer.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(script, {ecmaVersion: 'latest', sourceType: 'module'});
  const definition = tree.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'inferDispatchFailureData');
  assert(definition);
  const project = new Function('nodeTypes', script.slice(definition.start, definition.end) +
    ';return inferDispatchFailureData;')(nodeTypes);
  let reads = 0;
  const detail = {code: 'MoonBitHostFailure', primaryCode: 'NodeManagedRunRuntimeUnavailable',
    issueTag: 7, nestedIssueTag: 2, ref: {private: true}, input: 'never disclose'};
  for (const key of ['message', 'stack', 'cause']) Object.defineProperty(detail, key,
    {get() {reads++; throw new Error('private');}});
  assert.deepEqual(project(detail), {code: 'MoonBitHostFailure',
    primaryCode: 'NodeManagedRunRuntimeUnavailable', issueTag: 7, nestedIssueTag: 2});
  assert(Object.isFrozen(project(detail)));
  const accessors = {};
  for (const key of ['code', 'primaryCode', 'issueTag', 'nestedIssueTag']) Object.defineProperty(accessors, key,
    {get() {reads++; throw new Error('private');}});
  assert.equal(project(accessors), undefined);
  const proxy = new Proxy({}, {get() {reads++; throw new Error('private');},
    getOwnPropertyDescriptor() {reads++; throw new Error('private');}});
  assert.equal(project(proxy), undefined);
  assert.equal(project({code: 'not a typed code', primaryCode: 'x'.repeat(129),
    issueTag: -1, nestedIssueTag: 65536}), undefined);
  assert.equal(reads, 0);
});

test('packed INFER terminal failure context excludes Run references rows and opaque values', () => {
  const script = readFileSync(new URL('./fixtures/packed-single-infer.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(script, {ecmaVersion: 'latest', sourceType: 'module'});
  const definition = tree.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'inferTerminalFailureData');
  assert(definition);
  const project = new Function('nodeTypes', script.slice(definition.start, definition.end) +
    ';return inferTerminalFailureData;')(nodeTypes);
  let reads = 0;
  const terminal = {status: 'failed', next_action: {kind: 'none'},
    terminal_error: {code: 'ACTQL_E_UNPUBLISHED_RUN'}, run_id: 'never disclose',
    ref: {private: true}, rows: ['never disclose']};
  for (const key of ['message', 'stack', 'cause']) Object.defineProperty(terminal, key,
    {get() {reads++; throw new Error('private');}});
  assert.deepEqual(project(terminal), {status: 'failed', nextAction: 'none',
    terminalCode: 'ACTQL_E_UNPUBLISHED_RUN'});
  const proxy = new Proxy({}, {getOwnPropertyDescriptor() {reads++; throw new Error('private');}});
  assert.deepEqual(project(proxy), {});
  assert.deepEqual(project({status: 'failed', next_action: proxy, terminal_error: proxy}),
    {status: 'failed'});
  const accessors = {};
  for (const key of ['status', 'next_action', 'terminal_error']) Object.defineProperty(accessors, key,
    {get() {reads++; throw new Error('private');}});
  assert.deepEqual(project(accessors), {});
  assert.equal(reads, 0);
});

test('Effect fixture diagnostics preserve original throws and avoid opaque values', () => {
  const script = readFileSync(new URL('../adapters/host-node/fixtures/installed-row-effect.fixture.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(script, {ecmaVersion: 'latest', sourceType: 'module'});
  const host = tree.body.find(node => node.type === 'ExportNamedDeclaration' && node.declaration?.id?.name === 'effectHost');
  const definition = host.declaration.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'prepareDefinition'));
  assert(definition);
  const instantiate = new Function('prepareInstalledEffectManagedPlanRun', 't', 'nodeTypes',
    'const funded={manager:{}}, managedRuns={}, liveManagedRuns={}, moon={}, requests=new Map(),' +
    'installed={}, registry={}, values={}, installedContracts={}, assertCurrent=()=>{}, checked=x=>x;' +
    script.slice(definition.start, definition.end) + ';return prepareDefinition;');
  let reads = 0;
  const original = Object.assign(new Error('private'), {code: 'MoonBitHostFailure', cause: {$tag: 7}});
  for (const name of ['message', 'stack']) Object.defineProperty(original, name,
    {get() {reads++; throw new Error('private');}});
  const proxy = new Proxy({}, {getOwnPropertyDescriptor() {reads++; throw new Error('private');}});
  for (const cause of [original, undefined, proxy]) {
    for (const diagnosticThrows of [false, true]) {
      let calls = 0;
      const diagnostics = [];
      const prepare = instantiate(() => {calls++; throw cause;}, {diagnostic(value) {
        diagnostics.push(JSON.parse(value));
        if (diagnosticThrows) throw new Error('authored diagnostic failure');
      }}, nodeTypes);
      let rejected = false;
      try {prepare({prepared: {}, identity: {}});} catch (observed) {
        rejected = true;
        assert.equal(observed, cause);
      }
      assert(rejected);
      assert.equal(calls, 1);
      assert.deepEqual(diagnostics, [{phase: 'effect_definition_preparation',
        ...(cause === original ? {code: 'MoonBitHostFailure', issueTag: 7} : {}),
        limitsObserved: false}]);
    }
  }
  assert.equal(reads, 0);
});

test('packed INFER keeps at most its first original admission event in existing stderr evidence', () => {
  const script = readFileSync(new URL('./fixtures/packed-single-infer.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(script, {ecmaVersion: 'latest', sourceType: 'module'});
  const assignment = tree.body.find(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' &&
    node.expression.left.object?.name === 'authorization' &&
    node.expression.left.property?.name === 'observe');
  assert(assignment);
  const lines = [], detail = Object.freeze({boundary: 'model_provider'});
  const observe = new Function('authorization', 'inferPreparationFailureData', 'inferDispatchFailureData', 'console',
    'let inferFailureObserved=false,dispatchFailureObserved=false;const calls=0,inferFailureObservations=[];' + script.slice(assignment.start, assignment.end) +
    ';return authorization.observe;')({}, value => {
    assert.equal(value, detail); return value;
  }, value => ({code: value.code, issueTag: value.issueTag}), {error: line => lines.push(line)});
  observe('other_event', detail);
  observe('infer_preparation_rejected', detail);
  observe('infer_preparation_rejected', detail);
  observe('dispatch_failed', {code: 'MoonBitHostFailure', issueTag: 7});
  observe('dispatch_failed', {code: 'second', issueTag: 8});
  assert.deepEqual(lines.map(line => JSON.parse(line)),
    [{event: 'infer_preparation_rejected', boundary: 'model_provider'},
      {event: 'dispatch_failed', code: 'MoonBitHostFailure', issueTag: 7, calls: 0}]);
});

function packedEffectDriverSource() {
  const source = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  let template;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.name === 'writeFile' &&
        node.arguments[0]?.type === 'CallExpression' &&
        node.arguments[0].arguments.some(value => value.value === 'effect-run.mjs')) {
      assert.equal(template, undefined); template = node.arguments[1];
    }
    for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  };
  visit(parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(template.expressions.length, 0);
  return template.quasis[0].value.cooked;
}

test('packed pending composition reports its last original status without hiding the wait failure', async () => {
  const driver = packedEffectDriverSource();
  let branch;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && node.test.type === 'Identifier' &&
        node.test.name === 'pendingScratch') {assert.equal(branch, undefined); branch = node;}
    for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  };
  visit(parseJavaScript(driver, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(branch);
  const run = new Function('execution', 'waitFor', 'console',
    'return (async()=> ' + driver.slice(branch.consequent.start, branch.consequent.end) + ')();');
  for (const status of ['running', 'failed', 'needs_reconciliation']) {
    for (const primary of [new Error('original wait failure'), undefined]) {
      const lines = []; let reads = 0, rejected = false;
      try {
        await run({async status() {reads++; return {status, privateInput: 'never disclose'};}},
          async check => {assert.equal(await check(), false); throw primary;},
          {error: line => lines.push(line)});
      } catch (error) {rejected = true; assert.strictEqual(error, primary);}
      assert(rejected); assert.equal(reads, 1);
      assert.equal(lines.length, 1);
      assert.deepEqual(JSON.parse(lines[0].slice('packed composition wait '.length)), {
        boundary: 'pending-composition-wait', status, expectedStatus: 'waiting_checkpoint',
      });
      assert(!lines[0].includes('never disclose'));
    }
  }
  await run({async status() {return {status: 'waiting_checkpoint'};}},
    async check => assert.equal(await check(), true),
    {error() {assert.fail('successful waiting must not report a failure');}});
});

test('packed composition retains the first original Model admission event in command stderr', () => {
  const driver = packedEffectDriverSource();
  const tree = parseJavaScript(driver, {ecmaVersion: 'latest', sourceType: 'module'});
  const assignment = tree.body.find(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' &&
    node.expression.left.object?.name === 'authorization' &&
    node.expression.left.property?.name === 'observe');
  assert(assignment);
  const lines = [];
  const observe = new Function('authorization', 'inferPreparationFailureData', 'console', 'appendFileSync',
    'let inferPreparationFailureObserved=false;const resumeFailures=[];const optionalKind=undefined;' +
    driver.slice(assignment.start, assignment.end) + ';return authorization.observe;')(
      {}, inferPreparationFailureData, {error: line => lines.push(line)},
      () => assert.fail('Model preparation diagnostics must not write custody or business files'));
  observe('unrelated', {});
  observe('infer_preparation_rejected', {boundary: 'private-input'});
  observe('infer_preparation_rejected', {boundary: 'model_execution', code: 'MoonBitHostFailure',
    typedCause: 'missing_body', cause: {$tag: 3}, ref: 'private', input: ['private']});
  observe('infer_preparation_rejected', {boundary: 'model_dependencies', code: 'later'});
  assert.deepEqual(lines.map(line => JSON.parse(line)), [{event: 'infer_preparation_rejected',
    boundary: 'model_execution', code: 'MoonBitHostFailure', typedCause: 'missing_body', issueTag: 3}]);
});

test('both packed Model consumers copy their shared diagnostic without a checkout fallback', async () => {
  const name = 'packed-infer-preparation-diagnostic.mjs';
  for (const file of ['test-packed-single-infer.mjs', 'test-packed-salesforce-source.mjs']) {
    const source = readFileSync(new URL(file, import.meta.url), 'utf8');
    let loop, writer;
    const visit = node => {
      if (!node || typeof node !== 'object') return;
      if (node.type === 'ForOfStatement' && node.right.type === 'ArrayExpression' &&
          node.right.elements.some(value => value?.value === name)) loop = node;
      for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    };
    visit(parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}));
    assert(loop, file);
    const findWriter = node => {
      if (!node || typeof node !== 'object') return;
      if (node.type === 'AwaitExpression' && node.argument.type === 'CallExpression' &&
          node.argument.callee.name === 'writeFile') writer = node;
      for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(findWriter);
      else if (value && typeof value === 'object') findWriter(value);
    };
    findWriter(loop.body); assert(writer, file);
    const scratch = mkdtempSync(join(tmpdir(), 'actql-packed-diagnostic-'));
    try {
      const copy = new Function('root', 'repository', 'join', 'writeFile', 'readFile', 'name',
        'return (async()=>{' + source.slice(writer.start, writer.end) + ';})();');
      await copy(scratch, root, join, writeFile, readFile, name);
      assert.equal(readFileSync(join(scratch, name), 'utf8'),
        readFileSync(new URL('./fixtures/' + name, import.meta.url), 'utf8'));
      const copied = await import(pathToFileURL(join(scratch, name)).href);
      assert.deepEqual(copied.inferPreparationFailureData({boundary: 'model_provider', code: 'Original'}),
        {boundary: 'model_provider', code: 'Original'});
    } finally {rmSync(scratch, {recursive: true, force: true});}
  }
});

test('packed INFER metadata uses the same installed Local policy without reidentifying its Model', async () => {
  const script=readFileSync(new URL('./test-packed-single-infer.mjs',import.meta.url),'utf8');
  const tree=parseJavaScript(script,{ecmaVersion:'latest',sourceType:'module'});
  let writer;
  const declarations = new Map();
  (function visit(node){if(!node||typeof node!=='object')return;
    if(node.type==='VariableDeclaration'&&node.declarations.length===1&&
        ['baseEnvironment','hostCapacityPolicy'].includes(node.declarations[0].id?.name)){
      const name=node.declarations[0].id.name;
      assert.equal(declarations.has(name),false);declarations.set(name,node);
    }
    if(node.type==='CallExpression'&&node.callee.name==='writeFile'&&
        node.arguments[0]?.type==='CallExpression'&&node.arguments[0].callee.name==='join'&&
        node.arguments[0].arguments.some(arg=>arg.type==='Literal'&&arg.value==='base-environment.json')){
      assert.equal(writer,undefined);writer=node;
    }
    for(const value of Object.values(node))if(Array.isArray(value))value.forEach(visit);
    else if(value&&typeof value==='object')visit(value);
  })(tree);assert(writer);
  const wire=readFileSync(new URL('../spec/local-check-environment.json',import.meta.url),'utf8');
  const originalPolicy=Object.freeze({}), moon={
    clientLocalResourcePolicyOriginal(){return originalPolicy;},
    clientLocalResourcePolicyRowCeiling(value){assert.equal(value,originalPolicy);return 203;},
    clientLocalResourcePolicyModelRequestByteCeiling(value){assert.equal(value,originalPolicy);return 65536n;},
    clientProgramCheckEnvironment(value,cid){assert.equal(JSON.parse(value).evidence_bundle_cid,cid);return {};},
  };
  const actualHost=selectInstalledLocalMaterializationEnvironment(moon,wire.trimEnd(),
    JSON.parse(wire).host_policy_profile.capacity);
  assert.notEqual(JSON.parse(actualHost).host_policy_profile.capacity.max_model_request_bytes_per_item,
    JSON.parse(selectInstalledLocalMaterializationEnvironment(moon,wire.trimEnd()))
      .host_policy_profile.capacity.max_model_request_bytes_per_item);
  const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
  const bindings=['baseEnvironment','hostCapacityPolicy'].map(name=>{
    const declaration=declarations.get(name);assert(declaration&&declaration.end<writer.start);
    return script.slice(declaration.start,declaration.end);
  }).join('\n');
  const produce=new AsyncFunction('root','repository','readFile','join','installedRuntime',
    'selectInstalledLocalMaterializationEnvironment',bindings+'\nreturn ('+
    script.slice(writer.arguments[1].start,writer.arguments[1].end)+');');
  const prepared=await produce('/app','/repo',async(path,encoding)=>{
    assert.equal(path,join('/repo','spec/local-check-environment.json'));
    return encoding==='utf8'?wire:Buffer.from(wire);
  },join,moon,selectInstalledLocalMaterializationEnvironment);
  const configured=inferConfiguration(JSON.parse(prepared));
  const composed=composeInstalledCheckEnvironment(moon,actualHost,actualHost,
    configured.installation.environmentWire);
  assert.deepEqual(JSON.parse(composed).host_policy_profile,JSON.parse(actualHost).host_policy_profile);
  const raw=inferConfiguration(JSON.parse(wire));
  assert.equal(configured.taskCid,raw.taskCid);
  assert.deepEqual(configured.installation.executionContracts,raw.installation.executionContracts);
  assert.deepEqual(configured.installation.dependencyBodies,raw.installation.dependencyBodies);
  assert.deepEqual(JSON.parse(configured.installation.environmentWire).model_task_contracts,
    JSON.parse(raw.installation.environmentWire).model_task_contracts);
  const {evidence_bundle_cid: ignored,...changed}=JSON.parse(configured.installation.environmentWire);
  void ignored;
  changed.host_policy_profile.capacity.max_effect_items++;
  assert.throws(()=>composeInstalledCheckEnvironment(moon,actualHost,actualHost,
    inferCanonical({...changed,evidence_bundle_cid:inferCid(changed)})), error=>{
    assert.equal(error.code,'InstalledCheckEnvironmentConflict');assert.equal(error.cause,'EnvironmentBase');return true;
  });
  const originalFailure=new Error('OriginalLocalPolicyUnavailable');
  await assert.rejects(produce('/app','/repo',async()=>wire,join,
    {...moon,clientLocalResourcePolicyRowCeiling(){throw originalFailure;}},
    selectInstalledLocalMaterializationEnvironment), error=>error===originalFailure);
});

test('packed composition Source publications retain the authored Host policy before installation', async () => {
  const baseWire = readFileSync(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8').trimEnd();
  const base = JSON.parse(baseWire);
  // Explicit admission port: this checks the actual JS policy-composition
  // boundary and fixture identities, not native semantic or physical backing.
  const moon = {clientProgramCheckEnvironment(wire, evidenceCid) {
    const {evidence_bundle_cid: actual, ...body} = JSON.parse(wire);
    assert.equal(actual, evidenceCid);
    assert.equal(actual, contentCid(body));
    return {};
  }};
  for (const name of ['left', 'right']) {
    const original = JSON.parse(readFileSync(new URL(
      `../adapters/host-node/fixtures/two-source/${name}.environment.json`, import.meta.url), 'utf8'));
    const before = structuredClone(original);
    const unbound = await publicFixtureEnvironment(original);
    assert.deepEqual(JSON.parse(composeInstalledCheckEnvironment(moon, baseWire,
      canonicalText(unbound))).host_policy_profile, base.host_policy_profile);
    const {evidence_bundle_cid: ignored, ...differentHost} = structuredClone(base);
    void ignored;
    differentHost.host_policy_profile.capacity.max_relation_output_rows++;
    const differentHostWire = canonicalText({...differentHost,
      evidence_bundle_cid: contentCid(differentHost)});
    assert.throws(() => composeInstalledCheckEnvironment(moon, differentHostWire, canonicalText(unbound)),
      error => error.code === 'InstalledCheckEnvironmentConflict' && error.cause === 'EnvironmentBase');
    const selected = await publicFixtureEnvironment(original, base.host_policy_profile);
    assert.deepEqual(selected.host_policy_profile, base.host_policy_profile);
    assert.notStrictEqual(selected.host_policy_profile, base.host_policy_profile);
    for (const key of Object.keys(unbound).filter(key =>
      !['host_policy_profile', 'evidence_bundle_cid'].includes(key))) {
      assert.deepEqual(selected[key], unbound[key], key);
    }
    assert.deepEqual(original, before);
    const composed = composeInstalledCheckEnvironment(moon, baseWire, canonicalText(selected));
    assert.deepEqual(JSON.parse(composed).host_policy_profile, base.host_policy_profile);
    const changed = structuredClone(selected);
    changed.host_policy_profile.capacity.max_effect_items++;
    delete changed.evidence_bundle_cid;
    changed.evidence_bundle_cid = contentCid(changed);
    assert.throws(() => composeInstalledCheckEnvironment(moon, baseWire, canonicalText(changed)),
      error => error.code === 'InstalledCheckEnvironmentConflict' && error.cause === 'EnvironmentBase');
  }
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(script, {ecmaVersion: 'latest', sourceType: 'module'});
  const calls = [];
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.name === 'publicFixtureEnvironment') calls.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  })(tree);
  assert.equal(calls.length, 2);
  for (const call of calls) {
    assert.equal(script.slice(call.arguments[1].start, call.arguments[1].end),
      'hostBaseEnvironment.host_policy_profile');
  }
});

test('public check Source fixture keeps original declarations under the actual Local policy', async () => {
  const script=readFileSync(new URL('../adapters/host-node/client-check.test.mjs',import.meta.url),'utf8');
  const tree=parseJavaScript(script,{ecmaVersion:'latest',sourceType:'module'});
  const producer=tree.body.find(n=>n.type==='FunctionDeclaration'&&n.id.name==='installedSource');
  assert(producer);
  const end=producer.body.body.findIndex(n=>n.type==='VariableDeclaration'&&n.declarations[0]?.id.name==='database');
  assert.equal(end,4,'Only the original metadata prefix precedes provider setup');
  const source=JSON.parse(readFileSync(new URL('../adapters/host-node/fixtures/query-amount-environment.json',import.meta.url),'utf8'));
  const before=structuredClone(source);
  const wire=readFileSync(new URL('../spec/local-check-environment.json',import.meta.url),'utf8');
  const originalPolicy=Object.freeze({}), moon={
    clientLocalResourcePolicyOriginal(){return originalPolicy;},
    clientLocalResourcePolicyRowCeiling(value){assert.equal(value,originalPolicy);return 203;},
    clientLocalResourcePolicyModelRequestByteCeiling(value){assert.equal(value,originalPolicy);return 65536n;},
    clientProgramCheckEnvironment(value,cid){assert.equal(JSON.parse(value).evidence_bundle_cid,cid);return {};},
  };
  const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
  const construct=new AsyncFunction('environment','repository','readFile','join','contentCid','moon',
    'selectInstalledLocalMaterializationEnvironment','hostEnvironmentWire',
    producer.body.body.slice(0,end).map(n=>script.slice(n.start,n.end)).join('\n')+'\nreturn environment;');
  const document=await construct(source,'/repo',async path=>{
    assert.equal(path,join('/repo','spec/local-check-environment.json'));return wire;
  },join,contentCid,moon,selectInstalledLocalMaterializationEnvironment);
  const selected=selectInstalledLocalMaterializationEnvironment(moon,wire.trimEnd());
  const composed=composeInstalledCheckEnvironment(moon,selected,canonicalText(document));
  assert.deepEqual(JSON.parse(composed).host_policy_profile,JSON.parse(selected).host_policy_profile);
  for(const name of Object.keys(before).filter(n=>!['host_policy_profile','evidence_bundle_cid'].includes(n))){
    assert.strictEqual(document[name],source[name]);assert.deepEqual(document[name],before[name]);
  }
  assert.deepEqual(source,before);
});

test('public check Source fixture follows its independently supplied Remote Effect Host policy', async () => {
  const script = readFileSync(new URL('../adapters/host-node/client-check.test.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(script, {ecmaVersion: 'latest', sourceType: 'module'});
  const producer = tree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'installedSource');
  const end = producer.body.body.findIndex(node => node.type === 'VariableDeclaration' &&
    node.declarations[0]?.id.name === 'database');
  assert.equal(end, 4);
  const source = JSON.parse(readFileSync(new URL('../adapters/host-node/fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  const original = structuredClone(source);
  const wire = readFileSync(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8');
  const policy = Object.freeze({}), moon = {
    clientLocalResourcePolicyOriginal() {return policy;},
    clientLocalResourcePolicyRowCeiling(value) {assert.equal(value, policy); return 203;},
    clientProgramCheckEnvironment(value, cid) {assert.equal(JSON.parse(value).evidence_bundle_cid, cid); return {};},
  };
  const selected = selectInstalledHostEnvironment(moon, wire.trimEnd());
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const construct = new AsyncFunction('environment', 'repository', 'readFile', 'join', 'contentCid', 'moon',
    'selectInstalledLocalMaterializationEnvironment', 'hostEnvironmentWire',
    producer.body.body.slice(0, end).map(node => script.slice(node.start, node.end)).join('\n') + '\nreturn environment;');
  const document = await construct(source, '/repo', async () => wire, join, contentCid, moon,
    selectInstalledLocalMaterializationEnvironment, selected);
  const composed = composeInstalledCheckEnvironment(moon, selected, canonicalText(document));
  assert.deepEqual(JSON.parse(composed).host_policy_profile, JSON.parse(selected).host_policy_profile);
  assert.deepEqual(source, original);
  for (const key of Object.keys(original).filter(key => !['host_policy_profile', 'evidence_bundle_cid'].includes(key))) {
    assert.equal(document[key], source[key]);
  }
  const http = tree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'httpClient');
  const initialized = http.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations[0]?.id.name === 'sourceInstallation').declarations[0].init;
  assert.equal(initialized.type, 'AwaitExpression');
  assert.equal(initialized.argument.arguments[2]?.name, 'hostEnvironmentWire');
  const declaration = tree.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'installedConfigurations');
  const forwarded = [];
  const configure = new Function('installedSource', 'mkdir', 'join',
    script.slice(declaration.start, declaration.end) + ';return installedConfigurations;')(
    async (root, configuration, originalWire) => {
      forwarded.push({root, configuration, originalWire});
      return join(root, 'source-profile.json');
    }, async () => {}, join);
  const configuration = {};
  assert.deepEqual(await configure('/app', configuration, selected),
    {sourceProfilePath: join('/app', 'source-profile.json')});
  assert.deepEqual(await configure('/app', [configuration, configuration], selected),
    {sourceProfilePaths: [join('/app', 'source-0', 'source-profile.json'),
      join('/app', 'source-1', 'source-profile.json')]});
  assert.equal(forwarded.length, 3);
  assert(forwarded.every(call => call.configuration === configuration && call.originalWire === selected));
  const selection = http.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations[0]?.id.name === 'hostEnvironmentWire').declarations[0].init;
  const choose = new AsyncFunction('installed', 'moon', 'readFile', 'join', 'repository',
    'selectInstalledHostEnvironment', 'return (' + script.slice(selection.start, selection.end) + ');');
  let reads = 0;
  const read = async path => {
    assert.equal(path, join('/repo', 'spec/local-check-environment.json')); reads++; return wire;
  };
  assert.equal(await choose({}, moon, read, join, '/repo', selectInstalledHostEnvironment), undefined);
  assert.equal(reads, 0);
  assert.equal(await choose({effectInstallation: {}}, moon, read, join, '/repo',
    selectInstalledHostEnvironment), selected);
  assert.equal(reads, 1);
});

// Evaluate the existing CLI selection prelude, including its admission flags.
// The expected cases below remain independently authored, never read from output.
function fixtureSelection(script, flags, expression) {
  const start = script.indexOf('const admissionHttpsOnly = process.argv');
  const end = script.indexOf('const inferEnabled =');
  assert.ok(start >= 0 && end > start, 'complete registered CLI selection prelude');
  return JSON.parse(runInNewContext(script.slice(start, end) +
    '\nJSON.stringify(' + expression + ')',
  {process: {argv: ['node', 'harness', ...flags]}, optionalEffectCases}));
}

test('the submitted JSON fixture binds only the newly published MappingRef', () => {
  const original = structuredClone(compositionTemplate);
  const first = compositionProgram('fixture-mapping-first');
  const second = compositionProgram('fixture-mapping-second');
  const update = program => program.stages.find(stage => stage.id === 'apply').effects.save.update;
  assert.equal(update(first).mapping, 'fixture-mapping-first');
  assert.equal(update(second).mapping, 'fixture-mapping-second');
  update(first).mapping = update(second).mapping = '__PUBLICATION_MAPPING_REF__';
  assert.deepEqual(first, original);
  assert.deepEqual(second, original);
  assert.deepEqual(compositionTemplate, original);
  assert.throws(() => compositionProgram(''));
});

test('the authored text fixture binds only its published MappingRef', () => {
  for (const mapping of ['fixture-mapping-first', 'fixture-mapping-second']) {
    const text = compositionText(mapping);
    assert.equal(text.replace(mapping, '__PUBLICATION_MAPPING_REF__'), compositionTextTemplate);
    assert(text.includes('MAX_OUTPUT_ROWS 10'));
    assert(text.includes('|> ASSERT UNIQUE BY (id)'));
    assert(text.includes('|> EFFECT save UPDATE'));
    assert.equal(text.match(/WHERE id = id/gu).length, 2);
  }
  for (const mapping of ['', 'bad`reference', 'bad\nreference']) {
    assert.throws(() => compositionText(mapping));
  }
});

test('ordinary packed composition ships JSON and authored text with independent replay expectations', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const selection = flags => fixtureSelection(script, flags, 'compositionCases');
  assert.deepEqual(selection([]), ['source', 'infer', 'infer-model-approval', 'infer-text', 'infer-graph-node', 'infer-graph-edge', 'read-approval']);
  assert.deepEqual(selection(['--two-source-effect']), ['two-source']);
  assert.deepEqual(selection(['--composed-infer']), ['infer', 'infer-text']);
  assert.deepEqual(selection(['--model-approval-only']), ['infer-model-approval']);
  assert.deepEqual(selection(['--composed-text']), ['infer-text']);
  assert.deepEqual(selection(['--composed-graph-node']), ['infer-graph-node']);
  assert.deepEqual(selection(['--composed-graph-edge']), ['infer-graph-edge']);
  assert.deepEqual(selection(['--composed-graph']), ['infer-graph-node', 'infer-graph-edge']);
  assert.deepEqual(selection(['--two-source-read-approval']), ['read-approval']);
  assert.deepEqual(selection(['--optional-effect-only']), []);

  for (const name of ['composed-infer-effect.program.template.json',
    'composed-infer-effect.expected.json', 'composed-infer-effect.aql.template']) {
    assert(script.includes("'" + name + "'"), 'isolated consumer must receive ' + name);
  }
  assert.deepEqual(compositionExpectations.sourceReadSessions, [2, 0, 0, 0]);
  assert.deepEqual(compositionExpectations.modelInputs, [100, 200]);
  // INFER outcome=ok refines the value to the original non-null success
  // contract (language.md INFER), including its required risk field.
  const classify = compositionTemplate.stages.find(stage => stage.id === 'classify');
  assert.ok(classify.steps.some(step => JSON.stringify(step.filter) ===
    JSON.stringify({eq: [{field: 'outcome'}, {literal: 'ok'}]})));
  for (const fields of [compositionExpectations.classifiedColumns, compositionExpectations.updateColumns]) {
    assert.deepEqual(fields.find(field => field.name === 'risk').contract,
      {type: 'string', nullable: false});
  }
  assert.deepEqual(compositionExpectations.effectWriteCounts, [0, 0, 1, 1]);
  assert.deepEqual(compositionExpectations.restartBoundaries,
    ['capture-waiting', 'approval-committed']);
});

test('Source approval narrowing preserves ordinary optional Effect pairs and restart outputs', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const selection = flags => fixtureSelection(script, flags, 'optionalCases');
  assert.deepEqual(selection([]), ['native-json', 'broad-text']);
  assert.deepEqual(selection(['--optional-effect-only']), ['native-json', 'broad-text']);
  for (const flag of ['--two-source-read-approval', '--two-source-effect',
    '--composed-infer', '--composed-text']) assert.deepEqual(selection([flag]), []);
  const output = script.match(/process\.stdout\.write\((boundary[^,]+),/u)?.[1];
  assert.ok(output, 'the same termination driver must serve both approval paths and the pure pair');
  for (const [boundary, expected] of [
    ['source-waiting', 'held\\n'], ['capture-waiting', 'held\\n'], ['completed', 'held\\n'],
    ['source-approval-committed', 'approved\\n'], ['approval-committed', 'approved\\n'],
  ]) assert.equal(runInNewContext(output, {boundary}), expected);
  assert.ok(script.includes("name === 'effect_resume_failed' || name === 'source_resume_failed'"));
  assert.ok(script.includes("optionalKind && name === 'acquisition_completed'"));
});

test('packed Source approval keeps independent read and Effect restart counters', () => {
  const expected = JSON.parse(readFileSync(new URL(
    './fixtures/two-source-read-approval.expected.json', import.meta.url), 'utf8'));
  assert.deepEqual(expected.sourceProviderOpenCounts,
    [[1, 0], [1, 0], [1, 1], [1, 1], [1, 1], [1, 1]]);
  assert.deepEqual(expected.sourceReadSessions, [1, 0, 1, 0, 0, 0]);
  assert.deepEqual(expected.effectWriteCounts, [0, 0, 0, 0, 1, 1]);
  assert.deepEqual(expected.restartBoundaries, ['source-waiting',
    'source-approval-committed', 'capture-waiting', 'approval-committed']);
});

test('packed Source approval preserves the credential Site account identity', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const accountConfiguration = JSON.stringify({
    version: 'actql-execution-account-config/0.1', account_id: 'shared-site-account',
    entries: [{entry_id: 'a-fixture-model', outcome: 'allow',
      principal: {all: true}, connection: {any_of: ['unused-model']},
      resource: {any_of: ['unused-task']}, operation: {any_of: ['infer']}, exclusions: []}],
  });
  const setup = script.slice(script.indexOf('const authorization = JSON.parse(readFileSync'),
    script.indexOf('const pendingScratch ='));
  const actual = JSON.parse(runInNewContext(setup + '\nJSON.stringify(authorization)', {
    readFileSync: () => JSON.stringify({accountConfiguration}),
    sourceReadApproval: true, modelApproval: false,
    process: {env: {}, argv: ['node', 'packed-fixture']},
  }));
  assert.equal(actual.accountConfiguration, accountConfiguration,
    'an unused Model rule must not make Host and Site configuration CIDs diverge');
  assert(script.includes('if (!sourceReadApproval) {\n    const model = await modelConfiguration'),
    'Source approval case still installs no Model');
});

test('packed Effect target reads keep distinct approval phases and independent provider counts', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const select = flags => fixtureSelection(script, flags,
    '{targetReadApprovalEnabled, compositionCases, optionalCases}');
  assert.equal(select([]).targetReadApprovalEnabled, true);
  assert.deepEqual(select(['--target-read-approval']), {
    targetReadApprovalEnabled: true, compositionCases: [], optionalCases: []});
  assert.equal(select(['--two-source-read-approval']).targetReadApprovalEnabled, false);
  assert.deepEqual(select([]).compositionCases,
    ['source', 'infer', 'infer-model-approval', 'infer-text', 'infer-graph-node', 'infer-graph-edge', 'read-approval']);
  assert.deepEqual(select([]).optionalCases, ['native-json', 'broad-text']);
  const expected = JSON.parse(readFileSync(new URL(
    './fixtures/effect-target-read-approval.expected.json', import.meta.url), 'utf8'));
  assert.deepEqual(expected.targetReadCounts, [0, 0, 0, 0, 8, 8, 12, 12]);
  assert.deepEqual(expected.effectWriteCounts, [0, 0, 0, 0, 0, 0, 4, 4]);
  assert.equal(expected.writes.length, 4);
  assert.ok(script.includes("['target-answer', ['0'], 'approved']"));
  assert.ok(script.includes("['target-answer', ['1'], 'approved']"));
  assert.ok(script.includes("delete environment.ACTQL_LOCAL_SOURCE_PROFILE"));
  assert.ok(script.includes("'effect-target-read-approval.expected.json'"));
});

test('each Client group retains its acceptance commands exactly once', () => {
  const original = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'))
    .scripts['check:distribution-client'].split(' && ');
  assert.equal(original.length, 53, 'the existing full local gate remains unchanged');
  const prepared = ['npm ci --prefix packages/provider-ai-sdk --ignore-scripts',
    original.slice(0, 4).join('\n')];
  const partitions = {
    'client-distribution': [4],
    'client-distribution-callers': Array.from({length: 36}, (_, index) => index + 17),
    'client-distribution-mutations': [6, 7, 8, 9],
    'client-distribution-packed': [5, 10, 11, 12, 13, 14],
    'client-distribution-native': [15, 16],
  };
  for (const [name, indexes] of Object.entries(partitions)) {
    assert.deepEqual(runs(name), [
      ...(['client-distribution', 'client-distribution-callers', 'client-distribution-mutations'].includes(name) ? prepared : []),
      ...indexes.map(index => original[index]),
    ], name);
  }
  assert.deepEqual(Object.values(partitions).flat().sort((a, b) => a - b),
    Array.from({length: 49}, (_, index) => index + 4),
    'every original acceptance command remains exactly once; only four source-preparation commands repeat');
  assert(!jobs['client-distribution-packed'].steps.some(step => step.id === 'distribution-preparation'),
    'normal tar acceptance does not rebuild the checkout runtime');
  assert.deepEqual(jobs['client-distribution-native'].needs, ['select-targets', 'preflight']);
  assert.deepEqual(runs('client-packed'), [
    'node scripts/test-packed-local-node-assets.mjs',
    'node scripts/test-packed-sheets.mjs',
    'npm run check:packed-embedded-checkpoint',
    'node scripts/test-packed-single-infer.mjs',
    'node scripts/test-packed-infer-evaluation.mjs',
    'node scripts/test-packed-acquired-infer.mjs',
    'node --test scripts/packed-query-evidence.test.mjs\nnode scripts/test-packed-public-query.mjs',
    'node scripts/test-packed-result-description.mjs',
  ]);
  assert.deepEqual(runs('client-packed-composition'), ['node scripts/test-packed-salesforce-source.mjs']);
  assert.deepEqual(runs('client-salesforce'), [
    'node scripts/build-runtime-packages.mjs local-node',
    'npm run check:salesforce-site',
    'node adapters/connectors/salesforce/test/run-computation-probe.mjs',
    'node scripts/test-acquired-effect-computation-probe.mjs',
    `for boundary in before-effect-source effect-source before-effect-capture effect-capture before-publication-private publication-private; do
  node scripts/test-effect-capture-host-crash.mjs "$boundary"
done
for boundary in effect-source effect-capture publication-private; do
  node scripts/test-effect-capture-crash.mjs "$boundary"
done`,
  ]);
  for (const name of Object.keys(partitions)) for (const step of jobs[name].steps.filter(step => step.name?.startsWith('Test ')))
    assert.deepEqual(step.env, {TMPDIR: '${{ github.workspace }}/_build'});
  for (const name of groups) {
    assert.equal(jobs[name].if, normal);
    assert.equal(jobs[name]['runs-on'], 'ubuntu-24.04');
    assert.equal(jobs[name]['timeout-minutes'], 30);
    assert.equal(jobs[name].strategy, undefined, 'no fail-fast sibling cancellation');
    for (const step of jobs[name].steps.filter(step => step.run)) {
      let preparation;
      if (step.name?.startsWith('Test ')) {
        if (['client-packed', 'client-packed-composition', 'client-distribution-packed'].includes(name)) preparation = 'client-inputs';
        else if (name === 'client-distribution-native') preparation = 'native-client-preparation';
        else if (Object.hasOwn(partitions, name)) preparation = 'distribution-preparation';
      }
      assert.equal(step.if, preparation
        ? '${{ !cancelled() && steps.' + preparation + ".outcome == 'success' }}" : undefined,
      'independent cases require their original successful preparation, not a previous case');
      assert.equal(step['continue-on-error'], undefined);
    }
  }
  assert.deepEqual(jobs['client-salesforce'].needs, ['select-targets', 'preflight']);
  const manifest = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert(!manifest.scripts['check:local-node-assets'].includes('test-packed-salesforce-source'),
    'the packed composition acceptance moves from Host into the artifact consumer exactly once');
});

test('ordinary Local assets reuse tarballs while cold and external builds stay source-backed', () => {
  const {scripts} = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  const source = scripts['check:local-node-source-assets'];
  for (const file of ['test-packed-installed-connectors.mjs', 'test-packed-external-connector.mjs',
    'test-packed-external-installed.mjs']) assert(source.includes(file), file);
  assert(!source.includes('test-packed-local-node-assets.mjs'));
  assert.equal(scripts['check:local-node-assets'],
    'npm run check:local-node-source-assets && node scripts/test-packed-local-node-assets.mjs');
  assert.equal(scripts['postcheck:local-node-assets'], 'node scripts/test-packed-sheets.mjs');
  assert(jobs.host.steps.some(step => step.run === 'npm run check:local-node-source-assets'));
  assert(!jobs.host.steps.some(step => step.run === 'npm run check:local-node-assets'));
  assert(!jobs.host.needs.includes('client-packages'), 'source checks keep their independent start');
  for (const file of ['test-packed-local-node-assets.mjs', 'test-packed-sheets.mjs']) {
    const body = readFileSync(new URL(file, import.meta.url), 'utf8');
    assert(body.includes('packedClientPackage'));
    assert(!body.includes('delete environment.ACTQL_PACKED_CLIENT_PACKAGES'));
  }
});

test('one producer uploads only manifest and tarballs; consumers select its immutable artifact ID', () => {
  assert.deepEqual(runs('client-packages'), ['node scripts/packed-client-packages.mjs "$RUNNER_TEMP/actql-client-packages"']);
  const producer = jobs['client-packages'];
  const upload = producer.steps.find(step => step.id === 'packages');
  assert.equal(upload.uses, 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02');
  assert.equal(upload.with.name, 'actql-client-packages-${{ github.run_id }}-${{ github.run_attempt }}-${{ github.sha }}');
  assert.equal(upload.with['if-no-files-found'], 'error');
  assert.equal(upload.with['retention-days'], 7);
  assert.deepEqual(upload.with.path.trim().split('\n'), [
    'packed-client-packages.json', ...['client-wire', 'sdk', 'run-host-core', 'local-node', 'node']
      .map(name => `actql-${name}-0.0.0-development.tgz`),
  ].map(name => '${{ runner.temp }}/actql-client-packages/' + name));
  assert.deepEqual(producer.outputs, {'artifact-id': '${{ steps.packages.outputs.artifact-id }}'});
  for (const name of consumers) {
    assert.deepEqual(jobs[name].needs, ['select-targets', 'preflight', 'client-packages']);
    const download = jobs[name].steps.find(step => step.name === 'Download the exact Client package artifact');
    assert.equal(download.uses, './.github/actions/download-client-packages');
    assert.deepEqual(download.with, {
      'artifact-id': '${{ needs.client-packages.outputs.artifact-id }}',
      path: '${{ runner.temp }}/actql-client-packages',
    });
    assert.equal(jobs[name].env, undefined, 'runner context is unavailable in job-level env');
    assert(!jobs[name].steps.some(step => /cache@/.test(step.uses ?? '')));
  }
});

test('packed evidence uploads remain always-on after their original command', () => {
  const steps = jobs['client-packed'].steps;
  for (const [id, name] of [['packed-infer', 'packed-single-infer'],
    ['packed-infer-evaluation', 'packed-infer-evaluation'],
    ['packed-acquired-infer', 'packed-acquired-infer'],
    ['packed-query', 'packed-public-query'], ['packed-result-description', 'packed-result-description']]) {
    const command = steps.findIndex(step => step.id === id);
    const upload = steps[command + 1];
    assert(command >= 0);
    assert.equal(upload.uses, './.github/actions/upload-packed-query-evidence');
    assert.equal(upload.if, `always() && steps.${id}.outputs.evidence-directory != ''`);
    assert.deepEqual(upload.with, {
      directory: '${{ steps.' + id + '.outputs.evidence-directory }}',
      name: name + '-${{ github.sha }}',
    });
  }
});

test('the original client check succeeds only when every producer and acceptance group succeeds', () => {
  assert.deepEqual(jobs.client.needs, groups);
  assert.match(jobs.client.if, /always\(\)/u);
  assert.match(jobs.client.if, /!\(needs\.client-packages\.result == 'skipped'/u);
  assert(jobs.check.needs.includes('client'));
  const script = jobs.client.steps[0].run;
  const results = Object.fromEntries(groups.map(name => [name, {result: 'success'}]));
  assert.equal(run(script, {RESULTS: JSON.stringify(results)}).status, 0);
  for (const name of groups) {
    for (const result of ['failure', 'cancelled', 'skipped', 'in_progress', undefined]) {
      const candidate = {...results, [name]: {result}};
      const child = run(script, {RESULTS: JSON.stringify(candidate)});
      assert.equal(child.status, 1, `${name}: ${result}\n${child.stdout}\n${child.stderr}`);
    }
  }
  assert.equal(run(script, {RESULTS: '{}'}).status, 1);
});

test('local commands remain available for each independently retryable group', () => {
  for (const name of [...consumers, 'client-distribution-native', 'client-salesforce']) {
    const child = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'run', name, '--dry-run'], {cwd: root, encoding: 'utf8'});
    assert.equal(child.status, 0, child.stderr);
    for (const command of runs(name)) {
      if (command === 'npm ci --prefix packages/provider-ai-sdk --ignore-scripts') {
        assert(!child.stdout.includes(command), 'Local checks retain installed dependencies');
      } else assert(child.stdout.includes(command));
    }
  }
});

// Empty artifact-ids would make the upstream action select every artifact.
// This guard also accepts the original producer ID in a consumer-only retry.
test('download fails closed before the action for empty, malformed or multiple IDs', () => {
  const action = parse(readFileSync(new URL('../.github/actions/download-client-packages/action.yml', import.meta.url), 'utf8'));
  assert.equal(action.runs.using, 'composite');
  assert.equal(action.runs.steps.length, 3);
  const [guard, download] = action.runs.steps;
  assert.equal(guard.env.ARTIFACT_ID, '${{ inputs.artifact-id }}');
  assert.equal(guard['continue-on-error'], undefined);
  assert.equal(download.if, undefined, 'download requires the preceding guard to succeed');
  assert.equal(download.uses, 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093');
  assert.deepEqual(download.with, {'artifact-ids': '${{ inputs.artifact-id }}', path: '${{ inputs.path }}', 'merge-multiple': true});
  for (const id of ['', ' ', '0', '-1', '01', '1,2', '1\n2', 'undefined', '1.2', '1e3', '${{ missing }}']) {
    assert.equal(run(guard.run, {ARTIFACT_ID: id}).status, 1, JSON.stringify(id));
  }
  for (const attempt of ['1', '2']) {
    assert.equal(run(guard.run, {ARTIFACT_ID: '987654321', GITHUB_RUN_ATTEMPT: attempt}).status, 0);
  }
});

test('runner-private package/cache environment is set only after successful download', t => {
  const action = parse(readFileSync(new URL('../.github/actions/download-client-packages/action.yml', import.meta.url), 'utf8'));
  const step = action.runs.steps[2];
  assert.equal(step.if, undefined);
  assert.equal(step['continue-on-error'], undefined);
  assert.equal(step.env.PACKAGES_PATH, '${{ inputs.path }}');
  const scratch = mkdtempSync(join(tmpdir(), 'client-ci-env-'));
  t.after(() => rmSync(scratch, {recursive: true, force: true}));
  const environment = join(scratch, 'github-env');
  const packages = join(scratch, 'artifact');
  assert.equal(run(step.run, {PACKAGES_PATH: packages, GITHUB_ENV: environment, RUNNER_TEMP: scratch}).status, 0);
  assert.equal(readFileSync(environment, 'utf8'),
    `ACTQL_PACKED_CLIENT_PACKAGES=${packages}\nACTQL_TEST_NPM_CACHE=${scratch}/actql-npm-cache\n`);
  for (const job of Object.values(jobs)) {
    for (const value of Object.values(job.env ?? {})) {
      assert(!/\$\{\{[^}]*\brunner\./u.test(String(value)), 'runner context cannot be resolved before assigning a job runner');
    }
  }
});

test('admission-only flags narrow the existing Source case without ordinary Effect or Model selection', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  for (const flag of ['--admission-only', '--admission-https-only']) {
    assert.deepEqual(fixtureSelection(script, [flag],
      '{targetReadApprovalEnabled, compositionCases, optionalCases}'), {
      targetReadApprovalEnabled: false, compositionCases: ['source'], optionalCases: [],
    });
  }
});

// Pure fixture observation controls. These execute no Client, Host or Journal.
function checkpointObservationDeclarations() {
  const source = readFileSync(new URL('./fixtures/packed-embedded-checkpoint.mjs', import.meta.url), 'utf8');
  const ast = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const functionSource = name => {
    const declaration = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
    assert(declaration, `Missing actual fixture declaration ${name}`);
    return source.slice(declaration.start, declaration.end);
  };
  return {source, ast, functionSource};
}

test('packed checkpoint observation covers the configured retry inside the original child budget', () => {
  const {functionSource} = checkpointObservationDeclarations();
  const schedule = new Function('assert', functionSource('checkpointObservationSchedule') +
    ';return checkpointObservationSchedule;')(assert);
  assert.deepEqual(schedule(10000), {pollMs: 25, retryMs: 10100, polls: 808});
  assert.equal(schedule(10000).polls * schedule(10000).pollMs, 20200);
  assert(3 * 20200 < 120000);
  for (const invalid of [undefined, 0, -1, 999, 1000.5, 20000]) assert.throws(() => schedule(invalid));
});

test('packed checkpoint first diagnostic and public pending observations cannot overwrite each other', () => {
  const {source, ast, functionSource} = checkpointObservationDeclarations();
  const recordOriginal = new Function(functionSource('checkpointObservationRecord') +
    ';return checkpointObservationRecord;')();
  const records = [], events = [];
  const record = (kind, data) => recordOriginal(records, kind, data);
  const assignment = ast.body.find(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' && node.expression.left.type === 'MemberExpression' &&
    node.expression.left.object.name === 'authorization' && node.expression.left.property.name === 'faultInjection');
  assert(assignment);
  const callback = source.slice(assignment.expression.right.start, assignment.expression.right.end);
  const observe = new Function('record', 'appendFileSync', `
    let firstResumeFailure, retryClaimAfterFailure=false, recoveryAfterFailure=false;
    return ${callback};`)(record, (path, value) => {assert.equal(path, 'embedded-events.log'); events.push(value);});
  record('first-lookup', {kind: 'held', state: 'resuming'});
  observe('resume_claimed', {generation: 1});
  observe('resume_failed', {code: 'OriginalResumeFailure'});
  observe('sweep_failed', {code: 'LaterDifferentFailure'});
  observe('resume_claimed', {generation: 2});
  observe('run_observed', {});
  record('first-lookup', {kind: 'found'});
  assert.deepEqual(records.find(item => item.kind === 'first-lookup').data, {kind: 'held', state: 'resuming'});
  assert.deepEqual(records.find(item => item.kind === 'first-resume-failure').data,
    {event: 'resume_failed', code: 'OriginalResumeFailure'});
  assert.deepEqual(records.find(item => item.kind === 'resume-claim-after-failure').data, {generation: 2});
  assert(records.some(item => item.kind === 'run-observed-after-failure'));
  assert.equal(records.some(item => item.kind === 'busy'), false, 'a held lookup is not a typed busy cause');
  assert.deepEqual(events, ['resume_claimed\n', 'resume_failed\n', 'sweep_failed\n',
    'resume_claimed\n', 'run_observed\n']);
});

test('packed checkpoint close records actual return and preserves the first pending failure', async () => {
  const {functionSource} = checkpointObservationDeclarations();
  const records = [], record = (kind, data) => records.push({kind, data});
  let release;
  const first = {close() {assert.equal(this, first); return new Promise(resolve => {release = resolve;});}};
  const owner = new Function('record', 'initialClient', 'nodeTypes', `let client=initialClient; const closedClients=new WeakSet();
    ${functionSource('checkpointFailureData')}
    ${functionSource('closeClient')}
    return {closeClient,setClient(value){client=value;}};`)(record, first, nodeTypes);
  const closing = owner.closeClient('first');
  assert.deepEqual(records, [{kind: 'close-attempt:first', data: {first: true}}]);
  release(); await closing;
  assert.deepEqual(records.at(-1), {kind: 'close-returned:first', data: {first: true}});
  const failure = Object.assign(new Error('same pending cleanup'), {code: 'ClientCleanupPending'});
  const pending = {close() {assert.equal(this, pending); throw failure;}};
  owner.setClient(pending);
  await assert.rejects(owner.closeClient('pending'), error => error === failure);
  assert.deepEqual(records.at(-1), {kind: 'close-failed:pending',
    data: {first: true, name: null, code: 'ClientCleanupPending'}});
  assert.equal(records.some(item => item.kind === 'close-returned:pending'), false);
});

test('packed checkpoint failure capture reads only own scalar DATA without getters or opaque causes', () => {
  const {functionSource} = checkpointObservationDeclarations();
  const capture = new Function('nodeTypes', functionSource('checkpointFailureData') +
    ';return checkpointFailureData;')(nodeTypes);
  let reads = 0;
  const error = new Error('original scalar code');
  Object.defineProperty(error, 'code', {get() {reads++; throw new Error('must not run');}});
  Object.defineProperty(error, 'cause', {get() {reads++; throw new Error('opaque cause');}});
  assert.deepEqual(capture(error), {name: null, code: null});
  const proxy = new Proxy({}, {getOwnPropertyDescriptor() {reads++; throw new Error('opaque proxy');}});
  for (const value of [proxy, undefined, null, 1, 'failure']) {
    assert.deepEqual(capture(value), {name: null, code: null});
  }
  assert.equal(reads, 0);
  assert.deepEqual(capture({name: 'OriginalPublicFailure', code: 'UnexpectedOriginalCode'}),
    {name: 'OriginalPublicFailure', code: 'UnexpectedOriginalCode'});
});

test('packed checkpoint dispatch capture excludes messages, identities, getters and opaque values', () => {
  const {functionSource} = checkpointObservationDeclarations();
  const capture = new Function('nodeTypes', functionSource('checkpointDispatchFailureData') +
    ';return checkpointDispatchFailureData;')(nodeTypes);
  let reads = 0;
  const getter = {get() {reads++; throw new Error('must not inspect');}};
  const detail = Object.create({primaryCode: 'InheritedCode', issueTag: 1});
  for (const key of ['primaryCode', 'code', 'issueTag', 'nestedIssueTag', 'ref', 'cause']) {
    Object.defineProperty(detail, key, getter);
  }
  assert.deepEqual(capture(detail), {});
  const proxy = new Proxy({}, {getOwnPropertyDescriptor() {reads++; throw new Error('opaque');}});
  for (const value of [proxy, undefined, null, 1, 'failure', () => {}]) {
    assert.equal(capture(value), undefined);
  }
  const original = {primaryCode: 'OriginalFailure:Preparation', issueTag: 12, nestedIssueTag: 5,
    code: 'private message', message: 'private payload', ref: {opaque: true}, cause: proxy};
  const data = capture(original);
  assert.deepEqual(data, {primaryCode: 'OriginalFailure:Preparation', issueTag: 12, nestedIssueTag: 5});
  assert(Object.isFrozen(data));
  original.primaryCode = 'LaterFailure';
  assert.equal(data.primaryCode, 'OriginalFailure:Preparation');
  for (const primaryCode of ['', 'private message', 'X'.repeat(129), proxy, 1]) {
    assert.deepEqual(capture({primaryCode}), {});
  }
  for (const issueTag of [-1, 65536, 1.5, NaN, Infinity, '12', proxy]) {
    assert.deepEqual(capture({issueTag, nestedIssueTag: issueTag}), {});
  }
  assert.deepEqual(capture({issueTag: 0, nestedIssueTag: 65535}), {issueTag: 0, nestedIssueTag: 65535});
  assert.equal(reads, 0);
});

test('packed checkpoint emitted codes retain only exact authored labels without promoting a primary', () => {
  const {functionSource} = checkpointObservationDeclarations();
  const capture = new Function('nodeTypes', functionSource('checkpointDispatchFailureData') +
    ';return checkpointDispatchFailureData;')(nodeTypes);
  for (const code of ['InstalledManagedComputeRunUnavailable', 'CapturedRunPublicationFailed']) {
    assert.deepEqual(capture({code}), {emittedCode: code});
  }
  for (const code of ['PrivateButIdentifierShaped', 'private message', 'ClientDispatchFailed',
    'InstalledManagedComputeRunUnavailable:private-value', '', 1,
    {toString() {throw new Error('must not coerce');}}]) assert.deepEqual(capture({code}), {});
  const declaration = parseJavaScript(functionSource('checkpointDispatchFailureData'),
    {ecmaVersion: 'latest', sourceType: 'module'}).body[0];
  const labels = declaration.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'emittedCodes')).declarations[0].init.elements;
  const dispatch = readFileSync(new URL('../adapters/host-node/client-dispatch-owner.mjs', import.meta.url), 'utf8');
  const entry = readFileSync(new URL('../adapters/host-node/entry.mjs', import.meta.url), 'utf8');
  for (const label of labels) {
    assert.equal(label.type, 'Literal');
    assert.equal(typeof label.value, 'string');
    assert(dispatch.includes(`new Error('${label.value}')`) ||
      dispatch.includes(`new TypeError('${label.value}')`) || entry.includes(`= '${label.value}'`),
    `Missing original authored dispatch label: ${label.value}`);
  }
});

test('packed checkpoint first dispatch hooks retain no capabilities and do not repeat', () => {
  const {source, ast, functionSource} = checkpointObservationDeclarations();
  const assignment = ast.body.find(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' && node.expression.left.type === 'MemberExpression' &&
    node.expression.left.object.name === 'authorization' && node.expression.left.property.name === 'faultInjection');
  const callback = source.slice(assignment.expression.right.start, assignment.expression.right.end);
  const records = [], events = [];
  const recordOriginal = new Function(functionSource('checkpointObservationRecord') +
    ';return checkpointObservationRecord;')();
  const observe = new Function('record', 'appendFileSync', `
    let firstResumeFailure, retryClaimAfterFailure=false, recoveryAfterFailure=false;
    return ${callback};`)((kind, data) => recordOriginal(records, kind, data),
    (path, text) => {assert.equal(path, 'embedded-events.log'); events.push(text);});
  const opaque = new Proxy({}, {get() {throw new Error('must not inspect original capability');}});
  for (let index = 0; index < 100; index++) {
    assert.equal(observe('dispatch_reserved', opaque), undefined);
    assert.equal(observe('physical_start_reserved', opaque), undefined);
  }
  assert.deepEqual(records, [{kind: 'first-dispatch_reserved', data: {}},
    {kind: 'first-physical_start_reserved', data: {}}]);
  assert.equal(events.length, 200, 'the original event log remains unchanged');
});

test('packed checkpoint observes only the existing dispatch event and preserves its first DATA', () => {
  const {source, ast, functionSource} = checkpointObservationDeclarations();
  const assignment = ast.body.find(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' && node.expression.left.type === 'MemberExpression' &&
    node.expression.left.object.name === 'authorization' && node.expression.left.property.name === 'observe');
  assert(assignment);
  const opening = ast.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(declaration => declaration.id.name === 'open'));
  assert(assignment.end < opening.start, 'the existing observer is configured before the original connect');
  const callback = source.slice(assignment.expression.right.start, assignment.expression.right.end);
  const records = [];
  const observe = new Function('nodeTypes', 'records', `
    ${functionSource('checkpointDispatchFailureData')}
    ${functionSource('checkpointObservationRecord')}
    const record=(kind,data)=>checkpointObservationRecord(records,kind,data);
    return ${callback};`)(nodeTypes, records);
  const opaque = new Proxy({}, {get() {throw new Error('must not read unrelated events');}});
  assert.equal(observe('resume_failed', opaque), undefined);
  assert.equal(observe('dispatch_settlement_failed', opaque), undefined);
  assert.equal(observe('dispatch_failed', null), undefined);
  assert.equal(observe('dispatch_failed', {primaryCode: 'OriginalFailure', issueTag: 12}), undefined);
  for (let index = 0; index < 100; index++) observe('dispatch_failed', {primaryCode: 'LaterFailure'});
  assert.deepEqual(records, [{kind: 'diagnostic:dispatch_failed',
    data: {primaryCode: 'OriginalFailure', issueTag: 12}}]);
});

test('Client distribution retains public foundation history for its unchanged historical SDK refusals', () => {
  const checkout = jobs['client-distribution'].steps.find(step =>
    step.uses?.startsWith('actions/checkout@'));
  assert.equal(checkout.with['persist-credentials'], false);
  assert.equal(checkout.with['fetch-depth'], 0);
});

// Execute only the authored fixture's account guard. No runtime, Store,
// historical record, signing key or operational writer is imported here.
test('synthetic held Salesforce fixture retains distinct Host observation and Run entries', () => {
  const source = readFileSync(new URL('./fixtures/synthetic-historical-held-salesforce.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const definition = tree.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'assertSyntheticSalesforceHostAccount');
  assert(definition);
  const check = new Function('assert', source.slice(definition.start, definition.end) +
    ';return assertSyntheticSalesforceHostAccount;')(assert);
  const entries = [{entry_id: 'host-results', outcome: 'allow', operation: {any_of: ['read']}},
    {entry_id: 'host-run', outcome: 'allow', operation: {any_of: ['write']}}];
  check({entries});
  for (const invalid of [entries.slice(1), [entries[1], entries[0]],
    [entries[0], {...entries[1], outcome: 'delegate'}],
    [{...entries[0], operation: {any_of: ['write']}}, entries[1]],
    [entries[0], {...entries[1], operation: {any_of: ['read']}}]]) {
    assert.throws(() => check({entries: invalid}), {code: 'ERR_ASSERTION'});
  }
});

test('packed Checkpoint owner reads only the original Program named Results', () => {
  const source = readFileSync(new URL('./test-packed-client-checkpoint.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  let template;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'TemplateLiteral' && node.quasis[0].value.cooked.includes('const installation = {')) {
      assert.equal(template, undefined); template = node;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  })(tree);
  assert(template);
  const generated = new Function('hostCapacityPolicy', 'return (' +
    source.slice(template.start, template.end) + ');')({});
  const actor = parseJavaScript(generated, {ecmaVersion: 'latest', sourceType: 'module'});
  const declaration = name => actor.body.filter(node => node.type === 'VariableDeclaration')
    .flatMap(node => node.declarations).find(node => node.id.name === name)?.init;
  const configuration = declaration('configuration'), tokens = declaration('tokens');
  assert(configuration && tokens);
  const userInfo = () => ({username: 'fixture-owner'});
  const retainedTokens = new Function('userInfo', 'return (' +
    generated.slice(tokens.start, tokens.end) + ');')(userInfo);
  assert.equal(retainedTokens.get('owner-token'), userInfo().username);
  assert.notEqual(retainedTokens.get('stranger-token'), userInfo().username);
  const configure = new Function('outcome', 'canonical', 'userInfo', 'process',
    'return (' + generated.slice(configuration.start, configuration.end) + ');');
  for (const [acquired, path] of [[false, '../packages/sdk/fixtures/values.json'],
    [true, '../adapters/connectors/duckdb/node/examples/program.json']]) {
    const original = JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
    const resources = [...Object.keys(original.results).map(name => 'result/' + name), 'run'].sort();
    const actorProcess = {env: {ACQUIRED: acquired ? '1' : '0'}};
    assert.equal(configure('missing', canonicalText, userInfo, actorProcess), undefined);
    for (const outcome of ['allow', 'deny', 'delegate']) {
      const account = JSON.parse(configure(outcome, canonicalText, userInfo, actorProcess));
      const read = account.entries.find(entry => entry.entry_id === 'owner-run-result-read');
      assert.deepEqual(read, {entry_id: 'owner-run-result-read', exclusions: [],
        connection: {any_of: ['actql-remote-host']}, operation: {any_of: ['read']},
        outcome: 'allow', principal: {any_of: [userInfo().username]},
        resource: {any_of: resources}});
      assert(!read.resource.any_of.includes('result/other'));
      const write = account.entries.find(entry => entry.entry_id === 'run-acceptance');
      assert.equal(write.outcome, outcome);
      assert.deepEqual(write.operation, {any_of: ['write']});
    }
  }
});

test('packed Checkpoint Source publication shares its explicit installed Host policy', async () => {
  const source = readFileSync(new URL('./test-packed-client-checkpoint.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const declarations = new Map();
  let publication, hostTemplate;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1 &&
        ['base', 'sourceBaseEnvironment', 'hostCapacityPolicy'].includes(node.declarations[0].id?.name)) {
      const name = node.declarations[0].id.name;
      assert.equal(declarations.has(name), false);
      declarations.set(name, node);
    }
    if (node.type === 'AssignmentExpression' && node.left.type === 'MemberExpression' &&
        node.left.object.name === 'environment' && node.left.property.name === 'host_policy_profile') {
      assert.equal(publication, undefined); publication = node;
    }
    if (node.type === 'TemplateLiteral' && node.quasis[0].value.cooked.includes('const installation = {')) {
      assert.equal(hostTemplate, undefined); hostTemplate = node;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  })(tree);
  assert(publication && hostTemplate);
  const wire = readFileSync(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8');
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const baseName = declarations.has('sourceBaseEnvironment') ? 'sourceBaseEnvironment' : 'base';
  const bindings = [baseName, ...(declarations.has('hostCapacityPolicy') ? ['hostCapacityPolicy'] : [])].map(name => {
    const declaration = declarations.get(name);
    assert(declaration, `Missing shared installed policy binding: ${name}`);
    return source.slice(declaration.start, declaration.end);
  }).join('\n');
  const prepare = new AsyncFunction('root', 'readFile', 'join', bindings +
    `\nreturn {sourceBaseEnvironment: ${baseName}, hostCapacityPolicy: typeof hostCapacityPolicy === 'undefined' ? undefined : hostCapacityPolicy};`);
  const selected = await prepare('/app', async (path, encoding) => {
    assert.equal(path, '/app/node_modules/@actql/local-node/spec/local-check-environment.json');
    assert.equal(encoding, 'utf8'); return wire;
  }, join);
  const published = JSON.parse(readFileSync(new URL('../adapters/host-node/fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  new Function('environment', baseName,
    source.slice(publication.start, publication.end))(published, selected.sourceBaseEnvironment);
  delete published.evidence_bundle_cid;
  published.evidence_bundle_cid = contentCid(published);
  const generated = new Function('hostCapacityPolicy', 'return (' +
    source.slice(hostTemplate.start, hostTemplate.end) + ');')(selected.hostCapacityPolicy);
  const generatedTree = parseJavaScript(generated, {ecmaVersion: 'latest', sourceType: 'module'});
  const installation = generatedTree.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations[0].id.name === 'installation').declarations[0].init;
  const options = new Function('process', 'configuration', 'tokens', 'decide', 'mark', 'readFileSync',
    'return (' + generated.slice(installation.start, installation.end) + ');')(
    {env: {STATE: '/state', ACQUIRED: '1'}, cwd: () => '/app'}, undefined, new Map(), undefined, () => {}, () => 'fixture-key');
  const originalPolicy = Object.freeze({});
  const moon = {
    clientLocalResourcePolicyOriginal: () => originalPolicy,
    clientLocalResourcePolicyRowCeiling(value) {assert.equal(value, originalPolicy); return 2097152;},
    clientLocalResourcePolicyModelRequestByteCeiling(value) {assert.equal(value, originalPolicy); return 65536n;},
    clientProgramCheckEnvironment: () => ({}),
  };
  const actualHost = selectInstalledLocalMaterializationEnvironment(moon, wire.trimEnd(), options.hostCapacityPolicy);
  const composed = composeInstalledCheckEnvironment(moon, actualHost, actualHost, canonicalText(published));
  assert.deepEqual(JSON.parse(composed).host_policy_profile, published.host_policy_profile);
  assert.deepEqual(options.hostCapacityPolicy, selected.sourceBaseEnvironment.host_policy_profile.capacity);
  const defaultHost = selectInstalledLocalMaterializationEnvironment(moon, wire.trimEnd());
  assert.throws(() => composeInstalledCheckEnvironment(moon, defaultHost, defaultHost, canonicalText(published)),
    error => error.code === 'InstalledCheckEnvironmentConflict' && error.cause === 'EnvironmentBase');
  const foreign = structuredClone(published);
  foreign.host_policy_profile.capacity.max_artifact_rows += 1;
  delete foreign.evidence_bundle_cid; foreign.evidence_bundle_cid = contentCid(foreign);
  assert.throws(() => composeInstalledCheckEnvironment(moon, actualHost, actualHost, canonicalText(foreign)),
    error => error.code === 'InstalledCheckEnvironmentConflict' && error.cause === 'EnvironmentBase');
});

test('historical Checkpoint identities retain the same explicit Host policy', () => {
  const wrapper = readFileSync(new URL('./test-packed-client-checkpoint.mjs', import.meta.url), 'utf8');
  assert.match(wrapper, /hostCapacityPolicy: installation\.hostCapacityPolicy,/);
  const hash = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
  const originalRoot = '/original-selected-root', principalId = 'fixture-owner';
  const raw = JSON.parse(readFileSync(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8'))
    .host_policy_profile.capacity;
  const expression = (source, name) => {
    const found = [];
    (function visit(node) {
      if (!node || typeof node !== 'object') return;
      if (node.type === 'VariableDeclarator' && node.id?.name === name) found.push(node.init);
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(visit);
        else if (value && typeof value === 'object') visit(value);
      }
    })(parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}));
    assert.equal(found.length, 1, name);
    return source.slice(found[0].start, found[0].end);
  };
  for (const name of ['values', 'query']) {
    const source = readFileSync(new URL(`./fixtures/synthetic-historical-held-${name}.mjs`, import.meta.url), 'utf8');
    const selected = new Function('hostCapacityPolicy',
      `return (${expression(source, 'effectiveHostCapacityPolicy')});`);
    const scope = new Function('root', 'principalId', 'effectiveHostCapacityPolicy', 'hash', 'cid',
      `return (${expression(source, 'authorityScopeCid')});`);
    const original = hash(JSON.stringify({version: 'actql-local-owner-scope/0.1', root: originalRoot, principalId}));
    assert.equal(scope(originalRoot, principalId, selected(undefined), hash, contentCid), original);
    const expected = {max_graph_construction_edges: 1000, max_graph_construction_input_rows: 1000,
      max_graph_construction_nodes: 1000, ...raw};
    assert.deepEqual(selected(raw), expected);
    const scoped = scope(originalRoot, principalId, selected(raw), hash, contentCid);
    assert.equal(scoped, hash(JSON.stringify({version: 'actql-local-owner-scope/0.1',
      root: originalRoot, principalId, hostCapacityPolicyCid: contentCid(expected)})));
    assert.notEqual(scoped, original);
    assert.notEqual(scope(originalRoot, principalId,
      selected({...raw, max_artifact_rows: raw.max_artifact_rows + 1}), hash, contentCid), scoped);
  }
  const values = readFileSync(new URL('./fixtures/synthetic-historical-held-values.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(values, {ecmaVersion: 'latest', sourceType: 'module'});
  const assignments = [];
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'AssignmentExpression' && node.left.property?.name === 'capacity' &&
        node.left.object.property?.name === 'host_policy_profile' &&
        node.left.object.object?.name === 'environmentBody') assignments.push(node.right);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  })(tree);
  assert.equal(assignments.length, 1);
  const normalized = {max_graph_construction_edges: 1000, max_graph_construction_input_rows: 1000,
    max_graph_construction_nodes: 1000, ...raw};
  const bindingCapacity = new Function('environmentBody', 'effectEnvironmentWire', 'effectiveHostCapacityPolicy',
    `return (${values.slice(assignments[0].start, assignments[0].end)});`)(
    {host_policy_profile: {capacity: raw}}, undefined, normalized);
  assert.deepEqual(bindingCapacity, normalized);
});

test('packed Query Source Hosts and reopens retain the published fixture policy', async () => {
  const source = readFileSync(new URL('./test-node-client-package.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  function nodes(tree, predicate) {
    const found = [];
    (function visit(node) {
      if (!node || typeof node !== 'object') return;
      if (predicate(node)) found.push(node);
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(visit);
        else if (value && typeof value === 'object') visit(value);
      }
    })(tree);
    return found;
  }
  const baseWire = readFileSync(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8');
  const start = source.indexOf('const sourceCatalog = await readFile(');
  const end = source.indexOf('const compileCapturedQuery = ', start);
  assert(start > 0 && end > start);
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const prepare = new AsyncFunction('root', 'repository', 'readFile', 'join', 'assert', 'machineCid',
    source.slice(start, end) + '\nreturn sourceEnvironment;');
  const published = await prepare('/app', root, async (path, encoding) => {
    assert.equal(encoding, 'utf8');
    if (path === '/app/node_modules/@actql/local-node/spec/local-check-environment.json') return baseWire;
    assert.equal(path, join(root, 'src/query_integration/query_amount_catalog_wbtest.mbt'));
    return readFile(path, encoding);
  }, join, assert, machineCid);
  const profileBindings = nodes(tree, node => node.type === 'VariableDeclarator' &&
    node.id.name === 'sourceProfilePath');
  assert.equal(profileBindings.length, 1);
  assert.equal(profileBindings[0].init.callee.name, 'join');
  assert.equal(profileBindings[0].init.arguments[1].value, 'source-profile.json');
  const profiles = nodes(tree, node => node.type === 'CallExpression' && node.callee.name === 'writeFile' &&
    node.arguments[0]?.type === 'Identifier' && node.arguments[0].name === 'sourceProfilePath');
  assert.equal(profiles.length, 1);
  const profile = profiles[0].arguments[1].arguments[0];
  const wireNode = profile.properties.find(property => property.key.name === 'checkEnvironmentWire').value;
  const publishedWire = new Function('canonicalText', 'sourceEnvironment',
    'return (' + source.slice(wireNode.start, wireNode.end) + ');')(canonicalText, published);
  const authorization = nodes(tree, node => node.type === 'VariableDeclarator' &&
    node.id.name === 'remoteAuthorization');
  assert.equal(authorization.length, 1);
  const remoteAuthorization = new Function('userInfo',
    'return (' + source.slice(authorization[0].init.start, authorization[0].init.end) + ');')(
    () => ({username: 'fixture-operator'}));
  const originalPolicy = Object.freeze({});
  const moon = {
    clientLocalResourcePolicyOriginal: () => originalPolicy,
    clientLocalResourcePolicyRowCeiling(value) {assert.equal(value, originalPolicy); return 2097152;},
    clientLocalResourcePolicyModelRequestByteCeiling(value) {assert.equal(value, originalPolicy); return 65536n;},
    clientProgramCheckEnvironment: () => ({}),
  };
  let checked = 0;
  function checkOptions(text, node, policy, embedded) {
    const options = new Function('hostCapacityPolicy', 'root', 'join', 'sourceProfilePath', 'process',
      'remoteAuthorization', 'readFileSync',
      'return (' + text.slice(node.start, node.end) + ');')(policy, '/app', join, '/app/source-profile.json',
      {env: {}, cwd: () => '/app'}, remoteAuthorization, (path, encoding) => {
        assert.equal(path, 'remote-authorization.json'); assert.equal(encoding, 'utf8');
        return JSON.stringify(remoteAuthorization);
      });
    if (!embedded) assert.deepEqual(options.authorization, remoteAuthorization);
    const selected = embedded ? options.installation?.hostCapacityPolicy : options.hostCapacityPolicy;
    const effective = selectInstalledLocalMaterializationEnvironment(moon, baseWire.trimEnd(), selected);
    const composed = composeInstalledCheckEnvironment(moon, effective, effective, publishedWire);
    assert.deepEqual(JSON.parse(composed).host_policy_profile, published.host_policy_profile);
    assert.deepEqual(selected, published.host_policy_profile.capacity);
    checked++;
  }
  const remote = nodes(tree, node => node.type === 'CallExpression' &&
    node.callee.name === 'openInstalledRemoteHttpHost');
  assert.equal(remote.length, 1);
  checkOptions(source, remote[0].arguments[0], published.host_policy_profile.capacity, false);
  for (const file of ['smoke.mjs', 'restart.mjs', 'restart-remote-host.mjs']) {
    const writers = nodes(tree, node => node.type === 'CallExpression' && node.callee.name === 'writeFile' &&
      node.arguments[0]?.type === 'CallExpression' && node.arguments[0].arguments.some(
        arg => arg.type === 'Literal' && arg.value === file));
    assert.equal(writers.length, 1);
    const template = writers[0].arguments[1];
    assert.equal(template.expressions.length, 0);
    const text = template.quasis[0].value.cooked;
    const actor = parseJavaScript(text, {ecmaVersion: 'latest', sourceType: 'module'});
    const bindings = actor.body.filter(node => node.type === 'VariableDeclaration' &&
      node.declarations[0].id.name === 'hostCapacityPolicy');
    assert(bindings.length <= 1);
    const policy = bindings.length === 0 ? undefined : new Function('readFileSync',
      text.slice(bindings[0].start, bindings[0].end) + '\nreturn hostCapacityPolicy;')((path, encoding) => {
      assert.equal(path, 'source-profile.json'); assert.equal(encoding, 'utf8');
      return JSON.stringify({checkEnvironmentWire: publishedWire});
    });
    const calls = nodes(actor, node => node.type === 'CallExpression' &&
      ['connect', 'runApplication', 'runAcquiredApplication', 'openInstalledRemoteHttpHost'].includes(node.callee.name) &&
      node.arguments[0]?.type === 'ObjectExpression');
    for (const call of calls) {
      const properties = call.arguments[0].properties;
      const value = name => properties.find(property => property.key.name === name)?.value;
      const embedded = call.callee.name !== 'openInstalledRemoteHttpHost';
      if (embedded && (value('mode')?.value !== 'local' || value('endpoint') !== undefined)) continue;
      checkOptions(text, call.arguments[0], policy, embedded);
    }
  }
  assert.equal(checked, 7, 'initial, projection, acquired, variant and both restart Host openings');
  assert.throws(() => composeInstalledCheckEnvironment(moon,
    selectInstalledLocalMaterializationEnvironment(moon, baseWire.trimEnd()),
    selectInstalledLocalMaterializationEnvironment(moon, baseWire.trimEnd()), publishedWire),
  error => error.code === 'InstalledCheckEnvironmentConflict' && error.cause === 'EnvironmentBase');
});

// Actual SDK admission with explicit Host wire replies, not installed execution
// or physical-stop acceptance. The callers are extracted from the packed scripts.
test('packed terminal cancellation keeps the SDK attempt and original terminal fact separate', async t => {
  const {connectInProcess} = await import('../packages/sdk/host-port.mjs');
  const source = readFileSync(new URL('./test-node-client-package.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const writer = tree.body.map(node => node.expression?.argument).find(node =>
    node?.callee?.name === 'writeFile' && node.arguments[0]?.arguments?.some(
      value => value.value === 'smoke.mjs'));
  assert(writer);
  assert.equal(writer.arguments[1].expressions.length, 0);
  const actor = writer.arguments[1].quasis[0].value.cooked;
  const segments = [
    ['execution', "assert.deepEqual(rows, [{id: 1}, {id: 2}]);",
      "await assert.rejects(execution.result('answer').all({maxRows: 1}),"],
    ['acquiredStarted', "assert.deepEqual(await acquiredStarted.result('b').all(), acquiredLocal.b);",
      "writeFileSync('acquired-local-ref.json',"],
  ];
  for (const [name, before, after] of segments) {
    const start = actor.indexOf(before), end = actor.indexOf(after, start);
    assert(start >= 0 && end > start);
    const check = new Function('assert', name, 'return (async () => {' +
      actor.slice(start + before.length, end) + '})();');
    async function fixture({physicalStop = 'confirmed', foreign = false} = {}) {
      const calls = [], ref = {namespaceId: 'packed-terminal',
        authorityScopeCid: 'sha256:' + 'a'.repeat(64), runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
      const client = await connectInProcess({mode: 'local', owner: 'local'}, {perform(operation, body) {
        if (operation === 'connect') return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'packed-terminal', capabilities: [], limits: {
            maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
        if (operation === 'close') return;
        calls.push(operation);
        if (operation === 'attach') return {ref, durability: 'durable', revision: 1};
        assert.deepEqual(body.ref, ref);
        if (operation === 'status') return {version: 'actql-run-state/0.1', run_id: 'terminal', revision: 41,
          status: 'succeeded', updated_at: '2026-10-09T00:00:00.000Z', next_action: {kind: 'none'},
          result_available: false, result_availability: {answer: {state: 'unavailable', reason: 'not_published',
            observed_at: '2026-10-09T00:00:00.000Z'}},
          control: {revision: 19, cancellation_requested: false, physical_stop: physicalStop}};
        assert.equal(operation, 'cancel');
        return {kind: 'already_satisfied', attemptRef: body.attemptRef,
          cancellation: {kind: 'already_terminal', ref: foreign ? {...ref, runDefinitionCid: 'sha256:' + 'c'.repeat(64)} : ref,
            cancelRef: {...ref, cancelId: body.cancelId, expectedRevision: body.expectedRevision}, revision: 19}};
      }});
      t.after(() => client.close());
      return {run: await client.attach(ref), calls};
    }
    const original = await fixture();
    await check(assert, original.run);
    assert.deepEqual(original.calls, ['attach', 'status', 'cancel', ...(name === 'execution' ? ['status'] : [])]);
    const foreign = await fixture({foreign: true});
    await assert.rejects(check(assert, foreign.run), {code: 'CancellationUnknown'});
    assert.equal(foreign.calls.filter(value => value === 'cancel').length, 1);
    if (name === 'execution') {
      const pending = await fixture({physicalStop: 'unknown'});
      await assert.rejects(check(assert, pending.run), {code: 'ERR_ASSERTION'});
      assert.equal(pending.calls.filter(value => value === 'cancel').length, 1,
        'a terminal cancellation fact cannot replace the separate physical-stop observation');
    }
  }
});

test('packed expired recovery supplies its original unresolved lookup before SDK submission', async t => {
  const {connectInProcess} = await import('../packages/sdk/host-port.mjs');
  const {getSubmissionOutcome} = await import('../packages/sdk/index.mjs');
  const {submissionEpoch} = await import('../packages/sdk/submission-fixture.mjs');
  const source = readFileSync(new URL('./test-packed-client-checkpoint.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const writer = tree.body.map(node => node.expression?.argument).find(node =>
    node?.callee?.name === 'writeFile' && node.arguments[0]?.arguments?.some(value => value.value === 'client.mjs'));
  assert(writer);
  assert.equal(writer.arguments[1].expressions.length, 0);
  const actor = writer.arguments[1].quasis[0].value.cooked;
  const body = parseJavaScript(actor, {ecmaVersion: 'latest', sourceType: 'module'});
  const steps = body.body.flatMap(node => node.declarations ?? []).find(node => node.id.name === 'steps');
  const method = steps.init.properties.find(node => node.key.name === 'recoveredAgain');
  const recoveredAgain = new Function('as', 'assert', 'requestId', 'text', 'process',
    'return ({' + actor.slice(method.start, method.end) + '}).recoveredAgain;');
  const calls = [], requestId = 'expired-original', text = '{"original":"historical input"}';
  const ref = {namespaceId: 'packed-recovery', authorityScopeCid: submissionEpoch.authorityScopeCid,
    runDefinitionCid: 'sha256:' + 'd'.repeat(64)};
  const client = await connectInProcess({mode: 'local', owner: 'local'}, {perform(operation, packet) {
    if (operation === 'connect') return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'durable', scopeRef: 'packed-recovery', capabilities: ['aql-document'], submissionEpoch,
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
        maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
    if (operation === 'close') return;
    calls.push(operation);
    if (operation === 'lookup-request') return {kind: 'found', requestId, ref,
      durability: 'durable', lookupExpiresAt: '2099-01-01'};
    if (operation === 'attach') {assert.deepEqual(packet.ref, ref); return {ref, durability: 'durable', revision: 1};}
    if (operation === 'wait') return {version: 'actql-run-state/0.1', run_id: 'expired', revision: 1,
      status: 'failed', updated_at: '2026-10-09T00:00:00.000Z', next_action: {kind: 'none'},
      result_available: false, result_availability: {answer: {state: 'unavailable', reason: 'not_published',
        observed_at: '2026-10-09T00:00:00.000Z'}}};
    assert.equal(operation, 'submit-named-intent');
    return {kind: 'observed', requestName: packet.requestName, intentCid: packet.intentCid,
      attemptRef: packet.attemptRef, outcome: {kind: 'preparation_failed', submissionRef: packet.submissionRef,
        intentCid: packet.intentCid, problem: {code: 'ACTQL_E_DELEGATION_UNAVAILABLE', classification: 'operation_failed'}}};
  }});
  t.after(() => client.close());
  let originalLookup, submittedOptions;
  const owner = {async lookupRequest(id) {assert.equal(id, requestId); return originalLookup = await client.lookupRequest(id);},
    attach: reference => client.attach(reference), startSource(value, options) {
      assert.equal(value, text); submittedOptions = options; return client.startSource(value, options);
    }};
  await recoveredAgain(async token => {assert.equal(token, 'owner-token'); return owner;},
    assert, requestId, text, {env: {EXPECT_STATUS: 'failed'}})();
  assert.equal(submittedOptions.unresolvedHistory, originalLookup);
  assert.deepEqual(calls, ['lookup-request', 'attach', 'wait'], 'historical recovery never submits another intent');
  await assert.rejects(client.startSource(text, {format: 'json', requestId: 'ordinary-new-name'}), error => {
    assert.equal(error.code, 'SubmissionPreparationFailed');
    assert.deepEqual(getSubmissionOutcome(error).problem,
      {code: 'ACTQL_E_DELEGATION_UNAVAILABLE', classification: 'operation_failed'});
    return true;
  });
  assert.equal(calls.filter(value => value === 'submit-named-intent').length, 1,
    'ordinary requestId-only first binding keeps its separate legitimate Host operation');
});

test('computation cleanup keeps shared reservations and cumulative use', async () => {
  const source = await readFile(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const declaration = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'assertCompletedComputationCleanup');
  assert.ok(declaration);
  const check = new Function('assert', source.slice(declaration.start, declaration.end) +
    '; return assertCompletedComputationCleanup;')(assert);
  const snapshot = (heldBytes, transferredBytes, planningWork) => ({resourceUsage: {
    reservedExecutionBytes: '100', reservedRetentionBytes: '50', reservedTransferBytes: '10',
    heldBytes, transferredBytes, planningWork,
  }});
  const completed = snapshot('40', '3', '7'), pending = snapshot('20', '4', '8');
  const released = snapshot('0', '6', '9');
  check(completed, pending, released);
  for (const key of ['transferredBytes', 'planningWork']) {
    const regressedPending = structuredClone(pending);
    regressedPending.resourceUsage[key] = '0';
    assert.throws(() => check(completed, regressedPending, released));
    const regressedRelease = structuredClone(released);
    regressedRelease.resourceUsage[key] = '0';
    assert.throws(() => check(completed, pending, regressedRelease));
  }
  assert.throws(() => check(completed, pending, snapshot('1', '6', '9')));
  assert.throws(() => check(completed, pending, undefined));
});
import './packed-duckdb-capability-input.test.mjs';
import './historical-typed-values-binding.test.mjs';

import './packed-remote-observation-policy.test.mjs';
