// Meaning definitions for the existing interactive protocol registry. This is
// not another identity registry or an expression parser. The compiler alone
// issues and binds facts; shape admission conveys no provenance or permission.
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
const integer = {type: 'integer', minimum: 0, maximum: 2147483647};
const choice = (...values) => ({type: 'string', enum: values});
const list = items => ({type: 'array', items, minItems: 0});
const ref = name => ({$ref: `#/schemas/${name}`});
const object = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});

// This finite first projection is not the language's supported-expression set.
// Other checked forms remain explicitly unprojected, not language refusals.
export const explanationPredicateOperators = Object.freeze([
  'and', 'or', 'not', 'eq', 'neq', 'lt', 'lte', 'gt', 'gte',
  'is_null', 'not_null', 'is_distinct_from',
]);

export function explanationFactSchemas({logicalOperators}) {
  const schemas = {};
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
  return schemas;
}
