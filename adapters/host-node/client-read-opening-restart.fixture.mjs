// A fresh process reopens only the real journal and publication Store.
import {writeFile} from 'node:fs/promises';
import {openReadOpeningFixture, connectOpeningHost} from './client-read-opening.fixture.mjs';

const {directory, entrance, ref, attemptId, output, requestId, newRead = false} = JSON.parse(process.argv[2]);
const fixture = await openReadOpeningFixture(directory);
const host = await connectOpeningHost(fixture, entrance, directory);
try {
  if (newRead) console.log('RESTORED_READ_121_PHASE', 'connected');
  const run = await host.client.attach(ref);
  const status = await run.status();
  const result = run.result('answer');
  const first = await result.deliveryAttempt(attemptId);
  const second = await result.deliveryAttempt(attemptId);
  const request = requestId === undefined ? undefined : await host.client.lookupRequest(requestId);
  const retained = fixture.retainedAdmission(ref);
  const lookupCounts = {...fixture.counts};
  if (newRead) console.log('RESTORED_READ_121_PHASE', 'original-found');
  let rows, readAttempt;
  if (newRead) {
    const reader = result.rows(); rows = await Array.fromAsync(reader);
    await host.settled();
    console.log('RESTORED_READ_121_PHASE', 'read', rows.length);
    readAttempt = await result.deliveryAttempt(reader.attemptId);
    if (reader.state() !== 'complete') throw new Error('RestoredReadIncomplete');
  }
  await writeFile(output, JSON.stringify({ref: run.ref, status: status.status,
    first, second, request, lookupCounts, rows, readAttempt,
    valuesHostPolicyOriginal: retained?.valuesHostPolicyOriginal,
    counts: fixture.counts}));
  if (newRead) console.log('RESTORED_READ_121_PHASE', 'saved');
} finally {
  await host.close(); await fixture.close();
}
