import './generate-check-reason-catalog.test.mjs';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {buildClientHostWire, nativeProgramSchema} from './generate-client-host-wire.mjs';

const registry = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-client-host.json', import.meta.url), 'utf8'));
const protocol = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-protocol-schemas.json', import.meta.url), 'utf8'));

function withNativeFormatter(body, check) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-wire-format-test-'));
  const originalHome = process.env.MOON_HOME, originalTemp = process.env.TMPDIR;
  mkdirSync(join(directory, 'bin'));
  // The configured temp root can be inside the repository's ESM package.
  // Keep this test executable's CommonJS format explicit in either location.
  writeFileSync(join(directory, 'bin', 'package.json'), '{"type":"commonjs"}\n');
  const report = join(directory, 'calls.jsonl');
  writeFileSync(join(directory, 'bin', 'moonfmt'), `#!${process.execPath}\n` +
    `const {fstatSync, readFileSync, appendFileSync} = require('node:fs');\n` +
    `const assert = require('node:assert/strict');\n` +
    `assert.deepEqual(process.argv.slice(2), ['-']);\n` +
    `assert.equal(fstatSync(0).isFile(), true, 'formatter stdin must be a regular file');\n` +
    `const input = readFileSync(0, 'utf8');\n` +
    `appendFileSync(${JSON.stringify(report)}, JSON.stringify({input, pid: process.pid})+'\\n');\n` + body,
  {mode: 0o700});
  process.env.MOON_HOME = directory;
  process.env.TMPDIR = directory;
  try {
    check(() => readFileSync(report, 'utf8').trim().split('\n').map(JSON.parse));
    assert.deepEqual(readdirSync(directory).sort(), ['bin', 'calls.jsonl']);
  } finally {
    if (originalHome === undefined) delete process.env.MOON_HOME;
    else process.env.MOON_HOME = originalHome;
    if (originalTemp === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = originalTemp;
    rmSync(directory, {recursive: true, force: true});
  }
}

test('Native wire formatter receives complete source through regular-file stdin', () => {
  withNativeFormatter(`process.stdout.write('formatted:'+input);\n`, calls => {
    const output = buildClientHostWire(registry, protocol);
    const inputs = calls();
    assert.equal(inputs.length, 2);
    assert.ok(Buffer.byteLength(inputs[0].input) > 65536);
    assert.equal(output.native, 'formatted:' + inputs[0].input);
    assert.equal(output.nativeTests, 'formatted:' + inputs[1].input);
    assert.match(inputs[0].input, /fn wire_/u);
    assert.match(inputs[1].input, /fn wire_/u);
  });
});

test('Native wire formatter prepares its configured missing temp parent without fallback', () => {
  withNativeFormatter(`process.stdout.write(input);\n`, calls => {
    const originalTemp = process.env.TMPDIR;
    const parent = join(originalTemp, 'not-created', 'parent');
    process.env.TMPDIR = parent;
    try {
      const output = buildClientHostWire(registry, protocol);
      const inputs = calls();
      assert.equal(inputs.length, 2);
      assert.equal(output.native, inputs[0].input);
      assert.equal(output.nativeTests, inputs[1].input);
      assert.deepEqual(readdirSync(parent), []);
      // An invalid configured parent must still refuse, without using another
      // temp root or replacing the existing object.
      const invalid = join(parent, 'regular-file');
      writeFileSync(invalid, 'retained original');
      process.env.TMPDIR = invalid;
      assert.throws(() => buildClientHostWire(registry, protocol), error =>
        ['EEXIST', 'ENOTDIR'].includes(error.code));
      assert.equal(readFileSync(invalid, 'utf8'), 'retained original');
      assert.equal(calls().length, 2);
    } finally {
      process.env.TMPDIR = originalTemp;
      rmSync(join(originalTemp, 'not-created'), {recursive: true, force: true});
    }
  });
});

test('Native wire formatter failure is not replaced by unformatted output', () => {
  withNativeFormatter(`process.stderr.write('selected formatter failure'); process.exit(23);\n`, calls => {
    assert.throws(() => buildClientHostWire(registry, protocol), error =>
      error.status === 23 && error.stderr.includes('selected formatter failure'));
    assert.equal(calls().length, 1);
  });
});

test('Native wire formatter retains its existing deadline and cleans failed input', {timeout: 15000}, () => {
  withNativeFormatter(`setInterval(() => {}, 1000);\n`, calls => {
    assert.throws(() => buildClientHostWire(registry, protocol), error =>
      error.code === 'ETIMEDOUT' && error.signal === 'SIGTERM');
    const [call] = calls();
    assert.throws(() => process.kill(call.pid, 0), {code: 'ESRCH'});
    assert.equal(calls().length, 1);
  });
});

