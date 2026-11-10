import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {EventEmitter} from 'node:events';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {test} from 'node:test';
import {createTransportOwner, requireCompleteInventory, sourceFixturePaths, observePackedSubmissionCause,
  runSubmissionCauseObserver, createPackedHostFailureDiagnostics, selectAcceptanceTimeout}
  from './fixtures/packed-query-transport-owner.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {publicQueryResultOracles} from './fixtures/public-query-input.mjs';

const helper = new URL('./fixtures/packed-query-transport-owner.mjs', import.meta.url).href;
const command = (name, source) => ({name, args: ['--input-type=module', '-e', source]});

async function fixtureSyntax(path) {
  const {parse} = await import('acorn');
  const source = await readFile(new URL(path, import.meta.url), 'utf8');
  const nodes = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (typeof node.type === 'string') nodes.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {sourceType: 'module', ecmaVersion: 'latest'}));
  return {source, nodes};
}

for (const [name, expression] of Object.entries({
  normal: {gte: [{field: 'amount'}, {literal: 20}]},
  unsupportedPredicate: {gt: [{add: [{field: 'id'}, {literal: 1}]}, {literal: 2}]},
})) test(`planner requirement vectors independently bind ${name} input and every identity preimage`, async () => {
  const vectors = JSON.parse(await readFile(new URL('./fixtures/planner-selection-requirement-preimages.json', import.meta.url), 'utf8'));
  const vector = vectors[name];
  const {plannerSelectionProgram, plannerSelectionRequirementCids} = await import('./fixtures/planner-selection-public-query.mjs');
  const input = JSON.parse(plannerSelectionProgram(vector.filter));
  const environment = JSON.parse(await readFile(new URL('../adapters/host-node/fixtures/two-source/left.environment.json', import.meta.url), 'utf8'));
  const aoa = JSON.parse(await readFile(new URL('../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']' :
    value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
  const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
  const common = {binding_references: [], bindings: {}, expression_contract_cid: aoa.expression_contract_cid,
    parameter_references: [], parameters: {}};
  const stages = input.stages.map((stage, index) => ({...common,
    local_body: {effects: {}, inputs: stage.inputs, results: stage.results,
      steps: stage.steps.map((step, ordinal) => index === 0 && ordinal === 0 ? {...step, filter: expression} : step)},
    version: 'actql-stage-semantics/0.1'}));
  assert.deepEqual(vector.expression, expression);
  assert.deepEqual(vector.stageSemantics, stages);
  const semantics = {...common, actql_version: input.version,
    program_template: {exports: input.results, stages: [
      {after: 'initial', id: 'acquire', imports: {}, stage_semantics_cid: cid(stages[0])},
      {after: 'completed', id: 'ordered_result', imports: input.stages[1].inputs, stage_semantics_cid: cid(stages[1])},
    ]}, version: 'actql-program-semantics/0.1'};
  assert.deepEqual(vector.programSemantics, semantics);
  const definition = {id: input.id, program_semantics_cid: cid(semantics), version: 'actql-program-definition/0.1'};
  assert.deepEqual(vector.programDefinition, definition);
  const view = environment.source_views[0];
  const schema = environment.connector_catalogs[0].contracts.find(contract => contract.cid === view.output.schema.cid).body.fields;
  const requirement = {filter: {expression_cid: cid(expression), occurrence: '/steps/0/filter'},
    input_contract_cid: cid(schema), logical_guards: {max_rows: 100, max_value_bytes: 10000},
    output_contract_cid: cid({id: schema.id}),
    owner: {input: 'remote', program_source_cid: cid(definition), stage: 'acquire'},
    parameter_values_cid: cid({values: {}, version: 'actql-parameter-values/0.1'}), request: {},
    select: {fields: [{input: 'id', output: 'id'}], occurrence: '/steps/1/select'},
    source_contract_cid: view.contract_cid, source_order_cid: null,
    source_ref: environment.schema_snapshots[0].source_ref,
    source_validation: {fields: Object.keys(schema).sort(), scope: 'selected_scan'}, version: 'actql-query-acquisition/0.1'};
  assert.deepEqual(vector.requirement, requirement);
  assert.equal(vector.cid, cid(requirement));
  assert.equal(plannerSelectionRequirementCids[name], vector.cid,
    'installation estimates must bind this complete original requirement, never a historical hash');
});

test('public query HTTPS observation selects only its original operator and authored Result names', async () => {
  const {parse} = await import('acorn');
  const source = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const declarations = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === 'createPublicQueryHttpAuthorization') declarations.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(syntax);
  assert.equal(declarations.length, 1);
  const declaration = declarations[0];
  const create = Function('userInfo', 'canonical', 'publicQueryResultOracles',
    `return (${source.slice(declaration.start, declaration.end)});`)(
      () => ({username: 'query-operator'}), JSON.stringify, publicQueryResultOracles);
  const account = JSON.parse(create({primaryResultName: 'selected', successes: [
    {name: 'one'}, {name: 'two', results: {secondary: {}, selected: {}}},
  ]}).accountConfiguration);
  assert.deepEqual(account, {version: 'actql-execution-account-config/0.1',
    account_id: 'packed-query-http', entries: [
      {entry_id: 'read-original', outcome: 'allow', principal: {any_of: ['query-operator']},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/secondary', 'result/selected', 'run']},
        operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'request-original', outcome: 'allow', principal: {any_of: ['query-operator']},
        connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['duckdb-acquired']},
        operation: {any_of: ['write']}, exclusions: []},
    ]});
  assert.match(source, /authorization: hostFailures\.authorization\(httpAuthorization\)/u);
  assert.match(source, /recordCohort\('remote', directory, cohort, authorization \?\? httpAuthorization\)/u);
  assert.match(source, /if \(authorization !== undefined\) saved\.authorization = authorization/u);
});

test('exact physical HTTPS targets forward only their authored Run and Result observation policy', async () => {
  const {parse} = await import('acorn');
  const source = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const nodes = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (typeof node.type === 'string') nodes.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(syntax);
  const declaration = name => nodes.find(node =>
    node.type === 'FunctionDeclaration' && node.id.name === name);
  const policy = declaration('createPublicQueryHttpAuthorization');
  const create = Function('userInfo', 'canonical', 'publicQueryResultOracles',
    `return (${source.slice(policy.start, policy.end)});`)(
      () => ({username: 'exact-operator'}), JSON.stringify, publicQueryResultOracles);
  const entry = declaration('exerciseExactPhysicalTargets');
  const targets = nodes.find(node => node.type === 'VariableDeclarator' && node.id.name === 'exactTargetPairs').init;
  const exactTargetPairs = Function(`return (${source.slice(targets.start, targets.end)});`)();
  const files = new Map(), installed = new Map(), opened = [], calls = [];
  let hostCloses = 0, serverCloses = 0;
  const baseProfile = {original: 'source-profile'};
  const ports = {
    assert, exactTargetPairs, sourceProfilePath: 'source.json', hostCapacityPolicy: {original: 'capacity'},
    resolve: path => path,
    async readFile(path) {return path === 'source.json' ? JSON.stringify(baseProfile) : 'fixture-TLS';},
    async writeFile(path, bytes) {files.set(path, JSON.parse(bytes));},
    observe: () => () => ({original: 'no-provider-I/O'}),
    async connect(options) {
      const {directory, sourceProfilePath} = options.installation;
      const profile = files.get(sourceProfilePath), original = installed.get(directory);
      if (original !== undefined && (profile.schema !== original.profile.schema || profile.table !== original.profile.table)) {
        throw new TypeError('InstalledHostConfigurationMismatch');
      }
      const entry = original ?? {profile, leases: 0};
      entry.leases++;
      installed.set(directory, entry);
      return {async close() {if (--entry.leases === 0) installed.delete(directory);}};
    },
    createPublicQueryHttpAuthorization: create,
    async exercisePublicQueryInput(_connect, options, input) {
      calls.push({options, input});
      if (options.mode === 'local') {
        const client = await ports.connect(options);
        await client.close();
        return;
      }
      const host = opened.at(-1);
      assert.ok(host.authorization, 'the actual exact-target HTTP Host must receive its operator policy');
      const account = JSON.parse(host.authorization.accountConfiguration);
      assert.deepEqual(account, JSON.parse(create({successes: input.successes}).accountConfiguration));
      assert.deepEqual(account.entries[0].resource, {any_of: ['result/main', 'run']});
      assert.deepEqual(account.entries[0].principal, {any_of: ['exact-operator']});
      assert.deepEqual(account.entries[0].connection, {any_of: ['actql-remote-host']});
      assert.deepEqual(account.entries[0].operation, {any_of: ['read']});
      assert.equal(host.authenticate('Bearer fixture-token'), 'exact-operator');
      assert.equal(host.authenticate('Bearer other-token'), undefined);
    },
    async openInstalledRemoteHttpHost(options) {
      opened.push(options);
      return {handler() {}, async close() {hostCloses++;}};
    },
    createServer() {
      return {listen(_port, _host, callback) {callback();}, address() {return {port: 443};},
        closeAllConnections() {}, close(callback) {serverCloses++; callback();}};
    },
    userInfo: () => ({username: 'exact-operator'}),
  };
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  await AsyncFunction(...Object.keys(ports),
    `return (${source.slice(entry.start, entry.end)})();`)(...Object.values(ports));
  assert.equal(opened.length, 4);
  assert.equal(hostCloses, 4);
  assert.equal(serverCloses, 4);
  assert.equal(calls.length, 8);
  assert.equal(installed.size, 0, 'every retained original Host lease must be closed');
  assert.deepEqual(calls.map(({input}) => input.successes[0].expected), [
    [{id: 101, amount: 11}], [{id: 101, amount: 11}],
    [{id: 202, amount: 22}], [{id: 202, amount: 22}],
    [{id: 303, amount: 33}], [{id: 303, amount: 33}],
    [{id: 404, amount: 44}], [{id: 404, amount: 44}],
  ]);
});

