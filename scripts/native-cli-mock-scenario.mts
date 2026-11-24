import {nativeMockAcceptanceObservations, projectInitialAdoptionArguments} from '../packages/native-cli/lib/project-scaffold.mjs';
import {mixedDeleteUpdateMockProject, threeWriteMockProject} from '../adapters/host-node/fixtures/mock-multiple-targets.fixture.mjs';
// Public README/Quickstart commands only. The installed runner supplies a new
// exited process for every invocation. Unit doubles validate these assertions,
// not Native execution, signatures, custody or an installed package.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fstatSync} from 'node:fs';
import {lstat, mkdir, open, readFile, stat, unlink, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';

type CaptureOptions = {cwd: string; env?: NodeJS.ProcessEnv; stderrPath: string;
  timeout?: number; maxBuffer?: number; killSignal?: NodeJS.Signals};
type ChildOutcome = {code: number | null; signal: NodeJS.Signals | null; pid?: number};
type CommandFailure = NodeJS.ErrnoException & {groupStopError?: string};
type LauncherTiming = {units: 'nanoseconds'; preparation: number; child: number; total: number};
type LauncherTimings = 'optional' | 'required';
type MockWorkOptions = {minimumWrites?: number; modelRows?: number; writeOrdinals?: readonly number[]};
type Work = ReturnType<typeof requireNativeMockWork>;
type CommandRecord = {stdout: string; stderr: string; signal: string | null; code: string | number | null;
  launcherTiming?: LauncherTiming; acceptance?: Work};
type ObservedCommand = CommandRecord & {args: readonly string[]; cwd: string; workflowPhase: string};
type ScenarioOptions<Command extends CommandRecord> = {root: string; template: keyof typeof expectedChanges;
  run: (args: readonly string[], cwd: string) => Command | Promise<Command>;
  launcherTimings?: LauncherTimings};
// Parsed fixture and receipt views are interpreted by the existing assertions.
type Checkpoint = {checkpoint_id: string; checkpoint_cid: string};
type RunState = {version: string; status: string; run_id: string; checkpoint: Checkpoint};
type SourceRow = {id: string; [field: string]: unknown};
type TargetData = {salesforce: Record<string, {rows: SourceRow[]}>};
type PreviewRow = {state: string; value: Record<string, unknown>};
type ResultRow = SourceRow & {review: {outcome: string; value: unknown}; risk: {outcome: string; value: unknown}};
type ObservationGroup = Pick<ReturnType<typeof nativeMockAcceptanceObservations>[number], 'events'>;
type EffectWrite = {ordinal: number; key: string; dispatch: string; fileReceipt: string; rowReceipt: string};

export const mockTemplates = Object.freeze(['deal-review-mock', 'churn-risk-mock'] as const);

export const expectedChanges = Object.freeze({
  'deal-review-mock': {
    resource: 'Opportunity', model: 'review' as const, answers: [
      {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'},
      {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'},
    ],
    rows: [
      {id: '006Acme', StageName: 'Negotiation', NextStep: 'Send revised pricing by Friday'},
      {id: '006Globex', StageName: 'Closed Lost', NextStep: 'Revisit next fiscal year'},
    ],
  },
  'churn-risk-mock': {
    resource: 'Account', model: 'risk' as const, answers: [
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
export async function captureNativeMockCommand(command: string, args: readonly string[], {
  cwd, env, stderrPath, timeout = 120_000, maxBuffer = 8 * 1024 * 1024,
  killSignal = 'SIGKILL',
}: CaptureOptions) {
  assert(Number.isSafeInteger(timeout) && timeout > 0);
  assert(Number.isSafeInteger(maxBuffer) && maxBuffer > 0);
  const sink = await open(stderrPath, 'wx+', 0o600);
  try {
    const stdout: Buffer[] = [];
    let stdoutBytes = 0, failure: CommandFailure | undefined, killed = false;
    const outcome = await new Promise<ChildOutcome>(resolve => {
      // Same owned-group pattern as the existing Resident watchdog: only this
      // fresh command and its inherited Native descendants receive a signal.
      const child = spawn(command, args, {cwd, env, detached:true, stdio: ['ignore', 'pipe', sink.fd]});
      let stopping = false;
      const stop = (error: CommandFailure) => {
        failure ??= error;
        if (stopping) return;
        stopping = true;
        if (Number.isInteger(child.pid) && child.pid! > 0) {
          try {process.kill(-child.pid!, killSignal); killed = true;}
          catch (issue) {if ((issue as NodeJS.ErrnoException).code !== 'ESRCH') failure.groupStopError = (issue as NodeJS.ErrnoException).code ?? (issue as Error).message;}
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
        } catch (error) {stop(error as CommandFailure);}
      }, 25);
      const onTerm = () => stop(Object.assign(new Error('Native command observer interrupted'), {code:'ECANCELED'}));
      process.once('SIGTERM', onTerm); process.once('SIGINT', onTerm);
      child.stdout!.on('data', chunk => {
        const remaining = maxBuffer - stdoutBytes;
        if (remaining > 0) stdout.push(chunk.subarray(0, remaining));
        stdoutBytes += chunk.length;
        if (stdoutBytes > maxBuffer) stop(Object.assign(new Error('stdout maxBuffer exceeded'),
          {code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER'}));
      });
      child.stdout!.once('error', stop);
      child.once('error', error => {failure ??= error;});
      child.once('close', (code, signal) => {
        clearTimeout(timer); clearInterval(monitor);
        process.removeListener('SIGTERM', onTerm); process.removeListener('SIGINT', onTerm);
        resolve({code, signal, pid: child.pid});
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
    const result = {pid: outcome.pid, stdout: Buffer.concat(stdout).toString('utf8'),
      stderr: body.subarray(0, offset).toString('utf8')};
    if (failure || outcome.code !== 0 || outcome.signal !== null) {
      throw Object.assign(failure ?? new Error('Native command failed'), result,
        {code: failure?.code ?? outcome.code, exitCode: outcome.code, signal: outcome.signal, killed});
    }
    return result;
  } finally {await sink.close();}
}

async function targetSnapshot(file: string) {
  const bytes = await readFile(file);
  const info = await stat(file, {bigint: true});
  // atime is deliberately excluded: a metadata/Result read may inspect DATA,
  // but must not rewrite it, even with identical bytes or a replacement inode.
  return {sha256: createHash('sha256').update(bytes).digest('hex'),
    bytes: bytes.toString('utf8'), device: String(info.dev), inode: String(info.ino),
    size: String(info.size), mtimeNs: String(info.mtimeNs), ctimeNs: String(info.ctimeNs)};
}

function runState(record: CommandRecord, expectedStatus: string, runId?: string) {
  const value = JSON.parse(record.stdout) as RunState;
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

function checkpointId(state: RunState) {
  assert.equal(typeof state.checkpoint?.checkpoint_id, 'string');
  assert(state.checkpoint.checkpoint_id.length > 0);
  assert.equal(typeof state.checkpoint.checkpoint_cid, 'string');
  assert.match(state.checkpoint.checkpoint_cid, /^sha256:[0-9a-f]{64}$/u);
  return state.checkpoint.checkpoint_id;
}

// One read-only presentation of the SAME saved Checkpoint. The independent
// template rows supply the expected changes, never parsed product output.
function waitingHuman(record: CommandRecord, original: RunState, before: Awaited<ReturnType<typeof targetSnapshot>>,
  change: Readonly<{resource: string; rows: readonly SourceRow[]}>, {completeBefore = false}: {completeBefore?: boolean} = {}) {
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
  const values = <T,>(prefix: string): T[] => lines.filter(line => line.startsWith(prefix))
    .map(line => JSON.parse(line.slice(prefix.length)) as T);
  const identities = values<string>('    Row: '), previous = values<PreviewRow>('      Before: '), next = values<PreviewRow>('      After: ');
  assert.deepEqual([...identities].sort(), change.rows.map(row => row.id).sort(),
    'Human Preview must display the exact original target rows');
  assert.equal(previous.length, change.rows.length, 'Human Preview must retain every before row');
  assert.equal(next.length, change.rows.length, 'Human Preview must retain every after row');
  const originals = (JSON.parse(before.bytes) as TargetData).salesforce[change.resource].rows;
  for (const [index, id] of identities.entries()) {
    const expected = change.rows.find(row => row.id === id)!;
    const source = originals.find(row => row.id === id)!;
    const fields = Object.fromEntries(Object.entries(expected).filter(([name]) => name !== 'id'));
    assert.equal(previous[index].state, 'present', 'Human Preview must retain observed before evidence');
    assert.equal(next[index].state, 'present', 'Human Preview must retain the original intended change');
    if (completeBefore) assert.deepEqual(previous[index].value, source);
    for (const field of Object.keys(fields)) assert.deepEqual(previous[index].value[field], source[field],
      `Human Preview must retain original before ${field}`);
    assert.deepEqual(next[index].value, fields, 'Human Preview must retain the exact intended after fields');
  }
  return {runId: original.run_id, checkpointId: original.checkpoint.checkpoint_id,
    checkpointCid: original.checkpoint.checkpoint_cid, rows: identities.length};
}


export function requireNativeMockWork(args: readonly string[], groups: readonly ObservationGroup[], rows: number, {
  minimumWrites = rows, modelRows = rows, writeOrdinals,
}: MockWorkOptions = {}) {
  assert(Number.isSafeInteger(minimumWrites) && minimumWrites >= 0 && minimumWrites <= rows);
  assert(Number.isSafeInteger(modelRows) && modelRows >= 0);
  if (writeOrdinals !== undefined) assert(Array.isArray(writeOrdinals) &&
    minimumWrites === rows && writeOrdinals.length === rows &&
    writeOrdinals.every(value => Number.isSafeInteger(value) && value >= 0 && value < rows),
  'A multi-member observation requires every expected member-local row ordinal');
  const model: string[] = [], modelSlots: number[] = [], writes: EffectWrite[] = [];
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
  assert.equal(model.length, args[0] === 'run' ? modelRows : 0, 'Actual Model start count differs');
  assert.equal(new Set(model).size, model.length, 'Repeated original Model attempt');
  assert.deepEqual([...modelSlots].sort((a,b)=>a-b), args[0] === 'run'
    ? Array.from({length:modelRows},(_,index)=>index) : [], 'Changed original Model slots');
  if (args[0] === 'approve') {
    assert(writes.length >= minimumWrites && writes.length <= rows, 'Actual target replacement count differs');
    assert(writes.every(row => Number.isSafeInteger(row.ordinal) && row.ordinal >= 0 && row.ordinal < rows));
    if (writeOrdinals === undefined) {
      assert.equal(new Set(writes.map(row => row.ordinal)).size, writes.length, 'Repeated original Effect ordinal');
      if (minimumWrites === rows)
        assert.deepEqual(writes.map(row=>row.ordinal).sort((a,b)=>a-b), Array.from({length:rows},(_,index)=>index), 'Changed original Effect ordinals');
    } else {
      assert.deepEqual(writes.map(row => row.ordinal), writeOrdinals, 'Changed original Effect member row ordinals');
      assert.equal(new Set(writes.map(row => row.dispatch)).size, writes.length, 'Repeated original Effect dispatch');
    }
  } else assert.equal(writes.length, 0, 'Unexpected target replacement');
  for (const field of ['key', 'fileReceipt', 'rowReceipt'] as const) assert.equal(new Set(writes.map(row => row[field])).size, writes.length, 'Repeated Effect operation/receipt');
  return {modelAttempts: model, writes};
}

// The Node launcher's PID-less timing envelope is outside the Native stream.
// Remove only its one canonical final line; never filter Native diagnostics.
export function nativeLauncherEnvelope(stderr: string, mode: LauncherTimings) {
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
  let timing: LauncherTiming;
  try { timing = JSON.parse(body); } catch { assert.fail('Malformed Node launcher timing trailer'); }
  assert(timing && !Array.isArray(timing) && typeof timing === 'object' &&
    Object.keys(timing).join(',') === 'units,preparation,child,total' && JSON.stringify(timing) === body,
    'Noncanonical Node launcher timing trailer fields');
  assert(timing.units === 'nanoseconds', 'Invalid Node launcher timing units');
  assert((['preparation','child','total'] as const).every(key => Number.isSafeInteger(timing[key]) && timing[key] >= 0 && !Object.is(timing[key], -0)),
    'Invalid Node launcher timing quantity');
  assert(timing.preparation <= Number.MAX_SAFE_INTEGER - timing.child && timing.preparation + timing.child === timing.total,
    'Inconsistent Node launcher timing total');
  return {native: stderr.slice(0, start), timing};
}

function nativeMockScenarioCommands<Command extends CommandRecord>({project, run, launcherTimings, rows, work}:
  Readonly<{project: string; run: ScenarioOptions<Command>['run']; launcherTimings: LauncherTimings; rows: number; work?: MockWorkOptions}>) {
  assert(['optional','required'].includes(launcherTimings), 'Invalid launcher observation contract');
  assert.equal(typeof run, 'function');
  const commands: (ObservedCommand & Command)[] = [];
  async function invoke(workflowPhase: string, args: readonly string[], cwd = project) {
    const record = await run(args, cwd);
    commands.push({args, cwd, ...record, workflowPhase});
    assert.equal(record.signal, null, `${args[0]} terminated by signal`);
    assert.equal(record.code, 0, `${args.join(' ')} failed: ${record.stderr}`);
    const envelope = nativeLauncherEnvelope(record.stderr, launcherTimings);
    const observations = nativeMockAcceptanceObservations(envelope.native);
    if (envelope.timing) { record.launcherTiming = envelope.timing; commands.at(-1)!.launcherTiming = envelope.timing; }
    assert.equal(observations.length, args[0] === 'init' ? 2 : 1, 'Native child observations missing or duplicated');
    record.acceptance = requireNativeMockWork(args, observations, rows, work);
    commands.at(-1)!.acceptance = record.acceptance;
    return record;
  }
  return {commands, invoke};
}

export async function runNativeCliMockScenario<Command extends CommandRecord>(
  {root, template, run, launcherTimings = 'optional'}: ScenarioOptions<Command>,
) {
  assert(mockTemplates.includes(template), 'Unknown Native mock acceptance template');
  const project = join(root, template), file = join(project, 'mock/data.json');
  const {commands, invoke} = nativeMockScenarioCommands({project, run, launcherTimings,
    rows: expectedChanges[template].rows.length});
  await invoke('scaffold', ['init', '--template', template, project], root);
  const before = await targetSnapshot(file);
  const original = runState(await invoke('prepare', ['run', `${template.slice(0, -5)}.aql`,
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
  const pending = runState(await invoke('waiting-status', ['status', runId, '--json']), 'waiting_checkpoint', runId);
  assert.equal(checkpointId(pending), checkpoint);
  assert.equal(pending.checkpoint.checkpoint_cid, original.checkpoint.checkpoint_cid);
  assert.deepEqual(await targetSnapshot(file), before, 'Pending status must not write');
  // The AQL and Model answers are already gone. HUMAN status must consume the
  // same saved review, not prepare another Run or repeat Source/Model work.
  const humanWaiting = waitingHuman(await invoke('waiting-review', ['status', runId]), original, before, expectedChanges[template]);
  assert.deepEqual(await targetSnapshot(file), before, 'Human waiting status must not write');

  await invoke('approval', ['approve', checkpoint, '--wait', '--json']);
  const after = await targetSnapshot(file);
  const actual = JSON.parse(after.bytes), expected = JSON.parse(before.bytes) as TargetData;
  const change = expectedChanges[template];
  for (const update of change.rows) {
    const row = expected.salesforce[change.resource].rows.find(value => value.id === update.id);
    assert(row, 'Independent fixture target must exist');
    Object.assign(row, update);
  }
  assert.deepEqual(actual, expected, 'Only the independently expected target fields may change');
  assert.notEqual(after.sha256, before.sha256, 'Approval must perform the mock write');
  runState(await invoke('completed-status', ['status', runId, '--json']), 'succeeded', runId);
  assert.deepEqual(await targetSnapshot(file), after, 'Completed status must not rewrite the target');

  const resultArguments = ['result', runId, '--result', 'updates', '--format', 'jsonl'];
  const first = await invoke('result', resultArguments);
  const rows = first.stdout.trim().split('\n').map(line => JSON.parse(line) as ResultRow);
  assert.equal(rows.length, 2, 'Both independently expected updates must be retained');
  assert.deepEqual(rows.map(value => value.id).sort(), change.rows.map(value => value.id).sort());
  const originalRows = (JSON.parse(before.bytes) as TargetData).salesforce[change.resource].rows;
  for (const [index, update] of change.rows.entries()) {
    const row = rows.find(value => value.id === update.id)!;
    assert.equal(row[change.model]?.outcome, 'ok', 'The retained mock Model outcome must be present');
    assert.deepEqual(row[change.model].value, change.answers[index]);
    if (template === 'deal-review-mock') {
      const originalRow = originalRows.find(value => value.id === update.id)!;
      assert.equal(row.StageName, originalRow.StageName, 'Result must retain the pre-write Source');
      assert.equal(row.NextStep, originalRow.NextStep, 'Result must retain the pre-write Source');
    }
  }
  assert.deepEqual(await targetSnapshot(file), after, 'Reading Result must not replay the Effect');
  runState(await invoke('saved-status', ['status', runId, '--json']), 'succeeded', runId);
  const reread = await invoke('saved-result', resultArguments);
  assert.equal(reread.stdout, first.stdout, 'Fresh-process Result must retain original bytes');
  assert.deepEqual(await targetSnapshot(file), after, 'Saved Run/Result reread must not rewrite the target');
  return {template, runId, checkpointId: checkpoint, checkpointCid: original.checkpoint.checkpoint_cid,
    beforeSha256: before.sha256, afterSha256: after.sha256, humanWaiting, resultRows: rows.length,
    resultSha256: createHash('sha256').update(first.stdout).digest('hex'), commands};
}

export function runNativeSharedFileMockScenario<Command extends CommandRecord>(
  {root, run, launcherTimings = 'optional'}: Omit<ScenarioOptions<Command>, 'template'>,
) {
  const fixture = threeWriteMockProject();
  const changes: readonly SharedMockChange[] = fixture.changes.map(change => ({...change, kind: 'update'}));
  return runNativeSharedFileMutation({project: join(root, 'native-shared-file-mock'),
    fixture, changes, decision: 'approve', run, launcherTimings});
}

type SharedMockChange = Readonly<{kind: 'update' | 'delete'; resource: string; id: string; after?: string}>;
type SharedMockFixture = Readonly<{files: Readonly<Record<string, string>>;
  before: string; after: string; programFile: string; rows: readonly unknown[]}>;
type SharedMockScenario<Command extends CommandRecord> = Omit<ScenarioOptions<Command>, 'template'>;
export async function runNativeMixedFileMockScenarios<Command extends CommandRecord>(
  {root, run, launcherTimings = 'optional'}: SharedMockScenario<Command>) {
  const fixture = mixedDeleteUpdateMockProject();
  const changes: readonly SharedMockChange[] = [
    {kind: 'delete', resource: 'Account', id: 'a1'},
    {kind: 'update', resource: 'Contact', id: 'c1', after: 'C-new'},
  ];
  const results = [];
  for (const decision of ['approve', 'reject'] as const) {
    const result = await runNativeSharedFileMutation({project: join(root, 'native-mixed-file-' + decision),
      fixture, changes, decision, run, launcherTimings});
    results.push({decision, ...result});
  }
  return results;
}

async function runNativeSharedFileMutation<Command extends CommandRecord>(
  {project, fixture, changes, decision, run, launcherTimings}: Omit<SharedMockScenario<Command>, 'root' | 'launcherTimings'> & {
    launcherTimings: LauncherTimings;
    project: string; fixture: SharedMockFixture; changes: readonly SharedMockChange[]; decision: 'approve' | 'reject';
  }) {
  const file = join(project, 'mock/data.json');
  const configuration = join(project, 'actql.config.json'), stateDirectory = join(project, '.actql');
  const {commands, invoke} = nativeMockScenarioCommands({project, run, launcherTimings,
    rows: changes.length, work: {modelRows: 0, writeOrdinals: changes.map(() => 0)}});
  await mkdir(project, {mode: 0o700});
  for (const [name, body] of Object.entries(fixture.files)) {
    const path = join(project, name);
    await mkdir(dirname(path), {recursive: true, mode: 0o700});
    await writeFile(path, body, {flag: 'wx', mode: 0o600});
  }
  const before = await targetSnapshot(file);
  assert.equal(before.bytes, fixture.before);
  await invoke('adoption', projectInitialAdoptionArguments({configuration, stateDirectory}));
  const original = runState(await invoke('prepare', ['run', fixture.programFile,
    '--format', 'aql-json', '--stop-before', 'commit', '--json']), 'waiting_checkpoint');
  const runId = original.run_id, checkpoint = checkpointId(original);
  await unlink(join(project, fixture.programFile));
  assert.deepEqual(await targetSnapshot(file), before, 'Preparation must retain all original target bytes');
  const pending = runState(await invoke('waiting-status', ['status', runId, '--json']), 'waiting_checkpoint', runId);
  assert.equal(checkpointId(pending), checkpoint);
  assert.equal(pending.checkpoint.checkpoint_cid, original.checkpoint.checkpoint_cid);
  const review = await invoke('waiting-review', ['status', runId]);
  const reviewLines = review.stdout.trimEnd().split('\n');
  const header = 'Stored Effect Preview (read-only; not approval):';
  const previewIndex = reviewLines.indexOf(header);
  assert(previewIndex >= 0, 'Original waiting Preview missing');
  for (const line of [`Run: ${JSON.stringify(runId)}`, `Checkpoint: ${JSON.stringify(checkpoint)}`,
    `  Original CID: ${JSON.stringify(original.checkpoint.checkpoint_cid)}`]) {
    assert(reviewLines.slice(0, previewIndex).includes(line), 'Waiting Review changed original identity');
  }
  const originalDocument = JSON.parse(fixture.before) as TargetData;
  assert.deepEqual(reviewLines.slice(previewIndex + 1).map(line => {
    const field = /^      (Before|After): (.+)$/u.exec(line);
    return field ? [field[1], JSON.parse(field[2])] : line;
  }), changes.flatMap(({kind, resource, id, after}) => [
    `  Effect: "${kind}"  Target: "connector://salesforce/${resource}"`,
    '  Items: 1', '  Preview strength: "full_diff"', '  Changes:',
    `    Row: ${JSON.stringify(id)}`,
    ['Before', {state: 'present', value: originalDocument.salesforce[resource].rows.find(row => row.id === id)}],
    ['After', kind === 'delete' ? {state: 'absent'} : {state: 'present', value: {value: after}}],
  ]), 'Original Review must preserve ordered targets and every intended change');
  assert.deepEqual(await targetSnapshot(file), before, 'Pending status must not write');

  await invoke(decision === 'approve' ? 'approval' : 'rejection',
    [decision, checkpoint, ...(decision === 'approve' ? ['--wait'] : []), '--json']);
  await assert.rejects(lstat(file + '.actql-write.lock'), {code: 'ENOENT'},
    'The original target lock path must be absent when the decision command returns');
  const after = await targetSnapshot(file);
  const common = {runId, checkpointId: checkpoint, checkpointCid: original.checkpoint.checkpoint_cid,
    beforeSha256: before.sha256, afterSha256: after.sha256, lockPathAbsent: true};
  if (decision === 'reject') {
    assert.deepEqual(after, before, 'Rejection must not replace the original file');
    runState(await invoke('saved-status', ['status', runId, '--json']), 'cancelled', runId);
    assert.deepEqual(await targetSnapshot(file), before, 'Saved rejection must not write');
    return {...common, commands};
  }
  if (changes.some(change => change.kind === 'delete')) {
    assert.equal(after.bytes, fixture.after, 'The ordered DELETE and UPDATE must preserve every untouched byte');
  } else {
    assert.deepEqual(JSON.parse(after.bytes), JSON.parse(fixture.after),
      'Only the independently expected updates may change');
  }
  assert.notEqual(after.sha256, before.sha256);
  runState(await invoke('completed-status', ['status', runId, '--json']), 'succeeded', runId);
  assert.deepEqual(await targetSnapshot(file), after, 'Completed status must not rewrite the target');

  const resultArguments = ['result', runId, '--result', 'updates', '--format', 'jsonl'];
  const first = await invoke('result', resultArguments);
  const rows = first.stdout.trimEnd().split('\n').map(line => JSON.parse(line));
  assert.deepEqual(rows, fixture.rows, 'Result must retain every independently expected field');
  assert.deepEqual(await targetSnapshot(file), after, 'Result must not replay any update');
  runState(await invoke('saved-status', ['status', runId, '--json']), 'succeeded', runId);
  const saved = await invoke('saved-result', resultArguments);
  assert.equal(saved.stdout, first.stdout, 'Fresh-process Saved Result must retain the original bytes');
  assert.deepEqual(await targetSnapshot(file), after, 'Saved lookup must not replay any update');
  return {...common, resultRows: rows.length,
    resultSha256: createHash('sha256').update(first.stdout).digest('hex'), commands};
}

export async function runNativeNullableMockScenarios<Command extends CommandRecord>({root, run, launcherTimings}:
  Omit<ScenarioOptions<Command>, 'template' | 'launcherTimings'> & {launcherTimings: LauncherTimings}) {
  const {definition, files, before: expectedBefore, after: expectedAfter} =
    await import('../adapters/host-node/fixtures/mock-nullable-update.fixture.mjs');
  const results = [];
  for (const decision of ['approve', 'reject'] as const) {
    const project = join(root, 'native-nullable-' + decision), file = join(project, 'mock/data.json');
    const {commands, invoke} = nativeMockScenarioCommands({project, run, launcherTimings, rows: 1, work: {modelRows: 0}});
    await mkdir(project, {mode: 0o700});
    const parameters = Object.fromEntries((['effect', 'read'] as const).flatMap(kind => [
      [kind + '-declarations.json', JSON.stringify(definition[kind].parameterDeclarations)],
      [kind + '-parameters.json', JSON.stringify(definition[kind].parameters)],
    ]));
    for (const [name, contents] of Object.entries({...files, ...parameters})) {
      const path = join(project, name);
      await mkdir(dirname(path), {recursive: true, mode: 0o700});
      await writeFile(path, contents, {flag: 'wx', mode: 0o600});
    }
    const before = await targetSnapshot(file);
    assert.equal(before.bytes, expectedBefore);
    await invoke('adoption', projectInitialAdoptionArguments({configuration: join(project, 'actql.config.json'),
      stateDirectory: join(project, '.actql')}));
    const runInput = (kind: 'effect' | 'read', filename: string, ...options: string[]) => ['run', filename, '--parameter-declarations-file',
      kind + '-declarations.json', '--params', kind + '-parameters.json', ...options, '--json'];
    const resultInput = (id: string, name: string) => ['result', id, '--result', name, '--format', 'jsonl'];
    const requireRows = (record: CommandRecord, expected: readonly SourceRow[]) =>
      assert.deepEqual(record.stdout.trimEnd().split('\n').map(line => JSON.parse(line)), expected);
    async function readAll(phase: string, rows: readonly SourceRow[]) {
      const scoped = runState(await invoke(phase + '-read', runInput('read', 'nullable-read.aql')), 'succeeded');
      requireRows(await invoke(phase + '-read-result', resultInput(scoped.run_id, definition.read.resultName)), rows);
    }
    const original = runState(await invoke('prepare',
      runInput('effect', 'nullable-update.aql', '--stop-before', 'commit')), 'waiting_checkpoint');
    const runId = original.run_id, checkpoint = checkpointId(original);
    await unlink(join(project, 'nullable-update.aql'));
    const humanWaiting = waitingHuman(await invoke('waiting-review', ['status', runId]), original, before,
      {resource: 'Account', rows: [{id: definition.review.identity, ...definition.review.changes}]},
      {completeBefore: true});
    await readAll('before', definition.read.beforeRows);
    assert.deepEqual(await targetSnapshot(file), before, 'Preview and Read must leave all original bytes unchanged');

    await invoke('decision', [decision, checkpoint, ...(decision === 'approve' ? ['--wait'] : []), '--json']);
    await assert.rejects(lstat(file + '.actql-write.lock'), {code: 'ENOENT'});
    const after = await targetSnapshot(file);
    if (decision === 'approve') {
      assert.equal(after.bytes, expectedAfter, 'Only the explicit NULL and empty Text fields may change');
      const result = resultInput(runId, definition.effect.resultName);
      const first = await invoke('result', result);
      requireRows(first, definition.effect.expectedRows);
      const saved = await invoke('saved-result', result);
      assert.equal(saved.stdout, first.stdout, 'Separate-process Saved must reuse the original Result');
      await readAll('after', definition.read.afterRows);
    } else assert.deepEqual(after, before, 'Rejection must not replace the original file');
    runState(await invoke('saved-status', ['status', runId, '--json']),
      decision === 'approve' ? 'succeeded' : 'cancelled', runId);
    assert.deepEqual(await targetSnapshot(file), after, 'Saved reads must never replay a write');
    results.push({decision, runId, checkpointId: checkpoint, checkpointCid: original.checkpoint.checkpoint_cid,
      beforeSha256: before.sha256, afterSha256: after.sha256, humanWaiting, lockPathAbsent: true, commands});
  }
  return results;
}
