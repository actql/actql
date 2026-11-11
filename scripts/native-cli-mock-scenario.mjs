import {nativeMockAcceptanceObservations} from '../packages/native-cli/lib/project-scaffold.mjs';
// Public README/Quickstart commands only. The installed runner supplies a new
// exited process for every invocation. Unit doubles validate these assertions,
// not Native execution, signatures, custody or an installed package.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fstatSync} from 'node:fs';
import {open, readFile, stat, unlink} from 'node:fs/promises';
import {join} from 'node:path';

export const mockTemplates = Object.freeze(['deal-review-mock', 'churn-risk-mock']);

const expectedChanges = Object.freeze({
  'deal-review-mock': {
    resource: 'Opportunity', model: 'review', answers: [
      {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'},
      {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'},
    ],
    rows: [
      {id: '006Acme', StageName: 'Negotiation', NextStep: 'Send revised pricing by Friday'},
      {id: '006Globex', StageName: 'Closed Lost', NextStep: 'Revisit next fiscal year'},
    ],
  },
  'churn-risk-mock': {
    resource: 'Account', model: 'risk', answers: [
      {level: 'high', reason: 'falling usage and a competitor evaluation'},
      {level: 'high', reason: 'support tickets about pricing'},
    ],
    rows: [
      {id: '001Acme', Churn_Risk__c: 'high', Risk_Reason__c: 'falling usage and a competitor evaluation'},
      {id: '001Globex', Churn_Risk__c: 'high', Risk_Reason__c: 'support tickets about pricing'},
    ],
  },
});

// The caller's existing scratch owner retains this exclusive diagnostic file.
// Native deliberately drops observations on pipe backpressure. A regular sink
// preserves its unchanged best-effort writer while the parent registry stays
// asynchronous. Read the original bytes only after the command has closed.
export async function captureNativeMockCommand(command, args, {
  cwd, env, stderrPath, timeout = 120_000, maxBuffer = 8 * 1024 * 1024,
  killSignal = 'SIGKILL',
}) {
  assert(Number.isSafeInteger(timeout) && timeout > 0);
  assert(Number.isSafeInteger(maxBuffer) && maxBuffer > 0);
  const sink = await open(stderrPath, 'wx+', 0o600);
  try {
    const stdout = [];
    let stdoutBytes = 0, failure, killed = false;
    const outcome = await new Promise(resolve => {
      // Same owned-group pattern as the existing Resident watchdog: only this
      // fresh command and its inherited Native descendants receive a signal.
      const child = spawn(command, args, {cwd, env, detached:true, stdio: ['ignore', 'pipe', sink.fd]});
      let stopping = false;
      const stop = error => {
        failure ??= error;
        if (stopping) return;
        stopping = true;
        if (Number.isInteger(child.pid) && child.pid > 0) {
          try {process.kill(-child.pid, killSignal); killed = true;}
          catch (issue) {if (issue.code !== 'ESRCH') failure.groupStopError = issue.code ?? issue.message;}
        }
      };
      const timer = setTimeout(() => stop(Object.assign(new Error('Native command timed out'),
        {code: 'ETIMEDOUT'})), timeout);
      // Keep the original live output ceiling, not just the final read bound.
      // This is the existing owned-process inspection cadence, not a new
      // product timeout, allocation tariff or Native diagnostic wait.
      const monitor = setInterval(() => {
        try {
          if (fstatSync(sink.fd).size > maxBuffer)
            stop(Object.assign(new Error('stderr maxBuffer exceeded'),
              {code:'ERR_CHILD_PROCESS_STDIO_MAXBUFFER'}));
        } catch (error) {stop(error);}
      }, 25);
      const onTerm = () => stop(Object.assign(new Error('Native command observer interrupted'), {code:'ECANCELED'}));
      process.once('SIGTERM', onTerm); process.once('SIGINT', onTerm);
      child.stdout.on('data', chunk => {
        const remaining = maxBuffer - stdoutBytes;
        if (remaining > 0) stdout.push(chunk.subarray(0, remaining));
        stdoutBytes += chunk.length;
        if (stdoutBytes > maxBuffer) stop(Object.assign(new Error('stdout maxBuffer exceeded'),
          {code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER'}));
      });
      child.stdout.once('error', stop);
      child.once('error', error => {failure ??= error;});
      child.once('close', (code, signal) => {
        clearTimeout(timer); clearInterval(monitor);
        process.removeListener('SIGTERM', onTerm); process.removeListener('SIGINT', onTerm);
        resolve({code, signal});
      });
    });
    const size = (await sink.stat()).size;
    const body = Buffer.alloc(Math.min(size, maxBuffer));
    let offset = 0;
    while (offset < body.length) {
      const {bytesRead} = await sink.read(body, offset, body.length - offset, offset);
      if (bytesRead === 0) break;
      offset += bytesRead;
    }
    if (size > maxBuffer) failure ??= Object.assign(new Error('stderr maxBuffer exceeded'),
      {code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER'});
    if (offset !== body.length || (await sink.stat()).size !== size)
      failure ??= Object.assign(new Error('Native diagnostic file changed after child close'),
        {code: 'ERR_NATIVE_MOCK_STDERR'});
    const result = {stdout: Buffer.concat(stdout).toString('utf8'),
      stderr: body.subarray(0, offset).toString('utf8')};
    if (failure || outcome.code !== 0 || outcome.signal !== null) {
      throw Object.assign(failure ?? new Error('Native command failed'), result,
        {code: failure?.code ?? outcome.code, exitCode: outcome.code, signal: outcome.signal, killed});
    }
    return result;
  } finally {await sink.close();}
}

async function targetSnapshot(file) {
  const bytes = await readFile(file);
  const info = await stat(file, {bigint: true});
  // atime is deliberately excluded: a metadata/Result read may inspect DATA,
  // but must not rewrite it, even with identical bytes or a replacement inode.
  return {sha256: createHash('sha256').update(bytes).digest('hex'),
    bytes: bytes.toString('utf8'), device: String(info.dev), inode: String(info.ino),
    size: String(info.size), mtimeNs: String(info.mtimeNs), ctimeNs: String(info.ctimeNs)};
}

function runState(record, expectedStatus, runId) {
  const value = JSON.parse(record.stdout);
  assert.equal(value.version, 'actql-run-state/0.1', 'A command receipt is not a Run state');
  assert.equal(value.status, expectedStatus);
  assert.doesNotMatch(record.stdout,
    /"(?:preview|effect_preview|review_projection|displayed_rows|before|after)"\s*:/u,
    'JSON Run state must not embed restricted Preview contents');
  assert.equal(typeof value.run_id, 'string');
  assert(value.run_id.length > 0, 'The original Run identity must be present');
  if (runId !== undefined) assert.equal(value.run_id, runId, 'Recovery must retain the original Run');
  return value;
}

function checkpointId(state) {
  assert.equal(typeof state.checkpoint?.checkpoint_id, 'string');
  assert(state.checkpoint.checkpoint_id.length > 0);
  assert.equal(typeof state.checkpoint.checkpoint_cid, 'string');
  assert.match(state.checkpoint.checkpoint_cid, /^sha256:[0-9a-f]{64}$/u);
  return state.checkpoint.checkpoint_id;
}

// One read-only presentation of the SAME saved Checkpoint. The independent
// template rows supply the expected changes, never parsed product output.
function waitingHuman(record, original, before, change) {
  const lines = record.stdout.trimEnd().split('\n');
  for (const [prefix, expected] of [
    ['Run: ', `Run: ${JSON.stringify(original.run_id)}`],
    ['State: ', 'State: "waiting_checkpoint"'],
    ['Checkpoint: ', `Checkpoint: ${JSON.stringify(original.checkpoint.checkpoint_id)}`],
    ['  Original CID: ', `  Original CID: ${JSON.stringify(original.checkpoint.checkpoint_cid)}`],
    ['Stored Effect Preview', 'Stored Effect Preview (read-only; not approval):'],
    ['  Effect: ', `  Effect: "update"  Target: ${JSON.stringify('connector://salesforce/' + change.resource)}`],
    ['  Items: ', `  Items: ${change.rows.length}`],
    ['  Preview strength: ', '  Preview strength: "full_diff"'],
    ['  Changes:', '  Changes:'],
  ]) assert.deepEqual(lines.filter(line => line.startsWith(prefix)), [expected],
    `Human waiting Preview must retain original ${prefix}`);
  const values = prefix => lines.filter(line => line.startsWith(prefix))
    .map(line => JSON.parse(line.slice(prefix.length)));
  const identities = values('    Row: '), previous = values('      Before: '), next = values('      After: ');
  assert.deepEqual([...identities].sort(), change.rows.map(row => row.id).sort(),
    'Human Preview must display the exact original target rows');
  assert.equal(previous.length, change.rows.length, 'Human Preview must retain every before row');
  assert.equal(next.length, change.rows.length, 'Human Preview must retain every after row');
  const originals = JSON.parse(before.bytes).salesforce[change.resource].rows;
  for (const [index, id] of identities.entries()) {
    const expected = change.rows.find(row => row.id === id);
    const source = originals.find(row => row.id === id);
    const fields = Object.fromEntries(Object.entries(expected).filter(([name]) => name !== 'id'));
    assert.equal(previous[index].state, 'present', 'Human Preview must retain observed before evidence');
    assert.equal(next[index].state, 'present', 'Human Preview must retain the original intended change');
    for (const field of Object.keys(fields)) assert.deepEqual(previous[index].value[field], source[field],
      `Human Preview must retain original before ${field}`);
    assert.deepEqual(next[index].value, fields, 'Human Preview must retain the exact intended after fields');
  }
  return {runId: original.run_id, checkpointId: original.checkpoint.checkpoint_id,
    checkpointCid: original.checkpoint.checkpoint_cid, rows: identities.length};
}


function requireNativeMockWork(args, groups, rows) {
  const model = [], modelSlots = [], writes = [];
  for (const group of groups) {
    const events = group.events;
    if (args[0] === 'run') {
      for (let index = 0; index < events.length; index += 3) {
        const chain = events.slice(index, index + 3);
        assert.deepEqual(chain.map(event => event.tag), [0, 1, 2], 'Model entry must return without retry/failure');
        assert(chain.every(event => event.ordinal === chain[0].ordinal && event.identity === chain[0].identity), 'Changed original Model attempt');
        model.push(chain[0].identity); modelSlots.push(chain[0].ordinal);
      }
    } else if (args[0] === 'approve') {
      for (let index = 0; index < events.length; index += 7) {
        const chain = events.slice(index, index + 7);
        assert.deepEqual(chain.map(event => event.tag), [5, 6, 7, 8, 9, 10, 11], 'Effect replacement must retain attempt, rename, final ACK and receipts');
        assert.equal(chain[0].identity, chain[3].identity, 'Changed original Effect dispatch key');
        assert(chain.filter(event => event.tag !== 6 && event.tag !== 7).every(event => event.ordinal === chain[0].ordinal), 'Changed original Effect row');
        writes.push({ordinal: chain[0].ordinal, key: chain[0].identity, dispatch: chain[4].identity, fileReceipt: chain[5].identity, rowReceipt: chain[6].identity});
      }
    } else assert.equal(events.length, 0, 'Status/Result/initialization replayed Model or Effect work');
  }
  assert.equal(model.length, args[0] === 'run' ? rows : 0, 'Actual Model start count differs');
  assert.equal(new Set(model).size, model.length, 'Repeated original Model attempt');
  assert.deepEqual([...modelSlots].sort((a,b)=>a-b), args[0] === 'run' ? Array.from({length:rows},(_,index)=>index) : [], 'Changed original Model slots');
  assert.equal(writes.length, args[0] === 'approve' ? rows : 0, 'Actual target replacement count differs');
  assert.deepEqual(writes.map(row=>row.ordinal).sort((a,b)=>a-b), args[0] === 'approve' ? Array.from({length:rows},(_,index)=>index) : [], 'Changed original Effect ordinals');
  for (const field of ['key', 'fileReceipt', 'rowReceipt']) assert.equal(new Set(writes.map(row => row[field])).size, writes.length, 'Repeated Effect operation/receipt');
  return {modelAttempts: model, writes};
}

// The Node launcher's PID-less timing envelope is outside the Native stream.
// Remove only its one canonical final line; never filter Native diagnostics.
export function nativeLauncherEnvelope(stderr, mode) {
  assert.equal(typeof stderr, 'string', 'Launcher diagnostic stream unavailable');
  const prefix = 'ACTQL_NATIVE_LAUNCHER_TIMINGS ';
  const start = stderr.indexOf(prefix);
  if (start < 0) {
    assert(mode === 'optional', 'Required Node launcher timing trailer missing');
    return {native: stderr};
  }
  assert(start > 0 && stderr[start - 1] === '\n' && stderr.indexOf('\n', start) === stderr.length - 1,
    'Node launcher timing trailer must occur exactly once at the end');
  const body = stderr.slice(start + prefix.length, -1);
  assert(body.length <= 256, 'Oversized Node launcher timing trailer');
  let timing;
  try { timing = JSON.parse(body); } catch { assert.fail('Malformed Node launcher timing trailer'); }
  assert(timing && !Array.isArray(timing) && typeof timing === 'object' &&
    Object.keys(timing).join(',') === 'units,preparation,child,total' && JSON.stringify(timing) === body,
    'Noncanonical Node launcher timing trailer fields');
  assert(timing.units === 'nanoseconds', 'Invalid Node launcher timing units');
  assert(['preparation','child','total'].every(key => Number.isSafeInteger(timing[key]) && timing[key] >= 0 && !Object.is(timing[key], -0)),
    'Invalid Node launcher timing quantity');
  assert(timing.preparation <= Number.MAX_SAFE_INTEGER - timing.child && timing.preparation + timing.child === timing.total,
    'Inconsistent Node launcher timing total');
  return {native: stderr.slice(0, start), timing};
}

export async function runNativeCliMockScenario({root, template, run, launcherTimings = 'optional'}) {
  assert(['optional','required'].includes(launcherTimings), 'Invalid launcher observation contract');
  assert(mockTemplates.includes(template), 'Unknown Native mock acceptance template');
  assert.equal(typeof run, 'function');
  const project = join(root, template), file = join(project, 'mock/data.json');
  const commands = [];
  async function invoke(args, cwd = project) {
    const record = await run(args, cwd);
    commands.push({args, cwd, ...record});
    assert.equal(record.signal, null, `${args[0]} terminated by signal`);
    assert.equal(record.code, 0, `${args.join(' ')} failed: ${record.stderr}`);
    const envelope = nativeLauncherEnvelope(record.stderr, launcherTimings);
    const observations = nativeMockAcceptanceObservations(envelope.native);
    if (envelope.timing) { record.launcherTiming = envelope.timing; commands.at(-1).launcherTiming = envelope.timing; }
    assert.equal(observations.length, args[0] === 'init' ? 2 : 1, 'Native child observations missing or duplicated');
    record.acceptance = requireNativeMockWork(args, observations, expectedChanges[template].rows.length);
    commands.at(-1).acceptance = record.acceptance;
    return record;
  }
  await invoke(['init', '--template', template, project], root);
  const before = await targetSnapshot(file);
  const original = runState(await invoke(['run', `${template.slice(0, -5)}.aql`,
    '--stop-before', 'commit', '--json']), 'waiting_checkpoint');
  const runId = original.run_id, checkpoint = checkpointId(original);
  // Resume must consume retained preparation, never recompile the input file.
  await unlink(join(project, `${template.slice(0, -5)}.aql`));
  // The waiting checkpoint already retains its Model outcome. Approval and
  // Result recovery must not need the original answer supplier again.
  await unlink(join(project, 'mock', `${template.slice(0, -5)}.v1.answers.yaml`));
  assert.deepEqual(await targetSnapshot(file), before, 'Run must not write before approval');

  // All commands have exited. The next command must find the same durable
  // Run/Checkpoint, not prepare another program or reconstruct a new preview.
  const pending = runState(await invoke(['status', runId, '--json']), 'waiting_checkpoint', runId);
  assert.equal(checkpointId(pending), checkpoint);
  assert.equal(pending.checkpoint.checkpoint_cid, original.checkpoint.checkpoint_cid);
  assert.deepEqual(await targetSnapshot(file), before, 'Pending status must not write');
  // The AQL and Model answers are already gone. HUMAN status must consume the
  // same saved review, not prepare another Run or repeat Source/Model work.
  const humanWaiting = waitingHuman(await invoke(['status', runId]), original, before, expectedChanges[template]);
  assert.deepEqual(await targetSnapshot(file), before, 'Human waiting status must not write');

  await invoke(['approve', checkpoint, '--wait', '--json']);
  const after = await targetSnapshot(file);
  const actual = JSON.parse(after.bytes), expected = JSON.parse(before.bytes);
  const change = expectedChanges[template];
  for (const update of change.rows) {
    const row = expected.salesforce[change.resource].rows.find(value => value.id === update.id);
    assert(row, 'Independent fixture target must exist');
    Object.assign(row, update);
  }
  assert.deepEqual(actual, expected, 'Only the independently expected target fields may change');
  assert.notEqual(after.sha256, before.sha256, 'Approval must perform the mock write');
  runState(await invoke(['status', runId, '--json']), 'succeeded', runId);
  assert.deepEqual(await targetSnapshot(file), after, 'Completed status must not rewrite the target');

  const resultArguments = ['result', runId, '--result', 'updates', '--format', 'jsonl'];
  const first = await invoke(resultArguments);
  const rows = first.stdout.trim().split('\n').map(line => JSON.parse(line));
  assert.equal(rows.length, 2, 'Both independently expected updates must be retained');
  assert.deepEqual(rows.map(value => value.id).sort(), change.rows.map(value => value.id).sort());
  const originalRows = JSON.parse(before.bytes).salesforce[change.resource].rows;
  for (const [index, update] of change.rows.entries()) {
    const row = rows.find(value => value.id === update.id);
    assert.equal(row[change.model]?.outcome, 'ok', 'The retained mock Model outcome must be present');
    assert.deepEqual(row[change.model].value, change.answers[index]);
    if (template === 'deal-review-mock') {
      const originalRow = originalRows.find(value => value.id === update.id);
      assert.equal(row.StageName, originalRow.StageName, 'Result must retain the pre-write Source');
      assert.equal(row.NextStep, originalRow.NextStep, 'Result must retain the pre-write Source');
    }
  }
  assert.deepEqual(await targetSnapshot(file), after, 'Reading Result must not replay the Effect');
  runState(await invoke(['status', runId, '--json']), 'succeeded', runId);
  const reread = await invoke(resultArguments);
  assert.equal(reread.stdout, first.stdout, 'Fresh-process Result must retain original bytes');
  assert.deepEqual(await targetSnapshot(file), after, 'Saved Run/Result reread must not rewrite the target');
  return {template, runId, checkpointId: checkpoint, checkpointCid: original.checkpoint.checkpoint_cid,
    beforeSha256: before.sha256, afterSha256: after.sha256, humanWaiting, resultRows: rows.length,
    resultSha256: createHash('sha256').update(first.stdout).digest('hex'), commands};
}
