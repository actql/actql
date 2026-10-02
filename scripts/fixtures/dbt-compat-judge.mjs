// Verdicts and evidence identities for the dbt compatibility probe. Reporting
// rules are pure; packageIdentity reads package files. Copied unchanged
// next to the acceptance in the external installation.

import {createHash} from 'node:crypto';
import {readdir, readFile} from 'node:fs/promises';
import {join} from 'node:path';

export const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);

// Rows compared with duplicates kept; order only where the case orders.
export function sameRows(actual, expected, order) {
  const multiset = rows => rows.map(canonical).sort();
  return order === 'unordered'
    ? canonical(multiset(actual)) === canonical(multiset(expected))
    : canonical(actual) === canonical(expected);
}

// Verdicts that fail the probe. Only a refusal at submission of a case that
// is observed (expect: "observe") is a finding rather than a failure; a Run
// that was admitted and then did not succeed is a fault of the run, never a
// statement about what ActQL supports.
export const FAILING_VERDICTS = Object.freeze(['baseline-failed',
  'wrong-result', 'run-failed']);

// item: {expect: "rows" | "observe", rows?, columns?, order?}
// outcome.stage: actql-submission-refused | actql-run-failed | named-result
export function judge(item, outcome, sourceColumns) {
  if (outcome.stage === 'actql-run-failed') return {verdict: 'run-failed',
    assertions: {runSucceeded: false}};
  if (outcome.stage === 'actql-submission-refused') {
    return {verdict: item.expect === 'observe' ? 'unsupported' : 'baseline-failed',
      assertions: {submissionAccepted: false, expectedRefusal: item.expect === 'observe'}};
  }
  if (outcome.stage !== 'named-result') {
    throw new TypeError(`Unknown probe stage ${outcome.stage}`);
  }
  const order = item.order ?? 'unordered';
  const problems = [];
  if (item.rows !== undefined && !sameRows(outcome.all, item.rows, order)) {
    problems.push('rows differ from the expected rows');
  }
  if (!sameRows(outcome.streamed, outcome.all, order)) {
    problems.push('streamed rows differ from all()');
  }
  if (outcome.streamState !== 'complete') {
    problems.push(`stream ended in state ${outcome.streamState}`);
  }
  const columns = item.columns ?? sourceColumns;
  if (item.rows !== undefined &&
      canonical(outcome.columns) !== canonical(columns)) {
    problems.push('result columns differ from the expected schema');
  }
  if (item.expect === 'rows' && item.rows === undefined) {
    problems.push('a rows case has no expected rows');
  }
  const assertions = {runSucceeded: true,
    expectedRows: item.rows === undefined ? null : sameRows(outcome.all, item.rows, order),
    expectedColumns: item.rows === undefined ? null : canonical(outcome.columns) === canonical(columns),
    streamedRows: sameRows(outcome.streamed, outcome.all, order),
    streamComplete: outcome.streamState === 'complete'};
  return problems.length === 0 ? {verdict: 'passed', assertions}
    : {verdict: 'wrong-result', problems, assertions};
}

// The probe passes only when dbt compile stayed offline and unconnected,
// every case has a verdict that is not failing, and no fault stopped it.
export function probeStatus({outcomes, compileProblems = [], fault}) {
  const failures = outcomes.filter(item =>
    FAILING_VERDICTS.includes(item.verdict) || item.verdict === undefined);
  return {status: outcomes.length > 0 && failures.length === 0 &&
    compileProblems.length === 0 &&
    fault === undefined ? 'passed' : 'failed', failures};
}

// Fingerprint the actual bytes, never normalized or rewritten SQL.
export function textIdentity(bytes) {
  const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes, 'utf8');
  return {bytes: buffer.length,
    sha256: createHash('sha256').update(buffer).digest('hex')};
}

// Compare the packed payload with the independently read installed payload.
// Dependencies have their own identity; npm's nested node_modules is not part
// of this package's tarball. Reject links rather than hashing their targets.
export async function packageIdentity(directory) {
  const files = [];
  async function visit(path = '') {
    for (const entry of await readdir(join(directory, path),
      {withFileTypes: true})) {
      if (entry.name === 'node_modules') continue;
      const name = path ? `${path}/${entry.name}` : entry.name;
      if (entry.isDirectory()) await visit(name);
      else if (entry.isFile()) files.push({path: name,
        ...textIdentity(await readFile(join(directory, name)))});
      else throw new Error(`Non-regular package entry: ${name}`);
    }
  }
  await visit();
  files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  const {name, version} = JSON.parse(await readFile(join(directory,
    'package.json'), 'utf8'));
  return {name, version, files: files.length,
    contentsSha256: textIdentity(canonical(files)).sha256};
}

export function expectedObservations(specification, compiled, programs = {}) {
  const expected = [];
  const add = (name, item, text, kind) => expected.push({case: name, item,
    kind, format: item.format, input: text === undefined ? null
      : textIdentity(text)});
  for (const item of specification.cases) {
    add(item.name, item, compiled[item.name], 'dbt-compiled');
    if (item.program !== undefined) add(`${item.name}:json-program`,
      {...item, format: 'json'}, programs[item.program], 'json-comparison');
    if (item.emptySource) add(`${item.name}:empty-source`,
      {...item, rows: []}, compiled[item.name], 'dbt-compiled-empty-source');
  }
  for (const item of specification.reproductions ?? []) {
    add(`reproduction:${item.name}`, item, item.text, 'handwritten');
  }
  return expected;
}

