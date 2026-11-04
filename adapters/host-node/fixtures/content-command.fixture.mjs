// Independently authored Source and Command declaration shared by actual
// compilation and public physical acceptance. Programs contain no Ref envelopes.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const commonRuntime = process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME
  ? pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME)
  : new URL('../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const moon = await import(commonRuntime);
export {moon};
import {checked} from '../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../installed-row-source.mjs';
import {canonical, cid} from './file-listing-source.fixture.mjs';
const baseWire = await readFile(new URL('../../../spec/local-check-environment.json', import.meta.url), 'utf8');
export function contentCommandFixture({contentMime = 'application/pdf',
  inputMime = 'application/pdf', targetKind = 'file', classification = 'unknown',
  baseEnvironmentWire = baseWire.trimEnd()} = {}) {
  const schema = {
    content: {type: 'content_ref', media_type: contentMime, nullable: false},
    destination: {type: 'resource_ref', resource_kind: 'file', nullable: false},
    name: {type: 'string', nullable: false},
  };
  const declarationViewsWire = JSON.stringify({views: [{
      resource: 'transfers', resource_kind: 'file', schema_wire: canonical(schema),
      schema_cid: cid(schema), facts_wire: '{}', data_classification: classification,
    }]});
  const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    'content-fixture', 'fixture', 'fixture/0.1', declarationViewsWire, undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const sourceEnvironment = rowSourceCheckEnvironment(baseEnvironmentWire, declared);
  const {evidence_bundle_cid: _, ...environmentBody} = JSON.parse(sourceEnvironment.wire);
  const role = (kind, contract) => {
    const body = {schema: 'actql.contract/0.1', id: `fixture.${kind}`,
      version: 'external', kind, body: contract};
    return {...body, cid: cid(body)};
  };
  const fields = {
    content: {type: 'content_ref', media_type: inputMime, nullable: false},
    name: {type: 'string', nullable: false},
  };
  const input = role('command_input', {type: 'object', nullable: false,
    additional_properties: false, fields});
  const output = role('command_output', {type: 'object', nullable: false,
    additional_properties: false, fields: {}});
  const reference = value => ({id: value.id, version: value.version, cid: value.cid});
  const commandBody = {schema: 'actql.command_contract/0.1',
    command_id: 'command:files.upload.v1', connector_id: 'content-fixture',
    version: 'fixture', target: {resource_kind: targetKind, cardinality: 'single'},
    input_schema: reference(input), output_schema: reference(output),
    input_contract: {additional_properties: false, fields},
    permissions: ['files.write'],
    preview: {strength: 'exact'}, outcome: 'synchronous',
    idempotency: {support: 'unsupported'}, reversibility: 'unknown',
    atomicity: 'single_target'};
  const command = {...commandBody, contract_cid: cid(commandBody)};
  const {catalog_cid: __, ...catalogBody} = environmentBody.connector_catalogs[0];
  catalogBody.commands = [command];
  catalogBody.contracts = [...catalogBody.contracts, input, output]
    .sort((left, right) => left.cid.localeCompare(right.cid));
  environmentBody.connector_catalogs = [{...catalogBody, catalog_cid: cid(catalogBody)}];
  environmentBody.command_contracts = [command];
  environmentBody.contract_registry = [...environmentBody.contract_registry, input, output]
    .sort((left, right) => cid(left).localeCompare(cid(right)));
  const environmentCid = cid(environmentBody);
  const environmentWire = canonical({...environmentBody, evidence_bundle_cid: environmentCid});
  const environment = moon.clientProgramCheckEnvironment(
    environmentWire,
    environmentCid, false, false, true, false, false, false, false);
  assert.ok(environment, 'the independently authored Catalog is wire-admitted');
  const program = {version: 'actql/0.1', id: 'content-command-plan', stages: [{
    id: 'capture', inputs: {transfers: {connector: 'content-fixture', resource: 'transfers', view: 'records'}},
    steps: [{from: 'transfers', filter: 'name IS NOT NULL', as: 'matching'},
      {from: 'matching', select: ['destination', 'name', 'content'], as: 'selected'}],
    results: {r: {from: 'selected', fields: ['destination', 'name', 'content']}},
  }, {
    id: 'save', inputs: {transfers: {result: {stage: 'capture', result: 'r'}}},
    steps: [{from: 'transfers', select: ['destination', 'name', 'content'], as: 'selected'}],
    results: {r: {from: 'selected', fields: ['destination', 'name', 'content']}},
    effects: {upload: {command: {from: {result: 'r'},
      target: {field: 'destination'}, contract: 'command:files.upload.v1',
      input: {name: {field: 'name'}, content: {field: 'content'}}}}},
  }], results: {r: {from: {stage: 'save', result: 'r'}}}};
  return {program, environment, environmentWire, command, declaration, declarationViewsWire, declared, schema,
    commandContracts: Object.freeze([canonical(input), canonical(output)]),
    commandCatalogCid: environmentBody.connector_catalogs[0].catalog_cid};
}

// Generation and destination acquisition are distinct checked dependencies.
// The original destination Ref is joined back by name; SERIALIZE does not
// invent a Resource, carry unrelated input fields, or authorize an upload.
export function generatedContentCommandProgram({preserveOrder = false,
  retainSerializationMetadata = false, exposeAttachmentResult = false} = {}) {
  const program = {version: 'actql/0.1', id: 'generated-content-command', stages: [{
    id: 'capture', inputs: {
      transfers: {connector: 'content-fixture', resource: 'transfers', view: 'records'},
    }, steps: [
      {from: 'transfers', filter: 'name IS NOT NULL', as: 'matching'},
      {select: ['destination', 'name'], as: 'destinations'},
    ], results: {r: {from: 'destinations', fields: ['destination', 'name']}},
  }, {
    id: 'save', inputs: {
      transfers: {result: {stage: 'capture', result: 'r'}},
    }, steps: [
      {from: 'transfers', select: ['name'], as: 'names'},
      {assert_rows: {unique_by: ['name']}, as: 'unique_names'},
      ...(preserveOrder ? [{sort: [{name: 'asc'}], as: 'ordered_names'}] : []),
      {serialize: {format: 'csv', fields: ['name'], name: 'approved.csv',
        header: true, null_marker: '\\N',
        ...(preserveOrder ? {preserve_order: true} : {order_by: [{name: 'asc'}]}),
        bounds: {max_rows: 1, max_bytes: 32}}, as: 'attachment'},
      {from: 'attachment', join: {with: 'transfers', kind: 'inner',
      on: [{left: 'name', right: 'name'}], max_output_rows: 1,
      select: {destination: 'right.destination', name: 'left.name', content: 'left.content'}},
      as: 'selected'}],
    results: {r: {from: 'selected', fields: ['destination', 'name', 'content']}},
    effects: {upload: {command: {from: {result: 'r'},
      target: {field: 'destination'}, contract: 'command:files.upload.v1',
      input: {name: {field: 'name'}, content: {field: 'content'}}}}},
  }], results: {r: {from: {stage: 'save', result: 'r'}}}};
  if (exposeAttachmentResult) {
    program.stages[1].results.attachment = {from: 'attachment',
      fields: ['name', 'content', 'media_type', 'size_bytes', 'row_count']};
    program.results.attachment = {from: {stage: 'save', result: 'attachment'}};
  }
  if (retainSerializationMetadata) {
    // Preserve every SERIALIZE field through the real ordinary JOIN and
    // terminal Result. Command inputs remain exactly name/content.
    const save = program.stages[1];
    for (const field of ['media_type', 'size_bytes', 'row_count']) {
      save.steps.at(-1).join.select[field] = `left.${field}`;
      save.results.r.fields.push(field);
    }
  }
  return program;
}

// This is an independently authored text workflow, not a rendering of the JSON
// fixture. DATA aliases reuse the admitted Source through the ordinary lowerer.
export function generatedContentCommandSource({preserveOrder = false, format = 'text'} = {}) {
  const destination = 'FROM files.transfers |> WHERE name IS NOT NULL |> SELECT destination, name';
  const attachment = String.raw`FROM destinations |> SELECT name |> ASSERT UNIQUE BY (name)
    ${preserveOrder ? '|> ORDER BY name' : ''}
    |> SERIALIZE FORMAT CSV ${preserveOrder ? 'PRESERVE ORDER' : 'ORDER BY name'}
       OPTIONS (name = 'approved.csv', header = TRUE, null_marker = r'\N',
                max_rows = 1, max_bytes = 32)`;
  return `WITH destinations AS (${destination}), attachment AS (${attachment}) ` +
    String.raw`SELECT d.destination AS destination, a.name AS name, a.content AS content
    FROM attachment AS a JOIN destinations AS d ON a.name = d.name MAX_OUTPUT_ROWS 1
    |> RESULT r;
  EFFECT upload COMMAND FROM RESULT r AS t TARGET t.destination
    CONTRACT ${'`command:files.upload.v1`'} INPUT (name = t.name, content = t.content);`;
}

// The installed Source supplies a currently issued reference to physical Store
// bytes. This authored text never creates a reference envelope or regenerates
// the content; it uses the same checked COMMAND postlude as generated Content.
export function contentCommandSource({format = 'sql'} = {}) {
  const query = format === 'sql'
    ? 'SELECT destination, name, content FROM files.transfers WHERE name IS NOT NULL'
    : 'FROM files.transfers |> WHERE name IS NOT NULL |> SELECT destination, name, content';
  return `${query} |> RESULT r;
EFFECT upload COMMAND FROM RESULT r AS t TARGET t.destination
  CONTRACT \`command:files.upload.v1\` INPUT (name = t.name, content = t.content);`;
}

// One authored Program captures, generates, evaluates the actual Content and
// then asks for its Command approval. The Model output is not an upload grant.
export function generatedContentModelCommandProgram() {
  const program = generatedContentCommandProgram();
  program.id = 'generated-content-model-command';
  const classify = program.stages[1];
  classify.id = 'classify';
  delete classify.effects;
  classify.steps.splice(3);
  classify.steps.push(
    {assert_rows: {unique_by: ['name']}, as: 'unique_attachment'},
    {infer: {contract: 'model-task:risk-score.v1', key: 'name',
      input: {document: {field: 'content'}}}, as: 'classified'},
    {join: {with: 'attachment', kind: 'inner', cardinality: 'one_to_one', on: 'name',
      select: {name: 'left.name', outcome: 'left.outcome', value: 'left.value',
        content: 'right.content'}}, as: 'retained'},
  );
  classify.results = {r: {from: 'retained', fields: ['name', 'outcome', 'value', 'content']}};
  program.stages.push({id: 'save', inputs: {
    classified: {result: {stage: 'classify', result: 'r'}},
    transfers: {result: {stage: 'capture', result: 'r'}},
  }, steps: [{from: 'classified', join: {with: 'transfers', kind: 'inner',
    on: [{left: 'name', right: 'name'}], max_output_rows: 1,
    select: {destination: 'right.destination', name: 'left.name', content: 'left.content'}},
    as: 'selected'}],
  results: {r: {from: 'selected', fields: ['destination', 'name', 'content']}},
  effects: {upload: {command: {from: {result: 'r'}, target: {field: 'destination'},
    contract: 'command:files.upload.v1',
    input: {name: {field: 'name'}, content: {field: 'content'}}}}}});
  return program;
}

