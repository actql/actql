import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {setImmediate} from 'node:timers/promises';
import {canonicalText} from '../check-canonical-json.mjs';
import {nativeJoinedModelRun} from './native-joined-model-run.mjs';

const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');

export function nativeDependentModelInput(outputSchema) {
  assert.equal(outputSchema.type, 'object');
  return {type: 'object', nullable: false, additional_properties: false,
    fields: {prior: {...outputSchema, nullable: true}}};
}

export function nativeDependentModelDocument(document, schema) {
  const input = /^input:\n  notes: string\n  active_users: int64\n  trend: string$/mu;
  assert.match(document, input);
  const {additional_properties, ...authored} = schema.fields.prior;
  assert.equal(additional_properties, false);
  return document.replace(input, 'input:\n  prior: ' + canonicalText(authored));
}

// Both the authorized receiver and its producer are selected before adoption.
// These identities are preimages we authored into the local settings files.
export function nativeDependentModelOutputPolicy(producer, receiver) {
  for (const original of [producer, receiver]) {
    for (const property of ['task', 'profile', 'binding', 'outputSchema']) {
      assert.match(original[property], /^sha256:[0-9a-f]{64}$/u);
    }
  }
  assert.notEqual(producer.task, receiver.task);
  assert.notEqual(producer.binding, receiver.binding);
  return {
    version: 'actql-local-model-output-policy/0.1',
    receiving_profile_cid: receiver.profile,
    receiving_task_cid: receiver.task,
    inputs: [{
      input_index: 0, producer_stage: 1, producer_step: 1,
      producer_task_cid: producer.task, producer_binding_cid: producer.binding,
      producer_profile_cid: producer.profile, producer_schema_cid: producer.outputSchema,
      receiving_binding_cid: receiver.binding, classification: 'internal',
    }],
  };
}

export function nativeModelBindingIdentity(provider, originals, configuration) {
  return cid({
    version: 'actql-model-provider-binding/0.1', provider_id: provider,
    installation_revision_cid: originals.installationRevision.cid,
    configuration_contract_cid: originals.configurationContract.cid,
    configuration_cid: cid(configuration),
  });
}

export function nativeDependentModelRun(firstTask, secondTask, {receiverRateLimited = false} = {}) {
  const fixture = nativeJoinedModelRun(firstTask, secondTask);
  fixture.program.id = 'native-file-dependent-model-join';
  const [, first, second] = fixture.program.stages;
  assert.equal(first.id, 'first');
  assert.equal(second.id, 'second');
  first.steps[1].infer.on_non_success = 'fail';
  second.inputs = {rows: {result: {stage: 'first', result: 'rows'}}};
  second.steps[1].infer.input = {prior: {field: 'value'}};
  fixture.answers[0] = {level: 'low', reason: 'typed output of the first controlled Model'};
  fixture.answers[1] = {level: 'high', reason: 'received the first Model typed output'};
  const [row] = fixture.expectedRows;
  row.first_value = {...fixture.answers[0]};
  if (receiverRateLimited) {
    second.steps[1].infer.on_non_success = 'outcomes';
    row.second_outcome = 'failed:rate_limit';
    row.second_value = null;
  } else {
    row.second_value = {...fixture.answers[1]};
  }
  return {...fixture, expectedReceiverInput: {prior: {...fixture.answers[0]}}};
}

// The peer must still own the same live reply when the ordered custody read
// returns. An earlier client deadline or disconnect cannot be our fault cut.
export async function dropNativeDependentModelReply(request, response, inspect) {
  const {socket} = request;
  let peerEnded = false;
  const observePeerEnd = () => { peerEnded = true; };
  const requireUnsentReply = () => {
    assert(request.complete && response.socket === socket && !peerEnded &&
      socket.readable && !socket.readableEnded && socket.writable && !socket.destroyed &&
      !response.destroyed && !response.headersSent && !response.writableEnded,
    'B disconnected or started a reply before the controlled drop');
  };
  socket.once('end', observePeerEnd);
  socket.once('close', observePeerEnd);
  response.once('close', observePeerEnd);
  try {
    requireUnsentReply();
    const custody = await inspect();
    // SQLite reads can be synchronous within inspect. Let the socket report
    // any closure already ready before this peer initiates the deliberate cut.
    await setImmediate();
    requireUnsentReply();
    response.destroy();
    assert(response.destroyed && socket.destroyed, 'Controlled B drop did not close the original reply');
    return custody;
  } finally {
    socket.off('end', observePeerEnd);
    socket.off('close', observePeerEnd);
    response.off('close', observePeerEnd);
  }
}
