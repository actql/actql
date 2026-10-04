// One public acceptance implementation for source tests and the pack-once
// consumer. Callers supply ordinary public entry points, never a replacement
// compiler, source provider, acquisition implementation or expected output.
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {exercisePublicQueryInput} from './public-query-input.mjs';

export const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);

export async function loadTwoSourceFixtures(directory) {
  const json = async name => JSON.parse(await readFile(resolve(directory, name), 'utf8'));
  return {rows: await json('database-rows.json'),
    expected: await json('two-source-join.expected.json'),
    equalExpected: await json('equal-content-join.expected.json'),
    environments: {left: await json('left.environment.json'),
      right: await json('right.environment.json')},
    program: await readFile(resolve(directory, 'two-source-join.program.json'), 'utf8'),
    textProgram: await readFile(resolve(directory, 'two-source-join.aql'), 'utf8'),
    leftOnly: await readFile(resolve(directory, 'left-only.program.json'), 'utf8')};
}

export async function installTwoSourceFixtures({root, fixture, duckdb}) {
  await mkdir(root, {recursive: true});
  const databases = {}, profiles = {};
  for (const name of ['left', 'right', 'equal_content']) {
    const database = databases[name] = resolve(root, `${name}.duckdb`);
    const instance = await duckdb.DuckDBInstance.create(database);
    const connection = await instance.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
      for (const row of fixture.rows[name]) {
        await connection.run('INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
      }
    } finally { connection.closeSync(); instance.closeSync(); }
  }
  for (const [name, source, databaseName] of [['left', 'left', 'left'],
    ['right', 'right', 'right'], ['right_equal', 'right', 'equal_content'],
    ['right_missing', 'right', 'right'], ['left_broad', 'left', 'left'],
    ['right_broad', 'right', 'right'], ['right_missing_broad', 'right', 'right']]) {
    const environment = fixture.environments[source], database = databases[databaseName];
    const view = environment.source_views[0];
    profiles[name] = resolve(root, `${name}.profile.json`);
    await writeFile(profiles[name], canonical({
      acquisitionPlanning: {policy: 'priority', priority: name.endsWith('_broad')
        ? ['broadQuery', 'nativeQuery'] : ['nativeQuery', 'broadQuery']},
    version: 'actql-installed-duckdb-source/0.1', database, schema: 'main',
      queryAliases: [{name: source + '_records',
        sourceRef: environment.schema_snapshots[0].source_ref,
        sourceViewContractCid: view.contract_cid,
        schemaContractCid: view.output.schema.cid}],
      table: name.startsWith('right_missing') ? 'missing_records' : 'records',
      sourceRef: environment.schema_snapshots[0].source_ref,
      checkEnvironmentWire: canonical(environment),
      accountConfigurationWire: canonical({version: 'actql-execution-account-config/0.1',
        account_id: `two-source-${name}`, entries: [{entry_id: 'read-own-database',
          outcome: 'allow', principal: {all: true},
          connection: {any_of: ['local-database']}, resource: {any_of: [database]},
          operation: {any_of: ['read']}, exclusions: []}]}),
    }));
  }
  return {databases, profiles};
}

