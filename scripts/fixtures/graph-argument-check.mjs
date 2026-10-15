// Shared CHECK assertions for the checkout and clean installed package entrances.
// The literal JSON owns expected bytes; neither source search nor a product
// parser/checker creates this oracle.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

export const graphArgumentLiteralIds = Object.freeze([
  'components-kind-plain', 'components-max-output-rows-plain', 'subgraph-nodes-plain',
  'components-kind-emoji-crlf', 'components-max-output-rows-emoji-crlf', 'subgraph-nodes-emoji-crlf',
  'components-kind-decomposed-crlf', 'components-max-output-rows-decomposed-crlf', 'subgraph-nodes-decomposed-crlf',
  'components-kind-decoy-comment', 'components-max-output-rows-decoy-comment', 'subgraph-nodes-decoy-comment',
  'components-kind-repeated-plain', 'components-kind-repeated-emoji-crlf',
]);
const {cases: literals} = JSON.parse(readFileSync(
  new URL('./graph-argument-origin-literals.json', import.meta.url), 'utf8'));
assert.deepEqual(literals.map(item => item.id), graphArgumentLiteralIds);

export const graphArgumentCheckInventory = Object.freeze([
  ...graphArgumentLiteralIds,
  'components-valid-weak', 'components-valid-strong',
  'components-private-kind', 'components-output-zero', 'components-output-fraction',
  'subgraph-empty-ids', 'subgraph-unknown-selector', 'subgraph-where-implementation-limit',
  'components-protected-absent', 'components-protected-denied',
  'subgraph-protected-absent', 'subgraph-protected-denied',
  'subgraph-protected-value-absent', 'subgraph-protected-value-denied',
]);
export const graphArgumentNoExecution = Object.freeze({
  runs: 0, dispatchReservations: 0, physicalReservations: 0,
  sourceOpens: 0, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
});
export function requireGraphArgumentCheckReport(report, mode) {
  assert.equal(report.version, 'actql-graph-argument-check/0.1');
  assert.equal(report.mode, mode);
  assert.equal(report.beforeDispatchCalls, mode === 'remote' ? 0 : null);
  assert.deepEqual(report.expectedInventory, graphArgumentCheckInventory);
  assert.deepEqual(report.completedInventory, graphArgumentCheckInventory);
  assert.deepEqual(report.cases.map(item => item.id), graphArgumentCheckInventory);
  for (const item of report.cases) assert.deepEqual(item.noExecution, graphArgumentNoExecution, item.id);
  assert.deepEqual(report.noExecution, graphArgumentNoExecution);
  assert.equal(report.complete, true);
  assert.equal(report.primaryError, null);
}

const prefix = 'WITH n AS (SELECT 1 AS node_key), g AS (GRAPH ' +
  '(NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) ';
const options = Object.freeze({kind: 'text', scope: 'bound_input', format: 'aql-text'});
const protectedSource = [{boundary: 'source_resolution', reason: 'unresolved_protected'}];
const explanations = {
  invalid_kind: {kind: 'known', summary: 'The components kind is invalid.',
    hint: 'Choose weak or strong for components kind.'},
  invalid_output_rows: {kind: 'known', summary: 'The components output row limit is invalid.',
    hint: 'Supply a positive safe integer for components max_output_rows.'},
  invalid_node_selector: {kind: 'known', summary: 'The Subgraph node selector is invalid.',
    hint: 'Provide one selector: nonempty ids, a named Relation with an id field, or a node where predicate.'},
};

