// Public-client observations for the standard REST conformance caller. This
// owns no Host, reader, retry, authority or provider transport state machine.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

const scalarFailure = cause => Object.freeze({name: String(cause?.name ?? 'Error'),
  message: String(cause?.message ?? cause),
  ...(typeof cause?.code === 'string' ? {code: cause.code} : {})});
const save = async (directory, name, value) => {
  await mkdir(directory, {recursive: true});
  await writeFile(join(directory, name), JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});
};

// These are the existing system tool locations on the selected CI profiles.
// A missing or failed tool is still an unsuccessful observation, never FD0.
export function scopedStateFdCommand(platform) {
  return platform === 'linux' ? '/usr/bin/lsof' : '/usr/sbin/lsof';
}

export function observeOwnScopedStateFds(roots) {
  assert(Array.isArray(roots) && roots.length > 0);
  const command = scopedStateFdCommand(process.platform);
  const observations = roots.map(root => {
    const args = ['-nP', '-a', '-p', String(process.pid), '+D', root, '-F', 'pfn'];
    const result = spawnSync(command, args, {encoding: 'utf8', maxBuffer: 1024 * 1024});
    const exactEmpty = result.status === 1 && result.stdout === '' && result.stderr === '' && !result.error;
    return {root, pid: process.pid, command, args,
      exitCode: result.status, stdout: result.stdout, stderr: result.stderr,
      ...(result.error ? {error: scalarFailure(result.error)} : {}), exactEmpty};
  });
  // This observation runs in the same still-live application process after
  // the awaited close. Process exit can never supply a close ACK here.
  return {pid: process.pid, aliveAfterClose: true, observations,
    scopedStateFd0: observations.every(value => value.exactEmpty)};
}

async function withFirstClose(client, {outputRoot, stateRoots}, operation) {
  let primary, value, closeFailure;
  const close = {attempted: false, acknowledged: false, businessPassed: false};
  try { value = await operation(); close.businessPassed = true; }
  catch (cause) { primary = cause; }
  try {
    close.attempted = true;
    await client.close();
    close.acknowledged = true;
  } catch (cause) { closeFailure = cause; close.failure = scalarFailure(cause); }
  close.fd = observeOwnScopedStateFds(stateRoots);
  await save(outputRoot, 'first-close.json', close);
  if (!primary && closeFailure) primary = closeFailure;
  if (!primary && !close.fd.scopedStateFd0) primary = new Error('StandardRestScopedStateFdStillOpen');
  await save(outputRoot, 'outcome.json', {passed: !primary,
    ...(primary ? {primary: scalarFailure(primary)} : {}),
    publicCloseAcknowledged: close.acknowledged, scopedStateFd0: close.fd.scopedStateFd0});
  if (primary) throw primary;
  return value;
}

export async function captureStandardRestRead(client, {publicSdk, program,
  assertRows, outputRoot, stateRoots}) {
  // Capture the getter from the SAME installed public namespace selected by
  // the consumer, once before any await. Never import a source SDK WeakMap.
  const getSubmissionInput = publicSdk?.getSubmissionInput;
  return withFirstClose(client, {outputRoot, stateRoots}, async () => {
    assert.equal(typeof getSubmissionInput, 'function');
    assert.equal(typeof assertRows, 'function');
    const pending = client.startSource(JSON.stringify(program), {format: 'json'});
    // Observe this SAME original pending before even the synchronous getter
    // can throw. This observation neither retries nor classifies acceptance.
    const settled = Promise.resolve(pending).then(value => ({value}),
      cause => ({failed: true, cause}));
    let input;
    try {input = Reflect.apply(getSubmissionInput, publicSdk, [pending]);}
    catch (cause) {
      await save(outputRoot, 'original-submission-input.json',
        {available: false, projectionFailure: scalarFailure(cause)});
      throw cause;
    }
    await save(outputRoot, 'original-submission-input.json',
      input === undefined ? {available: false} : {available: true, input});
    const outcome = await settled;
    if (outcome.failed) throw outcome.cause;
    assert.notEqual(input, undefined, 'OriginalStandardRestSubmissionInputUnavailable');
    const execution = outcome.value;
    const reference = structuredClone(execution.ref);
    await save(outputRoot, 'original-reference.json', reference);
    const waited = await execution.wait();
    await save(outputRoot, 'original-wait.json', waited);
    assert.equal(waited.status, 'succeeded');
    const state = await execution.status();
    await save(outputRoot, 'original-state.json', state);
    assert.equal(state.status, 'succeeded');
    const result = execution.result('rows');
    const rows = await result.all();
    await save(outputRoot, 'original-rows.json', rows);
    assertRows(rows);
    return {reference, rows};
  });
}

export async function recoverStandardRestRead(client, {reference, originalRows,
  assertRows, outputRoot, stateRoots}) {
  return withFirstClose(client, {outputRoot, stateRoots}, async () => {
    assert.equal(typeof assertRows, 'function');
    // This is the same original public Run, not a second submission. The
    // caller's async child keeps the parent HTTPS event loop available.
    const execution = await client.attach(reference);
    const state = await execution.status();
    await save(outputRoot, 'saved-state.json', state);
    assert.equal(state.status, 'succeeded');
    assert.deepEqual(execution.ref, reference);
    const rows = await execution.result('rows').all();
    await save(outputRoot, 'saved-rows.json', rows);
    assertRows(rows); assert.deepEqual(rows, originalRows);
    return {reference, rows};
  });
}
