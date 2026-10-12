// Each invocation opens the real installed Host in a genuinely fresh process.
// This verifies saved Content Result recovery, not COMMAND approval recovery.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {connectEmbeddedLocal} from '../embedded-local.mjs';

const {options, program, ref} = JSON.parse(await readFile(process.argv[2], 'utf8'));
const phase = process.argv[3];
assert.ok(phase === 'create' || phase === 'read');
let starts = 0;
options.installation.authorization.faultInjection = async step => {
  if (step !== 'content_workspace_reserved') return;
  starts++;
  assert.equal(phase, 'create', 'restoration cannot re-enter the original producer');
};
const client = await connectEmbeddedLocal(options);
try {
  const run = phase === 'create'
    ? await client.startSource(JSON.stringify(program), {format: 'json',
      submissionRef: client.newSubmission({nonce: 'content-process'})})
    : await client.attach(ref);
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = await run.result('file').all();
  process.stdout.write(JSON.stringify({pid: process.pid, starts, status: state.status,
    ref: run.ref, rows}) + '\n');
} finally {
  await client.close();
}
