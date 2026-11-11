import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {readmeQuickstart} from './readme-quickstart.mjs';
import {parse} from 'acorn';

const markdown = await readFile(new URL('../docs/development.md', import.meta.url), 'utf8');
test('README has one executable Program, Client, expected output and command set', () => {
  const value = readmeQuickstart(markdown);
  assert.match(value.program, /id: customer.open_orders/u);
  assert.match(value.client, /from '@actql\/node'/u);
  assert.match(value.client, /client\.newSubmission\(\{nonce: 'customer-open-orders'\}\)/u);
  assert.match(value.client, /format: 'yaml', submissionRef/u);
  assert.match(value.client, /writeFile\('submission\.json'/u);
  assert.doesNotMatch(value.client, /requestId:/u);
  assert.equal(value.install, 'npm init -y >/dev/null\n' +
    'npm install --ignore-scripts --no-save "$ACTQL_PACKED_CLIENT_PACKAGES"/*.tgz');
  assert.deepEqual(value.expected.trimEnd().split('\n').map(JSON.parse),
    [{customer_id: 'c1', order_count: 1, total_amount: 120},
      {customer_id: 'c2', order_count: 1, total_amount: 80}]);
});
test('ambiguous examples and command drift fail instead of skipping acceptance', () => {
  assert.throws(() => readmeQuickstart(markdown.replace('### Run a query',
    '```yaml\nother: example\n```\n### Run a query')), /AmbiguousQuickstart/u);
  assert.throws(() => readmeQuickstart(markdown.replace('node quickstart.mjs',
    'node different.mjs')), /ChangedQuickstartCommands/u);
});

test('README HTTPS operator selects only current principal reads and the original pure request target', async () => {
  const source = await readFile(new URL('./fixtures/packed-readme-quickstart.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const declarations = syntax.body.filter(node => node.type === 'VariableDeclaration')
    .flatMap(node => node.declarations);
  const original = declarations.find(node => node.id.name === 'httpAuthorization');
  assert(original);
  const authorization = Function('userInfo', `return (${source.slice(original.init.start, original.init.end)});`)(
    () => ({username: 'readme-operator'}));
  assert.deepEqual(JSON.parse(authorization.accountConfiguration), {
    version: 'actql-execution-account-config/0.1', account_id: 'readme-http',
    entries: [{entry_id: 'read-original', outcome: 'allow',
      principal: {any_of: ['readme-operator']}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/main', 'run']}, operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'request-original', outcome: 'allow',
      principal: {any_of: ['readme-operator']}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['source-free-values']}, operation: {any_of: ['write']}, exclusions: []}],
  });
  const host = declarations.find(node => node.id.name === 'host').init.argument;
  assert.equal(host.callee.name, 'openInstalledRemoteHttpHost');
  const selected = host.arguments[0].properties.find(node => node.key.name === 'authorization');
  assert.equal(selected.value.name, 'httpAuthorization');
});
