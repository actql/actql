import assert from 'node:assert/strict';

// Independently specified original UTF-8 ranges; no search or product decoder
// supplies expected positions, including comments with the same spelling.
export const unaliasedColumnOrigins = [
  {text: 'SELECT missing', start: 7, end: 14, token: 'missing'},
  {text: '/*😀*/\r\nSELECT missing', start: 17, end: 24, token: 'missing'},
  {text: 'SELECT `é😀`', start: 7, end: 15, token: '`é😀`'},
  {text: 'SELECT `e\u0301😀`', start: 7, end: 16, token: '`e\u0301😀`'},
  {text: 'SELECT missing FROM records', start: 7, end: 14, token: 'missing'},
  {text: 'SELECT records.missing FROM records', start: 7, end: 22, token: 'records.missing'},
  {text: 'SELECT id, missing FROM records', start: 11, end: 18, token: 'missing'},
  {text: '/* missing */ SELECT missing', start: 21, end: 28, token: 'missing'},
];

export async function exerciseUnaliasedColumnOrigins(client, {getCheckInput, resolveCheckLocation}) {
  for (const format of ['sql', 'aql-text']) {
    for (const {text, start, end, token} of unaliasedColumnOrigins) {
      const outcome = await client.check(text, {kind: 'text', scope: 'bound_input', format});
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'invalid');
      const input = getCheckInput(outcome, 'source');
      assert.equal(input.text, text);
      const location = {document_id: 'source', revision: input.revision, kind: 'text',
        start_byte: start, end_byte: end, precision: 'exact'};
      assert.deepEqual(outcome.report.reasons, [{code: 'query_expression_invalid',
        facts: {issue: 'unknown_reference'}, location}]);
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
      assert.equal(resolveCheckLocation(outcome, location).text, token);
      assert.equal(resolveCheckLocation(outcome, location, {...input, text: 'SELECT 1'}), undefined);
      assert.equal(resolveCheckLocation(structuredClone(outcome), location), undefined);
    }
    for (const text of ['SELECT missing FROM never_configured',
      'SELECT never_configured.missing FROM never_configured']) {
      const outcome = await client.check(text, {kind: 'text', scope: 'bound_input', format});
      assert.equal(outcome.report.verdict, 'undetermined');
      assert.deepEqual(outcome.report.reasons, []);
      assert.deepEqual(outcome.report.coverage, {limits: [],
        unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
    }
  }
}
