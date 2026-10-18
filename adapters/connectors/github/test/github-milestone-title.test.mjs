// Milestone is the provider's title observation, never its numeric or node ID.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../../../_build/js/release/build/connectors/github/host_node/host_node.js';

const issue = milestone => ({number: 1, id: 'I_1', node_id: 'I_1',
  title: 'issue', state: 'OPEN', body: '', author: {login: 'octo'},
  comments: {totalCount: 0}, milestone,
  createdAt: '2026-10-01T00:00:00Z', updatedAt: '2026-10-02T00:00:00Z',
  closedAt: null});
const graph = value => JSON.parse(moon.githubIssuesPageJson(Buffer.from(
  JSON.stringify({data: {node: {__typename: 'Repository', id: 'R_A',
    databaseId: 17, nameWithOwner: 'octo/repo', issues: {
      pageInfo: {hasNextPage: false, endCursor: null}, nodes: [value]}}}})),
  100_000, 10_000, 32, 100, 'R_A', 17, 'octo/repo'));
const rest = value => {
  const node = {...value, state: 'open', user: value.author, comments: 0,
    created_at: value.createdAt, updated_at: value.updatedAt, closed_at: null};
  return JSON.parse(moon.githubIssuePageJson(Buffer.from(JSON.stringify([node])),
    100_000, 10_000, 32, 100));
};

for (const [name, project] of [['GraphQL', graph], ['REST', rest]]) {
  test(`${name} milestone preserves title separately from every provider ID`, () => {
    for (const title of ['2', '*', 'none', 'null', '', '  release β / 日本語  ']) {
      const result = project(issue({title, number: 71, databaseId: 805, id: 'M_X'}));
      assert.equal(result.page.rows[0].milestone, title);
      assert.equal(result.page.rows[0].node_id, 'I_1');
    }
  });
  test(`${name} milestone absence is NULL and malformed requested objects refuse`, () => {
    assert.equal(project(issue(null)).page.rows[0].milestone, null);
    for (const value of [{}, {number: 2}, {title: null}, {title: 2}, '*', [], false]) {
      assert.ok(project(issue(value)).refused, JSON.stringify(value));
    }
    const missing = issue(null);
    delete missing.milestone;
    assert.ok(project(missing).refused);
  });
}

test('the fixed read requests title without sending a milestone selector', () => {
  const result = JSON.parse(moon.githubIssuesRequestJson('R_A', 10, false, '',
    'all', [], false, ''));
  const body = JSON.parse(result.body);
  assert.match(body.query, /milestone \{ title \}/u);
  assert.doesNotMatch(body.query, /\$milestone|milestone\s*:/u);
  assert.equal(Object.hasOwn(body.variables, 'milestone'), false);
});