// Observe the real Native driver. Equal bytes cannot conceal use of the wrong
// installed database, and installing an unused source must not open it.
export function observeTwoSourceProvider(duckdb, databases) {
  const {DuckDBInstance, DuckDBPreparedStatement, DuckDBConnection,
    DuckDBExtractedStatements} = duckdb;
  const sourceDatabases = new Set(Object.values(databases));
  const original = {create: DuckDBInstance.create, connect: DuckDBInstance.prototype.connect,
    extract: DuckDBConnection.prototype.extractStatements,
    prepare: DuckDBExtractedStatements.prototype.prepare, stream: DuckDBPreparedStatement.prototype.stream};
  const instanceDatabase = new WeakMap(), connectionDatabase = new WeakMap();
  const extractedSql = new WeakMap(), extractedConnection = new WeakMap();
  const preparedSql = new WeakMap(), preparedConnection = new WeakMap(), sessions = new WeakMap();
  let sourceIo = 0, sourceReads = 0, sourceReadSessions = 0;
  const sourceReadCommands = [], sourceProviderOpens = [];
  DuckDBInstance.create = async function(database, ...rest) {
    if (sourceDatabases.has(database)) sourceProviderOpens.push(database);
    const instance = await Reflect.apply(original.create, this, [database, ...rest]);
    instanceDatabase.set(instance, database); return instance;
  };
  DuckDBInstance.prototype.connect = async function(...args) {
    const connection = await Reflect.apply(original.connect, this, args);
    connectionDatabase.set(connection, instanceDatabase.get(this)); return connection;
  };
  DuckDBConnection.prototype.extractStatements = async function(sql) {
    const statements = await Reflect.apply(original.extract, this, [sql]);
    extractedSql.set(statements, sql); extractedConnection.set(statements, this); return statements;
  };
  DuckDBExtractedStatements.prototype.prepare = async function(index) {
    const statement = await Reflect.apply(original.prepare, this, [index]);
    preparedSql.set(statement, extractedSql.get(this));
    preparedConnection.set(statement, extractedConnection.get(this)); return statement;
  };
  DuckDBPreparedStatement.prototype.stream = function(...args) {
    sourceIo++;
    if (/\bFROM\s+(?:"main"\.)?"records"(?=\s|$)/iu.test(preparedSql.get(this) ?? '')) {
      sourceReads++;
      const connection = preparedConnection.get(this), database = connectionDatabase.get(connection);
      assert.ok(connection && sourceDatabases.has(database), 'source scan retains exact physical identity');
      if (!sessions.has(connection)) sessions.set(connection, ++sourceReadSessions);
      sourceReadCommands.push({session: sessions.get(connection), database, sql: preparedSql.get(this)});
    }
    return Reflect.apply(original.stream, this, args);
  };
  return {snapshot: () => ({sourceIo, sourceReads, sourceReadSessions,
    sourceReadCommands: sourceReadCommands.slice(), sourceProviderOpens: sourceProviderOpens.slice()}),
  restore() {
    DuckDBInstance.create = original.create; DuckDBInstance.prototype.connect = original.connect;
    DuckDBConnection.prototype.extractStatements = original.extract;
    DuckDBExtractedStatements.prototype.prepare = original.prepare;
    DuckDBPreparedStatement.prototype.stream = original.stream;
  }};
}

