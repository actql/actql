// Prepared public cancellation caller only. No Host/reader/authority owner.
// Requires the admitted original ref before the held second-page response.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile, writeFile, link, unlink} from 'node:fs/promises';
import {setTimeout as delay} from 'node:timers/promises';
import {join} from 'node:path';
import {withInstalledFamilyFirstClose} from './fixture-source/adapters/host-node/fixtures/installed-family-read.fixture.mjs';
import {observeOwnScopedStateFds} from './conformance.mjs';

const save = (root, name, value) => writeFile(join(root, name),
  JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});

// Complete fixture bytes before publishing the polled name. Exclusive linking
// retains the original wx refusal; this is not a durable product receipt.
export async function publishStandardRestBarrier(path, body) {
  const pending = path + '.pending';
  await writeFile(pending, body, {flag: 'wx'});
  await link(pending, path);
  await unlink(pending);
}
const ownFailure = error => {
  const fields = error && typeof error === 'object' ? Object.getOwnPropertyDescriptors(error) : {};
  return Object.fromEntries(['name', 'message', 'code', 'cleanupPending'].flatMap(name => {
    const value = fields[name]?.value;
    return typeof value === 'string' || typeof value === 'boolean' ? [[name, value]] : [];
  }));
};
async function awaitPageBarrier(path, signal) {
  while (true) {
    signal.throwIfAborted();
    try { return JSON.parse(await readFile(path, 'utf8')); }
    catch (cause) { if (cause?.code !== 'ENOENT') throw cause; }
    await delay(10, undefined, {signal});
  }
}

export async function cancelStandardRestAtPageBarrier(client,
  {publicSdk, program, outputRoot, stateRoots, pageEnteredPath, cancellationReturnedPath}) {
  const getSubmissionInput = publicSdk?.getSubmissionInput;
  const explainCancellation = publicSdk?.explainCancellation;
  let primary, value, failed = false;
  try {
    value = await withInstalledFamilyFirstClose(client, join(outputRoot, 'first-close.json'), async () => {
      assert.equal(typeof getSubmissionInput, 'function');
      assert.equal(typeof explainCancellation, 'function');
      const pending = client.startSource(JSON.stringify(program), {format: 'json'});
      const settled = Promise.resolve(pending).then(value => ({value}), cause => ({failed: true, cause}));
      let input;
      try { input = Reflect.apply(getSubmissionInput, publicSdk, [pending]); }
      catch (cause) {
        await save(outputRoot, 'original-submission-input.json',
          {available: false, projectionFailure: ownFailure(cause)});
        throw cause;
      }
      await save(outputRoot, 'original-submission-input.json', {available: input !== undefined, input});
      assert.notEqual(input, undefined, 'OriginalStandardRestSubmissionInputUnavailable');
      const submission = await settled;
      if (submission.failed) throw submission.cause;
      const execution = submission.value;
      const reference = structuredClone(execution.ref);
      await save(outputRoot, 'original-reference-before-cancel.json', reference);
      const barrier = await awaitPageBarrier(pageEnteredPath, AbortSignal.timeout(30000));
      assert.equal(barrier.page, 2);
      assert.equal(barrier.replyHeld, true);
      const before = await execution.status();
      await save(outputRoot, 'state-before-cancel.json', before);
      assert.equal(before.status, 'running');
      assert.equal(before.result_available, false);
      assert.equal(before.control.physical_stop, 'unknown');
      assert(Number.isSafeInteger(before.control.revision));
      const options = {cancelId: randomUUID(), attemptId: randomUUID(),
        expectedRevision: before.control.revision};
      await save(outputRoot, 'original-cancellation-input-before-send.json', {reference, options});
      let answer, failure, cancellationFailed = false;
      try { answer = await execution.cancel(options); }
      catch (cause) { failure = cause; cancellationFailed = true; }
      // This fixture observation releases only the parent's original HTTP
      // response barrier; it is neither Host stop authority nor a close ACK.
      await publishStandardRestBarrier(cancellationReturnedPath, JSON.stringify({returned: true,
        ...(cancellationFailed ? {failure: ownFailure(failure)} : {answer})}) + '\n');
      if (cancellationFailed) throw failure;
      await save(outputRoot, 'original-cancellation-attempt.json', answer);
      const explanation = Reflect.apply(explainCancellation, publicSdk, [answer]);
      await save(outputRoot, 'original-cancellation-explanation.json',
        {available: explanation !== undefined, explanation});
      assert.equal(answer.kind, 'accepted');
      assert.equal(answer.cancellation.kind, 'accepted');
      assert.deepEqual(answer.cancellation.ref, reference);
      assert.deepEqual(answer.cancellation.cancelRef,
        {...reference, cancelId: options.cancelId, expectedRevision: options.expectedRevision});
      const state = await execution.wait();
      await save(outputRoot, 'terminal-state.json', state);
      assert.equal(state.status, 'cancelled');
      assert.equal(state.result_available, false);
      assert.equal(state.control.cancellation_requested, true);
      assert.equal(state.control.physical_stop, 'confirmed');
      return {reference, cancellation: answer.cancellation, state};
    });
  } catch (cause) { primary = cause; failed = true; }
  const fd = observeOwnScopedStateFds(stateRoots);
  await save(outputRoot, 'post-first-close-fd.json', fd);
  if (!failed && !fd.scopedStateFd0) { primary = new Error('OriginalCancelScopedFdStillOpen'); failed = true; }
  await save(outputRoot, 'outcome.json', {passed: !failed,
    ...(failed ? {primary: ownFailure(primary)} : {}), firstClose: 'first-close.json',
    scopedStateFd0: fd.scopedStateFd0, extraSubmitOrCancel: false});
  if (failed) throw primary;
  return value;
}
