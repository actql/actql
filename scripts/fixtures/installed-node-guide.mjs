// Staged with the two guides and existing Mock fixture in a normal consumer.
import assert from 'node:assert/strict';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {connect} from '@actql/node';
import {getCheckInput, resolveCheckTextRange} from '@actql/sdk';
import {workflowWorkObservation} from '../../adapters/host-node/fixtures/work-observation.fixture.mjs';
import {mockProjectFiles} from './salesforce-approval/mock-project.mjs';
import {salesforceUpdateCase} from './record-approval/cases.mjs';

async function snippet(guide, marker) {
  const document = await readFile(new URL('../../docs/guides/' + guide, import.meta.url), 'utf8');
  const matches = [...document.matchAll(/```ts\n([\s\S]*?)\n```/gu)]
    .map(([, body]) => body).filter(body => body.includes(marker));
  assert.equal(matches.length, 1, marker);
  return stripTypeScriptTypes(matches[0]);
}

const [check, review, start] = await Promise.all([
  snippet('node.md', "outcome.report.verdict === 'verified'"),
  snippet('node.md', 'function reviewEffect('),
  snippet('effects-and-approvals.md', "stopBefore: 'commit'"),
]);
const checkExample = new Function('client', 'console', 'return (async () => {' + check + '})();');
const reviewEffect = new Function(review + '\nreturn reviewEffect;')();
const startEffect = new Function('client', 'source', 'parameterDeclarations', 'parameters',
  'return (async () => {' + start + '\nreturn execution;})();');

const selection = {recordId: '001GuideRecord', previousName: 'Before guide approval', nextName: 'After guide approval'};
const program = await readFile(new URL('./salesforce-approval/update.aql', import.meta.url), 'utf8');
const {effect, review: expected} = salesforceUpdateCase({update: program}, selection);
const cwd = process.cwd();

for (const decision of ['approve', 'reject']) {
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-node-guide-'));
  const files = mockProjectFiles(selection);
  for (const [name, body] of Object.entries(files)) {
    const path = join(root, name);
    await mkdir(dirname(path), {recursive: true});
    await writeFile(path, body);
  }
  const target = join(root, 'mock/data.json');
  const before = await readFile(target, 'utf8');
  const writes = decision === 'approve' ? 1 : 0;
  const observer = workflowWorkObservation({trackOriginal: true});
  process.chdir(root);
  let client, original, location, completed = false;
  try {
    client = await connect({mode: 'local', profile: 'mock',
      installation: {directory: join(root, '.actql'), observation: observer.connection}});
    const localPlan = await client.plan('SELECT 1 AS n', {format: 'sql'});
    assert.equal(localPlan.version, 'actql-plan-view/0.1');
    const source = 'SELECT Id, Name FROM salesforce.accounts';
    const acquiredPlan = await client.plan(source, {format: 'sql'});
    assert.equal(acquiredPlan.version, 'actql-plan-view/0.1');
    assert.match(acquiredPlan.compiled_plan_cid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(observer.snapshot().sourceAcquisitionStarts, 0);
    assert.equal(observer.snapshot().modelCallStarts, 0);
    assert.equal(observer.snapshot().effectReplacementReturns, 0);
    assert.equal(await readFile(target, 'utf8'), before);
    const messages = [];
    await checkExample(client, {log: (...args) => messages.push(args)});
    assert.deepEqual(messages, [['Verified']]);
    const malformed = '\ufeff/*😀*/\r\nSELECT (';
    const outcome = await client.check(malformed, {kind: 'text', format: 'sql', scope: 'template_only'});
    assert.equal(outcome.outcome, 'completed');
    assert.equal(outcome.report.verdict, 'invalid');
    const input = getCheckInput(outcome, 'source');
    assert.equal(input.text, malformed);
    location = {kind: 'text', document_id: 'source', revision: input.revision,
      start_byte: 21, end_byte: 21, precision: 'exact'};
    assert.deepEqual(outcome.report.reasons, [{code: 'query_syntax_invalid', location}]);
    assert.deepEqual(resolveCheckTextRange(outcome, location).range,
      {start: {line: 1, character: 8}, end: {line: 1, character: 8}});

    const run = await startEffect(client, effect.document, effect.parameterDeclarations, effect.parameters);
    original = run.ref;
    async function checkScope(preview) {
      assert.deepEqual(preview.displayed_scope.effects.map(({kind, target, count}) => ({kind, target, count})),
        [{kind: 'update', target: expected.target, count: 1}]);
      assert.equal(preview.displayed_rows.length, 1);
      const [row] = preview.displayed_rows;
      assert.equal(row.target_row_identity, expected.identity);
      assert.equal(row.before.value.Name, expected.before.Name);
      assert.deepEqual(row.after, {state: 'present', value: expected.changes});
      assert.equal(await readFile(target, 'utf8'), before);
      assert.equal(observer.forOriginal(original).effectReplacementReturns, 0);
    }
    const deferred = await reviewEffect(client, run, async preview => {await checkScope(preview); return 'defer';});
    assert.equal(deferred.status, 'waiting_checkpoint');
    assert.deepEqual(await run.status(), deferred);
    const finished = await reviewEffect(client, run, async preview => {await checkScope(preview); return decision;});
    assert.equal(finished.run_id, deferred.run_id);
    assert.deepEqual(run.ref, original);
    assert.equal(finished.status, decision === 'approve' ? 'succeeded' : 'cancelled');
    if (writes) {
      const changed = JSON.parse(before);
      changed.salesforce.Account.rows.find(row => row.Id === selection.recordId).Name = selection.nextName;
      assert.deepEqual(JSON.parse(await readFile(target, 'utf8')), changed);
    } else assert.equal(await readFile(target, 'utf8'), before);
    completed = true;
  } finally {
    try {await client?.close();}
    finally {
      process.chdir(cwd);
      if (completed) await rm(root, {recursive: true});
    }
  }
  const work = observer.forOriginal(original);
  assert.equal(work.complete, true);
  assert.equal(work.effectReplacementReturns, writes);
  assert.equal(work.totals.effectReplacementReturns, writes);
  console.log(JSON.stringify({decision, verdict: 'verified', malformed: {code: 'query_syntax_invalid', location},
    target: expected.target, record: expected.identity, fields: Object.keys(expected.changes),
    writesBeforeDecision: 0, writesAfterDecision: writes, firstClose: true}));
}