test('packed two-source observations retain the same scoped policy as their source registration', async () => {
  const {parse} = await import('acorn');
  const accountFrom = async path => {
    const source = await readFile(new URL(path, import.meta.url), 'utf8');
    const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
    const accounts = [];
    const visit = node => {
      if (node === null || typeof node !== 'object') return;
      if (node.type === 'Property' && node.key.name === 'accountConfiguration') accounts.push(node.value);
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(visit);
        else if (value !== null && typeof value === 'object') visit(value);
      }
    };
    visit(syntax);
    assert.equal(accounts.length, 1);
    const [account] = accounts;
    return JSON.parse(Function('canonical', 'userInfo',
      `return (${source.slice(account.start, account.end)});`)(JSON.stringify,
        () => ({username: 'two-source-operator'})));
  };
  const packed = await accountFrom('./fixtures/packed-two-source-public-query.mjs');
  const source = await accountFrom('../adapters/host-node/two-source-public-host.test.mjs');
  assert.deepEqual(packed, source, 'ordinary packed observations use the existing source operator policy');
  assert.deepEqual(packed.entries[1], {entry_id: 'read-owned-test-run-results', outcome: 'allow',
    principal: {any_of: ['two-source-operator']}, connection: {any_of: ['actql-remote-host']},
    resource: {any_of: ['result/joined', 'result/single_source', 'run']},
    operation: {any_of: ['read']}, exclusions: []});
});

test('documented two-source HTTPS example uses the existing exact Result observer policy', async () => {
  const {source, nodes} = await fixtureSyntax('./fixtures/packed-two-source-example.mjs');
  const accounts = nodes.filter(node => node.type === 'Property' && node.key.name === 'accountConfiguration');
  assert.equal(accounts.length, 1);
  const value = accounts[0].value;
  const actual = JSON.parse(Function('canonical', 'userInfo',
    `return (${source.slice(value.start, value.end)});`)(JSON.stringify,
      () => ({username: 'example-operator'})));
  const original = await fixtureSyntax('./fixtures/packed-public-query.mjs');
  const declaration = original.nodes.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'createPublicQueryHttpAuthorization');
  const create = Function('userInfo', 'canonical', 'publicQueryResultOracles',
    `return (${original.source.slice(declaration.start, declaration.end)});`)(
      () => ({username: 'example-operator'}), JSON.stringify, publicQueryResultOracles);
  assert.deepEqual(actual, JSON.parse(create({successes: [{resultName: 'joined'}]}).accountConfiguration));
});

test('two-source example setup forwards its existing declared source capacity', async () => {
  const {source, nodes} = await fixtureSyntax('../examples/two-source-join/setup-example.mjs');
  const program = nodes.find(node => node.type === 'Program');
  const code = program.body.filter(node => node.type !== 'ImportDeclaration')
    .map(node => source.slice(node.start, node.end)).join('\n')
    .replaceAll('import.meta.url', JSON.stringify(new URL('../examples/two-source-join/setup-example.mjs', import.meta.url).href));
  const capacity = {max_artifact_rows: 1000};
  for (const changed of [false, true]) {
    const written = new Map();
    const ports = {
      assert, URL, resolve: (...parts) => parts.join('/'), async mkdir() {}, console: {log() {}},
      async readFile(url) {
        if (url.pathname.endsWith('database-rows.json')) return JSON.stringify({left: [], right: []});
        return JSON.stringify({host_policy_profile: {capacity: changed && url.pathname.endsWith('right.environment.json')
          ? {...capacity, max_artifact_rows: 999} : capacity}, schema_snapshots: [{source_ref: 'original-source'}]});
      },
      async writeFile(path, bytes) {written.set(path, JSON.parse(bytes));},
      DuckDBInstance: {async create() {return {async connect() {return {async run() {}, closeSync() {}};}, closeSync() {}};}},
    };
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    const run = () => AsyncFunction(...Object.keys(ports), code)(...Object.values(ports));
    if (changed) {
      await assert.rejects(run(), {code: 'ERR_ASSERTION'});
      assert.equal(written.has('two-source-example-data/connection.json'), false);
    } else {
      await run();
      assert.deepEqual(written.get('two-source-example-data/connection.json').installation.hostCapacityPolicy, capacity);
    }
  }
});

test('planner Host observation policy leaves original provider read Deny independent', async () => {
  const {source, nodes} = await fixtureSyntax('./fixtures/planner-selection-public-query.mjs');
  const account = nodes.find(node => node.type === 'VariableDeclarator' && node.id.name === 'accountConfiguration');
  const accountConfiguration = Function('canonical', `return (${source.slice(account.init.start, account.init.end)});`)(JSON.stringify);
  const declaration = nodes.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'hostAuthorization');
  const create = Function('generateKeyPairSync', 'accountConfiguration', 'canonical', 'userInfo',
    `return (${source.slice(declaration.start, declaration.end)});`)(
      () => ({publicKey: {export: () => 'public-fixture'}, privateKey: {export: () => 'private-fixture'}}),
      accountConfiguration, JSON.stringify, () => ({username: 'planner-operator'}));
  const observe = () => {};
  const authorization = create(observe);
  const policy = JSON.parse(authorization.accountConfiguration);
  assert.equal(authorization.observe, observe);
  assert.deepEqual(policy.entries[0], JSON.parse(accountConfiguration('allow', 'write', 'planner-selection-host')).entries[0]);
  assert.deepEqual(policy.entries[1], {entry_id: 'read-original', outcome: 'allow',
    principal: {any_of: ['planner-operator']}, connection: {any_of: ['actql-remote-host']},
    resource: {any_of: ['result/selected', 'run']}, operation: {any_of: ['read']}, exclusions: []});
  assert.deepEqual(JSON.parse(accountConfiguration('deny', 'read', 'provider-original')).entries,
    [{entry_id: 'fixture-entry', outcome: 'deny', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}]);
});

test('exact-string fresh Saved readers forward only the originally recorded operator policy', async () => {
  const original = await fixtureSyntax('./fixtures/packed-public-query.mjs');
  const record = original.nodes.find(node => node.type === 'VariableDeclarator' && node.id.name === 'recordString').init;
  const reader = await fixtureSyntax('./fixtures/string-values-restart.mjs');
  const entry = reader.nodes.find(node => node.type === 'IfStatement' &&
    node.test.type === 'UnaryExpression' && node.test.operator === '!' && node.test.argument.name === 'cohortOnly');
  assert.match(original.source, /recordString\(mode, authorization\)\(item\)/u);
  for (const authorization of [undefined, Object.freeze({accountConfiguration: 'original-scoped-policy'})]) {
    const retained = {hostCapacityPolicy: {original: 'capacity'}, sourceProfilePaths: {local: 'local-source', remote: 'remote-source'}};
    const recordString = Function('retainedStrings', `return (${original.source.slice(record.start, record.end)});`)(retained);
    const item = {name: 'exact-string-values', ref: {original: 'run'}, expected: [{value: 'e\u0301'}], columns: [{name: 'value'}]};
    recordString('local', undefined)(item);
    recordString('remote', authorization)(item);
    assert.equal(retained.remote.authorization, authorization);
    if (authorization === undefined) assert.equal(Object.hasOwn(retained.remote, 'authorization'), false);
    const opened = [], connections = [];
    let hostCloses = 0, clientCloses = 0;
    const ports = {
      assert, cohortOnly: false, mode: undefined, resolve: path => path, accepted: () => 1,
      async readFile(path) {return path === 'retained-string-results.json' ? JSON.stringify(retained) : 'fixture-TLS';},
      async connect(options) {
        connections.push(options);
        return {async attach(ref) {
          assert.deepEqual(ref, item.ref);
          return {async status() {return {status: 'succeeded'};}, result() {
            return {async all() {return item.expected;}, async describe() {return {columns: item.columns};}};
          }};
        }, async close() {clientCloses++;}};
      },
      async openInstalledRemoteHttpHost(options) {
        opened.push(options);return {handler() {}, async close() {hostCloses++;}};
      },
      createServer() {return {listen(_port, _host, callback) {callback();}, address() {return {port: 443};},
        closeAllConnections() {}, close(callback) {callback();}};},
      userInfo: () => ({username: 'saved-operator'}), console: {log() {}},
    };
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    await AsyncFunction(...Object.keys(ports), reader.source.slice(entry.start, entry.end))(...Object.values(ports));
    assert.equal(opened.length, 1);
    assert.deepEqual(opened[0].authorization, authorization);
    assert.equal(connections.length, 2);
    assert.equal(hostCloses, 1);
    assert.equal(clientCloses, 2);
  }
});

test('planner Local and HTTPS constructors retain the supplied original source capacity', async () => {
  const {source, nodes} = await fixtureSyntax('./fixtures/planner-selection-public-query.mjs');
  const declaration = nodes.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'openSingleSourcePublicHost');
  const opened = [], connected = [];
  let closes = 0;
  const create = Function('createServer', 'userInfo',
    `return (${source.slice(declaration.start, declaration.end)});`)(() => ({
      listen(_port, _host, callback) {callback();}, address() {return {port: 443};},
      closeAllConnections() {}, close(callback) {callback();},
    }), () => ({username: 'planner-operator'}));
  const hostCapacityPolicy = Object.freeze({max_artifact_rows: 1000});
  for (const mode of ['local', 'https']) {
    const running = await create({mode, directory: mode, sourceProfilePath: 'original-source',
      tls: {key: 'fixture', cert: 'fixture'}, authorization: {original: 'policy'}, hostCapacityPolicy,
      async connect(options) {connected.push(options);},
      async openInstalledRemoteHttpHost(options) {
        opened.push(options);return {handler() {}, async close() {closes++;}};
      }});
    await running.connect();
    await running.close();
  }
  assert.equal(connected[0].installation.hostCapacityPolicy, hostCapacityPolicy);
  assert.equal(opened[0].hostCapacityPolicy, hostCapacityPolicy);
  assert.equal(closes, 1);
});

test('planner refusals require the exact original durable preparation outcome', async () => {
  const {source, nodes} = await fixtureSyntax('./fixtures/planner-selection-public-query.mjs');
  const branch = nodes.find(node => node.type === 'IfStatement' &&
    source.slice(node.test.start, node.test.end) === 'item.denyRead || item.deferred');
  for (const scenario of [
    {item: {denyRead: true}, code: 'ACTQL_E_ACCOUNT_DENIED', kind: 'preparation_failed', valid: true},
    {item: {deferred: true}, code: 'ClientProgramRejected', kind: 'preparation_failed', valid: true},
    {item: {deferred: true}, code: 'ClientProgramUnsupported', kind: 'preparation_failed', valid: false},
    {item: {deferred: true}, code: 'ClientProgramRejected', kind: 'not_accepted', valid: false},
    {item: {deferred: true}, code: 'ClientProgramRejected', kind: 'preparation_failed', foreign: true, valid: false},
  ]) {
    const submissionRef = {original: 'fixture-submission'};
    const outcome = {kind: scenario.kind, submissionRef: scenario.foreign ? {foreign: 'submission'} : submissionRef,
      problem: {code: scenario.code}};
    let durableLookups = 0;
    const ports = {assert, items: [scenario.item], text: 'original-program', requestId: 'original-request', submissionRef,
      client: {async startSource() {throw Object.assign(new Error('SubmissionPreparationFailed'),
        {code: 'SubmissionPreparationFailed', outcome});},
        async lookupRequest() {assert.fail('legacy name lookup is not this original submission');},
        async lookupSubmission(ref) {assert.equal(ref, submissionRef);durableLookups++;return outcome;}},
      provider: {snapshot: () => ({sourceIo: 0})}, before: {sourceIo: 0},
      events: [], readSelection: () => ({original: 'selection'}), assertSelection() {},
      readTwoSourceJournal: () => [], directory: 'original-fixture', mode: 'local', installation: {source: {}},
      observations: [],
    };
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    const run = () => AsyncFunction(...Object.keys(ports),
      'for (const item of items) {' + source.slice(branch.start, branch.end) + '}')(...Object.values(ports));
    if (scenario.valid) {
      await run();
      assert.equal(durableLookups, 1);
      assert.equal(ports.observations.length, 1);
    } else {
      await assert.rejects(run(), {code: 'ERR_ASSERTION'});
      assert.equal(durableLookups, 0);
    }
  }
});

