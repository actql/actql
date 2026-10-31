import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareGmailLabelListPages, readGmailLabelList} from '../site/gmail-label-list-read.mjs';

// Current compiled Gmail Catalog/bridge plus actual shared page/legacy caller.
// No Common Request, Account, Resource allowance, physical HTTP or ordinary
// installation is supplied by the explicit invocation/transport ports here.
const moon = await import(process.env.ACTQL_GMAIL_LABEL_COMPONENT_URL ??
  new URL('../../../../_build/js/release/build/connectors/gmail/host_node/host_node.js', import.meta.url).href);
const limits = Object.freeze({maxResponseBytes: 4096, maxNodes: 256, maxDepth: 8, maxRows: 3,
  maxMailboxBytes: 128, maxTargetBytes: 1024, maxValueNodes: 32, maxValueTextBytes: 4096,
  maxRowsWireBytes: 4096, maxRowsWireNodes: 64, maxRowsWireDepth: 6});
const expected = [{id: 'INBOX', name: 'Inbox', type: 'system'},
  {id: 'Label_1', name: '顧客 / é 📩', type: 'user'}];
const create = (extra = {}) => prepareGmailLabelListPages({moon, mailbox: 'support+box@example.test',
  names: ['name'], limits, ...extra}, (method, receiver, args) => Reflect.apply(method, receiver, args));

test('actual Gmail Catalog supplies identical complete label cells to shared and original explicit callers', async () => {
  const body = Buffer.from(JSON.stringify({labels: expected}));
  const page = create(), request = page.fetchPage({pageIndex: 0});
  assert.equal(request.path, '/gmail/v1/users/support%2Bbox%40example.test/labels');
  assert.deepEqual(page.decodePage({accepted: true, statusCode: 200, body}), {rows: expected, rowCount: 2, done: true});
  let sends = 0, charges = 0, delivered;
  const grant = {}, scope = Object.freeze({operation: 'gmail:labels:list'});
  const authorization = {grant, scope, useId: 'same-original'};
  const result = await readGmailLabelList({moon, mailbox: 'support+box@example.test', names: ['name'], limits,
    initialAuthorization: authorization, credential: {binding: {}},
    current() {}, authorizationFor() {return authorization;},
    chargeResponse(original) {assert.strictEqual(original, body); charges++; return 'original-charge';},
    consumePage(rows, {charge}) {assert.equal(charge, 'original-charge'); delivered = rows;},
    callResource(input) {
      sends++; assert.equal(input.grant, grant);
      assert.equal(input.operations.get('gmail:labels:list').path,
        '/gmail/v1/users/support%2Bbox%40example.test/labels?fields=labels%28id%2Cname%2Ctype%29');
      return {accepted: true, statusCode: 200, body};
    }});
  assert.equal(result.pages, 1); assert.equal(result.rowCount, 2);
  assert.strictEqual(result.observations[0].body, body); assert.deepEqual(delivered, expected);
  assert.equal(sends, 1); assert.equal(charges, 1);
});

test('actual Gmail Catalog refuses malformed unselected labels duplicate keys continuation and one-short row limits', () => {
  for (const kind of ['missing', 'duplicate', 'continuation', 'foreign', 'one-short']) {
    const values = expected.map(row => ({...row}));
    let document = {labels: values};
    if (kind === 'missing') delete values[1].type;
    if (kind === 'duplicate') values[1].id = values[0].id;
    if (kind === 'continuation') document.nextPageToken = 'not-a-label-continuation';
    if (kind === 'foreign') document = {messages: values};
    const page = create(kind === 'one-short' ? {limits: {...limits, maxRows: 1}} : {});
    assert.throws(() => page.decodePage({accepted: true, statusCode: 200,
      body: Buffer.from(JSON.stringify(document))}), {code: 'MoonBitHostFailure'}, kind);
  }
});
