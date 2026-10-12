// Each invocation owns a genuinely fresh public Host, installed adapters and
// Store. Recovery uses the original captured input and workspace bytes. These
// synthetic keys/configurations are private test inputs, never public output.
import assert from 'node:assert/strict';
import {createPrivateKey, createPublicKey, sign} from 'node:crypto';
import {open, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {inspect} from 'node:util';
import {createGeneratedContentFixture} from './generated-content.fixture.mjs';
import {reopenContentCommandCustody} from './content-command-custody.fixture.mjs';
import {openContentCommandHost} from './content-command-host.fixture.mjs';
import {canonical} from './file-listing-source.fixture.mjs';
import {contentCommandSource, generatedContentCommandProgram, generatedContentCommandSource,
  generatedContentModelCommandProgram} from './content-command.fixture.mjs';
import {mediaInstallation, generatedContentModelProviders} from './generated-model-installation.fixture.mjs';

const configPath = process.argv[2];
const phase = process.argv[3];
assert.ok(['capture', 'approve-model', 'approve', 'read'].includes(phase));
const config = JSON.parse(await readFile(configPath, 'utf8'));
const keys = {privateKey: createPrivateKey(config.privateKey), publicKey: createPublicKey(config.publicKey)};
const closers = [];
let host;
let primaryFailure;
let modelCalls = 0, generations = 0;
let lastStatus, lastCheckpointKinds;
const startedAt = performance.now();
const persistenceTrace = [];
const computeProgress = new Map();
const observationProgress = {polls: 0};
const computeTrace = () => [...computeProgress.values()].map(value => ({...value,
  work: value.work.toString()}));
const durableFixture = async (name, value) => {
  const file = await open(join(config.root, name), 'wx');
  try { await file.writeFile(canonical(value)); await file.sync(); }
  finally { await file.close(); }
  const directory = await open(config.root, 'r');
  try { await directory.sync(); } finally { await directory.close(); }
};
try {
  let generated;
  if (phase === 'capture') {
    generated = await createGeneratedContentFixture({after: close => closers.push(close)}, {
      directory: join(config.root, 'content-store'), expiresAt: config.expiresAt});
    await generated.store.commitPhysicalHolding(generated.holding, [generated.physical.prepared]);
    await generated.issue();
    await durableFixture('content-custody.json', {configuration: generated.configuration,
      description: generated.description, binding: generated.binding, holding: generated.holding});
  } else {
    generated = await reopenContentCommandCustody(
      JSON.parse(await readFile(join(config.root, 'content-custody.json'), 'utf8')));
    closers.push(() => generated.store.close());
  }
  const media = config.modelCommand ? await mediaInstallation({requestBytes: 4096}) : undefined;
  host = await openContentCommandHost({scratch: {path: config.root}, generated, keys,
    entrance: config.entrance, allowSourceRead: phase === 'capture',
    generatedCommand: config.generatedCommand === true,
    modelApprovalRequired: config.modelApprovalRequired === true,
    ...(media === undefined ? {} : {
      modelInstallation: media.installation, hostCapacityPolicy: media.hostCapacityPolicy,
      registerModelProviders: generatedContentModelProviders({root: config.root,
        task: media.task, expected: Buffer.from('name\n"approved.csv"\n'),
        sourceWire: generated.description.wire, onSend: () => modelCalls++}),
    }),
    faultInjection(event, facts) {
      if (event === 'effect_content_generation_retained') generations++;
      // Summarize the existing validated Local observations without retaining
      // rows, references or an unbounded per-poll trace. These are diagnostic
      // deltas, never a replacement accounting owner or execution authority.
      if (event === 'local_compute_advanced' && Number.isInteger(facts?.task) &&
          typeof facts.work === 'string' && /^\d+$/u.test(facts.work) &&
          typeof facts.progress === 'string' && /^\d+$/u.test(facts.progress)) {
        const elapsedMs = Math.round(performance.now() - startedAt);
        let entry = computeProgress.get(facts.task);
        if (entry === undefined && computeProgress.size < 128) {
          entry = {task: facts.task, polls: 0, work: 0n, firstElapsedMs: elapsedMs};
          computeProgress.set(facts.task, entry);
        }
        if (entry !== undefined) {
          entry.polls++;
          entry.work += BigInt(facts.work);
          entry.lastElapsedMs = elapsedMs;
          entry.lastProgress = facts.progress;
        }
      }
      // Record existing boundary observations, not credentials or retained
      // payloads. This diagnoses persistence delay without relaxing deadlines.
      if (event !== 'local_compute_advanced' && persistenceTrace.length < 256) persistenceTrace.push({event,
        elapsedMs: Math.round(performance.now() - startedAt), role: facts?.role,
        slot: facts?.slot, complete: facts?.complete});
    },
    fault: phase === 'approve' ? config.fault : undefined});
  const {client} = host;
  let run, state;
  if (phase === 'capture') {
    const format = config.sourceFormat ?? 'program';
    assert.ok(['program', 'sql', 'aql-text'].includes(format));
    assert.ok(format === 'program' || !config.modelCommand);
    const program = format !== 'program' ? (config.generatedCommand
      ? generatedContentCommandSource({format: format === 'aql-text' ? 'text' : format})
      : contentCommandSource({format}))
      : config.modelCommand ? generatedContentModelCommandProgram()
      : config.generatedCommand ? generatedContentCommandProgram({
        preserveOrder: config.preserveOrder === true,
        retainSerializationMetadata: config.retainSerializationMetadata === true,
        exposeAttachmentResult: config.exposeAttachmentResult === true}) : host.fixture.program;
    const check = await client.check(program, format === 'program'
      ? {kind: 'program', scope: 'bound_input'}
      : {kind: 'text', format, scope: 'bound_input'});
    assert.equal(check.report.verdict, 'verified');
    assert.equal(host.reads(), 0);
    assert.equal(host.sends(), 0);
    run = await (format === 'program' ? client.start(program)
      : client.startSource(program, {format}));
    state = await run.wait({signal: AbortSignal.timeout(15000)});
    assert.equal(state.status, 'waiting_checkpoint', inspect({state, events: host.events}, {depth: 12}));
    assert.equal(host.reads(), 1);
    assert.equal(host.sends(), 0);
    const checkpoints = (await client.checkpoints()).items;
    assert.equal(checkpoints.length, 1);
    assert.equal(checkpoints[0].kind, config.modelApprovalRequired ? 'model_invocation' : 'effect_set');
    await durableFixture('original-run.json', {ref: run.ref, checkpointCid: checkpoints[0].checkpointCid});
    await assert.rejects(readFile(host.targetPath), {code: 'ENOENT'});
  } else {
    const original = JSON.parse(await readFile(join(config.root, 'original-run.json'), 'utf8'));
    run = await client.attach(original.ref);
    state = await run.status();
    if (phase === 'approve' || phase === 'approve-model') {
      assert.equal(state.status, 'waiting_checkpoint', inspect({state, events: host.events}, {depth: 12}));
      const checkpoint = (await client.checkpoints()).items.find(item =>
        item.kind === (phase === 'approve-model' ? 'model_invocation' : 'effect_set'));
      assert.ok(checkpoint);
      const approvedCid = phase === 'approve' && config.modelApprovalRequired
        ? JSON.parse(await readFile(join(config.root, 'command-checkpoint.json'), 'utf8')).checkpointCid
        : original.checkpointCid;
      assert.equal(checkpoint.checkpointCid, approvedCid);
      const answer = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {
        signer: {keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: original.ref.authorityScopeCid,
          sign: bytes => sign(null, bytes, keys.privateKey)}});
      assert.equal(answer.results[0].status, 'committed');
      observationProgress.approvalCommittedElapsedMs = Math.round(performance.now() - startedAt);
    }
    const signal = AbortSignal.timeout(15000);
    observationProgress.startedElapsedMs = Math.round(performance.now() - startedAt);
    do {
      state = await run.status({signal});
      observationProgress.polls++;
      observationProgress.lastElapsedMs = Math.round(performance.now() - startedAt);
      lastStatus = state.status;
      if (phase === 'approve-model' && state.status === 'waiting_checkpoint') {
        const items = (await client.checkpoints()).items;
        lastCheckpointKinds = items.map(item => item.kind);
        const command = items.find(item => item.kind === 'effect_set');
        if (command !== undefined) {
          assert.notEqual(command.checkpointCid, original.checkpointCid);
          await durableFixture('command-checkpoint.json', {checkpointCid: command.checkpointCid});
          break;
        }
      }
      if (!['resuming', 'running', 'waiting_checkpoint'].includes(state.status)) break;
      await delay(20, undefined, {signal});
    } while (true);
    if (phase === 'read' && config.fault !== undefined) {
      state = await run.reconcile({signal});
    }
    if (phase === 'approve-model') {
      assert.equal(state.status, 'waiting_checkpoint',
        inspect({state, events: host.events, modelCalls, generations}, {depth: 16}));
      assert.equal(host.reads(), 0, 'Model approval cannot acquire the original Source again');
      assert.equal(generations, 0, 'Model approval cannot regenerate Content');
      assert.equal(modelCalls, 1);
      assert.equal(host.sends(), 0, 'Model approval is not COMMAND approval');
      await assert.rejects(readFile(host.targetPath), {code: 'ENOENT'});
    } else {
      const completed = config.fault === undefined ||
        (config.fault === 'stop_projection' && phase === 'read');
      assert.equal(state.status, completed ? 'succeeded' : 'needs_reconciliation',
        inspect({state, events: host.events}, {depth: 16}));
      assert.equal(host.reads(), 0, 'restoration cannot call the original Source');
      assert.equal(host.sends(), phase === 'approve' ? 1 : 0,
        'a later process must not replay the original send');
      assert.deepEqual(await readFile(host.targetPath),
        Buffer.from(config.generatedCommand ? 'name\n"approved.csv"\n' : 'id\n'));
    }
  }
  const rows = state.status === 'succeeded' ? await run.result('r').all() : undefined;
  const attachmentRows = state.status === 'succeeded' && config.exposeAttachmentResult
    ? await run.result('attachment').all() : undefined;
  process.stdout.write(JSON.stringify({pid: process.pid, phase, ref: run.ref,
    status: state.status, reads: host.reads(), sends: host.sends(), rows, attachmentRows,
    modelCalls, generations, persistenceTrace, computeTrace: computeTrace(), observationProgress,
    writeGrants: host.writeGrants(), projections: host.projections,
    next_action: state.next_action, result_available: state.result_available}) + '\n');
} catch (error) {
  primaryFailure = error;
  process.stderr.write(inspect({phase, error, events: host?.events, modelCalls, generations,
    lastStatus, lastCheckpointKinds, persistenceTrace, computeTrace: computeTrace(), observationProgress},
    {depth: 16}) + '\n');
  throw error;
} finally {
  // Cleanup failure is also evidence, but must not hide the failed boundary
  // that caused it. A pending owner and its on-disk originals remain intact.
  let cleanupFailure;
  try { await host?.close(); } catch (error) { cleanupFailure = error; }
  for (const close of closers.reverse()) {
    try { await close(); } catch (error) { cleanupFailure ??= error; }
  }
  if (cleanupFailure !== undefined) {
    if (primaryFailure === undefined) throw cleanupFailure;
    process.stderr.write(inspect({cleanupFailure}, {depth: 8}) + '\n');
  }
}