test('Host failure diagnostics preserve original authorization and observer call semantics', () => {
  const result = Promise.resolve('original-return'), receiver = {}, detail = {code: 'ClientHostFailure'};
  const context = {}, calls = [];
  const authorization = Object.freeze({accountConfiguration: 'original-account', current: () => false,
    observe(...args) {
      calls.push({receiver: this, args});
      if (args[0] === 'model_recovery_failed') throw undefined;
      return result;
    }});
  const diagnostic = createPackedHostFailureDiagnostics(() => {});
  const wrapped = diagnostic.authorization(authorization);
  assert.equal(wrapped.accountConfiguration, authorization.accountConfiguration);
  assert.equal(wrapped.current, authorization.current);
  assert.equal(Reflect.apply(wrapped.observe, receiver, ['dispatch_failed', detail, context, 4]), result);
  let rejected = false;
  try { Reflect.apply(wrapped.observe, receiver, ['model_recovery_failed', detail]); }
  catch (error) { rejected = true; assert.equal(error, undefined); }
  assert.equal(rejected, true);
  assert.deepEqual(calls, [{receiver, args: ['dispatch_failed', detail, context, 4]},
    {receiver, args: ['model_recovery_failed', detail]}]);
  assert.equal(Object.hasOwn(diagnostic.authorization(undefined), 'accountConfiguration'), false);
});

test('Host failure diagnostics copy only allowlisted codes and own numeric tags without getters or payloads', () => {
  let reads = 0;
  const privateGetter = () => { reads++; throw new Error('PRIVATE_DIAGNOSTIC_PAYLOAD'); };
  const cause = Object.defineProperties({$tag: 6, _0: {$tag: 3}}, {
    message: {get: privateGetter}, stack: {get: privateGetter}, payload: {get: privateGetter},
  });
  const diagnostic = createPackedHostFailureDiagnostics(() => {});
  const authorization = diagnostic.authorization(undefined);
  authorization.observe('effect_start_failed', Object.defineProperties({code: 'ClientHostFailure', cause}, {
    ref: {get: privateGetter}, message: {get: privateGetter}, stack: {get: privateGetter},
  }));
  authorization.observe('dispatch_failed', Object.create({code: 'PRIVATE_DIAGNOSTIC_PAYLOAD', issueTag: 99}, {
    code: {get: privateGetter}, issueTag: {value: Infinity}, nestedIssueTag: {value: -1},
  }));
  authorization.observe('model_resume_failed', {code: 'PRIVATE_DIAGNOSTIC_PAYLOAD', issueTag: '6'});
  authorization.observe('dispatch_failed', new Proxy({}, {getOwnPropertyDescriptor: privateGetter}));
  authorization.observe('PRIVATE_DIAGNOSTIC_PAYLOAD', {code: 'ClientHostFailure'});
  const report = diagnostic.report();
  assert.equal(reads, 0);
  assert.equal(report.bestEffort, true);
  assert.equal(report.correlated, false);
  assert.equal(report.available, false);
  assert.equal(report.unavailable, true);
  assert.deepEqual(report.records, [
    {event: 'effect_start_failed', code: 'ClientHostFailure', issueTag: 6, nestedIssueTag: 3},
    {event: 'dispatch_failed'}, {event: 'model_resume_failed', codeOmitted: true},
    {event: 'dispatch_failed'},
  ]);
  assert.equal(JSON.stringify(report).includes('PRIVATE_DIAGNOSTIC_PAYLOAD'), false);
});

test('Host failure diagnostics read inherited MoonBit tags through only two DATA prototype hops', () => {
  let reads = 0;
  const privateGetter = () => { reads++; throw new Error('PRIVATE_PROTOTYPE_PAYLOAD'); };
  const privateFields = Object.fromEntries(['constructor', 'message', 'stack', 'payload'].map(key =>
    [key, {get: privateGetter}]));
  const outer = Object.defineProperties({$tag: 308}, privateFields);
  const inner = Object.defineProperties({$tag: 4}, privateFields);
  const diagnostic = createPackedHostFailureDiagnostics(() => {});
  const authorization = diagnostic.authorization(undefined);
  for (const hops of [1, 2]) {
    const wrap = prototype => hops === 1 ? Object.create(prototype) : Object.create(Object.create(prototype));
    const cause = Object.defineProperty(wrap(outer), '_0', {value: wrap(inner)});
    authorization.observe('effect_start_failed', {code: 'ClientHostFailure', cause});
  }
  authorization.observe('effect_start_failed', {code: 'ClientHostFailure',
    cause: Object.create(Object.create(Object.create({$tag: 999})))});
  authorization.observe('effect_start_failed', {code: 'ClientHostFailure',
    cause: Object.create(new Proxy({$tag: 999}, {
      getOwnPropertyDescriptor: privateGetter, getPrototypeOf: privateGetter, get: privateGetter,
    }))});
  authorization.observe('effect_start_failed', {code: 'ClientHostFailure',
    cause: Object.create(Object.defineProperty({}, '$tag', {get: privateGetter}))});
  const report = diagnostic.report();
  assert.equal(reads, 0);
  assert.equal(report.available, false);
  assert.equal(report.unavailable, true);
  assert.deepEqual(report.records, [
    {event: 'effect_start_failed', code: 'ClientHostFailure', issueTag: 308, nestedIssueTag: 4},
    {event: 'effect_start_failed', code: 'ClientHostFailure', issueTag: 308, nestedIssueTag: 4},
    {event: 'effect_start_failed', code: 'ClientHostFailure'},
    {event: 'effect_start_failed', code: 'ClientHostFailure'},
    {event: 'effect_start_failed', code: 'ClientHostFailure'},
  ]);
  assert.equal(JSON.stringify(report).includes('PRIVATE_PROTOTYPE_PAYLOAD'), false);
});

test('Host failure diagnostics retain at most eight recent sanitized records and absence stays unavailable', () => {
  const diagnostic = createPackedHostFailureDiagnostics(() => { throw new Error('ignored-report'); });
  assert.equal(diagnostic.report().available, false);
  assert.equal(diagnostic.report().unavailable, true);
  const authorization = diagnostic.authorization(undefined);
  for (let index = 0; index < 10; index++) {
    authorization.observe('dispatch_failed', {code: 'MoonBitHostFailure', issueTag: index});
  }
  const report = diagnostic.report();
  assert.equal(report.available, true);
  assert.equal(report.truncated, true);
  assert.deepEqual(report.records.map(record => record.issueTag), [2, 3, 4, 5, 6, 7, 8, 9]);
});

