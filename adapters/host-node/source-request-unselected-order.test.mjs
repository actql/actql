import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {installNodeClientSubmission} from './client-submission.mjs';
import {originalSubmission} from '../../packages/sdk/submission-fixture.mjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const open = ast.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'openInstalledHost');
const declarations = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator') declarations.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(open.body);
const body = ['selectedSourcePreparation', 'bindOwnedRequest', 'submissionService'].map(name => {
  const matches = declarations.filter(node => node.id.name === name);
  assert.equal(matches.length, 1, name);
  return `const ${source.slice(matches[0].start, matches[0].end)};`;
}).join('\n');
// Execute the installed Host's actual service assembly, including selection,
// with actual submission code. Common/Journal are explicit stopping ports.
const install = compileFunction(`${body}\nreturn {submissionService, bindOwnedRequest};`,
  ['preparation', 'installNodeClientSubmission', 'journal', 'moon', 'hostConnection',
    'authorizedScope', 'prepareSubmit', 'submit', 'lookupHeld', 'check']);
const cid = `sha256:${'a'.repeat(64)}`;

for (const selected of [false, true]) {
  test(`actual ${selected ? 'selected' : 'unselected'} Host wiring ${selected ? 'retains' : 'omits'} Source callback and preparation continuation`, async () => {
    const prepared = {}, marker = Object.freeze(new Error('OriginalJournalStop'));
    let binds = 0, thenCalls = 0;
    const native = Promise.resolve(prepared);
    Object.defineProperty(native, 'then', {value(...args) {
      thenCalls++; return Reflect.apply(Promise.prototype.then, this, args);
    }});
    const original = {};
    // The unselected preparation deliberately still has the real assembly's
    // defined no-op method. Its mere presence must not select downstream work.
    const preparation = {sourcePreparation: () => selected ? original : undefined,
      bindSourceRequest() {binds++;}};
    const journal = {recordSubmittedIntent() {throw marker;}, checkSubmittedIntent() {},
      lookupSubmittedIntent() {}, verifySubmissionEpoch: () => ({validity: 'admissible'}),
      submissionIdentity: () => ({requestId: 'original'})};
    const moon = {clientSubmittedIntent: () => ({}), clientSubmittedIntentCid: () => cid};
    const actual = install(preparation, installNodeClientSubmission, journal, moon, () => true,
      () => ({namespaceId: 'original', authorityScopeCid: cid}), () => native,
      () => assert.fail('NoDispatch'), () => ({kind: 'not_found'}), undefined);
    assert.equal(actual.bindOwnedRequest, selected ? preparation.bindSourceRequest : undefined);
    await assert.rejects(actual.submissionService.submitIntent({principalId: 'actor',
      connection: {mode: 'local', owner: 'local', durability: 'volatile', consentRefs: [], runners: []},
      submissionRef: originalSubmission('original-await'), intentCid: cid,
      kind: 'aql', input: {text: 'SELECT 1 AS n', format: 'sql'}, parameters: null}),
    error => error === marker);
    assert.equal(thenCalls, selected ? 1 : 0,
      'Native await must not be replaced by an unselected .then continuation');
    assert.equal(binds > 0, selected);
  });
}