export async function exerciseGraphArgumentChecks({denied, absent}, sdk,
  completedCase = async () => {}) {
  const {getCheckInput, resolveCheckLocation, explainCheckReason} = sdk;
  // Independent installations use different keyed context/input identities.
  // Validate each binding first, then replace only these opaque identities;
  // retain all public facts, locations, requirements and disclosure structure.
  function publicEnvelope(outcome) {
    assert.match(outcome.report.context_ref, /^ctx:[0-9a-f]{64}$/u);
    const revisions = new Map();
    for (const input of outcome.report.inputs) {
      assert.match(input.revision, /^rev:[0-9a-f]{64}$/u);
      assert.equal(getCheckInput(outcome, input.document_id).revision, input.revision);
      revisions.set(input.document_id, input.revision);
    }
    return {...outcome, report: {...outcome.report, context_ref: '<host-context>',
      inputs: outcome.report.inputs.map(input => ({...input, revision: '<' + input.document_id + '>'})),
      reasons: outcome.report.reasons.map(reason => {
        if (reason.location === undefined) return reason;
        assert.equal(reason.location.revision, revisions.get(reason.location.document_id));
        assert.ok(resolveCheckLocation(outcome, reason.location));
        return {...reason, location: {...reason.location, revision: '<' + reason.location.document_id + '>'}};
      })}};
  }
  let previous;
  async function invalid(fixture, issue) {
    const outcome = await denied.check(fixture.source, options);
    assert.equal(outcome.outcome, 'completed', fixture.id);
    assert.equal(outcome.report.verdict, 'invalid', fixture.id);
    const original = getCheckInput(outcome, 'source');
    assert.equal(original.documentId, 'source', fixture.id);
    assert.match(original.revision, /^rev:[0-9a-f]{64}$/u, fixture.id);
    assert.equal(original.kind, 'text', fixture.id);
    assert.equal(original.text, fixture.source, fixture.id);
    assert.deepEqual(outcome.report.inputs.find(input => input.document_id === 'source'),
      {document_id: 'source', revision: original.revision, kind: 'text',
        byte_length: Buffer.byteLength(fixture.source, 'utf8')}, fixture.id);
    const location = {document_id: 'source', revision: original.revision, kind: 'text',
      start_byte: fixture.startByte, end_byte: fixture.endByte, precision: 'exact'};
    assert.deepEqual(outcome.report.reasons, [{code: 'graph_operation_invalid',
      facts: {operation: fixture.operation, issue}, location}], fixture.id);
    assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []}, fixture.id);
    assert.deepEqual(outcome.report.requirements, [], fixture.id);
    const resolved = resolveCheckLocation(outcome, location);
    assert.equal(resolved.input, original, fixture.id);
    assert.equal(resolved.text, fixture.token, fixture.id);
    assert.equal(resolveCheckLocation(outcome, location,
      {...original, text: 'SELECT 1 AS replacement'}), undefined, fixture.id);
    assert.equal(resolveCheckLocation(outcome,
      {...location, document_id: 'parameter_values'}), undefined, fixture.id);
    assert.equal(resolveCheckLocation(outcome,
      {...location, revision: 'rev:' + '0'.repeat(64)}), undefined, fixture.id);
    assert.equal(resolveCheckLocation(JSON.parse(JSON.stringify(outcome)), location), undefined, fixture.id);
    if (previous) {
      assert.notEqual(previous.input.revision, original.revision, fixture.id);
      assert.equal(resolveCheckLocation(outcome, previous.location), undefined, fixture.id);
    }
    previous = {input: original, location};
    assert.deepEqual(explainCheckReason(outcome.report.reasons[0]), explanations[issue], fixture.id);
    assert.equal(JSON.stringify(outcome).includes('private-kind-value'), false);
    await completedCase(fixture.id);
    return outcome;
  }
  for (const fixture of literals) {
    await invalid(fixture, fixture.argument === 'kind' ? 'invalid_kind' :
      fixture.argument === 'max_output_rows' ? 'invalid_output_rows' : 'invalid_node_selector');
  }
  for (const kind of ['weak', 'strong']) {
    const outcome = await denied.check(prefix +
      `FROM g |> components(kind: '${kind}') |> SELECT component_size`, options);
    assert.equal(outcome.outcome, 'completed');
    assert.equal(outcome.report.verdict, 'verified');
    assert.deepEqual(outcome.report.reasons, []);
    assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
    assert.deepEqual(outcome.report.requirements, []);
    await completedCase('components-valid-' + kind);
  }
  for (const [id, arguments_, issue, startByte, endByte, token] of [
    ['components-private-kind', "kind: 'private-kind-value'", 'invalid_kind', 147, 167, "'private-kind-value'"],
    ['components-output-zero', "kind: 'weak', max_output_rows: 0", 'invalid_output_rows', 172, 173, '0'],
    ['components-output-fraction', "kind: 'weak', max_output_rows: 1.5", 'invalid_output_rows', 172, 175, '1.5'],
  ]) {
    await invalid({id, source: '/*😀*/\r\n' + prefix +
      `FROM g |> components(${arguments_}) |> SELECT component_size`,
    operation: 'components', startByte, endByte, token}, issue);
  }
  for (const [id, token, endByte] of [
    ['subgraph-empty-ids', '{ids: []}', 145],
    ['subgraph-unknown-selector', '{ids: [], unknown: true}', 160],
  ]) {
    await invalid({id, source: prefix +
      `FROM g |> subgraph(nodes: ${token}) |> node_rows() |> SELECT node_key`,
    operation: 'subgraph', startByte: 136, endByte, token}, 'invalid_node_selector');
  }
  const unsupported = await denied.check(prefix +
    'FROM g |> subgraph(nodes: {where: "true"}) |> node_rows() |> SELECT node_key', options);
  assert.equal(unsupported.outcome, 'completed');
  assert.equal(unsupported.report.verdict, 'undetermined');
  assert.deepEqual(unsupported.report.reasons, []);
  assert.deepEqual(unsupported.report.coverage, {limits: [{code: 'implementation_limit'}], unresolved: []});
  await completedCase('subgraph-where-implementation-limit');
  const protectedPrefix = prefix.replace('SELECT 1 AS node_key', 'SELECT id AS node_key FROM records');
  const protectedComponents = [];
  for (const [name, client] of Object.entries({absent, denied})) {
    const outcome = await client.check(protectedPrefix +
      "FROM g |> components(kind: 'private-kind-value') |> SELECT component_size", options);
    assert.equal(outcome.outcome, 'completed');
    assert.equal(outcome.report.verdict, 'undetermined');
    assert.deepEqual(outcome.report.reasons, []);
    assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: protectedSource});
    assert.equal(JSON.stringify(outcome).includes('private-kind-value'), false);
    protectedComponents.push(publicEnvelope(outcome));
  }
  assert.deepEqual(protectedComponents[0], protectedComponents[1]);
  for (const name of ['absent', 'denied']) await completedCase('components-protected-' + name);
  for (const wrongType of [false, true]) {
    const outcomes = [];
    for (const [name, client] of Object.entries({absent, denied})) {
      const outcome = await client.check(protectedPrefix +
        'FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key', {...options,
        parameterDeclarations: {minimum: {type: 'number'}},
        parameters: {minimum: wrongType ? 'private-value' : 1}});
      assert.equal(outcome.outcome, 'completed');
      assert.deepEqual({verdict: outcome.report.verdict,
        reasons: outcome.report.reasons.map(({location, ...reason}) => reason),
        coverage: outcome.report.coverage}, {
        verdict: wrongType ? 'invalid' : 'undetermined',
        reasons: wrongType ? [{code: 'supplied_value_type_mismatch', facts: {
          parameter: 'minimum', expected_type: 'number', actual_type: 'string'}}] : [],
        coverage: {limits: [], unresolved: protectedSource},
      });
      assert.equal(outcome.report.reasons.some(reason => reason.code === 'graph_operation_invalid'), false);
      assert.equal(JSON.stringify(outcome).includes('private-value'), false);
      outcomes.push(publicEnvelope(outcome));
    }
    assert.deepEqual(outcomes[0], outcomes[1],
      'absent and denied Sources retain the same public envelope apart from Host-keyed identities');
    for (const name of ['absent', 'denied']) {
      await completedCase('subgraph-protected-' + (wrongType ? 'value-' : '') + name);
    }
  }
}
