import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {readmeQuickstart} from './readme-quickstart.mjs';

const markdown = await readFile(new URL('../README.md', import.meta.url), 'utf8');
test('README has one executable Program, Client, expected output and command set', () => {
  const value = readmeQuickstart(markdown);
  assert.match(value.program, /id: customer.open_orders/u);
  assert.match(value.client, /from '@actql\/node'/u);
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