test('cold cohort restart preserves recorded authorization without Graph-only observer metadata', async () => {
  const {parse} = await import('acorn');
  const {observeRetainedGraphDispatch} = await import('./fixtures/retained-graph-observer.mjs');
  const source = await readFile(new URL('./fixtures/string-values-restart.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const loops = syntax.body.filter(node => node.type === 'ForOfStatement' && node.right.name === 'cohorts');
  assert.equal(loops.length, 1);
  const policySource = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const policySyntax = parse(policySource, {sourceType: 'module', ecmaVersion: 'latest'});
  const declarations = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === 'createPublicQueryHttpAuthorization') {
      declarations.push(node);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(policySyntax);
  assert.equal(declarations.length, 1);
  const [declaration] = declarations;
  const create = Function('userInfo', 'canonical', 'publicQueryResultOracles',
    `return (${policySource.slice(declaration.start, declaration.end)});`)(
      () => ({username: 'cold-reader'}), JSON.stringify, publicQueryResultOracles);
  const authorization = Object.freeze(create({primaryResultName: 'answer', successes: [
    {name: 'recorded', results: {answer: {}, secondary: {}}},
  ]}));
  const graphAuthorization = Object.freeze({...authorization,
    reviewers: [{keyId: 'fixture-only'}], hostKey: {privateKey: 'fixture-only'}});
  const cohorts = ['local', 'remote'].flatMap(mode => [
    {mode, directory: `${mode}-ordinary`, authorization},
    {mode, directory: `${mode}-observed`, authorization: graphAuthorization, expectedSampleNames: ['authored']},
    {mode, directory: `${mode}-no-recorded-policy`},
  ]);
  const reads = [], opened = [], wrapped = [], completedRoots = [], physicalDispatches = [];
  let hostsClosed = 0, serversClosed = 0, workerChecks = 0;
  const ports = {
    assert, cohorts, completedRoots, physicalDispatches, mode: undefined,
    worker: {check() {workerChecks++;}},
    observeRetainedGraphDispatch(original, events) {
      wrapped.push(original);
      return observeRetainedGraphDispatch(original, events);
    },
    async readRetainedCohort(cohort, options) {reads.push({cohort, options});},
    async openInstalledRemoteHttpHost(options) {
      opened.push(options);
      return {handler() {}, async close() {hostsClosed++;}};
    },
    createServer() {
      return {listen(_port, _host, callback) {callback();}, address() {return {port: 443};},
        closeAllConnections() {}, close(callback) {serversClosed++; callback();}};
    },
    async readFile() {return 'synthetic-TLS-fixture';},
    userInfo() {return {username: 'cold-reader'};},
  };
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  await AsyncFunction(...Object.keys(ports), source.slice(loops[0].start, loops[0].end))(...Object.values(ports));
  assert.deepEqual(completedRoots, cohorts.map(cohort => cohort.directory));
  assert.equal(reads.length, 6);
  assert.equal(workerChecks, 6);
  assert.equal(hostsClosed, 3);
  assert.equal(serversClosed, 3);
  assert.deepEqual(wrapped, [graphAuthorization, graphAuthorization]);
  assert.deepEqual(physicalDispatches, []);
  const policy = JSON.parse(authorization.accountConfiguration);
  assert.deepEqual(policy.entries.map(entry => ({principal: entry.principal,
    connection: entry.connection, resource: entry.resource, operation: entry.operation})), [
    {principal: {any_of: ['cold-reader']}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/answer', 'result/secondary', 'run']}, operation: {any_of: ['read']}},
    {principal: {any_of: ['cold-reader']}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['duckdb-acquired']}, operation: {any_of: ['write']}},
  ]);
  for (const {cohort, options} of reads) {
    const original = cohort.authorization;
    const installed = cohort.mode === 'local' ? options.installation :
      opened.find(item => item.directory === cohort.directory);
    assert.ok(installed);
    if (original === undefined) {
      assert.equal(installed.authorization, undefined, 'missing recorded policy must not invent grants');
    } else if (cohort.expectedSampleNames === undefined) {
      assert.equal(installed.authorization, original,
        'ordinary cold reader forwards the SAME recorded operator policy');
    } else {
      assert.equal(installed.authorization.accountConfiguration, original.accountConfiguration);
      assert.equal(installed.authorization.hostKey, original.hostKey);
      assert.equal(installed.authorization.reviewers, original.reviewers);
      assert.equal(typeof installed.authorization.faultInjection, 'function');
    }
  }
});

test('public query fixture names preserve explicit and structured exports independently of product output', () => {
  const expected = [{value: 1}], columns = [{name: 'value'}];
  const implicit = {format: 'sql', text: 'SELECT 1 AS value', expected, columns};
  assert.deepEqual(publicQueryResultOracles(implicit), {main: {rows: expected, columns}});
  assert.deepEqual(publicQueryResultOracles({...implicit, resultName: 'answer'}),
    {answer: {rows: expected, columns}});
  for (const format of ['json', 'aql-json']) {
    const structured = {...implicit, format, text: JSON.stringify({results: {answer: {from: {stage: 'main', result: 'answer'}}}})};
    assert.deepEqual(publicQueryResultOracles(structured), {answer: {rows: expected, columns}});
    assert.throws(() => publicQueryResultOracles({...structured,
      text: JSON.stringify({results: {answer: {}, other: {}}})}), /requires authored result oracles/u);
  }
  const results = {original: {rows: expected, columns}, answer: {rows: [], columns}};
  assert.equal(publicQueryResultOracles({...implicit, results}), results);
  assert.equal(publicQueryResultOracles(implicit).main.rows, expected);
});

test('scoped ORDER fixtures read the explicit authored export', async () => {
  const scope = JSON.parse(await readFile(new URL(
    '../spec/frontend/fixtures/pipe-scope/cases.json', import.meta.url), 'utf8'));
  const cases = scope.successes.filter(item => item.name.startsWith('scoped-order-'));
  assert.equal(cases.length, 4);
  for (const item of cases) {
    assert.match(item.text, /\|> RESULT answer$/u);
    assert.equal(item.resultName, 'answer');
    assert.deepEqual(publicQueryResultOracles(item), {
      answer: {rows: item.expected, columns: item.columns},
    });
  }
});
async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-transport-owner-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  return directory;
}

async function diagnosticTarget(t) {
  const directory = await fixture(t), path = join(directory, 'original-ingress.mjs');
  await writeFile(path, `const publicFailure = error => error;
function unusedResult(original) {
  try {throw original;}
  catch (error) {
    throw publicFailure(error);
  }
}
export function originalIngress(original) {
  try {throw original;}
  catch (error) {
    throw publicFailure(error);
  }
}
`);
  const sourceURL = pathToFileURL(path);
  return {path, sourceURL, ...await import(sourceURL.href)};
}

test('packed cause observer drains the original resume acknowledgement before session retirement', {timeout: 5000}, async () => {
  const source = 'original diagnostic fixture', url = 'file:///original-diagnostic-fixture.mjs';
  const calls = [], messages = [], port = new EventEmitter(), session = new EventEmitter();
  let resume, notifyResume, notifyLoaded, notifyClosed;
  const resuming = new Promise(resolve => {notifyResume = resolve;});
  const loaded = new Promise(resolve => {notifyLoaded = resolve;});
  const closed = new Promise(resolve => {notifyClosed = resolve;});
  port.postMessage = value => {messages.push(value); if (value.kind === 'loaded') notifyLoaded();};
  port.close = () => {calls.push('port.close'); notifyClosed();};
  session.connectToMainThread = () => calls.push('connect');
  session.disconnect = () => calls.push('disconnect');
  session.post = (method, parameters, callback) => {
    calls.push(method);
    if (method === 'Debugger.resume') {resume = () => callback(null, {}); notifyResume(); return;}
    queueMicrotask(() => callback(null,
      method === 'Debugger.setBreakpointByUrl' ? {breakpointId: 'original-breakpoint'} :
      method === 'Debugger.getScriptSource' ? {scriptSource: source} :
      method === 'Debugger.evaluateOnCallFrame' ? {result: {value: [{edge: 'original', type: 'Error'}]}} : {}));
  };
  await runSubmissionCauseObserver({session, parentPort: port,
    workerData: {url, frame: 0, lineNumber: 0, sha256: createHash('sha256').update(source).digest('hex')}});
  try {
    session.emit('Debugger.scriptParsed', {params: {url, scriptId: 'original-script'}});
    await loaded;
    session.emit('Debugger.paused', {params: {callFrames: [{
      callFrameId: 'original-frame', location: {scriptId: 'original-script'},
    }]}});
    await resuming;
    port.emit('message', {kind: 'close'});
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls.includes('Debugger.disable'), false, 'Disable cannot overlap the original resume flight');
    assert.equal(calls.includes('disconnect'), false);
  } finally {
    resume?.(); port.emit('message', {kind: 'close'}); await closed;
  }
  assert.equal(calls.filter(value => value === 'disconnect').length, 1);
  assert.equal(calls.filter(value => value === 'port.close').length, 1);
  assert.equal(messages.filter(value => value.kind === 'primary').length, 1);
});

for (const method of ['Debugger.enable', 'Debugger.getScriptSource']) {
test(`packed cause observer drains original ${method} before retiring its session once`, {timeout: 5000}, async () => {
  const source = 'original startup fixture', url = 'file:///original-startup-fixture.mjs';
  const calls = [], session = new EventEmitter(), port = new EventEmitter();
  let release, notifyPending, notifyClosed;
  const pending = new Promise(resolve => {notifyPending = resolve;});
  const closed = new Promise(resolve => {notifyClosed = resolve;});
  port.postMessage = () => {};
  port.close = () => {calls.push('port.close'); notifyClosed();};
  session.connectToMainThread = () => {};
  session.disconnect = () => calls.push('disconnect');
  session.post = (selected, parameters, callback) => {
    calls.push(selected);
    const result = selected === 'Debugger.setBreakpointByUrl' ? {breakpointId: 'original-breakpoint'} :
      selected === 'Debugger.getScriptSource' ? {scriptSource: source} : {};
    if (selected === method) {release = () => callback(null, result); notifyPending();}
    else queueMicrotask(() => callback(null, result));
  };
  const starting = runSubmissionCauseObserver({session, parentPort: port,
    workerData: {url, frame: 0, lineNumber: 0, sha256: createHash('sha256').update(source).digest('hex')}});
  try {
    if (method === 'Debugger.getScriptSource') {
      await starting;
      session.emit('Debugger.scriptParsed', {params: {url, scriptId: 'original-script'}});
    }
    await pending;
    port.emit('message', {kind: 'close'});
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls.includes('Debugger.disable'), false);
    assert.equal(calls.includes('disconnect'), false);
  } finally {
    release?.(); port.emit('message', {kind: 'close'}); await starting; await closed;
  }
  assert.equal(calls.filter(value => value === 'disconnect').length, 1);
  assert.equal(calls.filter(value => value === 'Debugger.disable').length, 1);
  assert.equal(calls.filter(value => value === 'port.close').length, 1);
  if (method === 'Debugger.enable') assert.equal(calls.includes('Debugger.setBreakpointByUrl'), false);
});
}

for (const matches of [true, false]) {
test(`packed cause observer validates an already loaded ${matches ? 'matching' : 'mismatched'} Source before arming its boundary`, {timeout: 5000}, async () => {
  const source = 'original loaded Source', url = 'file:///original-loaded-source.mjs';
  const session = new EventEmitter(), port = new EventEmitter(), calls = [], messages = [];
  let release, notifyPending, notifyClosed;
  const pending = new Promise(resolve => {notifyPending = resolve;});
  const closed = new Promise(resolve => {notifyClosed = resolve;});
  session.connectToMainThread = () => {};
  session.disconnect = () => calls.push('disconnect');
  port.postMessage = value => messages.push(value);
  port.close = () => {calls.push('port.close'); notifyClosed();};
  session.post = (method, parameters, callback) => {
    calls.push(method);
    if (method === 'Debugger.getScriptSource') {
      release = () => callback(null, {scriptSource: matches ? source : 'different Source'});
      notifyPending();
      return;
    }
    queueMicrotask(() => {
      if (method === 'Debugger.enable') session.emit('Debugger.scriptParsed', {
        params: {url, scriptId: 'original-loaded-script'},
      });
      callback(null, method === 'Debugger.setBreakpointByUrl'
        ? {breakpointId: 'original-breakpoint'} : {});
    });
  };
  const starting = runSubmissionCauseObserver({session, parentPort: port,
    workerData: {url, frame: 0, lineNumber: 0,
      sha256: createHash('sha256').update(source).digest('hex')}});
  try {
    await pending;
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls.includes('Debugger.setBreakpointByUrl'), false,
      'An already loaded original must finish its Source validation before its boundary is armed');
    assert.equal(messages.some(value => value.kind === 'ready'), false);
    release();
    await starting;
    assert.equal(calls.includes('Debugger.setBreakpointByUrl'), matches);
    assert.equal(messages.some(value => value.kind === 'ready'), matches);
    assert.equal(messages.some(value => value.kind === 'loaded'), matches);
    assert.equal(messages.some(value => value.kind === 'unavailable'), !matches);
  } finally {
    release?.(); port.emit('message', {kind: 'close'}); await starting; await closed;
  }
  assert.equal(calls.filter(value => value === 'disconnect').length, 1);
  assert.equal(calls.filter(value => value === 'port.close').length, 1);
});
}

