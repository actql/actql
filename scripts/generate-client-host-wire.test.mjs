import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {buildClientHostWire} from './generate-client-host-wire.mjs';

const registry = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-client-host.json', import.meta.url), 'utf8'));
const protocol = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-protocol-schemas.json', import.meta.url), 'utf8'));

test('generated Client–Host guards and types match the machine contract',
  async () => {
    const outputs = buildClientHostWire(registry, protocol);
    assert.equal(outputs.module, await readFile(new URL(
      '../packages/client-wire/client-host.generated.js', import.meta.url),
    'utf8'));
    assert.equal(outputs.native, await readFile(new URL(
      '../src/cmd/native_client/wire.generated.mbt', import.meta.url), 'utf8'));
    assert.equal(outputs.types, await readFile(new URL(
      '../packages/client-wire/client-host.generated.d.ts', import.meta.url),
    'utf8'));
  });

test('schema and operation mutations invalidate generated Client–Host wire',
  () => {
    const original = buildClientHostWire(registry, protocol);
    const changed = structuredClone(registry);
    changed.schemas.profile.properties.limits.properties.maxRows.minimum = 2;
    assert.notEqual(buildClientHostWire(changed, protocol).module,
      original.module);
    changed.operations.connect.push('nonce');
    assert.notEqual(buildClientHostWire(changed, protocol).module,
      original.module);
    changed.schemas.submit_preparation_error.properties.code.enum
      .push('UnexpectedSubmitError');
    assert.notEqual(buildClientHostWire(changed, protocol).types,
      original.types);
    changed.schemas.profile.properties.limits.properties.maxRows.type = 'number';
    assert.throws(() => buildClientHostWire(changed, protocol),
      /UnsupportedPublicationType/);
    const changedState = structuredClone(protocol);
    changedState.artifact_schemas.run_state.properties.run_id.minLength = 2;
    assert.notEqual(buildClientHostWire(registry, changedState).module,
      original.module);
  });

test('generated check validator rejects contradictory evidence and partial verification',
  async () => {
    const {validCheckOutcomeShape: valid} = await import(
      '../packages/client-wire/client-host.generated.js');
    const report = {context_ref: 'ctx:fixture', requirements: [], inputs: [{document_id: 'source', revision: 'rev:' + '1'.repeat(64), kind: 'text', byte_length: 1}], scope: {kind: 'bound_input'},
      verdict: 'verified', reasons: [], coverage: {limits: [], unresolved: []}};
    const outcome = report => ({version: 'actql-check-outcome/0.1', reason_schema_cid: protocol.artifact_schema_cids.check_reason, outcome_schema_cid: protocol.artifact_schema_cids.check_outcome,
      outcome: 'completed', report});
    assert.equal(valid(outcome(report)), true);
    for (const changed of [
      {...report, coverage: {limits: [{code: 'future_limit'}], unresolved: []}},
      {...report, coverage: {limits: [], unresolved: [
        {boundary: 'future_boundary', reason: 'unresolved_protected'}]}},
      {...report, reasons: [{code: 'future_violation'}]},
      {...report, verdict: 'invalid'},
      {...report, verdict: 'undetermined'},
      {...report, verdict: 'undetermined', reasons: [{code: 'future_violation'}]},
    ]) assert.equal(valid(outcome(changed)), false, JSON.stringify(changed));
    assert.equal(valid({version: 'actql-check-outcome/0.1', reason_schema_cid: protocol.artifact_schema_cids.check_reason, outcome_schema_cid: protocol.artifact_schema_cids.check_outcome, outcome: 'failed', correlation_ref: 'corr:fixture',
      problem: {code: 'future_problem'}, partial_report: report}), false);
    assert.equal(valid(outcome({...report, verdict: 'invalid',
      reasons: [{code: 'future_violation'}]})), true);
    assert.equal(valid(outcome({...report, verdict: 'undetermined',
      coverage: {limits: [{code: 'future_limit'}], unresolved: []}})), true);
  });