test('Native schema discovery preserves the full registered Program schema', async () => {
  const output = nativeProgramSchema(protocol);
  assert.equal(output, await readFile(new URL(
    '../src/cmd/native_client/program_schema.generated.mbt', import.meta.url), 'utf8'));
  // Decode both string layers, independently of the generation function: the
  // first is the Moon string literal, the second is the original JSON body.
  const literal = output.slice(output.indexOf('-> String {\n  ') + '-> String {\n  '.length, -3);
  const segments = literal.split(' +\n  ');
  assert.ok(segments.length > 1);
  assert.ok(segments.every(segment => segment.length < 32768));
  const actual = JSON.parse(segments.map(segment => JSON.parse(segment)).join(''));
  const original = protocol.artifact_schemas.executable_plan.properties.execution_material.properties.program;
  assert.deepEqual(actual, original);
  assert.equal(actual.$id, 'https://smooth.dev/schemas/actql/0.1.json');
  assert.ok(actual.$defs && actual.properties && actual.allOf);
});

test('Native schema segments preserve Unicode and escaped annotation bytes', () => {
  const changed = structuredClone(protocol);
  const original = changed.artifact_schemas.executable_plan.properties.execution_material.properties.program;
  original.description = ('🧪漢字\\\"\n').repeat(3000);
  const output = nativeProgramSchema(changed);
  const literal = output.slice(output.indexOf('-> String {\n  ') + '-> String {\n  '.length, -3);
  const segments = literal.split(' +\n  ');
  assert.ok(segments.every(segment => segment.length < 32768));
  assert.equal(segments.map(segment => JSON.parse(segment)).join(''), JSON.stringify(original));
});

test('Native schema discovery tracks annotations without changing wire guards', () => {
  const changed = structuredClone(protocol);
  changed.artifact_schemas.executable_plan.properties.execution_material.properties.program
    .description = 'An independently changed schema annotation.';
  assert.notEqual(nativeProgramSchema(changed), nativeProgramSchema(protocol));
  assert.deepEqual(buildClientHostWire(registry, changed), buildClientHostWire(registry, protocol));
  for (const program of [undefined, null, [], false, 'not-a-schema']) {
    const missing = structuredClone(protocol);
    missing.artifact_schemas.executable_plan.properties.execution_material.properties.program = program;
    assert.throws(() => nativeProgramSchema(missing), /MissingProgramSchema/);
  }
  const oversized = structuredClone(protocol);
  oversized.artifact_schemas.executable_plan.properties.execution_material.properties.program
    .description = 'x'.repeat(1048576);
  assert.throws(() => nativeProgramSchema(oversized), /NativeProgramSchemaOutputLimit/);
});

test('optional request fields are closed projections of the registered operation', async () => {
  const {validClientBody} = await import('../packages/client-wire/index.mjs');
  const body = {connection: {mode: 'local', owner: 'local', consentRefs: [], runners: []}, requestId: 'original',
    kind: 'program', input: {}, parameters: null};
  assert.equal(validClientBody('submit', body), true);
  assert.equal(validClientBody('submit', {...body, stopBefore: 'commit'}), true);
  assert.equal(validClientBody('submit', {...body, readOnly: true}), true);
  assert.equal(validClientBody('submit', {...body, readOnly: true, stopBefore: 'commit'}), true);
  for (const readOnly of [undefined, false, null, 'true', 1, {}, []]) {
    assert.equal(validClientBody('submit', {...body, readOnly}), false);
  }
  for (const key of ['readonly', 'read_only', 'queryOnly']) {
    assert.equal(validClientBody('submit', {...body, [key]: true}), false);
  }
  for (const stopBefore of [undefined, null, '', 'prepare', false, 1, {}, ['commit']]) {
    assert.equal(validClientBody('submit', {...body, stopBefore}), false);
  }
  assert.equal(validClientBody('submit', {...body, stopBefore: 'commit', extra: 1}), false);
  assert.equal(validClientBody('status', {connection: body.connection, stopBefore: 'commit'}), false);
  const output = buildClientHostWire(registry, protocol);
  const changed = structuredClone(registry);
  changed.request_optional_fields.submit.stopBefore.const = 'independent-mutated-stop';
  assert.notEqual(buildClientHostWire(changed, protocol).module, output.module);
  for (const mutate of [
    value => {delete value.request_optional_fields;},
    value => {value.request_optional_fields = null;},
    value => {value.request_optional_fields.unknown = {stopBefore: {const: 'commit'}};},
    value => {value.request_optional_fields.submit.parameters = {const: null};},
    value => {value.request_optional_fields.submit = [];},
  ]) {
    const bad = structuredClone(registry); mutate(bad);
    assert.throws(() => buildClientHostWire(bad, protocol), /InvalidClientHostOptionalFields/);
  }
});

