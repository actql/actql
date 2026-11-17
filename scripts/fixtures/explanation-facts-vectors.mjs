// Independently authored structural DATA. Expected SHA-256 preimages were
// calculated with sorted-key UTF-8 JSON outside the product issuer/codec.
const cid = c => `sha256:${c.repeat(64)}`;
const type = kind => ({projection: 'shape_and_nullability', kind, nullable: false});
const key = {version: 'actql-logical-step-key/0.1', compiled_plan_cid: cid('a'),
  stage_ordinal: 0, occurrence: {kind: 'operation', operation_ordinal: 0},
  self_cid: 'sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8'};
export const explanationBody = {version: 'actql-explanation-facts/0.1',
  disclosure: 'structural', program_definition_cid: cid('c'), parameter_values_cid: cid('d'),
  compiled_plan_cid: cid('a'), logical_map_cid: cid('b'), steps: [{step_id: key.self_cid,
    key, operator: 'filter', input_ports: [cid('e')], output_ports: [cid('f')],
    meaning: {kind: 'filter', predicate: {state: 'projected', root: 0, nodes: [
      {form: 'operation', operator: 'gt', children: [1, 2], type: type('boolean')},
      {form: 'field', scope: 'fields', name: 'id', type: type('number')},
      {form: 'literal_redacted', type: type('number')},
    ]}}}]};
export const explanationCid = 'sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682';
export const explanationFacts = {...explanationBody, self_cid: explanationCid};
export const originalExplanationRun = {namespaceId: 'original-namespace',
  authorityScopeCid: cid('0'), runDefinitionCid: cid('1')};
export const runExplanation = {version: 'actql-run-explanation-view/0.1',
  run_ref: originalExplanationRun, explanation: {state: 'projected', facts: explanationFacts}};
export const unprojectedRunExplanation = {version: 'actql-run-explanation-view/0.1',
  run_ref: originalExplanationRun,
  explanation: {state: 'not_projected', reason: 'not_retained'}};

export const explanationLeakageVectors = [
  ...['value', 'value_cid', 'length', 'byte_length', 'text', 'source', 'prompt'].map(field => {
    const value = structuredClone(explanationFacts);
    value.steps[0].meaning.predicate.nodes[2][field] = field.endsWith('cid') ? cid('2') : 'private';
    return {field: `literal.${field}`, value};
  }),
  ...['max_utf8_bytes', 'max_codepoints', 'enumeration', 'contract_cid'].map(field => {
    const value = structuredClone(explanationFacts);
    value.steps[0].meaning.predicate.nodes[2].type[field] = field.endsWith('cid') ? cid('2') : 17;
    return {field: `type.${field}`, value};
  }),
  ...['prompt', 'source_body', 'can_execute', 'sample'].map(field => ({field,
    value: {...structuredClone(explanationFacts), [field]: 'private'}})),
  {field: 'values.row_count', value: {...structuredClone(explanationFacts), steps: [{
    ...structuredClone(explanationFacts.steps[0]), operator: 'values',
    meaning: {kind: 'values', schema: {fields: []}, row_count: 9},
  }]}},
];