test('typed public facts are closed and locations bind declared input revisions', async () => {
  const {validCheckOutcome: valid, checkReasonSchemaCid, checkOutcomeSchemaCid} = await import(
    '../packages/client-wire/index.mjs');
  const revision = 'rev:' + '2'.repeat(64);
  const location = {kind: 'structured', document_id: 'parameters', revision,
    pointer: '/minimum'};
  const reason = {code: 'supplied_value_type_mismatch', location,
    facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'}};
  const outcome = reason => ({version: 'actql-check-outcome/0.1',
    reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid, outcome: 'completed', report: {
      context_ref: 'ctx:fixture', scope: {kind: 'bound_input'}, verdict: 'invalid',
      inputs: [{document_id: 'source', kind: 'text', revision, byte_length: 6},
        {document_id: 'parameters', kind: 'structured', revision, byte_length: 20}],
      requirements: [], reasons: [reason], coverage: {limits: [], unresolved: []}}});
  assert.equal(valid(outcome(reason)), true);
  for (const changed of [
    {...reason, facts: {parameter: 'minimum', expected_type: 'number'}},
    {...reason, facts: {...reason.facts, value: 'secret'}},
    {...reason, code: 'future_code'},
    {...reason, location: {...location, revision: 'rev:' + '3'.repeat(64)}},
    {...reason, location: {...location, pointer: '/bad~escape'}},
  ]) assert.equal(valid(outcome(changed)), false, JSON.stringify(changed));
  assert.equal(valid(outcome({code: 'future_code'})), true);
  const defaultLocation = {...location, document_id: 'parameter_declarations',
    pointer: '/minimum/default'};
  const defaultReason = {...reason, code: 'parameter_default_type_mismatch',
    location: defaultLocation};
  const defaultOutcome = value => {
    const answer = outcome(value);
    answer.report.inputs.push({document_id: 'parameter_declarations', kind: 'structured',
      revision, byte_length: 58});
    return answer;
  };
  assert.equal(valid(defaultOutcome(defaultReason)), true);
  const {location: _defaultLocation, ...unlocatedDefault} = defaultReason;
  assert.equal(valid(defaultOutcome(unlocatedDefault)), true);
  for (const changed of [
    {code: defaultReason.code}, {...defaultReason, facts: {}},
    {...defaultReason, facts: {parameter: 'minimum', expected_type: 'number'}},
    {...defaultReason, facts: {...defaultReason.facts, value: 'private-default'}},
    {...defaultReason, facts: {...defaultReason.facts, actual_type: 'private-default'}},
    {...defaultReason, location},
    {...defaultReason, location: {...defaultLocation, revision: 'rev:' + '3'.repeat(64)}},
    {...defaultReason, location: {...defaultLocation, kind: 'text', pointer: undefined,
      start_byte: 0, end_byte: 1, precision: 'exact'}},
    {...defaultReason, code: 'parameter_declarations_invalid'},
    {...defaultReason, code: 'future_code'},
  ]) assert.equal(valid(defaultOutcome(changed)), false, '[check-mutation:default-schema]');
  const constraint = {code: 'supplied_value_constraint_violation', location,
    facts: {parameter: 'minimum', constraint: 'numeric'}};
  assert.equal(valid(outcome(constraint)), true);
  for (const changed of [
    {...constraint, facts: undefined},
    {...constraint, facts: {parameter: 'minimum'}},
    {...constraint, facts: {...constraint.facts, constraint: 'future_constraint'}},
    {...constraint, facts: {...constraint.facts, value: 0}},
    {...constraint, code: 'parameter_undeclared'},
    {...constraint, code: 'future_code'},
  ]) assert.equal(valid(outcome(changed)), false, '[check-mutation:constraint-schema]');
  const expression = {code: 'query_expression_invalid', facts: {issue: 'invalid_number'},
    location: {kind: 'text', document_id: 'source', revision,
      start_byte: 0, end_byte: 6, precision: 'exact'}};
  for (const issue of ['unknown_reference', 'invalid_arguments', 'invalid_number', 'expected_boolean']) {
    assert.equal(valid(outcome({...expression, facts: {issue}})), true);
    assert.equal(valid(outcome({code: expression.code, facts: {issue}})), true);
  }
  for (const changed of [
    {code: expression.code}, {...expression, facts: {}},
    {...expression, facts: {issue: 'invalid_escape'}},
    {...expression, facts: {issue: 'future_issue'}},
    {...expression, facts: {...expression.facts, name: 'private_name'}},
    {...expression, location}, {...expression, code: 'query_invalid'},
    {...expression, code: 'future_code'},
  ]) assert.equal(valid(outcome(changed)), false, '[check-mutation:expression-schema]');
  const graph = {code: 'graph_operation_invalid',
    facts: {operation: 'components', issue: 'invalid_kind'}};
  for (const issue of ['invalid_kind', 'invalid_output_rows']) {
    assert.equal(valid(outcome({...graph, facts: {...graph.facts, issue}})), true);
  }
  const selector = {code: 'graph_operation_invalid',
    facts: {operation: 'subgraph', issue: 'invalid_node_selector'}};
  assert.equal(valid(outcome(selector)), true);
  for (const changed of [
    {code: selector.code}, {...selector, facts: {operation: 'subgraph'}},
    {...selector, facts: {operation: 'components', issue: 'invalid_node_selector'}},
    {...selector, facts: {operation: 'subgraph', issue: 'invalid_output_rows'}},
    {...selector, facts: {...selector.facts, value: 'private_selector'}},
    {...selector, code: 'program_invalid'}, {...selector, code: 'future_code'},
  ]) assert.equal(valid(outcome(changed)), false, '[check-mutation:subgraph-schema]');
  for (const changed of [
    {code: graph.code}, {...graph, facts: {issue: 'invalid_kind'}},
    {...graph, facts: {operation: 'subgraph', issue: 'invalid_kind'}},
    {...graph, facts: {operation: 'components', issue: 'unknown_reference'}},
    {...graph, facts: {operation: 'components', issue: 'future_issue'}},
    {...graph, facts: {...graph.facts, value: 'private_kind'}},
    {...graph, code: 'program_invalid'}, {...graph, code: 'future_code'},
    {...graph, code: 'query_expression_invalid'}, {...graph, location},
  ]) assert.equal(valid(outcome(changed)), false, '[check-mutation:graph-schema]');
  const lexical = {code: 'query_lexical_invalid', facts: {issue: 'invalid_escape'},
    location: {kind: 'text', document_id: 'source', revision,
      start_byte: 6, end_byte: 6, precision: 'exact'}};
  assert.equal(valid(outcome(lexical)), true);
  const {location: _omitted, ...unlocated} = lexical;
  assert.equal(valid(outcome(unlocated)), true, 'unowned locations may be omitted');
  for (const changed of [
    {code: 'query_lexical_invalid'},
    {...lexical, facts: {}},
    {...lexical, facts: {issue: 'future_issue'}},
    {...lexical, facts: {issue: 'unknown_reference'}},
    {...lexical, facts: {issue: 'invalid_arguments'}},
    {...lexical, facts: {...lexical.facts, token: 'private text'}},
    {...lexical, location},
    {...lexical, code: 'parameter_undeclared'},
    {...lexical, code: 'future_code'},
    {...lexical, code: 'query_syntax_invalid'},
  ]) assert.equal(valid(outcome(changed)), false, '[check-mutation:lexical-schema]');
});


test('authoritative structural and behavioral mutations reach both consumers', async () => {
  const original = buildClientHostWire(registry, protocol);
  const changed = structuredClone(registry);
  changed.schemas.profile.properties.scopeRef.maxLength = 255;
  changed.response_rules.profile.requireRequested.durability = 'volatile';
  const output = buildClientHostWire(changed, protocol);
  assert.notEqual(output.native, original.native);
  assert.match(output.native, /text.length\(\) > 255/);
  assert.match(output.native, /connection.get\("durability"\) == Some\(Json::string\("volatile"\)\)/);
  const generated = await import(`data:text/javascript;base64,${Buffer.from(output.module).toString('base64')}`);
  const {profile, connection} = await import('./fixtures/client-wire-contract-corpus.mjs');
  assert.equal(generated.validProfileContract({...profile, scopeRef:'a'.repeat(256)}, connection), false);
  assert.equal(generated.validProfileContract(profile, {...connection,durability:'volatile'}), false);
});

test('Native projection refuses unsupported rules instead of silently dropping them', () => {
  for (const mutate of [
    value => { value.schemas.profile.properties.scopeRef.pattern = '^future$'; },
    value => { value.schemas.profile.allOf = [{additionalProperties:false}]; },
    value => { value.schemas.profile.properties.mode.const = 'remote'; },
    value => { value.schemas.profile.properties.scopeRef.allOf = [{maxLength:255}]; },
    value => { value.schemas.admission.properties.revision.allOf = [{minimum:2}]; },
    value => { value.schemas.profile.properties.scopeRef.not = {const:'forbidden'}; value.schemas.profile.properties.scopeRef.$ref = '#/$defs/value_contract'; },
    value => { value.response_rules.profile.matchConnection.push('unknownField'); },
  ]) {
    const changed = structuredClone(registry); mutate(changed);
    assert.throws(() => buildClientHostWire(changed, protocol), /UnsupportedNativeWire|InvalidClientHostResponseRule/);
  }
});

test('request reply schema and relation changes reach both generated consumers', async () => {
  const original = buildClientHostWire(registry, protocol);
  for (const mutate of [
    value => { value.schemas.lookup_found.properties.lookupExpiresAt.maxLength = 255; },
    value => { value.schemas.lookup_unknown.properties.reason.maxLength = 255; },
    value => { value.schemas.lookup_not_found.properties.kind.const = 'absent'; },
    value => { value.schemas.held.properties.prepareAttemptId.maxLength = 255; },
    value => { value.schemas.held.allOf[0].oneOf[2].required.push('checkpoint'); },
    value => { value.request_response_rules.held.matchRequest = 'prepareAttemptId'; },
  ]) {
    const changed = structuredClone(registry); mutate(changed);
    const output = buildClientHostWire(changed, protocol);
    assert.notEqual(output.module, original.module, 'JS freshness detects changed authority');
    assert.notEqual(output.native, original.native, 'Native freshness detects changed authority');
  }
  const changed = structuredClone(registry);
  changed.schemas.lookup_unknown.properties.reason.maxLength = 255;
  changed.schemas.held.allOf[0].oneOf[2].required.push('checkpoint');
  const output = buildClientHostWire(changed, protocol);
  const generated = await import(`data:text/javascript;base64,${Buffer.from(output.module).toString('base64')}`);
  const unknown = {kind: 'unknown', reason: 'a'.repeat(256)};
  const ended = {kind: 'held', requestId: 'fixed-request', prepareAttemptId: 'attempt-a',
    durability: 'durable', lookupExpiresAt: 'opaque-expiry', state: 'ended', endReason: 'cancelled'};
  assert.equal(generated.validRequestLookupContract(unknown, 'fixed-request'), false);
  assert.equal(generated.validHeldContract(ended, 'fixed-request'), false);
  const binding = structuredClone(registry);
  binding.request_response_rules.held.matchRequest = 'prepareAttemptId';
  const rebound = buildClientHostWire(binding, protocol);
  const relation = await import(`data:text/javascript;base64,${Buffer.from(rebound.module).toString('base64')}`);
  assert.equal(relation.validHeldContract(ended, 'fixed-request'), false);
  assert.equal(relation.validHeldContract(ended, 'attempt-a'), true);
});

test('request response derivation fails closed on ambiguous or unsupported bindings', () => {
  for (const mutate of [
    value => { delete value.request_response_rules; },
    value => { value.request_response_rules.extra = {}; },
    value => { value.request_response_rules.held.extra = true; },
    value => { value.request_response_rules.held.schemas = []; },
    value => { value.request_response_rules.held.schemas = ['held', 'held']; },
    value => { value.request_response_rules.held.schemas = ['future']; },
    value => { value.request_response_rules.held.schemas = ['lookup_unknown']; },
    value => { value.request_response_rules.held.matchRequest = 'missing'; },
    value => { value.request_response_rules.held.matchRequest = ['requestId']; },
    value => { value.schemas.held.required = value.schemas.held.required.filter(key => key !== 'requestId'); },
    value => { value.schemas.lookup_found.properties.requestId.maxLength = 255; },
    value => { value.schemas.held.properties.requestId.type = 'integer'; },
    value => { value.schemas.held.additionalProperties = true; },
  ]) {
    const changed = structuredClone(registry); mutate(changed);
    assert.throws(() => buildClientHostWire(changed, protocol), /InvalidClientHostRequestResponseRule/);
  }
});
