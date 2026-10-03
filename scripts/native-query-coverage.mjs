// File-level selection only: Moon owns compilation, discovery and execution.
// New environment readers conservatively retain the old full harness suite.
import {spawn} from 'node:child_process';
import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {assertTestExecution} from './test-execution.mjs';

export const nativeQueryCoverage = JSON.parse(readFileSync(
  new URL('./native-query-coverage.json', import.meta.url), 'utf8'));
const packagePath = 'src/query_integration';
const owners = ['http-client', 'remote-runtime'];
const environmentReader = /\b(?:get_env_var|(?:secure_)?getenv|environ)\b|ACTQL_TEST_/u;
const queryReader = /get_env_var|native_duckdb_test_library|native_resident_test_prerequisites|native_duckdb_test_variable/u;
const testNames = source => [...source.matchAll(/^test "([^"]+)"/gmu)]
  .map(match => match[1]);
const variables = source => [...new Set([
  ...source.matchAll(/"(ACTQL_[A-Z_]+)"/gu),
  ...source.matchAll(/get_env_var\s*\(\s*"([^"]+)"/gu),
].map(match => match[1]))].sort();
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
const identifiers = source => source.match(/\b[a-zA-Z_][a-zA-Z_0-9]*\b/gu) ?? [];

// Package-local helper reachability is conservative: comments/unused identifiers
// can trigger fallback. Function values and aliases count, not only direct calls.
function queryEnvironmentHelpers(sources) {
  const functions = new Map();
  for (const [path, source] of Object.entries(sources)) {
    if (!path.startsWith(`${packagePath}/`)) continue;
    const starts = [...source.matchAll(/^(?:(?:pub )?fn ([a-zA-Z_][a-zA-Z_0-9]*)\b|test\b)/gmu)];
    for (let index = 0; index < starts.length; index++) {
      if (starts[index][1]) functions.set(starts[index][1],
        source.slice(starts[index].index, starts[index + 1]?.index));
    }
  }
  const affected = new Set();
  let changed = true;
  while (changed) {
    changed = false;
    for (const [name, body] of functions) {
      if (affected.has(name)) continue;
      if (queryReader.test(body) || identifiers(body).some(name => affected.has(name))) {
        affected.add(name); changed = true;
      }
    }
  }
  return affected;
}

export function readNativeQuerySources(root) {
  const sources = {};
  function visit(path) {
    for (const entry of readdirSync(join(root, path), {withFileTypes: true})) {
      const name = `${path}/${entry.name}`;
      if (entry.isDirectory()) visit(name);
      else if (/\.(?:mbt|c|cc|cpp|h)$/u.test(name)) {
        sources[name] = readFileSync(join(root, name), 'utf8');
      }
    }
  }
  visit('src');
  return sources;
}

export function selectNativeQueryTests(owner, sources, env,
  manifest = nativeQueryCoverage) {
  if (!owners.includes(owner)) throw new Error(`Unknown native harness: ${owner}`);
  const entries = Object.entries(manifest.files ?? {});
  if (entries.length === 0) throw new Error('Missing native query ownership inventory');
  const selected = [];
  const reasons = [];
  let expected = 0;
  let total = 0;
  const helpers = queryEnvironmentHelpers(sources);
  for (const [file, entry] of entries) {
    if (!/^[a-z_]+_wbtest\.mbt$/u.test(file) ||
        !Array.isArray(entry.owners) || entry.owners.length === 0 ||
        new Set(entry.owners).size !== entry.owners.length ||
        entry.owners.some(value => !owners.includes(value)) ||
        !Array.isArray(entry.tests) || entry.tests.length === 0 ||
        new Set(entry.tests).size !== entry.tests.length ||
        !Array.isArray(entry.variables)) {
      throw new Error(`Malformed native query ownership: ${file}`);
    }
    const source = sources[`${packagePath}/${file}`];
    const found = testNames(source ?? '');
    if (entry.tests.some(name => !found.includes(name))) {
      throw new Error(`Missing required native query case: ${file}`);
    }
    if (!same(found, entry.tests) || !same(variables(source), entry.variables)) {
      reasons.push(`changed native query cases or environment: ${file}`);
    }
    if (entry.owners.includes(owner)) {
      selected.push(`${packagePath}/${file}`);
      expected += found.length;
    }
  }
  for (const [path, source] of Object.entries(sources)) {
    if (path.startsWith(`${packagePath}/`)) {
      total += testNames(source).length;
      const file = path.slice(packagePath.length + 1);
      const readsEnvironment = environmentReader.test(source) || queryReader.test(source) ||
        identifiers(source).some(name => helpers.has(name));
      if (readsEnvironment && !manifest.files[file]) {
        reasons.push(`unowned native query environment reader: ${file}`);
      }
    } else if (!/_(?:wb|bb)?test\.mbt$/u.test(path) && environmentReader.test(source)) {
      // Reviewed production surfaces: temporary file placement, and passing
      // the unchanged environment into an executor child. Neither selects
      // query test cases. New reads keep the full suite until reviewed.
      const allowed = path === 'src/platform_native/remote_journal/inspection_stub.c'
        ? source.replace('getenv("TMPDIR")', '')
        : path === 'src/platform_native/executor_slot/executor_slot_stub.c'
          ? source.replace('extern char **environ;', '')
            .replace('posix_spawn(&pid, path, &actions, NULL, argv, environ)', '')
          : source;
      if (environmentReader.test(allowed)) reasons.push(`production environment reader: ${path}`);
    }
  }
  const required = manifest.requiredEnvironment?.[owner];
  if (!Array.isArray(required) || required.length === 0) {
    throw new Error(`Missing required native environment inventory: ${owner}`);
  }
  for (const name of required) {
    if (typeof env[name] !== 'string' || env[name].length === 0) {
      throw new Error(`Required native query prerequisite missing: ${name}`);
    }
  }
  if (owner === 'http-client' && env.ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS !== '1') {
    throw new Error('Native query DuckDB execution must be required');
  }
  if (expected === 0 || total === 0) throw new Error('Empty native query selection');
  return {paths: reasons.length ? [packagePath] : selected,
    expected: reasons.length ? total : expected,
    mode: reasons.length ? 'full-fallback' : 'subset', reasons};
}

export function assertNativeQueryExecution(selection, result) {
  const checked = assertTestExecution('moon', 'moon',
    ['test', ...selection.paths, '--target', 'native'], result);
  if (checked.counts.passed !== selection.expected) {
    throw new Error(`Native query coverage mismatch: expected ${selection.expected}, ` +
      `executed ${checked.counts.passed}`);
  }
  return checked.counts;
}

export async function runNativeQueryTests(moon, owner, {cwd, env}) {
  const root = cwd instanceof URL ? fileURLToPath(cwd) : cwd;
  const selection = selectNativeQueryTests(owner, readNativeQuerySources(root), env);
  console.log(`Native query ${owner}: ${selection.mode}, ${selection.expected} cases`);
  for (const reason of selection.reasons) console.log(`Full query fallback: ${reason}`);
  const child = spawn(moon, ['test', ...selection.paths, '--target', 'native'],
    {cwd, env, stdio: ['ignore', 'pipe', 'pipe']});
  // Keep bounded summary tails while forwarding normal compiler/test output.
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', chunk => {
    process.stdout.write(chunk); stdout = (stdout + chunk).slice(-65536);
  });
  child.stderr.on('data', chunk => {
    process.stderr.write(chunk); stderr = (stderr + chunk).slice(-65536);
  });
  const result = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (status, signal) => resolve({status, signal, stdout, stderr}));
  });
  assertNativeQueryExecution(selection, result);
}
