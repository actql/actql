import test from 'node:test';
import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog, catalogPath} from './actions.mjs';
import {actionInputs, sharedFiles, hash} from './inputs.mjs';
import {sealReceipt, canonicalReceipt} from './receipts.mjs';
import {applicability, checkApplications} from './applications.mjs';

const old = 'a'.repeat(40), current = 'b'.repeat(40);
const catalog = readCatalog(); catalog.actions = catalog.actions.filter(action => ['model', 'session-js'].includes(action.id));
const selected = catalog.actions[1];
const runtime = {profile: 'controlled-test-runtime', unresolved: []};
const files = new Map([...sharedFiles.map(path => [path, path]), [catalogPath, encode(catalog)],
  ['src/bounded_execution/moon.pkg', ''], ['src/bounded_execution/session.mbt', 'production'],
  ...['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs'].map(path => [`proofs/bounded-session/${path}`, path])]);
function tree(source = files) {
  return {entries: new Map([...source].map(([path]) => [path, {mode: '100644', kind: 'blob'}])),
    read: path => Buffer.from(source.get(path))};
}
function receipt(action = selected, revision = old, source = files) {
  const inputs = actionInputs({tree: tree(source), revision, action, runtime});
  return sealReceipt({origin: {repository: 'actql/actql', repositoryId: 1, workflowId: 2,
    workflowPath: '.github/workflows/ci.yml', runId: 3, runAttempt: 1, jobId: 4,
    testedRevision: revision, runHeadRevision: revision, branch: 'main', event: 'push'},
  action, inputs, status: 0, milliseconds: 10,
  output: action.id === 'model' ? 'Checked 14 theorems, expected claim types and axiom dependencies\n' : 'Total tests: 7, passed: 7, failed: 0.\n'});
}
const base = () => ({action: selected, receipt: receipt(), originTree: tree(), candidateTree: tree(),
  candidateRevision: current, runtime, acquisition: 'reused'});

test('reuse preserves original receipt; candidate manifest is independently reconstructed', () => {
  const request = base(), bytes = canonicalReceipt(request.receipt);
  assert.equal(applicability(request).revision, current);
  assert(canonicalReceipt(request.receipt).equals(bytes));
});

test('actual origin Git bytes cannot be replaced by a self-consistent carried source digest', () => {
  const source = new Map(files); source.set('src/bounded_execution/session.mbt', 'different origin body');
  assert.throws(() => applicability({...base(), originTree: tree(source)}), /actual origin Git/u);
});

for (const [name, change] of [
  ['relevant source', source => source.set('src/bounded_execution/session.mbt', 'new body')],
  ['fixture addition', source => source.set('src/bounded_execution/new_wbtest.mbt', 'new oracle')],
  ['policy checker', source => source.set('proofs/ci-evidence/Reuse.lean', 'weaker checker')],
]) test(`candidate ${name} cannot borrow unchanged receipt labels`, () => {
  const source = new Map(files); change(source);
  assert.throws(() => applicability({...base(), candidateTree: tree(source)}));
});

test('unknown runtime boundary cannot be cleared outside the hashed input', () => {
  const request = base();
  request.receipt.inputs = actionInputs({tree: tree(), revision: old, action: selected,
    runtime: {...runtime, unresolved: ['unreviewed loader']}});
  request.receipt.inputs.unresolved = [];
  assert.throws(() => applicability(request), /actual origin Git/u);
  assert.throws(() => applicability({...base(), runtime: {...runtime, unresolved: ['unreviewed loader']}}), /open source or runtime/u);
});

test('whole profile widening fails independently of connection/derived labels', () => {
  const expanded = {...selected, profile: 'UNCHECKED rows with arbitrary field types'};
  const renamed = receipt(expanded);
  assert.throws(() => applicability({...base(), receipt: renamed}), /Wrong action/u);
});

const context = {candidateRevision: current, repository: 'actql/actql', repositoryId: 1, workflowId: 2,
  runId: 30, runAttempt: 1, runHeadRevision: 'c'.repeat(40), ancestors: [old]};
