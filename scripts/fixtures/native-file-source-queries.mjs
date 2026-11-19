// Original issue3609 query shapes. These inputs do not simulate a Native reader.
import assert from 'node:assert/strict';
import {writeSync} from 'node:fs';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {canonicalText} from '../check-canonical-json.mjs';

const seed = [{account_id: '001Acme', active_users: 4, trend: 'down'},
  {account_id: '001Globex', active_users: 12, trend: 'flat'}];
export const nativeFileSourceQueries = Object.freeze([
  {name: 'projection', sql: 'SELECT trend FROM snowflake.usage_30d', rows: [{trend: 'down'}, {trend: 'flat'}]},
  // The template declares active_users as int64. Its schema-directed JSONL
  // wire uses canonical decimal strings, independently of the seed JSON.
  {name: 'numeric-projection', sql: 'SELECT active_users FROM snowflake.usage_30d', rows: [{active_users: '4'}, {active_users: '12'}]},
  {name: 'key-projection', sql: 'SELECT account_id, trend FROM snowflake.usage_30d', rows: [
    {account_id: '001Acme', trend: 'down'}, {account_id: '001Globex', trend: 'flat'}]},
  {name: 'star', sql: 'SELECT * FROM snowflake.usage_30d', rows: [
    {account_id: '001Acme', active_users: '4', trend: 'down'},
    {account_id: '001Globex', active_users: '12', trend: 'flat'}]},
  {name: 'projection-literal', sql: 'SELECT trend, 1 AS n FROM snowflake.usage_30d', rows: [{trend: 'down', n: 1}, {trend: 'flat', n: 1}]},
  {name: 'count', sql: 'SELECT COUNT(*) AS n FROM snowflake.usage_30d', rows: [{n: 2}]},
  {name: 'sum', sql: "SELECT SUM(CASE WHEN trend = 'down' THEN 4 ELSE 12 END) AS total FROM snowflake.usage_30d", rows: [{total: 16}]},
  {name: 'average', sql: "SELECT AVG(CASE WHEN trend = 'down' THEN 4 ELSE 12 END) AS average FROM snowflake.usage_30d", rows: [{average: 8}]},
  {name: 'combined-control', sql: "SELECT SUM(CASE WHEN trend = 'down' THEN 4 ELSE 12 END) AS total, AVG(CASE WHEN trend = 'down' THEN 4 ELSE 12 END) AS average FROM snowflake.usage_30d", rows: [{total: 16, average: 8}]},
]);
// Existing read-only Mock contract: a legal WHERE and two original logical
// JOIN occurrences in the SAME physical file. Native execution is required;
// these independent full-row oracles are not planning/metadata acceptance.
export const nativeReadonlyMockQueries = Object.freeze([
  {name: 'readonly-filter', sql: "SELECT account_id, trend FROM snowflake.usage_30d WHERE trend = 'down'",
    rows: [{account_id: '001Acme', trend: 'down'}]},
  {name: 'readonly-join', sql: 'SELECT u.account_id, a.name AS account_name, u.trend FROM snowflake.usage_30d u JOIN salesforce.accounts a ON u.account_id = a.id',
    rows: [{account_id: '001Acme', account_name: 'Acme Corp', trend: 'down'},
      {account_id: '001Globex', account_name: 'Globex Inc', trend: 'flat'}]},
]);
export const nativeInstalledSourceQueries = Object.freeze([
  ...nativeFileSourceQueries, ...nativeReadonlyMockQueries,
]);
// Preserve the original hermetic command environment. These two metadata
// flags cannot choose a runtime, change a quote or reconfigure execution.
export function nativeFileSourceQueryEnvironment({fixture, args, emptyPath, home, environment}) {
  const child = {PATH: emptyPath, HOME: home, LANG: 'C.UTF-8', LC_ALL: 'C.UTF-8'};
  if (fixture.name === 'readonly-filter' && args[0] === 'sql' &&
    environment.ACTQL_NATIVE_TIMINGS === '1' &&
    environment.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS === '1')
    Object.assign(child, {ACTQL_NATIVE_TIMINGS: '1', ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS: '1'});
  return child;
}

// The complete original stderr remains in the existing case-owned file.
// Tee only one complete closed numeric row into the installed owner's command
// record, never arbitrary diagnostics/payloads/IDs. Missing/duplicate/truncated
// rows or a failed write stay unmeasured and cannot replace the primary.
export function retainNativeFileCapacityStderr(environment, stderr, write = body => writeSync(2, body)) {
  if (environment.ACTQL_NATIVE_TIMINGS !== '1' ||
    environment.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS !== '1' || typeof stderr !== 'string') return;
  const natural = '(?:0|[1-9][0-9]{0,18})', observed = `(?:-1|${natural})`;
  const row = new RegExp('^ACTQL_NATIVE_FILE_CAPACITY \\{"phase":1[0-6],"compute":(?:true|false),' +
    `"requested_execution":${natural},"task_capacity":${observed},` +
    `"limit_execution":${natural},"reserved_execution":${natural},` +
    `"entry_singleton_execution":${observed},"row_execution":${observed}\\}\\n`, 'gmu');
  const matches = [...stderr.matchAll(row)];
  if (matches.length === 1) {
    try { write(matches[0][0]); } catch { /* Diagnostic loss is not execution failure. */ }
  }
}

const multiset = rows => rows.map(canonicalText).sort();
const requireSuccess = result => {
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  return result;
};

export async function observeNativeFileSourceQuery({parent, fixture, cli}) {
  assert(nativeInstalledSourceQueries.includes(fixture), 'Select an original installed Source query');
  const project = join(parent, fixture.name);
  requireSuccess(await cli(['init', '--template', 'churn-risk-mock', project], parent));
  const path = join(project, 'mock/data.json'), original = await readFile(path);
  assert.deepEqual(JSON.parse(original).snowflake.usage_30d.rows, seed);
  let failed = false, primary;
  try {
    const program = join(project, fixture.name + '.sql');
    await writeFile(program, fixture.sql, {flag: 'wx', mode: 0o600});
    const checked = JSON.parse(requireSuccess(await cli(['check', program, '--format', 'sql', '--json'], project)).stdout);
    assert.equal(checked.report.verdict, 'verified');
    assert.equal(checked.report.runnable.verdict, 'yes');
    const result = requireSuccess(await cli(['sql', fixture.sql, '--format', 'jsonl'], project));
    const rows = result.stdout.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
    // Full canonical rows preserve field names, value types and multiplicity;
    // no order is promised by these queries. This is not Result.describe metadata.
    assert.deepEqual(multiset(rows), multiset(fixture.rows));
    return {name: fixture.name, checkRunnable: true, rows, inputUnchanged: true};
  } catch (error) {
    failed = true; primary = error;
    throw error;
  } finally {
    try {assert.deepEqual(await readFile(path), original);}
    catch (error) {
      if (failed) throw new AggregateError([primary, error], 'File query and original input correspondence failed');
      throw error;
    }
  }
}