const successful = command => command?.status === 0 &&
  command.signal === null && command.error === null;
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
const revision = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const equal = (a, b) => canonical(a) === canonical(b);

// The report judges actual command/installation/submission observations. A
// successful compile or query never implies dbt run, DDL or catalog support.
export function compatibilityReport({specification, compiled = {},
  programs = {}, commands = [], versions = {}, source = {}, packages = [],
  installed = [], outcomes = [], compileChecks = {}, fault}) {
  const problems = [];
  const projects = [...new Set(specification.cases.map(item => item.project))];
  const compileCommands = commands.filter(item => item.kind === 'dbt-compile');
  const acceptance = commands.filter(item => item.kind === 'acceptance');
  const requiredCommand = kind => {
    const entries = commands.filter(item => item.kind === kind);
    if (entries.length !== 1 || !successful(entries[0])) {
      problems.push(`missing or unsuccessful ${kind} execution`);
    }
  };
  requiredCommand('versions');
  for (const project of projects) {
    const entries = compileCommands.filter(item => item.project === project);
    if (entries.length !== 1 || !successful(entries[0])) {
      problems.push(`missing or unsuccessful dbt compile: ${project}`);
    }
    const check = compileChecks[project];
    if (!check || check.connectionOpens !== 0 || check.duckdbFiles?.length !== 0
      || check.userFile !== false) problems.push(`invalid compile checks: ${project}`);
  }
  for (const name of ['python', 'dbt-core', 'dbt-duckdb', 'dbt-adapters',
    'dbt-common', 'duckdb']) {
    if (typeof versions[name] !== 'string' || versions[name].length === 0) {
      problems.push(`missing observed version: ${name}`);
    }
  }
  if (!revision(source.before?.revision) || source.before?.clean !== true ||
    !equal(source.before, source.after)) problems.push('stale or dirty source identity');
  const compileEvidenceValid = problems.length === 0;
  requiredCommand('install');
  requiredCommand('acceptance');
  for (const name of ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node']) {
    const expected = packages.filter(item => item.name === `@actql/${name}`);
    const actual = installed.filter(item => item.name === `@actql/${name}`);
    const packed = expected[0];
    if (expected.length !== 1 || actual.length !== 1 ||
      packed?.revision !== source.before?.revision ||
      !digest(packed?.sha256) || !digest(packed?.contentsSha256) ||
      !(packed?.files > 0) || typeof packed?.version !== 'string' ||
      !equal(actual[0], packed && {name: packed.name, version: packed.version,
        files: packed.files, contentsSha256: packed.contentsSha256})) {
      problems.push(`missing or stale installed package: @actql/${name}`);
    }
  }
  const expected = expectedObservations(specification, compiled, programs);
  if (expected.length === 0 || outcomes.length === 0) problems.push('empty observations');
  const seen = new Set();
  for (const transport of ['local', 'http']) {
    for (const item of expected) {
      const key = `${transport}:${item.case}`;
      const matches = outcomes.filter(outcome => outcome.transport === transport &&
        outcome.case === item.case);
      if (matches.length !== 1) {
        problems.push(`missing or duplicate observation: ${key}`);
        continue;
      }
      seen.add(matches[0]);
      const outcome = matches[0];
      if (!item.input || !equal(outcome.input, item.input) ||
        outcome.format !== item.format) problems.push(`input mismatch: ${key}`);
      if (outcome.entry !== '@actql/node:client.aql' ||
        outcome.module !== 'node_modules/@actql/node/index.mjs') {
        problems.push(`missing public execution entry: ${key}`);
      }
      try {
        const judged = judge(item.item, outcome, specification.source.columns);
        if (outcome.verdict !== judged.verdict ||
          !equal(outcome.assertions, judged.assertions)) {
          problems.push(`verdict or assertions mismatch: ${key}`);
        }
      } catch {
        problems.push(`invalid observation: ${key}`);
      }
    }
  }
  if (seen.size !== outcomes.length) problems.push('unexpected observations');
  const result = probeStatus({outcomes, fault});
  const compilePassed = projects.length > 0 && projects.every(project => {
    const matches = compileCommands.filter(item => item.project === project);
    return matches.length === 1 && successful(matches[0]);
  });
  const status = result.status === 'passed' && problems.length === 0
    ? 'passed' : 'failed';
  return {status, problems, failures: result.failures,
  scope: {
    dbtCompile: {status: compileCommands.length ? 'tested' : 'not-attempted',
      outcome: compileCommands.length
        ? compileEvidenceValid && compilePassed ? 'passed' : 'failed' : null,
      commandOutcome: compileCommands.length
        ? compilePassed ? 'passed' : 'failed' : null,
      commands: compileCommands.map(item => item.id)},
    queryExecution: {status: outcomes.length ? 'tested' : 'not-attempted',
      outcome: outcomes.length ? status : null,
      commands: acceptance.map(item => item.id),
      entry: '@actql/node:client.aql', transports: ['local', 'http'],
      unsupported: outcomes.filter(item => item.verdict === 'unsupported')
        .map(({case: name, transport, code}) => ({case: name, transport, code}))},
    dbtRun: {status: 'not-attempted', reason: 'The probe invokes dbt compile only'},
    materialization: {status: 'not-attempted',
      reason: 'No dbt materialization or generated write SQL is executed'},
    catalogUpdates: {status: 'not-attempted',
      reason: 'No dbt catalog mutation or persisted relation is asserted'},
  }};
}
