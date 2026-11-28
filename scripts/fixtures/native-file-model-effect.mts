import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';
import {requireNativeMockWork} from '../native-cli-mock-scenario.mjs';

const hash = (bytes: string) => createHash('sha256').update(bytes).digest('hex');
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const wire = (value: unknown) => JSON.stringify(value, null, 2) + '\n';
const document = 'file-model-delete.aql';

type FixtureCatalog = {connections: {
  drive: unknown;
  salesforce: {writes: {
    resource: string; writable_fields?: string[]; operation?: string; permission: string;
  }[]};
}};

const textField = {type: 'string', nullable: false};
const filesView = {
  resource: 'files', resource_kind: 'record', data_classification: 'internal',
  schema: {id: textField, notes: textField, active_users: {type: 'int64', nullable: false}, trend: textField},
  facts: {relation_keys: {candidate_keys: [['id']]}},
};

export function nativeFileModelEffect(task: string) {
  assert.match(task, /^model-task:[a-z][a-z0-9.-]+$/u);
  const original = projectTemplateFiles('deal-review-mock');
  const catalog = JSON.parse(original['mock/catalog.json']) as FixtureCatalog;
  const [writer] = catalog.connections.salesforce.writes;
  const {writable_fields: writable, ...retained} = writer;
  assert.deepEqual(writable, ['StageName', 'NextStep']);
  assert.equal(writer.resource, 'Opportunity');
  catalog.connections.salesforce.writes = [{
    ...retained, operation: 'delete', permission: 'salesforce:record:delete',
  }];
  // The ordinary declared Relation selects its bounded physical row from the
  // same adopted File. No authored value is inserted into the Model prefix.
  catalog.connections.drive = {
    views: [filesView],
    query_aliases: [{name: 'drive.files', resource: 'files'}],
    data: [{resource: 'files', items_path: ['drive', 'files', 'rows'],
      key_path: ['drive', 'files', 'key'], primary_identity: 'id'}],
  };
  const project = JSON.parse(original['actql.config.json']) as {
    state_dir: string; mock: {answers: Record<string, string>};
  };
  project.state_dir = './host';
  project.mock.answers = {};
  const input = {
    notes: 'Acme Corp - Renewal',
    active_users: '17',
    trend: 'declining',
  };
  const data = JSON.parse(original['mock/data.json']) as {
    drive: {files: {key: string[]; rows: unknown[]}};
  };
  data.drive.files = {key: ['id'], rows: [{id: '006Acme', ...input}]};
  const before = wire(data);
  const removed = `{
          "id": "006Acme",
          "name": "Acme Corp - Renewal",
          "StageName": "Proposal",
          "NextStep": null
        },`;
  assert.equal(before.split(removed).length, 2);
  const after = before.replace(removed, '');
  const reply = {level: 'high', reason: 'controlled File decision'};
  return {
    files: {
      'actql.config.json': wire(project),
      'connectors.json': original['connectors.json'],
      'mock/catalog.json': wire(catalog),
      'mock/data.json': before,
      'model-tasks.json': wire({version: 'actql-model-tasks/0.1', tasks: {}, providers: {}}),
      [document]: `SELECT f.id, f.notes, f.active_users, f.trend
FROM drive.files AS f
|> ASSERT UNIQUE BY (id)
|> INFER \`${task}\` INPUT (notes, active_users, trend) AS advice
|> WHERE advice.outcome = 'ok' AND advice.value.level = 'high'
|> SELECT id, advice.outcome AS outcome, advice.value AS value
|> RESULT updates
|> EFFECT DELETE salesforce.Opportunity ID id;
`,
    },
    document, before, after, input, reply,
    resultName: 'updates',
    rows: [{id: '006Acme', outcome: 'ok', value: reply}],
  };
}

type Snapshot = {bytes: string; sha256: string; device: string; inode: string;
  size: string; mtimeNs: string; ctimeNs: string};
type Phase = Parameters<typeof requireNativeMockWork>[1][number] & {
  phase: string; pid: number; firstClose: boolean; physicalRequests: number;
  connections: {tcp: number; tls: number};
};
type RunState = {status: string; run_id: string};
type CheckpointState = RunState & {checkpoint: {checkpoint_id: string; checkpoint_cid: string}};
type Trace = {
  fixture: ReturnType<typeof nativeFileModelEffect>; phases: readonly Phase[];
  input: unknown; waiting: CheckpointState; preview: CheckpointState;
  completed: RunState; savedRows: unknown;
  before: Snapshot; pending: Snapshot; applied: Snapshot; afterSaved: Snapshot;
};

// Phase inputs are the existing CLI observer's subprocess/peer records.
// Saved availability and target bytes remain separate observations.
export function requireNativeFileModelEffectTrace({
  fixture, phases, input, waiting, preview, completed, savedRows, before, pending, applied, afterSaved,
}: Trace) {
  const names = ['adopt', 'check', 'run', 'waiting-status', 'approve', 'saved-status', 'saved-result'];
  assert.deepEqual(phases.map(({phase}) => phase), names);
  assert.equal(new Set(phases.map(({pid}) => pid)).size, names.length);
  for (const [index, phase] of phases.entries()) {
    assert(Number.isSafeInteger(phase.pid) && phase.pid > 0);
    assert.equal(phase.firstClose, true);
    const requests = index < 2 ? 0 : 1;
    assert.equal(phase.physicalRequests, requests);
    assert.deepEqual(phase.connections, {tcp: requests, tls: requests});
    if (phase.phase !== 'run' && phase.phase !== 'approve') assert.deepEqual(phase.events, []);
  }
  const {modelAttempts: [attempt]} = requireNativeMockWork(['run'], [phases[2]], 1);
  assert.match(attempt, cidPattern);
  const {writes: [write]} = requireNativeMockWork(['approve'], [phases[4]], 1);
  assert.deepEqual(input, fixture.input);
  assert.equal(waiting.status, 'waiting_checkpoint');
  assert.match(waiting.run_id, cidPattern);
  assert.equal(typeof waiting.checkpoint.checkpoint_id, 'string');
  assert(waiting.checkpoint.checkpoint_id.length > 0);
  assert.match(waiting.checkpoint.checkpoint_cid, cidPattern);
  assert.equal(preview.run_id, waiting.run_id);
  assert.equal(preview.status, 'waiting_checkpoint');
  assert.equal(preview.checkpoint.checkpoint_id, waiting.checkpoint.checkpoint_id);
  assert.equal(preview.checkpoint.checkpoint_cid, waiting.checkpoint.checkpoint_cid);
  assert.equal(completed.status, 'succeeded');
  assert.equal(completed.run_id, waiting.run_id);
  assert.deepEqual(savedRows, fixture.rows);
  assert.equal(before.bytes, fixture.before);
  assert.equal(before.sha256, hash(before.bytes));
  assert.deepEqual(pending, before, 'Preview must not change the original target file');
  assert.equal(applied.bytes, fixture.after, 'Approval must remove only the selected original row');
  assert.equal(applied.sha256, hash(applied.bytes));
  assert.deepEqual(afterSaved, applied, 'Saved must preserve the approved target file');
  return {runId: waiting.run_id, checkpointId: waiting.checkpoint.checkpoint_id,
    checkpointCid: waiting.checkpoint.checkpoint_cid, attempt, write, beforeSha256: before.sha256,
    afterSha256: applied.sha256};
}
