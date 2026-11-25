// Meaning definitions for the existing interactive protocol registry. This is
// not another identity registry or an expression parser. The compiler alone
// issues and binds facts; shape admission conveys no provenance or permission.
import type {project} from './generate-client-publication-wire.mjs';

type Schema = ReturnType<typeof project>;

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'} satisfies Schema;
const text = {type: 'string', minLength: 1} satisfies Schema;
const integer = {type: 'integer', minimum: 0, maximum: 2147483647} satisfies Schema;
const choice = (...values: string[]): Schema => ({type: 'string', enum: values});
const list = (items: Schema): Schema => ({type: 'array', items, minItems: 0});
const ref = (name: string) => ({$ref: `#/schemas/${name}`});
const object = <Fields extends Record<string, Schema>>(properties: Fields) => ({type: 'object' as const, additionalProperties: false,
  required: Object.keys(properties), properties});

// This finite first projection is not the language's supported-expression set.
// Other checked forms remain explicitly unprojected, not language refusals.
export const explanationPredicateOperators = Object.freeze([
  'and', 'or', 'not', 'eq', 'neq', 'lt', 'lte', 'gt', 'gte',
  'is_null', 'not_null', 'is_distinct_from',
]);

export function explanationFactSchemas({logicalOperators, effectDeclaration}: Readonly<{
  logicalOperators: readonly string[]; effectDeclaration: Schema;
}>): Record<string, Schema> {
  const schemas: Record<string, Schema> = {};
  // Inferred Text limits can reveal a literal's UTF-8 length. Do not serialize
  // bounds, enumerations or a contract/value CID as a supposedly safe type.
  // The projection explicitly describes shape/nullability, not a full contract.
  schemas.explanation_type = object({projection: {const: 'shape_and_nullability'},
    kind: choice('string', 'number', 'boolean', 'timestamp', 'date', 'json',
      'decimal', 'array', 'object', 'vector', 'resource_ref', 'content_ref', 'int64'),
    nullable: {type: 'boolean'}});
  schemas.explanation_schema = object({fields: list(object({name: text,
    presence: choice('required', 'conditional'), type: ref('explanation_type')}))});
  schemas.explanation_expression_node = {oneOf: [
    object({form: {const: 'literal_redacted'}, type: ref('explanation_type')}),
    object({form: {const: 'field'}, scope: choice('fields', 'left', 'right'),
      name: text, type: ref('explanation_type')}),
    object({form: {const: 'parameter'}, name: text, type: ref('explanation_type')}),
    object({form: {const: 'operation'}, operator: choice(...explanationPredicateOperators),
      children: list(integer), type: ref('explanation_type')}),
  ]};
  schemas.explanation_predicate = {oneOf: [
    object({state: {const: 'projected'}, root: {const: 0},
      nodes: {...list(ref('explanation_expression_node')), minItems: 1}}),
    object({state: {const: 'not_projected'}, reason: {const: 'expression_form_not_projected'}}),
  ]};
  schemas.explanation_meaning = {oneOf: [
    object({kind: {const: 'input_output'}}),
    // Authored VALUES row count is still a literal collection's cardinality;
    // the structural-only public profile deliberately excludes it and rows.
    object({kind: {const: 'values'}, schema: ref('explanation_schema')}),
    object({kind: {const: 'filter'}, predicate: ref('explanation_predicate')}),
    object({kind: {const: 'projection'}, operation: choice('select', 'rename', 'drop'),
      fields: list(object({input: text, output: text}))}),
    object({kind: {const: 'join'}, join_kind: choice('inner', 'left', 'right', 'full', 'semi', 'anti'),
      null_key: choice('no_match', 'fail'), keys: list(object({left: text, right: text}))}),
    object({kind: {const: 'not_projected'}, reason: {const: 'operation_facts_not_projected'}}),
  ]};
  schemas.explanation_step = object({step_id: cid, key: ref('logical_step_key'),
    operator: {oneOf: [{type: 'null'}, choice(...logicalOperators)]},
    input_ports: list(cid), output_ports: list(cid), meaning: ref('explanation_meaning')});
  schemas.explanation_facts = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-explanation-facts-0.1.json',
    ...object({version: {const: 'actql-explanation-facts/0.1'},
      disclosure: {const: 'structural'},
      program_definition_cid: cid, parameter_values_cid: cid,
      compiled_plan_cid: cid, logical_map_cid: cid,
      steps: list(ref('explanation_step')), self_cid: cid}),
  };
  // Like the existing Run Plan view, this binds an existing original Run, not
  // a new identity domain. Old/Normal Runs cannot be repaired by compilation.
  schemas.run_explanation_view = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-run-explanation-view-0.1.json',
    ...object({version: {const: 'actql-run-explanation-view/0.1'},
      run_ref: {$ref: 'actql-client-host.json#/schemas/run_ref'},
      explanation: {oneOf: [
        object({state: {const: 'projected'}, facts: ref('explanation_facts')}),
        object({state: {const: 'not_projected'}, reason: choice('not_retained', 'profile_not_supported')}),
      ]}}),
  };
  const consumer = object({step_id: cid, port_id: cid});
  const producer: Schema = {oneOf: [
    object({state: {const: 'projected'}, step_id: cid, port_id: cid}),
    object({state: {const: 'not_projected'}, reason: {const: 'no_original_port'}}),
  ]};
  const modelBinding: Schema = {oneOf: [
    object({state: choice('field', 'parameter'), name: text}),
    object({state: {const: 'redacted'}}),
    object({state: {const: 'not_projected'}, reason: {const: 'expression_form_not_projected'}}),
  ]};
  const declaredWrites = object({state: {const: 'declared'}, fields: {...list(text), uniqueItems: true}});
  const unprojectedCommand = object({state: {const: 'not_projected'},
    reason: {const: 'command_fields_not_projected'}});
  const member: Schema = {...object({declaration: effectDeclaration,
    write_fields: {oneOf: [declaredWrites, unprojectedCommand]}}),
    allOf: [{if: {type: 'object', required: ['declaration'], properties: {
      declaration: {type: 'object', required: ['effect_kind'],
        properties: {effect_kind: {const: 'command'}}},
    }},
    then: {type: 'object', properties: {write_fields: unprojectedCommand}},
    else: {type: 'object', properties: {write_fields: declaredWrites}}}]};
  const item: Schema = {oneOf: [
    {...object({kind: {const: 'source'}, stage_input: object({kind: {const: 'stage_input'},
      stage_ordinal: integer, input_port_ordinal: integer}),
      source_view: object({catalog_cid: cid, connector: text, contract_cid: cid,
        resource: text, selection: choice('explicit', 'sole_view'), view: text}),
      request_kind: choice('direct', 'keyed'), link_state: choice('linked', 'not_projected'),
      consuming_ports: list(consumer)}),
      allOf: [{if: {type: 'object', properties: {link_state: {const: 'linked'}}, required: ['link_state']},
        then: {type: 'object', properties: {consuming_ports: {...list(consumer), minItems: 1}}},
        else: {type: 'object', properties: {consuming_ports: {...list(consumer), maxItems: 0}}}}]},
    object({kind: {const: 'model_task'}, task_id: text, task_version: text, contract_cid: cid,
      dispatch_unit: {const: 'input_row'}, producer,
      input_bindings: list(object({role: text, binding: modelBinding, type: ref('explanation_type')})),
      output_fields: list(object({name: text, type: ref('explanation_type')}))}),
    object({kind: {const: 'result'}, name: text, stage_ordinal: integer, producer}),
    object({kind: {const: 'effect_set'}, unit_id: text,
      members: {...list(member), minItems: 1, maxItems: 64}}),
  ]};
  schemas.explanation_context = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-explanation-context-0.1.json',
    ...object({version: {const: 'actql-explanation-context/0.1'}, disclosure: {const: 'structural'},
      binding: object({program_definition_cid: cid, parameter_values_cid: cid,
        check_environment_cid: cid, compiled_plan_cid: cid, logical_map_cid: cid}),
      items: list(item)}),
  };
  // A transport envelope around the original Plan and its two facets. Its
  // references share the Plan and Map binding; the reader checks that binding.
  const explanationView = (plan: Schema) => object({version: {const: 'actql-static-explanation/0.1'},
    plan, facts: ref('explanation_facts'), context: ref('explanation_context')});
  schemas.static_explanation_view = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-static-explanation-0.1.json',
    ...explanationView({oneOf: [ref('plan_view'), ref('effectful_static_plan_view')]}),
  };
  schemas.run_explanation_context_view = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-run-explanation-context-view-0.1.json',
    ...object({version: {const: 'actql-run-explanation-context-view/0.1'},
      run_ref: {$ref: 'actql-client-host.json#/schemas/run_ref'},
      explanation: {oneOf: [
        object({state: {const: 'projected'}, view: explanationView(ref('plan_view'))}),
        object({state: {const: 'not_projected'}, reason: {const: 'not_retained'}}),
      ]}}),
  };
  return schemas;
}
