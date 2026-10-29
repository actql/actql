// Public-client assertions shared by ordinary JSON row-family scenarios.
// The caller obtains a fresh Client from the selected installed Host and
// checks its physical release separately. No private factory or Run replay
// is used, and a failed phase is never continued by these helpers.
import assert from 'node:assert/strict';
import {lstat, readFile, writeFile} from 'node:fs/promises';
import {isAbsolute, join} from 'node:path';
import {isDeepStrictEqual} from 'node:util';

export function installedFamilyReadPaths(root) {
  assert.equal(typeof root, 'string');
  assert(isAbsolute(root));
  return Object.freeze(Object.fromEntries([
    ['reference', 'original-reference.json'],
    ['firstState', 'first-state.json'],
    ['firstRows', 'first-rows.json'],
    ['firstDescription', 'first-description.json'],
    ['firstClose', 'first-close.json'],
    ['recoveredRows', 'recovered-rows.json'],
    ['recoveredState', 'recovered-state.json'],
    ['recoveredDescription', 'recovered-description.json'],
    ['recoveredClose', 'recovered-close.json'],
  ].map(([name, file]) => [name, join(root, file)])));
}

function originalRef(value) {
  // The actual SDK admits the wire. These assertions require the public
  // correspondence fields rather than inventing a replacement reference.
  for (const name of ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']) {
    assert.equal(typeof value?.[name], 'string', `Missing original ${name}`);
    assert(value[name].length > 0, `Empty original ${name}`);
  }
  return structuredClone(value);
}

function readScenario(scenario) {
  assert.equal(scenario.approval, 'none');
  assert.equal(typeof scenario.id, 'string');
  assert.equal(typeof scenario.program?.text, 'string');
  assert.equal(typeof scenario.program?.format, 'string');
  assert.equal(typeof scenario.result?.name, 'string');
  assert(Array.isArray(scenario.result.rows));
  assert(Array.isArray(scenario.result.columns));
  assert(isDeepStrictEqual(JSON.parse(JSON.stringify(scenario.result.rows)), scenario.result.rows));
  assert(isDeepStrictEqual(JSON.parse(JSON.stringify(scenario.result.columns)), scenario.result.columns));
}

// These observed-data assertions are also used by thin physical Host test
// adapters. They confer no authority and do not manufacture Host-specific
// Result references or schema metadata that a public API does not expose.
export {originalRef as familyReadRunReference, readScenario as assertFamilyReadScenario};

export function assertFamilyReadState(state, originalRunId) {
  assert.equal(state.status, 'succeeded');
  assert.equal(state.result_available, true);
  assert.equal(typeof state.run_id, 'string');
  assert(state.run_id.length > 0);
  if (arguments.length === 2) assert.equal(state.run_id, originalRunId);
}

export function assertFamilyReadRows(rows, scenario, originalRows) {
  if (arguments.length === 3) assert.deepEqual(rows, originalRows);
  assert.deepEqual(rows, scenario.result.rows);
}

export function assertFamilyReadProgram(captured, scenario) {
  assert.equal(captured.scenarioId, scenario.id);
  assert.deepEqual(captured.program, scenario.program);
}

async function absent(paths) {
  for (const path of paths) {
    await assert.rejects(lstat(path), {code: 'ENOENT'},
      `Existing scenario original cannot be overwritten: ${path}`);
  }
}

async function save(path, value) {
  const raw = JSON.stringify(value);
  await writeFile(path, raw + '\n', {encoding: 'utf8', mode: 0o600, flag: 'wx'});
}

async function withFirstClose(client, path, operation) {
  let value, primary, cleanup, businessFailed = false, cleanupFailed = false;
  try { value = await operation(); }
  catch (cause) { primary = cause; businessFailed = true; }
  try { await client.close(); }
  catch (cause) { cleanup = cause; cleanupFailed = true; }
  const close = {acknowledged: !cleanupFailed,
    businessPassed: !businessFailed,
    primaryCode: primary?.code ?? null,
    cleanupCode: cleanup?.code ?? null,
    cleanupPending: typeof cleanup?.cleanupPending === 'boolean'
      ? cleanup.cleanupPending : null};
  try { await save(path, close); }
  catch (cause) {
    throw new AggregateError([...(businessFailed ? [primary] : []),
      ...(cleanupFailed ? [cleanup] : []), cause],
    'Family fixture close receipt unavailable', {cause: businessFailed ? primary : cleanupFailed ? cleanup : cause});
  }
  if (businessFailed && cleanupFailed) {
    throw new AggregateError([primary, cleanup], 'Family read and first close failed',
      {cause: primary});
  }
  if (businessFailed) throw primary;
  if (cleanupFailed) throw cleanup;
  return {...value, firstClose: close};
}

function resultOnOriginal(execution, ref, name) {
  const result = execution.result(name);
  assert.deepEqual(result.ref, {run: ref, resultName: name});
  assert.deepEqual(result.execution.ref, ref);
  return result;
}