test('packed cause observer still arms a later-loaded Source before its original import', {timeout: 5000}, async () => {
  const source = 'original later Source', url = 'file:///original-later-source.mjs';
  const session = new EventEmitter(), port = new EventEmitter(), messages = [];
  let notifyLoaded, notifyClosed;
  const loaded = new Promise(resolve => {notifyLoaded = resolve;});
  const closed = new Promise(resolve => {notifyClosed = resolve;});
  session.connectToMainThread = () => {};
  session.disconnect = () => {};
  session.post = (method, parameters, callback) => queueMicrotask(() => callback(null,
    method === 'Debugger.getScriptSource' ? {scriptSource: source} :
    method === 'Debugger.setBreakpointByUrl' ? {breakpointId: 'original-breakpoint'} : {}));
  port.postMessage = value => {messages.push(value); if (value.kind === 'loaded') notifyLoaded();};
  port.close = () => notifyClosed();
  await runSubmissionCauseObserver({session, parentPort: port,
    workerData: {url, frame: 0, lineNumber: 0,
      sha256: createHash('sha256').update(source).digest('hex')}});
  try {
    assert.deepEqual(messages.map(value => value.kind), ['ready']);
    session.emit('Debugger.scriptParsed', {params: {url, scriptId: 'original-later-script'}});
    await loaded;
    assert.deepEqual(messages.map(value => value.kind), ['ready', 'loaded']);
  } finally {port.emit('message', {kind: 'close'}); await closed;}
});

test('packed cause observer retains its Worker until the disconnect callback turn completes', async () => {
  const session = new EventEmitter(), port = new EventEmitter(), calls = [];
  let notifyClosed;
  const closed = new Promise(resolve => {notifyClosed = resolve;});
  session.connectToMainThread = () => {};
  session.post = (method, parameters, callback) => queueMicrotask(() => callback(null,
    method === 'Debugger.setBreakpointByUrl' ? {breakpointId: 'original-breakpoint'} : {}));
  session.disconnect = () => {
    calls.push('disconnect');
    setImmediate(() => calls.push('disconnect.callback'));
  };
  port.postMessage = () => {};
  port.close = () => {calls.push('port.close'); notifyClosed();};
  await runSubmissionCauseObserver({session, parentPort: port,
    workerData: {url: 'file:///original-disconnect-fixture.mjs', frame: 0, lineNumber: 0,
      sha256: createHash('sha256').update('original disconnect fixture').digest('hex')}});
  port.emit('message', {kind: 'close'});
  await closed;
  assert.deepEqual(calls, ['disconnect', 'disconnect.callback', 'port.close']);
});

test('packed cause observer captures bounded original DATA and always resumes the same throw', async t => {
  const target = await diagnosticTarget(t), reports = [];
  const original = Object.assign(new TypeError('private-message-never-reported'), {
    code: 'ClientProgramUnsupported', requestId: 'private-request-never-reported',
    cause: Object.assign(new Error('private-inner-never-reported'), {code:'ForeignRequestOriginal'}),
  });
  let reads = 0, enumerations = 0;
  Object.defineProperty(original, '_0', {get() {reads++; throw new Error('accessor invoked');}});
  Object.defineProperty(original, 'unrelatedPrivateField', {get() {reads++; throw new Error('private field read');}});
  const reflected = [];
  const primary = new Proxy(original, {
    ownKeys() {enumerations++; throw new Error('private fields enumerated');},
    getOwnPropertyDescriptor(target, key) {
      reflected.push(key);
      assert.ok(['code','cause','primaryFailure','_0','_1','_2'].includes(key));
      return Reflect.getOwnPropertyDescriptor(target, key);
    },
  });
  original.cause.primaryFailure = primary;
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {
    assert.throws(() => target.originalIngress(primary), error => error === primary);
    assert.throws(() => target.originalIngress(primary), error => error === primary);
  } finally {await observer.close();}
  await observer.close();
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, true);
  assert.equal(reports[0].originalCauseTypes.length, 1, 'only the first original boundary is observed');
  assert.deepEqual(reports[0].originalCauseTypes[0], [
    {edge:'original',type:'TypeError',code:'ClientProgramUnsupported'},
    {edge:'cause',type:'Error',code:'ForeignRequestOriginal'},
    {edge:'_0',type:'Accessor'},
  ]);
  assert.equal(reads, 0);
  assert.equal(enumerations, 0);
  assert.ok(reflected.length > 0);
  assert.ok(!reflected.includes('stack') && !reflected.includes('unrelatedPrivateField'));
  assert.doesNotMatch(JSON.stringify(reports), /private-|requestId|message|stack/u);
});

test('packed cause observer report failure cannot replace the original exception or cleanup', async t => {
  const target = await diagnosticTarget(t);
  const primary = new RangeError('original'), diagnostic = new Error('report unavailable');
  let reports = 0, caught;
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report() {reports++;throw diagnostic;}});
  try {target.originalIngress(primary);}
  catch (error) {caught=error;}
  finally {await observer.close();}
  assert.equal(caught, primary);
  assert.equal(reports, 1);
  assert.throws(() => target.originalIngress(primary), error => error === primary);
});

test('packed cause observer refuses a loaded Source mismatch without changing the original result', async t => {
  const target = await diagnosticTarget(t), reports = [];
  await writeFile(target.path, (await readFile(target.path, 'utf8'))+'\n// changed after original import\n');
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  const primary = new Error('unchanged original');
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
});

test('packed cause observer inspection failure resumes and preserves the original exception', async t => {
  const target = await diagnosticTarget(t), reports = [];
  const primary = new Proxy(new Error('original'), {
    getOwnPropertyDescriptor() {throw new Error('descriptor inspection unavailable');},
  });
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
});

test('packed cause observer never sends a private inspection exception to Inspector formatting', async t => {
  const target = await diagnosticTarget(t), reports = [];
  let reads = 0;
  const privateFailure = new Error('private-inspection-failure');
  for (const name of ['stack', 'message', 'name']) Object.defineProperty(privateFailure, name,
    {get() {reads++;throw new Error('private-inspection-getter');}});
  const primary = new Proxy(new Error('original'), {
    getOwnPropertyDescriptor() {throw privateFailure;},
  });
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reads, 0, 'Reflection failure must stay inside the bounded inspection expression');
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
  assert.deepEqual(reports[0].originalCauseTypes, []);
  assert.doesNotMatch(JSON.stringify(reports), /private-|message|stack/u);
});

test('packed cause observer discards partial DATA when nested reflection fails', async t => {
  const target = await diagnosticTarget(t), reports = [];
  let reads = 0;
  const privateFailure = new Error('private-nested-inspection-failure');
  Object.defineProperty(privateFailure, 'stack', {get() {reads++;throw new Error('private-getter');}});
  const primary = Object.assign(new Error('original'), {code:'ClientProgramUnsupported',
    cause:new Proxy({}, {getOwnPropertyDescriptor() {throw privateFailure;}})});
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reads, 0);
  assert.equal(reports[0].available, false);
  assert.deepEqual(reports[0].originalCauseTypes, [], 'The earlier original row is not a complete observation');
  assert.doesNotMatch(JSON.stringify(reports), /private-|ClientProgramUnsupported|message|stack/u);
});

test('packed cause observer retains a closed Node failure code without collecting its message', async t => {
  const target = await diagnosticTarget(t), reports = [];
  const primary = Object.assign(new Error('private-SQL-never-reported'), {code:'ERR_SQLITE_ERROR'});
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[{edge:'original',type:'Error',code:'ERR_SQLITE_ERROR'}]]);
  assert.doesNotMatch(JSON.stringify(reports), /private-SQL/u);
});

test('packed cause observer omits a plausible private code and forged MoonBit constructor name', async t => {
  const target = await diagnosticTarget(t), reports = [];
  class _MPrivateInputSecret extends Error {}
  const primary = Object.assign(new _MPrivateInputSecret('private-message'), {code:'ClientPrivateInputSecret'});
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[{edge:'original',type:'MoonBit',codeOmitted:true,codeType:'String'}]]);
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-message/u);
});

test('packed cause observer retains exact factory codes and primitive edge types without their values', async t => {
  const target = await diagnosticTarget(t), reports = [];
  const primary = Object.assign(new Error('private-factory-message'), {
    code:'MoonBitHostFailure', cause:9234567, _0:undefined, _1:null,
    _2:{code:'NodeManagedRunAdmissionUnavailable', cause:'private-primitive-string', primaryFailure:()=> 'private-function',
      _0:true, _1:9234568n, _2:Symbol('private-symbol')},
  });
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[
    {edge:'original',type:'Error',code:'MoonBitHostFailure'},
    {edge:'cause',type:'Number'}, {edge:'_0',type:'Undefined'}, {edge:'_1',type:'Null'},
    {edge:'_2',type:'Object',code:'NodeManagedRunAdmissionUnavailable'}, {edge:'cause',type:'String'},
    {edge:'primaryFailure',type:'Function'}, {edge:'_0',type:'Boolean'},
    {edge:'_1',type:'BigInt'}, {edge:'_2',type:'Symbol'},
  ]]);
  assert.doesNotMatch(JSON.stringify(reports), /9234567|9234568|private-/u);
});

test('packed cause observer retains reviewed Local preparation factory codes with an undefined cause', async t => {
  const codes = ['RunHostCompilationRejected', 'RunHostTaskCompilationRejected',
    'RunHostAdmissionRejected', 'RunHostStaticPlanRejected', 'RunHostOriginalPlanRejected'];
  const factory = await readFile(new URL('../adapters/host-common/runtime-core.mjs', import.meta.url), 'utf8');
  assert(factory.includes("new Error(code, {cause: error.cause})"));
  for (const code of codes) assert(factory.includes(`'${code}'`), code);
  const target = await diagnosticTarget(t), reports = [];
  const error = code => Object.assign(new Error('private-factory-message'), {code, cause:undefined});
  const original = error(codes[0]);
  original.primaryFailure = error(codes[1]); original._0 = error(codes[2]);
  original._1 = error(codes[3]); original._2 = error(codes[4]);
  original._2.cause = error('RunHostPrivateInputSecret');
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(original), value => value === original);}
  finally {await observer.close();}
  assert.equal(reports[0].available, true);
  const rows = reports[0].originalCauseTypes.flat();
  assert.deepEqual(rows.flatMap(row => row.code === undefined ? [] : [row.code]).sort(), [...codes].sort());
  assert.equal(rows.filter(row => row.type === 'Undefined').length, 5);
  assert(rows.some(row => row.type === 'Error' && row.codeOmitted === true));
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-factory-message|message|stack/u);
});

