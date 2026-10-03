// Authored from the adopted INFER output contract, not compiler/reader output.
export const source = "SELECT DISTINCT 'ticket-1' AS id " +
  "|> EXTEND 'urgent' AS text " +
  "|> INFER `model-task:packed-risk.v1` ITEM KEY (id) " +
  'INPUT (text = text) AS assessment';
export const expectedRows = [{assessment: {
  input_key: {id: 'ticket-1'}, outcome: 'ok',
  value: {reason: null, risk: 'high'},
}}];
// Literal id has an eight-byte bound; outcome is the common unbounded String
// contract. The ModelTask's closed object is nullable in outcomes publication.
export const expectedColumns = [{name: 'assessment', contract: {
  type: 'object', nullable: false, additional_properties: false, fields: {
    input_key: {type: 'object', nullable: false,
      additional_properties: false, fields: {
        id: {type: 'string', nullable: false, max_utf8_bytes: 8},
      }},
    outcome: {type: 'string', nullable: false},
    value: {type: 'object', nullable: true, additional_properties: false,
      fields: {reason: {type: 'string', nullable: true},
        risk: {type: 'string', nullable: false}}},
  },
}}];

const prefix = "SELECT DISTINCT 'ticket-1' AS id |> EXTEND 'urgent' AS text";
const infer = '|> INFER `model-task:packed-risk.v1` ITEM KEY (id) INPUT (text = text)';
const keptColumns = [
  {name: 'id', contract: {type: 'string', nullable: false, max_utf8_bytes: 8}},
  {name: 'note', contract: {type: 'string', nullable: false, max_utf8_bytes: 6}},
  ...expectedColumns,
];
const keptRows = [{id: 'ticket-1', note: 'urgent', assessment: {
  input_key: {id: 'ticket-1'}, outcome: 'ok',
  value: {reason: null, risk: 'high'},
}}];

// All cases are authored from the common outcome, key and projection rules.
// No expected row or contract is obtained from a compiler or Result reader.
export const sourceCases = {
  minimal: {source, rows: expectedRows, columns: expectedColumns, calls: 1,
    inputWire: '"urgent"'},
  keep: {source: `${prefix} ${infer} KEEP (id, text AS note) AS assessment`,
    rows: keptRows, columns: keptColumns, calls: 1, inputWire: '"urgent"'},
  'keep-filter': {
    source: `${prefix} ${infer} KEEP (id, text AS note) AS assessment ` +
      "|> WHERE assessment.outcome = 'ok' AND assessment.value.risk = 'high'",
    rows: keptRows, columns: keptColumns, calls: 1, inputWire: '"urgent"'},
  'nullable-keep': {
    source: "SELECT DISTINCT 'ticket-1' AS id |> EXTEND CAST(NULL AS STRING) AS text " +
      `${infer} KEEP (id, text AS note) AS assessment`,
    rows: [{id: 'ticket-1', note: null, assessment: {
      input_key: {id: 'ticket-1'}, outcome: 'ok',
      value: {reason: null, risk: 'high'},
    }}],
    columns: [keptColumns[0], {name: 'note', contract: {type: 'string', nullable: true}},
      ...expectedColumns], calls: 1, inputWire: 'null'},
  empty: {source: `${prefix} |> WHERE FALSE ${infer} KEEP (id, text AS note) AS assessment`,
    rows: [], columns: keptColumns, calls: 0},
  'provider-error': {source, rows: [{assessment: {
    input_key: {id: 'ticket-1'}, outcome: 'failed:provider_error', value: null,
  }}], columns: expectedColumns, calls: 1, inputWire: '"urgent"',
    noResponse: true},
  'provider-error-projection': {
    source: `${source} |> SELECT assessment.outcome AS outcome, assessment.value.risk AS risk`,
    rows: [{outcome: 'failed:provider_error', risk: null}],
    columns: [{name: 'outcome', contract: {type: 'string', nullable: false}},
      {name: 'risk', contract: {type: 'string', nullable: true}}],
    calls: 1, inputWire: '"urgent"', noResponse: true},
};

export const sourceRefusals = {
  'dropped-input': `${prefix} ${infer} AS assessment |> SELECT text`,
  'old-alias': `${prefix} |> AS original ${infer} KEEP (id) AS assessment |> SELECT original.text`,
  'unproven-key': `${prefix} |> INFER \`model-task:packed-risk.v1\` ITEM KEY (text) INPUT (text = text) AS assessment`,
  'name-collision': `${prefix} ${infer} KEEP (id AS assessment) AS assessment`,
};