// Shared observation/first-close mechanics for the approval scenario. These
// helpers do not open a Host, authorize an operation or issue a retry.
export {absent as assertAbsentInstalledFamilyObservations,
  save as saveInstalledFamilyObservation,
  withFirstClose as withInstalledFamilyFirstClose,
  resultOnOriginal as installedFamilyResultOnOriginal};

export async function captureInstalledFamilyRead(client, {scenario, paths}) {
  return withFirstClose(client, paths.firstClose, async () => {
    readScenario(scenario);
    await absent([paths.reference, paths.firstState, paths.firstRows, paths.firstDescription, paths.firstClose]);
    const options = {format: scenario.program.format};
    if (Object.hasOwn(scenario.program, 'parameters')) {
      options.parameters = scenario.program.parameters;
    }
    const execution = await client.startSource(scenario.program.text, options);
    const ref = originalRef(execution.ref);
    await save(paths.reference, {scenarioId: scenario.id,
      program: scenario.program, ref});
    const state = await execution.wait();
    await save(paths.firstState, {ref, state});
    assertFamilyReadState(state);
    const result = resultOnOriginal(execution, ref, scenario.result.name);
    const rows = await result.all();
    // Save the actual first rows before description or independent assertions.
    // A later failure cannot turn an unavailable first array into equality.
    const rowsRecordedExactly = isDeepStrictEqual(JSON.parse(JSON.stringify(rows)), rows);
    await save(paths.firstRows, {ref, runId: state.run_id,
      resultRef: result.ref, rows, rowsRecordedExactly});
    assert(rowsRecordedExactly, 'Fixture receipt lost a row value distinction');
    const description = await result.describe();
    const columnsRecordedExactly = isDeepStrictEqual(
      JSON.parse(JSON.stringify(description.columns)), description.columns);
    await save(paths.firstDescription, {ref, resultRef: result.ref,
      columns: description.columns, columnsRecordedExactly});
    assert(columnsRecordedExactly, 'Fixture receipt lost a column distinction');
    assertFamilyReadRows(rows, scenario);
    assert.deepEqual(description.columns, scenario.result.columns);
    return {ref, runId: state.run_id, resultName: scenario.result.name};
  });
}

export async function recoverInstalledFamilyRead(client, {scenario, paths}) {
  return withFirstClose(client, paths.recoveredClose, async () => {
    readScenario(scenario);
    await absent([paths.recoveredState, paths.recoveredRows, paths.recoveredDescription, paths.recoveredClose]);
    const read = async path => JSON.parse(await readFile(path, 'utf8'));
    const captured = await read(paths.reference);
    const first = await read(paths.firstRows);
    const firstDescription = await read(paths.firstDescription);
    const firstState = await read(paths.firstState);
    const firstClose = await read(paths.firstClose);
    assert.equal(firstClose.acknowledged, true);
    assert.equal(firstClose.businessPassed, true);
    assert.equal(first.rowsRecordedExactly, true);
    assert.equal(firstDescription.columnsRecordedExactly, true);
    assertFamilyReadProgram(captured, scenario);
    const ref = originalRef(captured.ref);
    assert.deepEqual(first.ref, ref);
    assert.deepEqual(firstState.ref, ref);
    assertFamilyReadState(firstState.state, first.runId);
    assert.deepEqual(first.resultRef, {run: ref, resultName: scenario.result.name});
    assert.deepEqual(firstDescription.ref, ref);
    assert.deepEqual(firstDescription.resultRef, first.resultRef);
    const execution = await client.attach(ref);
    assert.deepEqual(execution.ref, ref);
    // Materialize and preserve Saved before status or description can prewarm it.
    const result = resultOnOriginal(execution, ref, scenario.result.name);
    const rows = await result.all();
    const rowsRecordedExactly = isDeepStrictEqual(JSON.parse(JSON.stringify(rows)), rows);
    await save(paths.recoveredRows, {ref, runId: first.runId,
      resultRef: result.ref, rows, rowsRecordedExactly});
    assert(rowsRecordedExactly, 'Fixture receipt lost a recovered row distinction');
    const state = await execution.status();
    await save(paths.recoveredState, {ref, state});
    assertFamilyReadState(state, first.runId);
    const description = await result.describe();
    const columnsRecordedExactly = isDeepStrictEqual(
      JSON.parse(JSON.stringify(description.columns)), description.columns);
    await save(paths.recoveredDescription, {ref, resultRef: result.ref,
      columns: description.columns, columnsRecordedExactly});
    assert(columnsRecordedExactly, 'Fixture receipt lost a recovered column distinction');
    assertFamilyReadRows(rows, scenario, first.rows);
    assert.deepEqual(description.columns, firstDescription.columns);
    assert.deepEqual(description.columns, scenario.result.columns);
    return {ref, runId: state.run_id, resultName: scenario.result.name};
  });
}