test('generated Client–Host guards and types match the machine contract',
  async () => {
    const outputs = buildClientHostWire(registry, protocol);
    assert.equal(outputs.module, await readFile(new URL(
      '../packages/client-wire/client-host.generated.js', import.meta.url),
    'utf8'));
    assert.equal(outputs.native, await readFile(new URL(
      '../src/cmd/native_client/wire.generated.mbt', import.meta.url), 'utf8'));
    assert.equal(outputs.nativeTests, await readFile(new URL(
      '../src/cmd/native_client/wire_owner_observations.generated_wbtest.mbt', import.meta.url), 'utf8'));
    assert.equal(outputs.types, await readFile(new URL(
      '../packages/client-wire/client-host.generated.d.ts', import.meta.url),
    'utf8'));
    assert.equal(outputs.checkpointAnswers, await readFile(new URL(
      '../packages/sdk/internal/checkpoint-answer-contract.generated.mjs', import.meta.url), 'utf8'));
    assert.equal(outputs.runWait, await readFile(new URL(
      '../src/run_publication/run_wait.generated.mbt', import.meta.url), 'utf8'));
  });

test('SDK answer grammar projects existing Resolution and Evidence without changing other targets', async () => {
  const original = buildClientHostWire(registry, protocol);
  const changed = structuredClone(protocol);
  changed.artifact_schemas.checkpoint_resolution.properties.decision.enum = ['rejected'];
  const result = buildClientHostWire(registry, changed);
  assert.notEqual(result.checkpointAnswers, original.checkpointAnswers);
  for (const key of ['module', 'types', 'native', 'nativeTests', 'runWait']) {
    assert.equal(result[key], original[key], key);
  }
  const guard = await import('data:text/javascript;base64,' + Buffer.from(original.checkpointAnswers).toString('base64'));
  assert.equal(guard.validAnswerResolution({}), false);
  const evidence = JSON.parse(await readFile(new URL(
    '../portability/corpus/checkpoint-resolution-signatures.json', import.meta.url), 'utf8'));
  const resolution = evidence.cases.find(value => value.kind === 'checkpoint_resolution').artifact;
  assert.equal(guard.validAnswerResolution(resolution), true);
  assert.equal(guard.validAnswerResolution({...resolution, extra: true}), false);
  assert.equal(guard.validAnswerResolution({...resolution, prepare_attempt_id: 'foreign'}), false);
});