test('packed cause observer retains closed compiled-Run submission factory codes', async t => {
  const codes = [
    'RunHostResultPolicyRejected', 'RunHostResultSelectionRejected',
    'RunHostTaskDefinitionRejected', 'RunHostSourceFreeDefinitionRejected',
    'RunHostSourceFreeAdmissionRejected', 'RunHostTaskInvocationRejected', 'RunHostInvocationRejected',
  ];
  const factory = await readFile(new URL('../adapters/host-common/runtime-core.mjs', import.meta.url), 'utf8');
  assert(factory.includes('new Error(code, {cause: error.cause})'));
  for (const code of codes) assert(factory.includes(`'${code}'`), code);
  const target = await diagnosticTarget(t), reports = [];
  const errors = codes.map(code => Object.assign(new Error('private-submit-boundary'),
    {code, cause:undefined}));
  for (let index = 1; index < errors.length; index++) errors[index - 1].primaryFailure = errors[index];
  let reads = 0;
  Object.defineProperty(errors.at(-1), '_0', {get() {reads++;throw new Error('private-getter');}});
  errors.at(-1)._1 = {code:'RunHostPrivateInputSecret'};
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(errors[0]), error => error === errors[0]);}
  finally {await observer.close();}
  assert.equal(reads, 0);
  assert.equal(reports[0].available, true);
  const rows = reports[0].originalCauseTypes.flat();
  assert.deepEqual(rows.flatMap(row => row.code === undefined ? [] : [row.code]), codes);
  assert.equal(rows.filter(row => row.type === 'Undefined').length, codes.length);
  assert(rows.some(row => row.type === 'Accessor'));
  assert(rows.some(row => row.codeOmitted === true && row.codeType === 'String'));
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-|message|stack/u);
});

test('packed cause observer classifies omitted code descriptors without getters or values', async t => {
  const target = await diagnosticTarget(t), reports = [];
  let reads = 0;
  const original = Object.assign(new Error('private-code-description'), {
    code:undefined, _0:{code:'PrivateCodeSecret'}, _1:{code:9234567}, _2:{code:{}},
    cause:Object.defineProperty({}, 'code', {get() {reads++;throw new Error('private-getter');}}),
  });
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(original), value => value === original);}
  finally {await observer.close();}
  assert.equal(reads, 0);
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[
    {edge:'original',type:'Error',codeOmitted:true,codeType:'Undefined'},
    {edge:'cause',type:'Object',codeOmitted:true,codeType:'Accessor'},
    {edge:'_0',type:'Object',codeOmitted:true,codeType:'String'},
    {edge:'_1',type:'Object',codeOmitted:true,codeType:'Number'},
    {edge:'_2',type:'Object',codeOmitted:true,codeType:'Other'},
  ]]);
  assert.doesNotMatch(JSON.stringify(reports), /PrivateCodeSecret|9234567|private-|message|stack/u);
});

test('packed cause observer covers fixed submit factories without deriving categories from runtime data', {timeout: 30_000}, async t => {
  const {parse} = await import('acorn');
  const modules = [
    'adapters/host-node/in-process-client.mjs', 'adapters/host-node/client-http.mjs',
    'adapters/host-node/client-request-journal.mjs', 'adapters/host-node/client-submission.mjs',
    'adapters/host-node/client-program-preparation.mjs', 'adapters/host-node/client-submit.mjs',
    'adapters/host-node/ordinary-source-managed.mjs', 'adapters/host-node/source-managed-original-input.mjs',
    'adapters/host-node/embedded-local.mjs', 'adapters/host-node/local-account-config.mjs',
    'adapters/host-node/ordinary-local-account.mjs', 'adapters/host-node/ordinary-mock-account.mjs',
    'adapters/host-node/ordinary-host-control.mjs', 'adapters/host-node/ordinary-host-journal.mjs',
    'adapters/host-node/node-host-journal-installation.mjs', 'adapters/host-node/node-source-managed-installation.mjs',
    'adapters/host-node/client-source-operation.mjs', 'adapters/host-node/installed-row-source.mjs',
    'adapters/host-node/bounded-continuation-metadata.mjs', 'adapters/host-node/bounded-continuation-directory.mjs',
    'adapters/host-common/runtime-core.mjs', 'adapters/host-common/runtime-result.mjs',
    'adapters/host-common/sqlite-format-inspection.mjs', 'adapters/host-common/sqlite-transaction.mjs',
  ];
  const syntax = source => parse(source, {ecmaVersion:'latest', sourceType:'module'});
  const helperSource = await readFile(new URL('./fixtures/packed-query-transport-owner.mjs', import.meta.url), 'utf8');
  const declaration = syntax(helperSource).body.flatMap(node => node.declarations ?? [])
    .find(node => node.id.name === 'originalFailureCodes');
  assert.equal(declaration.init.callee.object.name, 'Object');
  assert.equal(declaration.init.callee.property.name, 'freeze');
  const entries = declaration.init.arguments[0];
  assert.equal(entries.type, 'ArrayExpression');
  assert(entries.elements.every(node => node.type === 'Literal' && typeof node.value === 'string'));
  const codes = entries.elements.map(node => node.value), fixed = new Set(codes);
  assert.equal(codes.length, fixed.size);
  const selected = new Set(), factoryArguments = {fail:0, invalid:0,
    clientOperationError:0, compiledRunResult:1, rejectSubmission:0, failure:0};
  const literal = node => {
    if (node?.type === 'Literal' && typeof node.value === 'string' && /^[A-Z][A-Za-z0-9_]+$/u.test(node.value)) {
      selected.add(node.value);
    } else if (node?.type === 'ConditionalExpression') {
      literal(node.consequent); literal(node.alternate);
    } else if (node?.type === 'LogicalExpression') {
      literal(node.left); literal(node.right);
    }
  };
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && Object.hasOwn(factoryArguments, node.callee.name)) {
      literal(node.arguments[factoryArguments[node.callee.name]]);
    }
    if (node.type === 'AssignmentExpression' && node.left.type === 'MemberExpression' && node.left.property.name === 'code') {
      literal(node.right);
    }
    if (node.type === 'Property' && ['code', 'unavailableCode', 'cleanupCode'].includes(node.key.name ?? node.key.value)) {
      literal(node.value);
    }
    if (node.type === 'VariableDeclarator' && ['issueCodes', 'effectIssueCodes'].includes(node.id.name)) {
      assert.equal(node.init.callee.object.name, 'Object');
      assert.equal(node.init.callee.property.name, 'freeze');
      assert.equal(node.init.arguments[0].type, 'ObjectExpression');
      for (const entry of node.init.arguments[0].properties) literal(entry.value);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  for (const path of modules) visit(syntax(await readFile(new URL('../' + path, import.meta.url), 'utf8')));
  // This actual transaction factory has exactly two selected Journal callers.
  // Expand only their Source-pinned prefixes, never an arbitrary runtime prefix.
  const transaction = await readFile(new URL('../adapters/host-common/sqlite-transaction.mjs', import.meta.url), 'utf8');
  const journal = await readFile(new URL('../adapters/host-node/client-request-journal.mjs', import.meta.url), 'utf8');
  for (const prefix of ['ClientRequestJournal', 'ClientObservation']) {
    assert(journal.includes(`'${prefix}'`));
    for (const suffix of ['ConnectionUnusable', 'CommitOutcomeUnknown', 'RollbackFailed']) {
      assert(transaction.includes('${prefix}' + suffix));
      selected.add(prefix + suffix);
    }
  }
  const http = await readFile(new URL('../adapters/host-node/client-http.mjs', import.meta.url), 'utf8');
  assert(http.includes("responseCode(error) === 500 ? 'ClientHostFailure'"));
  selected.add('ClientHostFailure');
  for (const code of selected) assert(fixed.has(code), 'Missing fixed production factory code: ' + code);
  // Execute all fixed categories in bounded batches. Foreign strings and
  // accessors stay omitted; the live observer still uses only this literal set.
  for (let offset = 0; offset < codes.length; offset += 7) {
    const batch = codes.slice(offset, offset + 7), target = await diagnosticTarget(t), reports = [];
    const originals = batch.map(code => Object.assign(new Error('private-original-message'), {code, cause:undefined}));
    for (let index = 1; index < originals.length; index++) originals[index - 1].primaryFailure = originals[index];
    let reads = 0;
    Object.defineProperty(originals.at(-1), '_0', {get() {reads++;throw new Error('private-getter');}});
    originals.at(-1)._1 = {code:'ClientPrivateFactoryPayload'};
    const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL, report:value=>reports.push(value)});
    try {assert.throws(() => target.originalIngress(originals[0]), error => error === originals[0]);}
    finally {await observer.close();}
    assert.equal(reads, 0); assert.equal(reports[0].available, true);
    const rows = reports[0].originalCauseTypes.flat();
    assert.deepEqual(rows.flatMap(row => row.code === undefined ? [] : [row.code]), batch);
    assert(rows.some(row => row.type === 'Accessor'));
    assert(rows.some(row => row.codeOmitted === true && row.codeType === 'String'));
    assert.doesNotMatch(JSON.stringify(reports), /private-|PrivateFactoryPayload|message|stack/u);
  }
});

async function statusDiagnosticTarget(t, transport, {foreignCaller = false} = {}) {
  const caller = foreignCaller ? 'foreignFailure' : 'publicFailure';
  const directory = await fixture(t), path = join(directory, 'status-ingress.mjs');
  const shared = `const statuses = new WeakMap(); let reads = 0;
const responseCode = error => { reads++; return statuses.get(error); };
export const statusReads = () => reads;
`;
  const source = transport === 'http' ? shared + `
function sendError(response, error) {
  const status = responseCode(error);
  response.writeHead(status, {'content-type': 'application/json'});
}
export function originalIngress(original, status) {
  statuses.set(original, status);
  try {throw original;}
  catch (error) {sendError({writeHead() {}}, error); throw error;}
}
` : shared + `
class ClientError extends Error {
  constructor(code, {status}) {super(code); this.code = code; this.status = status;}
}
const localErrors = new WeakSet();
const publicClientErrorStatus = responseCode;
const publicClientErrorCode = error => statuses.get(error) === 500 ? 'ClientHostFailure' : 'ClientProgramUnsupported';
const publicError = (code, status) => {
  const error = new ClientError(code, {status});
  delete error.stack;
  return error;
};
const ${caller} = error => localErrors.has(error) ? error
  : publicError(publicClientErrorCode(error), publicClientErrorStatus(error));
const host = {perform(operation, original, status) {
  statuses.set(original, status);
  try {throw original;}
  catch (error) {throw ${caller}(error);}
}};
export function originalIngress(original, status, operation = 'submit-intent') {
  return host.perform(operation, original, status);
}
`;
  await writeFile(path, source);
  const sourceURL = pathToFileURL(path);
  return {sourceURL, ...await import(sourceURL.href)};
}

