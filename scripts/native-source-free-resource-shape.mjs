// One original resource-shape case, shared by ordinary installed acceptance
// and its separately qualified diagnostic. The caller supplies the same
// installed CLI, checked configuration and independent streaming row verifier.
import assert from 'node:assert/strict';
import {writeFile, unlink} from 'node:fs/promises';
import {join} from 'node:path';

export async function observeNativeResourceOperatorShape({project, cli, configuration,
  fixture, outputDirectory, verifyRows}) {
  const command = async args => {
    const reply = await cli([...configuration, ...args], project);
    assert.equal(reply.code, 0); assert.equal(reply.signal, null);
    return reply;
  };
  const inputName = fixture.id + '.json', input = join(project, inputName);
  const wire = JSON.stringify(fixture.program), inputWireBytes = Buffer.byteLength(wire);
  if (fixture.id === 'few-long-strings') assert(inputWireBytes > 1048576);
  const first = join(outputDirectory, fixture.id + '-first.jsonl');
  const saved = join(outputDirectory, fixture.id + '-saved.jsonl');
  await writeFile(input, wire, {flag: 'wx', mode: 0o600});
  const original = JSON.parse((await command(['run', inputName, '--format', 'json', '--json'])).stdout);
  assert.equal(original.version, 'actql-run-state/0.1');
  assert.equal(original.status, 'succeeded');
  assert.equal(typeof original.run_id, 'string'); assert(original.run_id.length > 0);
  await command(['result', original.run_id, '--result', 'answer0', '--format', 'jsonl', '--output', first]);
  const firstRows = await verifyRows(first, fixture.expectedRows, fixture.key);
  if (fixture.id === 'few-long-strings') {
    assert.equal(firstRows.rows, 2); assert(firstRows.wireBytes > 1048576);
  }
  await unlink(input);
  const restored = JSON.parse((await command(['status', original.run_id, '--json'])).stdout);
  assert.deepEqual([restored.version, restored.run_id, restored.status],
    [original.version, original.run_id, original.status]);
  await command(['result', original.run_id, '--result', 'answer0', '--format', 'jsonl', '--output', saved]);
  const savedRows = await verifyRows(saved, fixture.expectedRows, fixture.key);
  assert.equal(savedRows.contentSha256, firstRows.contentSha256);
  if (fixture.id === 'small-input-large-output') {
    assert(inputWireBytes < 16384); assert(firstRows.wireBytes > 1048576);
    assert(firstRows.wireBytes > 100 * inputWireBytes);
  }
  return {id: fixture.id, runId: original.run_id, inputWireBytes,
    first: firstRows, saved: savedRows, inputRemovedBeforeSaved: true};
}
