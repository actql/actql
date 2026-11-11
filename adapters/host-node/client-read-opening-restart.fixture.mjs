// A fresh process reopens only the real journal and publication Store.
import {writeFile} from 'node:fs/promises';
import {openReadOpeningFixture, connectOpeningHost, traceReadRecovery} from './client-read-opening.fixture.mjs';

const {directory, entrance, ref, attemptId, output, submissionRef, newRead = false} = JSON.parse(process.argv[2]);
const fixture = await openReadOpeningFixture(directory);
const host = await connectOpeningHost(fixture, entrance, directory);
try {
  if (newRead) console.log('RESTORED_READ_121_PHASE', 'connected');
  const run = await host.client.attach(ref);
  const status = await run.status();
  const result = run.result('answer');
  const first = await result.deliveryAttempt(attemptId);
  const second = await result.deliveryAttempt(attemptId);
  const request = submissionRef === undefined ? undefined : await host.client.lookupSubmission(submissionRef);
  const retained = fixture.retainedAdmission(ref);
  const lookupCounts = {...fixture.counts};
  if (newRead) console.log('RESTORED_READ_121_PHASE', 'original-found');
  let rows, readAttempt, description, readState, rowsYielded, originalAfterRead;
  if (newRead) {
    description = await result.describe();
    traceReadRecovery('restored-fresh-read:start', {entrance});
    const reader = result.rows(); rows = await Array.fromAsync(reader);
    readState = reader.state();
    rowsYielded = reader.rowsYielded();
    traceReadRecovery('restored-fresh-read:finished', {entrance, rowsYielded});
    await host.settled();
    console.log('RESTORED_READ_121_PHASE', 'read', rows.length);
    readAttempt = await result.deliveryAttempt(reader.attemptId);
    originalAfterRead = await result.deliveryAttempt(attemptId);
    traceReadRecovery('restored-fresh-receipt:finished', {entrance});
    if (reader.state() !== 'complete') throw new Error('RestoredReadIncomplete');
  }
  await writeFile(output, JSON.stringify({pid: process.pid, ref: run.ref, status: status.status,
    first, second, request, lookupCounts, rows, readAttempt,
    description, readState, rowsYielded, originalAfterRead,
    runAdmissionEvidence: retained,
    counts: fixture.counts}));
  if (newRead) console.log('RESTORED_READ_121_PHASE', 'saved');
} finally {
  await host.close(); await fixture.close();
}
