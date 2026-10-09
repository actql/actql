// The public Client submits one Program; the Host acquires and joins both inputs.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {connect} from '@actql/node';

const connectionPath = process.argv[2] ?? 'two-source-example-data/connection.json';
const submissionPath = connectionPath + '.submission.json';
const options = JSON.parse(await readFile(connectionPath, 'utf8'));
const client = await connect(options);
try {
  const program = await readFile(new URL('two-source-join.program.json', import.meta.url), 'utf8');
  const connectionContext = {mode: client.profile.mode, scopeRef: client.profile.scopeRef,
    workspaceId: client.profile.workspaceId ?? null,
    ...(options.mode === 'remote' ? {endpoint: new URL(options.endpoint).href}
      : {installationDirectory: resolve(options.installation.directory)})};
  let submission;
  try { submission = JSON.parse(await readFile(submissionPath, 'utf8')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    submission = {submissionRef: client.newSubmission({nonce: 'two-source-join-example'}),
      connectionContext, document: program, format: 'json'};
    // Retain the original epoch and input before any possibly accepted send.
    await writeFile(submissionPath, JSON.stringify(submission) + '\n', {flag: 'wx', mode: 0o600});
  }
  assert.deepEqual(submission.connectionContext, connectionContext, 'SavedSubmissionConnectionChanged');
  assert.equal(submission.submissionRef.epoch.authorityScopeCid,
    client.profile.submissionEpoch.authorityScopeCid, 'SavedSubmissionOwnerChanged');
  assert.equal(submission.document, program, 'SavedSubmissionProgramChanged');
  assert.equal(submission.format, 'json', 'SavedSubmissionFormatChanged');
  const execution = await client.startSource(submission.document,
    {format: submission.format, submissionRef: submission.submissionRef});
  const state = await execution.wait({signal: AbortSignal.timeout(60_000)});
  if (state.status !== 'succeeded') throw new Error(JSON.stringify(state));
  const result = execution.result('joined');
  const description = await result.describe();
  const reader = result.rows();
  const rows = await Array.fromAsync(reader);
  if (reader.state() !== 'complete') throw new Error('IncompleteNamedResult');
  await writeFile('joined.jsonl', rows.map(row => JSON.stringify(row)).join('\n') + '\n');
  await writeFile('joined.schema.json', JSON.stringify(description, null, 2) + '\n');
  await writeFile('joined.run.json', JSON.stringify(execution.ref) + '\n');
} finally { client.close(); }
