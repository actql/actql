// A fresh process reopens only the real journal and publication Store.
import {writeFile} from 'node:fs/promises';
import {openReadOpeningFixture, connectOpeningHost} from './client-read-opening.fixture.mjs';

const {directory, entrance, ref, attemptId, output} = JSON.parse(process.argv[2]);
const fixture = await openReadOpeningFixture(directory);
const host = await connectOpeningHost(fixture, entrance, directory);
try {
  const run = await host.client.attach(ref);
  const status = await run.status();
  const result = run.result('answer');
  const first = await result.deliveryAttempt(attemptId);
  const second = await result.deliveryAttempt(attemptId);
  await writeFile(output, JSON.stringify({ref: run.ref, status: status.status, first, second, counts: fixture.counts}));
} finally {
  await host.close(); await fixture.close();
}