for (const transport of ['http', 'local']) {
  test(`packed cause observer captures only the first ${transport} 500 from its computed status and original frame`, async t => {
    const target = await statusDiagnosticTarget(t, transport), reports = [];
    const expected = Object.assign(new Error('private-decline'), {code:'ClientProgramUnsupported'});
    const original = Object.assign(new Error('private-primary'), {code:'MoonBitHostFailure'});
    let reflected = 0;
    const later = new Proxy(new Error('private-later'), {
      getPrototypeOf() {reflected++; throw new Error('Later original must not be inspected');},
    });
    const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
      boundary:transport + '-500', report:value=>reports.push(value)});
    const unchanged = (error, primary, status) => transport === 'http' ? error === primary
      : error !== primary && error.code === (status === 500 ? 'ClientHostFailure' : 'ClientProgramUnsupported') && error.status === status;
    try {
      assert.throws(() => target.originalIngress(expected, 422), error => unchanged(error, expected, 422));
      assert.throws(() => target.originalIngress(original, 500), error => unchanged(error, original, 500));
      assert.throws(() => target.originalIngress(later, 500), error => unchanged(error, later, 500));
    } finally {await observer.close();}
    assert.equal(target.statusReads(), 3, 'the breakpoint condition must not repeat status classification');
    assert.equal(reflected, 0, 'later errors are not reflected after the first 500');
    assert.equal(reports.length, 1);
    assert.equal(reports[0].available, true);
    assert.deepEqual(reports[0].originalCauseTypes, [[{edge:'original',type:'Error',code:'MoonBitHostFailure'}]]);
    assert.doesNotMatch(JSON.stringify(reports), /private-|decline|later|message|stack/u);
  });
}

test('packed cause observer refuses a different Local caller and still resumes its public outcome', async t => {
  const target = await statusDiagnosticTarget(t, 'local', {foreignCaller:true}), reports = [];
  const original = Object.assign(new Error('private-foreign-caller'), {code:'MoonBitHostFailure'});
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    boundary:'local-500', report:value=>reports.push(value)});
  try {
    assert.throws(() => target.originalIngress(original, 500), error =>
      error !== original && error.code === 'ClientHostFailure' && error.status === 500);
  } finally {await observer.close();}
  assert.equal(target.statusReads(), 1);
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
  assert.equal(reports[0].unavailableReason, 'original-caller-unavailable');
  assert.deepEqual(reports[0].originalCauseTypes, []);
  assert.doesNotMatch(JSON.stringify(reports), /private-|foreignFailure|message|stack/u);
});

test('packed submission cause ignores earlier non-submission failures without inspecting their errors', async t => {
  for (const operation of ['submit', 'submit-intent', 'submit-named-intent', 'restart-intent']) {
    const target = await statusDiagnosticTarget(t, 'local'), reports = [];
    let reflected = 0;
    const unrelated = new Proxy(new Error('private-unrelated'), {
      getPrototypeOf() {reflected++; throw new Error('Unrelated error must not be inspected');},
    });
    const original = Object.assign(new Error('private-submission'), {code: 'RunHostOriginalPlanRejected'});
    const observer = await observePackedSubmissionCause({sourceURL: target.sourceURL,
      boundary: 'local-submission-500', report: value => reports.push(value)});
    try {
      assert.throws(() => target.originalIngress(unrelated, 422, operation),
        {code: 'ClientProgramUnsupported', status: 422});
      for (const prior of ['read', 'result-describe', 'private-operation']) {
        assert.throws(() => target.originalIngress(unrelated, 500, prior),
          {code: 'ClientHostFailure', status: 500});
      }
      assert.throws(() => target.originalIngress(original, 500, operation),
        {code: 'ClientHostFailure', status: 500});
      assert.throws(() => target.originalIngress(unrelated, 500, operation),
        {code: 'ClientHostFailure', status: 500});
    } finally {await observer.close();}
    assert.equal(target.statusReads(), 6, 'Observation never repeats status classification');
    assert.equal(reflected, 0, 'Unrelated and later errors remain uninspected');
    assert.equal(reports.length, 1);
    assert.equal(reports[0].available, true);
    assert.deepEqual(reports[0].originalCauseTypes,
      [[{edge: 'original', type: 'Error', code: 'RunHostOriginalPlanRejected'}]]);
    assert.doesNotMatch(JSON.stringify(reports), /private-|message|stack/u);
  }
});

test('complete transport inventory rejects missing, duplicate, extra and reordered identities', () => {
  // Independently authored expected identities, not generated from a partition.
  const expected = ['standard/success/a', 'standard/failure/b', 'standard/refusal/c'];
  requireCompleteInventory(expected, [...expected]);
  for (const supplied of [expected.slice(0, 2), [...expected, expected[0]],
    [...expected, 'standard/success/foreign'], [...expected].reverse()]) {
    assert.throws(() => requireCompleteInventory(expected, supplied));
  }
  assert.throws(() => requireCompleteInventory(['duplicate', 'duplicate'], ['duplicate', 'duplicate']));
});

test('two actual workers isolate mutable source state and counters and both settle', async t => {
  const directory = await fixture(t);
  assert.deepEqual(sourceFixturePaths('local', 'standard', directory), {
    database: join(directory, 'records.duckdb'), sourceProfilePath: join(directory, 'source-profile.json'),
  });
  assert.deepEqual(sourceFixturePaths('remote', 'standard', directory), {
    database: join(directory, 'records-remote.duckdb'), sourceProfilePath: join(directory, 'source-profile-remote.json'),
  });
  const owner = createTransportOwner({deadline: Date.now() + 5000, forward() {}});
  try {
    await owner.run([['local', 11], ['remote', 17]].map(([mode, expected]) => command(mode, `
      import assert from 'node:assert/strict';
      import {writeFile, readFile} from 'node:fs/promises';
      import {ownTransportWorker, sourceFixturePaths} from ${JSON.stringify(helper)};
      const worker = ownTransportWorker();
      const file = sourceFixturePaths(${JSON.stringify(mode)}, 'standard', ${JSON.stringify(directory)}).database;
      globalThis.sourceCounter = 0;
      try {
        for (let row = 0; row < ${expected}; row++) {
          worker.check();
          await writeFile(file, String(row));
          await new Promise(resolve => setTimeout(resolve, 1));
          assert.equal(await readFile(file, 'utf8'), String(row));
          globalThis.sourceCounter++;
        }
        await writeFile(file + '.count', String(globalThis.sourceCounter));
      } finally { worker.release(); }
    `)));
    assert.equal(await readFile(join(directory, 'records.duckdb.count'), 'utf8'), '11');
    assert.equal(await readFile(join(directory, 'records-remote.duckdb.count'), 'utf8'), '17');
    const report = owner.report();
    assert.equal(report.liveChildren, 0);
    assert.equal(new Set(report.children.map(child => child.pid)).size, 2);
    assert.ok(report.children.every(child => child.terminal && child.status === 0));
  } finally { owner.close(); }
});

test('a worker failure remains primary and sibling cancellation finishes cleanup before release', async t => {
  const directory = await fixture(t);
  const owner = createTransportOwner({deadline: Date.now() + 5000, forward() {}});
  const ready = join(directory, 'ready'), cleaned = join(directory, 'cleaned');
  try {
    await assert.rejects(owner.run([
      command('original-failure', `
        import {access} from 'node:fs/promises';
        for (;;) { try { await access(${JSON.stringify(ready)}); break; }
          catch { await new Promise(resolve => setTimeout(resolve, 1)); } }
        process.exitCode = 9;
      `),
      command('sibling', `
        import {writeFile} from 'node:fs/promises';
        import {ownTransportWorker} from ${JSON.stringify(helper)};
        const worker = ownTransportWorker();
        try {
          await writeFile(${JSON.stringify(ready)}, 'ready');
          for (;;) { worker.check(); await new Promise(resolve => setTimeout(resolve, 1)); }
        } finally { await writeFile(${JSON.stringify(cleaned)}, 'closed'); worker.release(); }
      `),
    ]), /PackedQueryWorkerFailed:original-failure/u);
    assert.equal(await readFile(cleaned, 'utf8'), 'closed');
    assert.equal(owner.report().liveChildren, 0);
    assert.ok(owner.report().children.every(child => child.terminal));
    assert.equal(owner.report().children[0].status, 9);
  } finally { owner.close(); }
});

test('one absolute deadline stops both owned workers without granting a new child budget', async () => {
  const deadline = Date.now() + 200;
  const owner = createTransportOwner({deadline, forward() {}});
  try {
    await assert.rejects(owner.run(['local', 'remote'].map(mode => command(mode, `
      import {ownTransportWorker} from ${JSON.stringify(helper)};
      ownTransportWorker();
      setInterval(() => {}, 1000);
    `))), /PackedQueryAcceptanceDeadline/u);
    assert.equal(owner.report().deadline, deadline);
    assert.equal(owner.report().liveChildren, 0);
    assert.ok(owner.report().children.every(child => child.terminal && child.signal === 'SIGKILL'));
    assert.throws(() => owner.check(), /PackedQueryAcceptanceDeadline/u);
  } finally { owner.close(); }
});

test('the two workers consume one aggregate output allowance', async () => {
  const owner = createTransportOwner({deadline: Date.now() + 5000, outputLimit: 100, forward() {}});
  try {
    await assert.rejects(owner.run(['local', 'remote'].map(mode => command(mode,
      `process.stdout.write('x'.repeat(60));`))), /PackedQueryAggregateOutputLimit/u);
    assert.equal(owner.report().liveChildren, 0);
    assert.equal(owner.report().outputLimit, 100);
  } finally { owner.close(); }
});

