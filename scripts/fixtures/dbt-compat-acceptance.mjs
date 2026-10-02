// Copied unchanged into the external tarball installation by
// scripts/probe-dbt-compat.mjs. Submits each compiled dbt model exactly as
// dbt wrote it through the public Client on installed Local and HTTP, and
// records where it stops. Expected rows and schema come from cases.json,
// written from the synthetic source rows, not from ActQL output.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {inspect} from 'node:util';
import {resolve} from 'node:path';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from
  '@actql/local-node/http-host';
import {canonical, judge} from './dbt-compat-judge.mjs';

const [casesPath, compiledPath, resultsPath] = process.argv.slice(2);
const specification = JSON.parse(await readFile(casesPath, 'utf8'));
// {case name: compiled SQL text exactly as dbt wrote it}
const compiled = JSON.parse(await readFile(compiledPath, 'utf8'));

// Refusals of a submitted text by the ordinary Client admission. Anything
// else (connection, timeout, missing dependency) is a fault, not a finding.
const refusalCodes = new Set(['ClientProgramInvalidInput',
  'ClientParametersInvalid', 'ClientParametersTooLarge',
  'ClientProgramUnsupported', 'ClientProgramNeedsInputs',
  'ClientProgramRejected']);

// Test-only: case names whose admitted, successful Run is recorded as a Run
// failure, to show that such a failure fails the whole probe and keeps its
// evidence. Every injected outcome is marked as injected.
const injectedRunFailures = new Set((process.env
  .ACTQL_DBT_PROBE_INJECT_RUN_FAILURE ?? '').split(',').filter(Boolean));

// The check environment and source profile, built as the packed public-query
// acceptance builds them; only the alias name and table differ.
const environment = JSON.parse(await readFile('source-environment.json',
  'utf8'));
const base = JSON.parse(await readFile('base-environment.json', 'utf8'));
environment.host_policy_profile = base.host_policy_profile;
environment.connector_capabilities[0].capability_contract_cids.push(
  'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89');
environment.connector_capabilities[0].capability_contract_cids.sort();
delete environment.evidence_bundle_cid;
environment.evidence_bundle_cid = 'sha256:' + createHash('sha256')
  .update(canonical(environment)).digest('hex');

const {DuckDBInstance} = createRequire(new URL(
  './node_modules/@actql/local-node/package.json', import.meta.url))(
  '@duckdb/node-api');
const database = resolve('probe.duckdb');
const source = specification.source;
async function installRows(rows) {
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run(
      `CREATE TABLE IF NOT EXISTS ${source.table}(id DOUBLE, amount DOUBLE)`);
    await connection.run(`DELETE FROM ${source.table}`);
    for (const row of rows) {
      await connection.run(`INSERT INTO ${source.table} VALUES (?, ?)`,
        [row.id, row.amount]);
    }
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
}
await installRows(source.rows);
const view = environment.source_views[0];
const sourceProfilePath = resolve('source-profile.json');
await writeFile(sourceProfilePath, canonical({
  acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    version: 'actql-installed-duckdb-source/0.1', database,
  schema: 'main', table: source.table, sourceRef: 'connector://crm/main/r#v',
  // The exact relation name dbt rendered for ref('stg_orders').
  queryAliases: [{name: source.relation, sourceRef: 'connector://crm/main/r#v',
    sourceViewContractCid: view.contract_cid,
    schemaContractCid: view.output.schema.cid}],
  checkEnvironmentWire: canonical(environment),
  accountConfigurationWire: canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'dbt-probe',
    entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read']}, exclusions: []}]}),
}));

async function readAnswer(execution) {
  const result = execution.result('answer');
  const reader = result.rows();
  const streamed = [];
  for await (const row of reader) streamed.push(row);
  return {streamed, streamState: reader.state(), all: await result.all(),
    columns: (await result.describe()).columns};
}

// Each link of an error's cause chain without stacks: the Host's internal
// preparation issue is at the end where the transport carries it.
function causeChain(cause) {
  const chain = [];
  for (let depth = 0; cause !== undefined && cause !== null && depth < 8;
    depth += 1) {
    if (cause instanceof Error) {
      const {stack, cause: next, ...fields} = cause;
      chain.push({name: cause.name, message: cause.message,
        ...(Object.keys(fields).length === 0 ? {}
          : {fields: inspect(fields, {depth: 4, breakLength: Infinity})})});
      cause = next;
    } else {
      chain.push({value: inspect(cause, {depth: 4, breakLength: Infinity})
        .slice(0, 2000)});
      break;
    }
  }
  return chain;
}