export function readTwoSourceJournal(directory) {
  const journal = new DatabaseSync(resolve(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
  try {
    return journal.prepare(`SELECT caller_request_id, namespace_id, authority_scope_cid,
      run_definition_cid, run_admission_evidence_json, dispatch_reserved,
      physical_start_reserved, physical_close_confirmed, pre_dispatch_failure_confirmed,
      cancellation_requested, observed_terminal_outcome FROM client_requests
      ORDER BY caller_request_id`).all().map(row => ({...row}));
  } finally { journal.close(); }
}

export function expectedTwoSourceResults(fixture, variant) {
  return variant === 'unused-right' ? {single_source: {
    rows: [{id: 1, amount: null}, {id: 2, amount: 20},
      {id: 3, amount: 30}, {id: 3, amount: 30}],
    columns: [{name: 'id', contract: {type: 'number', nullable: false}},
      {name: 'amount', contract: {type: 'number', nullable: true}}],
  }} : {joined: {rows: variant === 'equal-content' ? fixture.equalExpected.rows : fixture.expected.rows,
    columns: fixture.expected.columns}};
}

export async function openTwoSourcePublicHost({connect, openInstalledRemoteHttpHost,
  mode, directory, sourceProfilePaths, tls, authorization}) {
  let host, server;
  let options = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory, sourceProfilePaths, ...(authorization === undefined ? {} : {authorization})}};
  if (mode === 'https') {
    host = await openInstalledRemoteHttpHost({directory, sourceProfilePaths, authorization,
      authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
    server = createServer(tls, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    options = {mode: 'remote', durability: 'durable', token: 'fixture-token',
      endpoint: `https://127.0.0.1:${server.address().port}/`};
  }
  let serverClosed = false;
  return {options, connect: () => connect(options), host,
    async close() {
      if (server && !serverClosed) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
        serverClosed = true;
      }
      await host?.close();
    }};
}

export async function exerciseTwoSourcePublicQuery({connect, openInstalledRemoteHttpHost,
  root, fixture, installation, provider, tls, authorization}) {
  const retained = [];
  for (const mode of ['local', 'https']) for (const variant of [
    'distinct', 'equal-content', 'unused-right', 'broad', 'native-text', 'broad-text']) {
    const broad = variant === 'broad' || variant === 'broad-text';
    const sourceProfilePaths = broad
      ? [installation.profiles.left_broad, installation.profiles.right_broad]
      : [installation.profiles.left,
        installation.profiles[variant === 'equal-content' ? 'right_equal' : 'right']];
    const directory = resolve(root, `${mode}-${variant}-state`);
    const expectedDatabases = variant === 'unused-right' ? [installation.databases.left]
      : [installation.databases.left, installation.databases[variant === 'equal-content' ? 'equal_content' : 'right']];
    const results = expectedTwoSourceResults(fixture, variant);
    const text = variant.endsWith('-text') ? fixture.textProgram
      : variant === 'unused-right' ? fixture.leftOnly : fixture.program;
    const format = variant.endsWith('-text') ? 'aql-text' : 'json';
    const observe = () => ({...provider.snapshot(), acceptedRuns: readTwoSourceJournal(directory).length});
    const before = provider.snapshot();
    const selections = [];
    const observedAuthorization = {...authorization, observe(name, detail) {
      if (name === 'acquisition_completed') selections.push(detail.acquisition?.selection);
    }};
    const running = await openTwoSourcePublicHost({connect, openInstalledRemoteHttpHost,
      mode, directory, sourceProfilePaths, tls, authorization: observedAuthorization});
    try {
      const checker = await running.connect();
      const check = await checker.check('SELECT 1 AS value', {format: 'sql'});
      assert.equal(check.outcome, 'completed');
      assert.match(check.report.context_ref, /^ctx:[0-9a-f]{64}$/u);
      assert.deepEqual({...check, report: {...check.report, context_ref: '<ctx>'}},
        {version: 'actql-check-outcome/0.1', outcome: 'completed',
          report: {context_ref: '<ctx>', scope: {kind: 'bound_input'},
            verdict: 'verified', reasons: [],
            coverage: {limits: [], unresolved: []}}});
      assert.deepEqual(provider.snapshot(), before, 'plural check performs no provider I/O');
      await exercisePublicQueryInput(connect, running.options, {
        requestPrefix: `${mode}-${variant}`, observe, refusals: [],
        successes: [{name: 'two-source-join', text, format, results,
          sourceReadSessionCount: expectedDatabases.length}],
        completedCase: item => retained.push({mode, variant, directory, sourceProfilePaths,
          ref: item.ref, requestId: `${mode}-${variant}-two-source-join`,
          submission: {document: text, format}}),
      });
      const commands = provider.snapshot().sourceReadCommands.slice(before.sourceReadCommands.length);
      const opens = provider.snapshot().sourceProviderOpens.slice(before.sourceProviderOpens.length);
      assert.deepEqual([...new Set(commands.map(command => command.database))].sort(), [...expectedDatabases].sort());
      for (const database of expectedDatabases) {
        assert.equal(new Set(commands.filter(command => command.database === database).map(command => command.session)).size, 1);
      }
      assert.ok(opens.every(database => expectedDatabases.includes(database)), 'unused source performs zero provider opens');
      assert.equal(selections.length, expectedDatabases.length);
      for (const selected of selections) {
        assert.equal(selected.status, 'selected');
        assert.equal(selected.selectedCandidate, broad ? 'broadQuery' : 'nativeQuery');
        assert.equal(selected.selectionBasis, 'explicitPriority');
        assert.ok(selected.nativeSupported && selected.broadSupported,
          'the common owner reports both eligible candidates before explicit priority');
      }
    } finally { await running.close(); }
  }
  assert.equal(retained.length, 12);
  return retained;
}

export async function verifyTwoSourceRetained({connect, openInstalledRemoteHttpHost,
  fixture, retained, provider, tls, authorization}) {
  assert.deepEqual(provider.snapshot().sourceProviderOpens, []);
  for (const item of retained) {
    const before = readTwoSourceJournal(item.directory);
    const running = await openTwoSourcePublicHost({connect, openInstalledRemoteHttpHost, tls, authorization, ...item});
    const client = await running.connect();
    try {
      const attached = await client.attach(item.ref);
      assert.equal((await attached.status()).status, 'succeeded');
      for (const [name, result] of Object.entries(expectedTwoSourceResults(fixture, item.variant))) {
        assert.deepEqual(await attached.result(name).all(), result.rows);
        assert.deepEqual((await attached.result(name).describe()).columns, result.columns);
        const reader = attached.result(name).rows();
        assert.deepEqual(await Array.fromAsync(reader), result.rows);
        assert.equal(reader.state(), 'complete');
      }
      assert.deepEqual((await client.lookupRequest(item.requestId)).ref, item.ref);
      assert.equal(typeof item.submission.document, 'string');
      assert.ok(['json', 'aql-text'].includes(item.submission.format));
      const resent = await client.aql(item.submission.document,
        {format: item.submission.format, requestId: item.requestId});
      assert.deepEqual(resent.ref, item.ref);
      assert.equal((await resent.status()).status, 'succeeded');
      assert.deepEqual(readTwoSourceJournal(item.directory), before, 'retained access adds no admission or physical transition');
      assert.deepEqual(provider.snapshot().sourceProviderOpens, [], 'fresh-process Result access never opens a source');
      assert.equal(provider.snapshot().sourceIo, 0, 'fresh-process Result access does not execute provider SQL');
    } finally { client.close(); await running.close(); }
  }
}