test('Native observation-only guards remain tested without adding a CLI operation', () => {
  const output = buildClientHostWire(registry, protocol);
  assert.doesNotMatch(output.native, /fn wire_owner_observations_shape\(/u);
  assert.match(output.nativeTests, /fn wire_owner_observations_shape\(/u);
  const changed = structuredClone(registry);
  changed.schemas.owner_observations.properties.owners.maxItems = 4;
  assert.notEqual(buildClientHostWire(changed, protocol).nativeTests, output.nativeTests);
  assert.equal(buildClientHostWire(changed, protocol).native, output.native);
});

test('Native string predicates discard only payloads without text constraints', () => {
  const probeRule = output => {
    const name = /fields\.get\("generator_probe"\) is Some\(item\) \{\s+if !(wire_rule_\d+)\(item\)/u
      .exec(output.nativeTests)?.[1];
    assert.ok(name, 'the selected property must invoke its generated predicate');
    return output.nativeTests.split(`fn ${name}(value : Json) -> Bool {`)[1]
      .split('\n///|')[0];
  };
  const changed = structuredClone(registry);
  changed.schemas.owner_ref.properties.generator_probe = {type: 'string'};
  const bare = buildClientHostWire(changed, protocol);
  assert.equal(probeRule(bare),
    '\n  guard value is String(_) else { return false }\n  true\n}\n');
  changed.schemas.owner_ref.properties.generator_probe = {
    type: 'string', minLength: 137, maxLength: 139,
  };
  const bounded = buildClientHostWire(changed, protocol);
  assert.equal(probeRule(bounded),
    '\n  guard value is String(text) else { return false }\n' +
    '  if text.iter().count() < 137 {\n    return false\n  }\n' +
    '  if text.length() > 139 {\n    return false\n  }\n  true\n}\n');
  assert.equal(bare.native, bounded.native,
    'an observation-only string rule cannot alter production guards');
  // Literal equality remains an independent check even when the redundant
  // string-kind guard does not need to retain the payload a second time.
  changed.schemas.owner_ref.properties.generator_probe = {
    type: 'string', const: 'independent-probe',
  };
  const literal = buildClientHostWire(changed, protocol);
  assert.match(probeRule(literal), /text == "independent-probe"/u);
  assert.match(probeRule(literal), /guard value is String\(_\)/u);
});

test('Native cancellation shapes retain each registered operation boundary', () => {
  const original = buildClientHostWire(registry, protocol).native;
  for (const name of ['cancellation_ref', 'cancellation', 'cancellation_lookup']) {
    assert.match(original, new RegExp(`fn wire_${name}_shape\\(`));
    const changed = structuredClone(registry);
    const branch = name === 'cancellation_lookup'
      ? changed.schemas[name].oneOf[1] : changed.schemas[name];
    const reference = name === 'cancellation_ref' ? branch : branch.properties.cancelRef;
    reference.properties.cancelId.maxLength = 255;
    assert.notEqual(buildClientHostWire(changed, protocol).native, original,
      `Native freshness includes ${name}, independently of JavaScript output`);
  }
});

test('received check report rules are complete for both generated consumers', () => {
  const output = buildClientHostWire(registry, protocol);
  assert.match(output.module, /export const validCheckOutcomeContract/);
  assert.match(output.native, /if !wire_check_report_contract\(value\)/);
  for (const change of [
    value => {delete value.check_report_rules;},
    value => {value.check_report_rules.pop();},
    value => {value.check_report_rules.push('future_rule');},
    value => {value.check_report_rules[1] = value.check_report_rules[0];},
  ]) {
    const changed = structuredClone(registry); change(changed);
    assert.throws(() => buildClientHostWire(changed, protocol), /InvalidClientCheckReportRules/);
  }
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
    // Public finite fact numbers do not change Native's integer control limits.
    assert.throws(() => buildClientHostWire(changed, protocol),
      /UnsupportedNativeWireConstraintType:integer/);
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
      verdict: 'verified', reasons: [], coverage: {limits: [], unresolved: []},
      runnable: {verdict:'no', reasons:[{code:'analysis_budget_exhausted'}]}};
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
      runnable: {verdict:'no', reasons:[{code:'analysis_budget_exhausted'}]},
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

test('check protocol discriminants derive from the registered schema without another validator', async () => {
  const {checkOutcomeProtocol} = await import('../packages/client-wire/index.mjs');
  assert.deepEqual(checkOutcomeProtocol, {version: 'actql-check-outcome/0.1',
    reasonSchemaCid: protocol.artifact_schema_cids.check_reason,
    outcomeSchemaCid: protocol.artifact_schema_cids.check_outcome,
    outcomes: ['completed', 'failed', 'unavailable']});
  assert.equal(Object.isFrozen(checkOutcomeProtocol.outcomes), true);
  const changed = structuredClone(protocol);
  const additional = structuredClone(changed.artifact_schemas.check_outcome.oneOf[0]);
  additional.properties.outcome.const = 'future_fixture';
  changed.artifact_schemas.check_outcome.oneOf.push(additional);
  const generated = buildClientHostWire(registry, changed);
  const future = await import('data:text/javascript;base64,' + Buffer.from(generated.module).toString('base64'));
  assert.deepEqual(future.checkOutcomeProtocol.outcomes, ['completed', 'failed', 'unavailable', 'future_fixture']);
  additional.properties.version.const = 'different_fixture';
  assert.throws(() => buildClientHostWire(registry, changed), /InvalidCheckOutcomeDiscriminants/);
});

test('Requirement fact identities require a coherent checked-contract and catalog update', async () => {
  const {applyCheckOutcomeSchema, checkOutcomeSchema} = await import('./check-outcome-contract.mjs');
  const {readCheckReasonCatalog, checkReasonSchemaFromCatalog} = await import('./check-reason-catalog.mjs');
  const {machineCid} = await import('./actql-spec-family.mjs');
  const changed = structuredClone(protocol);
  changed.schemas.canonical_value_contract.title += '-independent-fixture';
  assert.throws(() => applyCheckOutcomeSchema(changed), /StaleCheckReasonParameterContractSchema/);
  // The owned catalog is the reason-schema source. An intentional schema
  // change must update that explicit reference too; generation cannot hide it.
  const catalog = readCheckReasonCatalog();
  const pin = machineCid(changed.schemas.canonical_value_contract);
  for (const facts of catalog.reason_schema.properties.facts.oneOf) {
    if (facts.properties.admission) facts.properties.admission.properties.contract_schema_cid.const = pin;
  }
  changed.artifact_schemas.check_reason = checkReasonSchemaFromCatalog(catalog, pin);
  changed.artifact_schemas.check_outcome = checkOutcomeSchema(changed.artifact_schemas.check_reason);
  for (const name of ['check_reason', 'check_outcome']) {
    changed.artifact_schema_cids[name] = machineCid(changed.artifact_schemas[name]);
    assert.notEqual(changed.artifact_schema_cids[name], protocol.artifact_schema_cids[name]);
  }
  assert.notEqual(buildClientHostWire(registry, changed).module, buildClientHostWire(registry, protocol).module);
});

test('Run observation vocabulary derives from the registered state schema', async () => {
  const expected = ['preparing', 'running', 'waiting_checkpoint', 'resuming',
    'needs_reconciliation', 'succeeded', 'failed', 'cancelled'];
  const wire = await import('../packages/client-wire/index.mjs');
  assert.deepEqual(wire.runStateProtocol, {version: 'actql-run-state/0.1', statuses: expected});
  assert.ok(Object.isFrozen(wire.runStateProtocol.statuses));
  const future = structuredClone(protocol);
  future.artifact_schemas.run_state.properties.status.enum.push('future_state');
  assert.match(buildClientHostWire(registry, future).module, /"cancelled","future_state"/);
  future.artifact_schemas.run_state.properties.status.enum.push('future_state');
  assert.throws(() => buildClientHostWire(registry, future), /InvalidRunStateDiscriminants/);
});

test('wait correlation and Common projection follow the same registered rule', async () => {
  const original = buildClientHostWire(registry, protocol);
  const changed = structuredClone(registry);
  changed.request_response_rules.run_wait.stableStatuses.pop();
  const projected = buildClientHostWire(changed, protocol);
  assert.notEqual(projected.runWait, original.runWait);
  assert.notEqual(projected.module, original.module);
  assert.equal(projected.native, original.native,
    'the remote CLI does not issue the physical wait observation');
  for (const mutate of [
    value => { delete value.request_response_rules.run_wait; },
    value => { value.request_response_rules.run_wait.stableStatuses.push('future'); },
    value => { value.request_response_rules.run_wait.stableStatuses.push('failed'); },
    value => { value.request_response_rules.run_wait.revisionField = 'control'; },
  ]) {
    const invalid = structuredClone(registry); mutate(invalid);
    assert.throws(() => buildClientHostWire(invalid, protocol), /InvalidClientHostRequestResponseRule/);
  }
});


test('text Program envelopes have no independent 65536 UTF-16 ceiling', async () => {
  const {validClientBody, snapshotClientRequest} = await import('../packages/client-wire/index.mjs');
  const connection = {mode: 'local', owner: 'local', consentRefs: [], runners: []};
  for (const length of [65535, 65536, 65537]) {
    for (const text of ['x'.repeat(length), '日'.repeat(length),
      '😀'.repeat(Math.floor(length / 2)) + (length % 2 ? 'x' : ''),
      '\n'.repeat(length)]) {
      assert.equal(text.length, length);
      const input = {text, format: 'sql'};
      assert.equal(validClientBody('submit', {connection, requestId: 'text-demand',
        kind: 'aql', input, parameters: null}), true);
      assert.equal(validClientBody('check', {connection, scope: 'template_only',
        kind: 'text', input}), true);
      assert.equal(snapshotClientRequest({input}).input.text, text);
    }
  }
  for (const text of ['', 'a\0b']) {
    assert.equal(validClientBody('submit', {connection, requestId: 'invalid',
      kind: 'aql', input: {text, format: 'sql'}, parameters: null}), false);
    assert.equal(validClientBody('check', {connection, scope: 'template_only',
      kind: 'text', input: {text, format: 'sql'}}), false);
  }
  assert.throws(() => snapshotClientRequest({input: {text: 'x'.repeat(65537)},
    parameters: {value: Number.POSITIVE_INFINITY}}), /UnrepresentableClientNumber/);
});