// Best effort, from the field names the installed issue keeps: a syntax
// issue carries {issue, span}; a checker diagnostic carries the lowered
// Program {tree, index} and the node it refers to. Absent on HTTP.
function diagnosticLocation(error) {
  let value = error;
  while (value?.cause !== undefined && value instanceof Error) {
    value = value.cause;
  }
  for (let depth = 0; value !== null && typeof value === 'object' &&
    depth < 16; depth += 1) {
    if ('issue' in value && value.span?.start_line !== undefined) {
      const issue = value.issue;
      const text = typeof issue === 'object' && issue !== null &&
        Object.keys(issue).length === 1 ? issue[Object.keys(issue)[0]] : issue;
      return {syntax: {issue: String(text), line: value.span.start_line,
        column: value.span.start_column}};
    }
    if (Array.isArray(value.tree) && Number.isInteger(value.index)) {
      const edge = node => {
        const keys = Object.keys(node.edge ?? {});
        return keys.length === 0 ? null : node.edge[keys[0]];
      };
      const path = [];
      for (let at = value.index; at >= 0 && value.tree[at] !== undefined;
        at = value.tree[at].parent) {
        const key = edge(value.tree[at]);
        if (key !== null) path.unshift(key);
      }
      const children = value.tree.filter(node =>
        node.parent === value.index).map(edge);
      return {checked: {path: path.join('.'), children}};
    }
    const keys = Object.keys(value);
    value = value[keys.includes('cause') ? 'cause' : keys[0]];
  }
  return {};
}

// Submit one text and classify where it stops. Faults are thrown.
async function submit(client, requestId, text, format) {
  let execution;
  try {
    execution = await client.aql(text, {format, requestId});
  } catch (error) {
    if (refusalCodes.has(error?.code)) {
      // The installed Host's preparation issue, where the transport carries
      // it (in-process Local); HTTP returns only the public code.
      return {stage: 'actql-submission-refused', code: error.code,
        message: String(error.message), causes: causeChain(error.cause),
        ...diagnosticLocation(error)};
    }
    throw error;
  }
  const state = await execution.wait();
  if (state.status !== 'succeeded') {
    return {stage: 'actql-run-failed', state};
  }
  return {stage: 'named-result', ...await readAnswer(execution)};
}

// Submit, apply a test-only injected Run failure, judge and record.
async function record(client, transport, name, item, text, format) {
  let outcome = await submit(client,
    `dbt-${transport}-${name.replaceAll(':', '-')}`, text, format);
  if (injectedRunFailures.has(name) && outcome.stage === 'named-result') {
    outcome = {stage: 'actql-run-failed', injected: true,
      state: {status: 'failed',
        reason: 'injected by ACTQL_DBT_PROBE_INJECT_RUN_FAILURE'}};
  }
  const entry = {case: name, transport, ...outcome,
    ...judge(item, outcome, source.columns)};
  outcomes.push(entry);
  await writeOutcomes();
  return entry;
}

const outcomes = [];
// A fault (anything but a classified outcome) stops the run; the outcomes so
// far and the fault are written first, so the evidence shows where it stopped.
async function writeOutcomes(fault) {
  await writeFile(resultsPath, JSON.stringify({outcomes,
    ...(fault === undefined ? {} : {fault})}, null, 2) + '\n');
}

async function exercise(transport, options) {
  const client = await connect(options);
  try {
    for (const item of specification.cases) {
      const text = compiled[item.name];
      assert.equal(typeof text, 'string', `no compiled text for ${item.name}`);
      const entry = await record(client, transport, item.name, item, text,
        item.format);
      if (entry.stage === 'named-result' && item.program !== undefined) {
        // The same filter and projection authored as a JSON Program. It goes
        // through the same runtime, so it is a comparison, not an oracle:
        // it must reproduce the dbt model's rows.
        await record(client, transport, `${item.name}:json-program`,
          {expect: 'rows', rows: entry.all, order: 'unordered'},
          await readFile(item.program, 'utf8'), 'json');
      }
    }
    // Hand-written minimal texts, each differing from a positive control in
    // one construct, to locate a refusal. They are not dbt output.
    for (const item of specification.reproductions ?? []) {
      await record(client, transport, `reproduction:${item.name}`, item,
        item.text, item.format);
    }
    // Empty source: the same compiled text yields no rows and the same schema.
    await installRows([]);
    for (const item of specification.cases.filter(item => item.emptySource)) {
      await record(client, transport, `${item.name}:empty-source`,
        {...item, rows: []}, compiled[item.name], item.format);
    }
    await installRows(source.rows);
  } finally {
    client.close?.();
  }
}

let current = 'local';
try {
await exercise('local', {mode: 'local', owner: 'local',
  durability: 'durable', installation: {directory: resolve('local-state'),
    sourceProfilePath}});
current = 'http';
const host = await openInstalledRemoteHttpHost({
  directory: resolve('remote-state'), sourceProfilePath,
  authenticate: header => header === 'Bearer probe-token'
    ? userInfo().username : undefined,
});
const server = createServer({key: await readFile('remote.key'),
  cert: await readFile('remote.crt')}, host.handler);
await new Promise(done => server.listen(0, '127.0.0.1', done));
try {
  await exercise('http', {mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'probe-token', durability: 'durable'});
} finally {
  server.closeAllConnections();
  await new Promise(done => server.close(done));
  await host.close();
}
} catch (error) {
  await writeOutcomes({transport: current,
    after: outcomes.at(-1)?.case ?? null, code: error?.code ?? null,
    message: String(error?.message),
    cause: error?.cause?.code ?? error?.cause?.message ?? null,
    rootCause: error?.cause?.cause?.message ?? null});
  throw error;
}
await writeOutcomes();
for (const item of outcomes) {
  console.log(`${item.transport}\t${item.case}\t${item.stage}\t${
    item.verdict}${item.code ? '\t' + item.code : ''}`);
}