test('abrupt coordinator death stops its worker through the owned IPC connection', async t => {
  const directory = await fixture(t);
  const stopped = join(directory, 'stopped');
  const worker = `
    import {writeFileSync} from 'node:fs';
    import {ownTransportWorker} from ${JSON.stringify(helper)};
    ownTransportWorker();
    process.on('exit', () => writeFileSync(${JSON.stringify(stopped)}, 'physically stopped'));
    process.send({ready: true});
    setInterval(() => {}, 1000);
  `;
  const parent = spawn(process.execPath, ['--input-type=module', '-e', `
    import {spawn} from 'node:child_process';
    const child = spawn(process.execPath, ['--input-type=module', '-e', ${JSON.stringify(worker)}],
      {stdio: ['ignore', 'ignore', 'ignore', 'ipc'], detached: false});
    child.once('message', () => process.send({ready: true}));
    process.on('disconnect', () => { child.kill('SIGKILL'); process.exit(1); });
  `], {stdio: ['ignore', 'ignore', 'ignore', 'ipc'], detached: false});
  t.after(() => { if (parent.exitCode === null && parent.signalCode === null) parent.kill('SIGKILL'); });
  const terminal = new Promise(resolve => parent.once('close', resolve));
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('fixture worker did not become ready')), 3000);
    parent.once('message', () => { clearTimeout(timer); resolve(); });
    parent.once('error', error => { clearTimeout(timer); reject(error); });
  });
  parent.kill('SIGKILL');
  await terminal;
  const deadline = Date.now() + 3000;
  for (;;) {
    try { assert.equal(await readFile(stopped, 'utf8'), 'physically stopped'); break; }
    catch (error) {
      if (error.code !== 'ENOENT' || Date.now() >= deadline) throw error;
      await new Promise(resolve => setTimeout(resolve, 5));
    }
  }
});

test('the serial tail runs once after both terminal workers and its failure is retained', async t => {
  const directory = await fixture(t);
  for (const name of ['packed-query-transports.mjs', 'packed-query-transport-owner.mjs',
    'packed-query-worker.mjs', 'retained-fixture-values.mjs',
    'graph-argument-check.mjs', 'graph-argument-origin-literals.json']) {
    await writeFile(join(directory, name), await readFile(new URL(`./fixtures/${name}`, import.meta.url)));
  }
  await writeFile(join(directory, 'acceptance.mjs'), `
    import {writeFile, readFile} from 'node:fs/promises';
    import {encodeRetainedFixture} from './retained-fixture-values.mjs';
    const mode = process.env.ACTQL_TEST_QUERY_TRANSPORT;
    if (mode === 'tail') {
      await readFile('finished.local'); await readFile('finished.remote');
      await writeFile('tail-once', 'one', {flag: 'wx'});
      throw new Error('IndependentlyAuthoredTailFailure');
    }
    const inventory = [JSON.stringify(['standard', 'refusals', 0, 'authored-case', 'a'.repeat(64)])];
    await writeFile('transport-completion.' + mode + '.json', JSON.stringify({mode, complete: true,
      expectedInventory: inventory, completedInventory: inventory, expectedRetainedCohorts: 0, needsTail: true}));
    await writeFile('retained-cohort-results.' + mode + '.json', encodeRetainedFixture([]));
    await writeFile('finished.' + mode, 'finished');
  `);
  const child = spawn(process.execPath, [join(directory, 'packed-query-transports.mjs')], {
    cwd: directory, env: {...process.env, ACTQL_TEST_QUERY_DEADLINE: String(Date.now() + 5000)},
    stdio: ['ignore', 'pipe', 'pipe'], detached: false,
  });
  child.stdout.resume(); child.stderr.resume();
  const timeout = setTimeout(() => child.kill('SIGKILL'), 5000);
  let status;
  try { status = await new Promise(resolve => child.once('close', resolve)); }
  finally { clearTimeout(timeout); }
  assert.equal(status, 1);
  const report = JSON.parse(await readFile(join(directory, 'transport-processes.json'), 'utf8'));
  assert.equal(report.complete, false);
  assert.equal(report.primaryError, 'IndependentlyAuthoredTailFailure');
  assert.equal(report.liveChildren, 0);
  assert.equal(report.children.length, 2);
  assert.ok(report.children.every(receipt => receipt.terminal && receipt.status === 0));
  assert.equal(await readFile(join(directory, 'tail-once'), 'utf8'), 'one');
});

for (const cohortOnly of [false, true]) {
test(`restart assigns each related root to one of two serial transport workers (cohort only: ${cohortOnly})`, async t => {
  const directory = await fixture(t);
  for (const name of ['packed-query-restart-transports.mjs', 'packed-query-transport-owner.mjs',
    'packed-query-worker.mjs', 'retained-fixture-values.mjs']) {
    await writeFile(join(directory, name), await readFile(new URL(`./fixtures/${name}`, import.meta.url)));
  }
  const cohorts = [
    {mode: 'local', directory: 'local-first'}, {mode: 'local', directory: 'local-next'},
    {mode: 'remote', directory: 'remote-first'}, {mode: 'remote', directory: 'remote-next'},
  ];
  await writeFile(join(directory, 'retained-cohort-results.json'), encodeRetainedFixture(cohorts));
  await writeFile(join(directory, 'string-values-restart.mjs'), `
    import {writeFile} from 'node:fs/promises';
    import {transportWorker} from './packed-query-transport-owner.mjs';
    const worker = transportWorker(), mode = process.env.ACTQL_TEST_QUERY_TRANSPORT;
    const expected = mode === 'local' ? ['local-first', 'local-next'] : ['remote-first', 'remote-next'];
    const completedRoots = [];
    for (const root of expected) {
      worker.check();
      await new Promise(resolve => setTimeout(resolve, 1));
      completedRoots.push(root);
    }
    await writeFile('transport-restart.' + mode + '.json', JSON.stringify({mode,
      stringComplete: process.env.ACTQL_TEST_RETAINED_COHORT_ONLY !== '1', completedRoots}));
  `);
  const child = spawn(process.execPath, [join(directory, 'packed-query-restart-transports.mjs')], {
    cwd: directory, env: {...process.env, ACTQL_TEST_RETAINED_COHORT_ONLY: cohortOnly ? '1' : '0',
      ACTQL_TEST_QUERY_RESTART_DEADLINE: String(Date.now() + 5000)},
    stdio: ['ignore', 'pipe', 'pipe'], detached: false,
  });
  child.stdout.resume(); child.stderr.resume();
  const timeout = setTimeout(() => child.kill('SIGKILL'), 5000);
  let status;
  try { status = await new Promise(resolve => child.once('close', resolve)); }
  finally { clearTimeout(timeout); }
  assert.equal(status, 0);
  const report = JSON.parse(await readFile(join(directory, 'transport-restart-processes.json'), 'utf8'));
  assert.equal(report.timeoutMs, 120_000);
  assert.equal(report.complete, true);
  assert.equal(report.liveChildren, 0);
  assert.equal(report.children.length, 2, 'no new process or allowance per root');
  assert.deepEqual(report.roots, [
    {mode: 'local', expectedRoots: 2, completedRoots: 2},
    {mode: 'remote', expectedRoots: 2, completedRoots: 2},
  ]);
});
}


test('transport harness admits a selected finite envelope while preserving its default', () => {
  const ordinary = createTransportOwner({deadline: Date.now() + 1000, forward() {}});
  try { assert.equal(ordinary.report().timeoutMs, 900_000); }
  finally { ordinary.close(); }
  const selected = createTransportOwner({deadline: Date.now() + 1_799_000,
    timeoutMs: 1_800_000, forward() {}});
  try {
    assert.equal(selected.report().timeoutMs, 1_800_000);
    assert.equal(selected.report().outputLimit, 8 * 1024 * 1024);
    assert.equal(selected.report().liveChildren, 0);
  } finally { selected.close(); }
});

test('transport harness refuses an unbounded or inconsistent selected envelope', () => {
  for (const timeoutMs of [0, -1, 0.5, NaN, Infinity, 1_800_001]) {
    assert.throws(() => createTransportOwner({deadline: Date.now() + 1000,
      timeoutMs, forward() {}}));
  }
  assert.throws(() => createTransportOwner({deadline: Date.now() + 901_000,
    forward() {}}));
  assert.throws(() => createTransportOwner({deadline: Date.now() + 1_801_000,
    timeoutMs: 1_800_000, forward() {}}));
});


test('canonical query timeout selector rejects invalid input before package work', () => {
  assert.equal(selectAcceptanceTimeout({}), 900_000);
  for (const value of ['1', '120000', '1800000']) {
    assert.equal(selectAcceptanceTimeout({ACTQL_TEST_QUERY_TIMEOUT_MS: value}), Number(value));
  }
  for (const value of ['', '0', '-1', '0.5', 'NaN', 'Infinity', '1800001']) {
    assert.throws(() => selectAcceptanceTimeout({ACTQL_TEST_QUERY_TIMEOUT_MS: value}));
  }
});

test('canonical query launcher forwards one selected envelope to deadline and command', async () => {
  const {parse} = await import('acorn');
  const source = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const declarations = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'VariableDeclaration' && node.declarations.some(declaration =>
        declaration.id.name === 'acceptanceDeadline' || declaration.id.name === 'output' &&
        declaration.init?.type === 'CallExpression' && declaration.init.callee.name === 'run' &&
        declaration.init.arguments[1]?.elements?.[0]?.value === 'packed-query-transports.mjs')) {
      declarations.push(node);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(syntax);
  assert.equal(declarations.length, 2);
  const invoke = Function('run', 'process', 'root', 'runtimeEnvironment', 'acceptanceTimeout', 'Date',
    declarations.map(node => source.slice(node.start, node.end)).join('\n'));
  for (const environment of [{}, {ACTQL_TEST_QUERY_TIMEOUT_MS: '1800000'}]) {
    const selected = selectAcceptanceTimeout(environment);
    const calls = [];
    invoke((...args) => { calls.push(args); return ''; },
      {execPath: process.execPath, argv: []}, 'owned-consumer', {original: 'unchanged'}, selected,
      {now: () => 1000});
    assert.equal(calls.length, 1);
    const [command, args, root, passed, timeout] = calls[0];
    assert.equal(command, process.execPath);
    assert.deepEqual(args, ['packed-query-transports.mjs']);
    assert.equal(root, 'owned-consumer');
    assert.equal(passed.original, 'unchanged');
    assert.equal(passed.ACTQL_TEST_QUERY_TIMEOUT_MS, String(selected));
    assert.equal(passed.ACTQL_TEST_QUERY_DEADLINE, String(1000 + selected));
    assert.equal(passed.ACTQL_TEST_QUERY_EXPECT_FULL_CORPUS, '1');
    assert.equal(timeout, selected);
    const owner = createTransportOwner({deadline: Date.now() + selected - 100, timeoutMs: selected,
      forward() {}});
    try { assert.equal(owner.report().timeoutMs, selected); }
    finally { owner.close(); }
  }
});
