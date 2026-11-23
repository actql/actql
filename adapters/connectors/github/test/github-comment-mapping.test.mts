// The GitHub comment write as a connector declaration: the common runtime
// generates its create Mapping from src/connectors/github/writes.json, and a
// Program that targets it passes Check against the neutral row-source
// environment. Nothing here sends a request.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment, rowSourceMapping} from
  '../../../host-node/installed-row-source.mjs';

type Common = Parameters<typeof import('../host/installed-github-source.mjs').restoreGitHubDeclaration>[0] &
  Parameters<typeof rowSourceMapping>[0] & Readonly<{
    clientProgramCheckEnvironment(wire: string, cid: string, ...flags: readonly boolean[]): unknown;
    clientProgramEffectPreparationReady(outcome: unknown): unknown;
    clientProgramPrepareEffectComputationWithParameters(document: string, format: string, environment: unknown,
      parameters: undefined, evidence: readonly unknown[]): unknown;
  }>;
type Declared = Parameters<typeof rowSourceCheckEnvironment>[1] & Readonly<{manifest_entry_cid: string}>;
const moon = await import(new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href) as Common;
const repository = new URL('../../../../', import.meta.url);
const read = (path: string) => readFile(new URL(path, repository), 'utf8');
const [views, writes, baseWire] = await Promise.all([
  read('src/connectors/github/source-views.json'),
  read('src/connectors/github/writes.json'),
  read('spec/local-check-environment.json').then(wire => wire.trimEnd()),
]);
const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
  'gh-hello', 'github', 'github/0.1', views, undefined));
const declared = JSON.parse(
  moon.clientProgramRowSourceDeclarationJson(declaration)) as Declared;
const sources = [
  {target: 'subject_id', field: 'node_id', null_behavior: 'reject'},
  {target: 'body', field: 'comment', null_behavior: 'reject'}];

const prepare = (mappings: readonly string[]) => {
  const environment = rowSourceCheckEnvironment(baseWire, declared, mappings);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(
    environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  // Raw JSON checker fixture only; no installed Request or execution owner.
  return (request: Readonly<{input: unknown}>) => moon.clientProgramEffectPreparationReady(
    moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(request.input), 'json', checkedEnvironment, undefined, []));
};

const request = (input: unknown) => ({kind: 'program', input, parameters: null});

const commentProgram = (target: string, mapping: string) => ({version: 'actql/0.1',
  id: 'github-comment', stages: [{id: 'source', inputs: {},
    steps: [{values: {schema: {
      node_id: {type: 'string', nullable: false},
      comment: {type: 'string', nullable: false}},
    rows: [{node_id: 'I_1', comment: 'hello'}]}, as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['node_id', 'comment']}},
    effects: {comment: {create: {target, mapping,
      from: {result: 'rows'}}}}}],
  results: {answer: {from: {stage: 'source', result: 'rows'}}}});

test('the declared GitHub comment write yields a Mapping a Program can target',
  () => {
    const mapping = rowSourceMapping(moon, declaration, writes,
      'issue_comments', sources);
    assert.match(mapping.mappingRef,
      /^mapping:gh-hello\/issue_comments\/create-[0-9a-f]{16}\.v1$/u);
    assert.equal(mapping.target, 'connector://gh-hello/issue_comments');
    assert.deepEqual(mapping.writeFields, ['body', 'subject_id']);
    const body = JSON.parse(mapping.body);
    assert.equal(body.connector_manifest_cid, declared.manifest_entry_cid);
    assert.deepEqual(body.permission_rules, [{effect_kind: 'create',
      selector_class: 'none', write_fields: ['body', 'subject_id'],
      permissions: ['github:issues:comment:create']}]);
    assert.equal(body.minimum_approval, 'required');
    assert.deepEqual(body.row_mapping, {
      subject_id: {field: 'node_id', null_behavior: 'reject'},
      body: {field: 'comment', null_behavior: 'reject'}});

    const prepared = prepare([mapping.body])(
      request(commentProgram(mapping.target, mapping.mappingRef)));
    assert.ok(prepared);
    // The read-only environment is unchanged when no Mapping is declared.
    assert.equal(rowSourceCheckEnvironment(baseWire, declared).wire,
      rowSourceCheckEnvironment(baseWire, declared, []).wire);
  });

test('a Program is refused when its Mapping is not declared or not its target',
  () => {
    const mapping = rowSourceMapping(moon, declaration, writes,
      'issue_comments', sources);
    assert.equal(prepare([])(
      request(commentProgram(mapping.target, mapping.mappingRef))), undefined);
    assert.equal(prepare([mapping.body])(
      request(commentProgram('connector://gh-hello/issues',
        mapping.mappingRef))), undefined);
  });

test('undeclared or incomplete writes are refused before any Mapping exists',
  () => {
    const refused = (resource: string, given: readonly unknown[]) => assert.throws(
      () => rowSourceMapping(moon, declaration, writes, resource, given),
      error => typeof (error as {code?: unknown}).code === 'string');
    refused('issues', sources);
    refused('issue_comments', [sources[1]]);
    refused('issue_comments', [...sources,
      {target: 'id', field: 'x', null_behavior: 'reject'}]);
    assert.throws(() => rowSourceMapping(moon, declaration, writes,
      'issues', sources), {code: 'RowSourceMappingNotWritable'});
    assert.throws(() => rowSourceMapping(moon, declaration, writes,
      'issue_comments', [sources[1]]),
    {code: 'RowSourceMappingMissingRequiredField'});
  });
