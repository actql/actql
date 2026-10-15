// Copy into an ordinary installed consumer. Only the public Node Client is
// imported here; the application supplies its actual trusted installation.
// This is not a provider/profile installer or permission to make a paid call.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {resolve, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

const [phase, applicationPath, selectedState, selectedEvidence, milliseconds] = process.argv.slice(2);
const failure = code => Object.assign(new Error(code), {code});
const report = value => process.stdout.write(`${JSON.stringify(value)}\n`);
let client;
let primary;
let completed;
try {
  if (!['run', 'read'].includes(phase) || !applicationPath ||
      !selectedState || !selectedEvidence || !/^[1-9][0-9]*$/u.test(milliseconds ?? '')) {
    throw failure('M1ExplicitSelectionRequired');
  }
  const timeout = Number(milliseconds);
  if (!Number.isSafeInteger(timeout) || timeout > 2147483647) throw failure('M1InvalidDeadline');
  const stateDir = resolve(selectedState);
  const evidence = resolve(selectedEvidence);
  const application = resolve(applicationPath);
  const file = name => join(evidence, name + '.json');
  const save = (name, value) => writeFileSync(file(name), JSON.stringify(value) + '\n',
    {flag: 'wx', mode: 0o600});
  const read = name => JSON.parse(readFileSync(file(name), 'utf8'));
  const original = {stateDir, application,
    applicationSha256: createHash('sha256').update(readFileSync(application)).digest('hex')};
  if (phase === 'run') {
    // Refuse before importing application code or opening a Host. Never turn a
    // retained/Unknown request into deliberate new work by rerunning run.
    if (existsSync(evidence) || existsSync(stateDir)) throw failure('M1FreshStartRequired');
    mkdirSync(evidence, {mode: 0o700});
    save('selection', original);
  } else {
    assert.deepEqual(read('selection'), original, 'The original application/Store selection changed');
    if (!existsSync(stateDir)) throw failure('M1OriginalStateRequired');
  }
  const app = (await import(pathToFileURL(application).href)).default;
  if (!app || typeof app.installation !== 'object' || !app.program ||
      typeof app.resultName !== 'string' || !app.resultName ||
      !Array.isArray(app.expectedRows) || app.expectedRows.length !== 1) {
    throw failure('M1ApplicationRequired');
  }
  if (phase === 'run' && (!app.signer || typeof app.signer.sign !== 'function')) {
    throw failure('M1ReviewerRequired');
  }
  // No checkout/internal runtime fallback and no fixture provider is supplied.
  const {open} = await import('@actql/node');
  const signal = AbortSignal.timeout(timeout);
  client = await open({stateDir, durability: 'durable', installation: app.installation});
  const until = async observe => {
    for (;;) {
      signal.throwIfAborted();
      const value = await observe();
      if (value !== undefined) return value;
      await delay(25, undefined, {signal});
    }
  };
  let run;
  if (phase === 'run') {
    const submissionRef = client.newSubmission();
    save('submission', submissionRef); // Before the one original submit.
    run = await client.start(app.program, {submissionRef, signal});
    save('run', run.ref);
    const checkpoint = await until(async () => {
      const page = await client.checkpoints({signal});
      return page.items.find(item => item.kind === 'model_invocation' &&
        item.subject?.runDefinitionCid === run.ref.runDefinitionCid);
    });
    // Read the actual disclosed review, not a fabricated checkpoint summary.
    // Do not log its body, input, credentials or model response.
    await client.reviewCheckpoint(checkpoint, {signal});
    save('checkpoint', {checkpointCid: checkpoint.checkpointCid, runRef: run.ref});
    // Explicitly selected run executes the accepted approval scenario in the
    // SAME original live Host. Cold restoration is not made a first-start gate.
    // A lost resolution reply never causes a second submit or resolution here.
    save('approval-attempt', {checkpointCid: checkpoint.checkpointCid});
    const resolution = await client.resolveCheckpoints([
      {checkpoint, decision: 'approved'},
    ], {signer: app.signer, signal});
    save('approval-observation', resolution);
    assert.equal(resolution.results.length, 1);
    assert.equal(resolution.results[0].status, 'committed');
    const state = await run.wait({until: 'terminal', signal});
    if (state.status !== 'succeeded') throw failure('M1OriginalRunNotSuccessful');
  } else {
    const ref = read('run');
    run = await client.attach(ref, {signal});
    assert.deepEqual(run.ref, ref);
    // A fresh process only attaches/reads; it never submits, resolves,
    // reconciles, re-prepares, or resumes the original Model operation.
    const state = await run.status({signal});
    if (state.status !== 'succeeded') throw failure('M1OriginalRunNotSuccessful');
  }
  const rows = await run.result(app.resultName).all({signal, maxRows: 1});
  assert.deepEqual(rows, app.expectedRows);
  completed = {phase, outcome: 'original_named_result_matched'};
} catch (error) {
  primary = error;
}
let cleanup;
try { await client?.close(); } catch (error) { cleanup = error; }
// A method returning or a script exit is not a physical ACK/GC/funding proof.
// Actual dispatch/Provider/Store evidence must accompany the installed run.
if (primary || cleanup) {
  report({phase, outcome: 'failed', error: primary?.code ?? primary?.name ?? null,
    cleanupError: cleanup?.code ?? cleanup?.name ?? null,
    evidenceRetained: true, automaticResubmit: false});
  process.exitCode = 1;
} else {
  report({...completed, clientClose: 'completed', physicalDispatches: null,
    physicalCleanup: 'not_independently_measured', normalProfile: null});
}
