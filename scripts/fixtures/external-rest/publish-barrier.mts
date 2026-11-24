import {writeFile, link, unlink} from 'node:fs/promises';

// Complete fixture bytes before publishing the polled name. Exclusive linking
// retains the original wx refusal; this is not a durable product receipt.
export async function publishStandardRestBarrier(path: string, body: string) {
  const pending = path + '.pending';
  await writeFile(pending, body, {flag: 'wx'});
  await link(pending, path);
  await unlink(pending);
}