function gateRequest(entries = catalog.actions.map(action => ({actionId: action.id, acquisition: 'reused', archive: '/controlled.zip', artifactId: 6}))) {
  return {context, runtime, protectedRevision: old, entries, treeAt: () => tree(),
    read: async ({action}) => {
      const value = receipt(action);
      return {receipt: value, receiptDigest: hash(canonicalReceipt(value)), artifactId: 6, archiveDigest: 'd'.repeat(64)};
    }, prove: (required, applications) => {
      assert.deepEqual(required.map(entry => entry.action), ['model', 'session-js']);
      assert.deepEqual(applications.map(entry => entry.action), ['model', 'session-js']);
      return {accepted: true, inputDigest: hash(encode({required, applications}))};
    }};
}

test('complete family checker constructs Lean data from independently checked applications', async () => {
  const result = await checkApplications(gateRequest());
  assert.deepEqual(result.requiredActions, ['model', 'session-js']);
  assert.equal(result.applications[1].originRevision, old);
  assert.equal(result.applications[1].candidateRevision, current);
});

test('missing, extra and duplicate leaves cannot disappear from final required inventory', async () => {
  const request = gateRequest();
  await assert.rejects(checkApplications({...request, entries: request.entries.slice(0, 1)}), /Incomplete/u);
  await assert.rejects(checkApplications({...request, entries: [request.entries[0], request.entries[0]]}), /duplicate/u);
  await assert.rejects(checkApplications({...request, entries: [request.entries[0], {...request.entries[1], actionId: 'session-native'}]}), /Extra/u);
});

test('candidate cannot delete a protected required registration', async () => {
  const reduced = new Map(files); reduced.set(catalogPath, encode({...catalog, actions: [catalog.actions[0]]}));
  await assert.rejects(checkApplications({...gateRequest(), treeAt: revision => revision === old ? tree() : tree(reduced)}), /Removed required action/u);
});

test('a wholly consistent wrong-target receipt is refused before plan proof', async () => {
  await assert.rejects(checkApplications({...gateRequest(), read: async () => ({receipt: receipt({...selected, target: 'native',
    command: ['moon', 'test', 'src/bounded_execution', '--target', 'native', '--deny-warn']}),
    receiptDigest: 'e'.repeat(64), artifactId: 6, archiveDigest: 'd'.repeat(64)})}), /Wrong action/u);
});

function addedRequest() {
  const extra = {...selected, id: 'additional-session-js', profile: 'independent added fixture obligation'};
  const candidate = {...catalog, actions: [...catalog.actions, extra]};
  const source = new Map(files); source.set(catalogPath, encode(candidate));
  const request = gateRequest();
  request.treeAt = revision => revision === old ? tree() : tree(source);
  request.entries.push({actionId: extra.id, acquisition: 'fresh', archive: '/candidate.zip', artifactId: 7});
  request.read = async ({action}) => {
    const fresh = action.id === extra.id, value = receipt(action, fresh ? current : old, fresh ? source : files);
    return {receipt: value, receiptDigest: hash(canonicalReceipt(value)), artifactId: fresh ? 7 : 6,
      archiveDigest: 'd'.repeat(64)};
  };
  request.prove = (required, applications) => {
    assert.deepEqual(required.map(entry => entry.action), candidate.actions.map(action => action.id));
    assert.equal(applications.find(entry => entry.action === extra.id).reused, false);
    return {accepted: true, inputDigest: hash(encode({required, applications}))};
  };
  return request;
}

test('an added obligation requires its own candidate receipt and enters the complete Lean requirement input', async () => {
  const result = await checkApplications(addedRequest());
  assert.deepEqual(result.requiredActions, ['model', 'session-js', 'additional-session-js']);
  assert.equal(result.applications[2].acquisition, 'fresh');
  assert.equal(result.applications[2].originRevision, current);
});

test('added obligation cannot disappear, borrow an old receipt or relabel itself as reusable', async () => {
  const missing = addedRequest(); missing.entries.pop();
  await assert.rejects(checkApplications(missing), /Incomplete required applications/u);
  const reused = addedRequest(); reused.entries[2].acquisition = 'reused';
  await assert.rejects(checkApplications(reused), /Unreviewed\/changed reusable registration/u);
  const wrong = addedRequest(), read = wrong.read;
  wrong.read = args => read({...args, action: args.action.id === 'additional-session-js' ? selected : args.action});
  await assert.rejects(checkApplications(wrong), /Wrong action descriptor/u);
});
