import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {types as nodeTypes} from 'node:util';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual shared callback with explicit current/Site ports. These
// controls issue no authority, perform no transport and establish no funding.
const source = readFileSync(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
const syntax = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const owner = syntax.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'createInstalledRowSource');
assert(owner);
const callbacks = [];
function visit(node) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'Property' && node.key?.name === 'authorizeReadChild' &&
      node.value.type === 'ArrowFunctionExpression') callbacks.push(node.value);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  }
}
visit(owner);
assert.equal(callbacks.length, 1);
const callback = source.slice(callbacks[0].start, callbacks[0].end);

function fixture(current) {
  const grant = Object.freeze({scope: {}, grant: {}});
  let calls = 0;
  const ports = {readerDemand: undefined, owner: {resource: 'records'}, operation: 'read',
    nodeTypes, fail: code => {throw Object.assign(new Error(code), {code});},
    currentRead: async () => {calls++;if (current) await current();},
    prepared: {}, access: {}, signal: undefined,
    site: {issueReadGrant() {assert.fail('No child-specific grant in this control');}},
    granted: {}, grant, limits: {maxPages: 2}, runInvocationCid: 'original-run',
    dispatchRequestCid: 'original-request', nonce: 'original', directReadIdentity: undefined,
    text: value => typeof value === 'string' && value.length > 0};
  const authorize = Function(...Object.keys(ports),
    'let readChildIndex=0,rootReadUses=0,propertyOccurrences=0;' +
    'const readChildUses=new Map(),readChildOriginals=new WeakMap();return ' + callback + ';')
    (...Object.values(ports));
  return {authorize, grant, calls: () => calls};
}

test('undeclared child authorization spends each ordinal once within its existing page budget', async () => {
  const f = fixture();
  const first = await f.authorize('read', 0);
  assert.equal(first.originalAuthorization, f.grant);
  assert.equal(first.authorization.useId, 'original-read-0');
  await assert.rejects(f.authorize('read', 0), {code: 'InvalidInstalledSourceReadChild'});
  await assert.rejects(f.authorize('read', 2), {code: 'InvalidInstalledSourceReadChild'});
  assert.equal(f.calls(), 1);
  const second = await f.authorize('read', 1);
  assert.equal(second.originalAuthorization, f.grant);
  assert.equal(second.authorization.useId, 'original-read-1');
  await assert.rejects(f.authorize('read', 2), {code: 'InvalidInstalledSourceReadChild'});
  assert.equal(f.calls(), 2);
});

test('undeclared child authorization consumes its ordinal before reentrant or failed current checks', async () => {
  let f, entered = false;
  const original = new Error('OriginalCurrentRefusal');
  f = fixture(async () => {
    if (entered) return;
    entered = true;
    await assert.rejects(f.authorize('read', 0), {code: 'InvalidInstalledSourceReadChild'});
    throw original;
  });
  await assert.rejects(f.authorize('read', 0), cause => cause === original);
  assert.equal(f.calls(), 1);
  await assert.rejects(f.authorize('read', 0), {code: 'InvalidInstalledSourceReadChild'});
  assert.equal((await f.authorize('read', 1)).originalAuthorization, f.grant);
  assert.equal(f.calls(), 2);
});
