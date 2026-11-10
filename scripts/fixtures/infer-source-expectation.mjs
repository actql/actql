// Authored from the adopted INFER output contract, not compiler/reader output.
export const source = "SELECT DISTINCT 'ticket-1' AS id " +
  "|> EXTEND 'urgent' AS text " +
  "|> INFER `model-task:packed-risk.v1` ITEM KEY (id) " +
  'INPUT (text = text) AS assessment |> SELECT assessment';
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
// TRUE strict equality on assessment.value.risk proves that same receiver
// non-null; unrelated nullable members keep their original contracts.
const filteredColumns = [keptColumns[0], keptColumns[1], {
  ...expectedColumns[0], contract: {
    ...expectedColumns[0].contract,
    fields: {...expectedColumns[0].contract.fields,
      value: {...expectedColumns[0].contract.fields.value, nullable: false}},
  },
}];
const keptRows = [{id: 'ticket-1', note: 'urgent', assessment: {
  input_key: {id: 'ticket-1'}, outcome: 'ok',
  value: {reason: null, risk: 'high'},
}}];

// Default/wildcard retention exposes the authored input layout before the struct.
const retainedColumns = [
  keptColumns[0],
  {name: 'text', contract: {type: 'string', nullable: false, max_utf8_bytes: 6}},
  ...expectedColumns,
];
const retainedRows = [{id: 'ticket-1', text: 'urgent', ...expectedRows[0]}];

// Independent old/new values and contracts expose accidental replacement-slot
// adoption: the proven key is Number 7, while the visible replacement is Text.
const historicalPrefix = "SELECT 7 AS id |> EXTEND 'urgent' AS text " +
  "|> ASSERT UNIQUE BY (id) |> SET id = 'same' " +
  '|> RENAME id AS replacement_id |> AS `current`';
const omittedInfer = '|> INFER `model-task:packed-risk.v1` INPUT (text = text) AS assessment';
const historicalOutcome = {input_key: {id: 7}, outcome: 'ok',
  value: {reason: null, risk: 'high'}};
const historicalColumn = {name: 'assessment', contract: {
  ...expectedColumns[0].contract,
  fields: {...expectedColumns[0].contract.fields,
    input_key: {type: 'object', nullable: false, additional_properties: false,
      fields: {id: {type: 'number', nullable: false}}}},
}};
const replacementColumn = {name: 'replacement_id',
  contract: {type: 'string', nullable: false, max_utf8_bytes: 4}};
const historicalColumns = [replacementColumn, retainedColumns[1], historicalColumn];
const stableHistoricalColumn = {name: 'assessment', contract: {
  ...historicalColumn.contract,
  fields: {...historicalColumn.contract.fields,
    input_key: {type: 'object', nullable: false, additional_properties: false,
      fields: {stable_id: {type: 'number', nullable: false}}}},
}};
const compositeHistoricalColumn = {name: 'assessment', contract: {
  ...historicalColumn.contract,
  fields: {...historicalColumn.contract.fields,
    input_key: {type: 'object', nullable: false, additional_properties: false,
      fields: {secret: {type: 'string', nullable: false, max_utf8_bytes: 7},
        id: {type: 'number', nullable: false}}}},
}};

// All cases are authored from the common outcome, key and projection rules.
// No expected row or contract is obtained from a compiler or Result reader.
export const sourceCases = {
  'default-keep': {
    source: `${prefix} ${infer} AS assessment`,
    rows: retainedRows, columns: retainedColumns, calls: 1, inputWire: '"urgent"',
  },
  'wildcard-keep': {
    source: `${prefix} ${infer} KEEP (*) AS assessment`,
    rows: retainedRows, columns: retainedColumns, calls: 1, inputWire: '"urgent"',
  },
  'omitted-item-key': {
    source: `${prefix} |> INFER \`model-task:packed-risk.v1\` INPUT (text = text) AS assessment`,
    rows: retainedRows, columns: retainedColumns, calls: 1, inputWire: '"urgent"',
  },
  'historical-key': {
    source: `${historicalPrefix} ${omittedInfer}`,
    rows: [{replacement_id: 'same', text: 'urgent', assessment: historicalOutcome}],
    columns: historicalColumns, calls: 1, inputWire: '"urgent"',
  },
  'historical-key-frozen': {
    source: `${historicalPrefix} ${omittedInfer} |> RENAME replacement_id AS renamed_again`,
    rows: [{renamed_again: 'same', text: 'urgent', assessment: historicalOutcome}],
    columns: [{...replacementColumn, name: 'renamed_again'},
      retainedColumns[1], historicalColumn], calls: 1, inputWire: '"urgent"',
  },
  'historical-key-original-rename': {
    source: "SELECT 7 AS id |> EXTEND 'urgent' AS text |> ASSERT UNIQUE BY (id) " +
      "|> RENAME id AS stable_id |> SET stable_id = 'same' " +
      `|> RENAME stable_id AS replacement_id |> AS \`current\` ${omittedInfer}`,
    rows: [{replacement_id: 'same', text: 'urgent',
      assessment: {...historicalOutcome, input_key: {stable_id: 7}}}],
    columns: [replacementColumn, retainedColumns[1], stableHistoricalColumn],
    calls: 1, inputWire: '"urgent"',
  },
  'historical-key-composite': {
    source: "SELECT 7 AS id |> EXTEND 'urgent' AS text, 'private' AS secret " +
      "|> ASSERT UNIQUE BY (secret, id) |> SET id = 'same' " +
      `|> RENAME id AS replacement_id |> AS \`current\` ${omittedInfer}`,
    rows: [{replacement_id: 'same', text: 'urgent', secret: 'private',
      assessment: {...historicalOutcome, input_key: {secret: 'private', id: 7}}}],
    columns: [replacementColumn, retainedColumns[1],
      {name: 'secret', contract: {type: 'string', nullable: false, max_utf8_bytes: 7}},
      compositeHistoricalColumn], calls: 1, inputWire: '"urgent"',
  },
  'literal-input': {
    source: "SELECT DISTINCT 'ticket-1' AS id " +
      "|> INFER `model-task:packed-risk.v1` ITEM KEY (id) INPUT (text = 'urgent') AS assessment |> SELECT assessment",
    rows: expectedRows, columns: expectedColumns, calls: 1, inputWire: '"urgent"',
  },
  'expression-input': {
    source: "SELECT DISTINCT 'ticket-1' AS id " +
      "|> INFER `model-task:packed-risk.v1` ITEM KEY (id) INPUT (text = CONCAT('ur', 'gent')) AS assessment |> SELECT assessment",
    rows: expectedRows, columns: expectedColumns, calls: 1, inputWire: '"urgent"',
  },
  minimal: {source, rows: expectedRows, columns: expectedColumns, calls: 1,
    inputWire: '"urgent"'},
  'folded-input': {source: `${prefix} |> INFER \`model-task:packed-risk.v1\` ` +
      'ITEM KEY (id) INPUT (TEXT = text) AS assessment |> SELECT assessment',
    rows: expectedRows, columns: expectedColumns, calls: 1, inputWire: '"urgent"'},
  'quoted-input': {source: `${prefix} |> INFER \`model-task:packed-risk.v1\` ` +
      'ITEM KEY (id) INPUT (`TeXt` = text) AS assessment |> SELECT assessment',
    rows: expectedRows, columns: expectedColumns, calls: 1, inputWire: '"urgent"'},
  keep: {source: `${prefix} ${infer} KEEP (id, text AS note) AS assessment`,
    rows: keptRows, columns: keptColumns, calls: 1, inputWire: '"urgent"'},
  'keep-filter': {
    source: `${prefix} ${infer} KEEP (id, text AS note) AS assessment ` +
      "|> WHERE assessment.outcome = 'ok' AND assessment.value.risk = 'high'",
    rows: keptRows, columns: filteredColumns, calls: 1, inputWire: '"urgent"'},
  'folded-filter': {
    source: `${prefix} ${infer} KEEP (id, text AS note) AS assessment ` +
      "|> WHERE assessment.OUTCOME = 'ok' AND assessment.VaLuE.RiSk = 'high'",
    rows: keptRows, columns: filteredColumns, calls: 1, inputWire: '"urgent"'},
  'folded-projection': {
    source: `${source} |> SELECT assessment.VALUE.RISK AS risk, assessment.value.REASON AS reason`,
    rows: [{risk: 'high', reason: null}],
    columns: [{name: 'risk', contract: {type: 'string', nullable: true}},
      {name: 'reason', contract: {type: 'string', nullable: true}}],
    calls: 1, inputWire: '"urgent"'},
  'folded-key': {
    source: `${source} |> SELECT assessment.INPUT_KEY.ID AS id`,
    rows: [{id: 'ticket-1'}], columns: [keptColumns[0]],
    calls: 1, inputWire: '"urgent"'},
  'folded-empty': {
    source: `${prefix} |> WHERE FALSE ${infer} AS assessment |> SELECT assessment.VALUE.RISK AS risk`,
    rows: [], columns: [{name: 'risk', contract: {type: 'string', nullable: true}}], calls: 0},
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
  'provider-error-folded': {
    source: `${source} |> SELECT assessment.OUTCOME AS outcome, assessment.VALUE.RISK AS risk`,
    rows: [{outcome: 'failed:provider_error', risk: null}],
    columns: [{name: 'outcome', contract: {type: 'string', nullable: false}},
      {name: 'risk', contract: {type: 'string', nullable: true}}],
    calls: 1, inputWire: '"urgent"', noResponse: true},
  'provider-error-projection': {
    source: `${source} |> SELECT assessment.outcome AS outcome, assessment.value.risk AS risk`,
    rows: [{outcome: 'failed:provider_error', risk: null}],
    columns: [{name: 'outcome', contract: {type: 'string', nullable: false}},
      {name: 'risk', contract: {type: 'string', nullable: true}}],
    calls: 1, inputWire: '"urgent"', noResponse: true},
  // Positive controls must execute before the matching runtime refusals. The
  // UNION ALL control checks both occurrences before selecting one Model item.
  // No DISTINCT repairs the input, and the existing one-attempt profile stays fixed.
  // Filtering by a separate position removes the second occurrence even in the
  // duplicate case: a skipped guard cannot pass by reaching an INFER duplicate.
  'guard-distinct': {
    source: 'FROM (SELECT 7 AS id, 0 AS position UNION ALL SELECT 8 AS id, 1 AS position) ' +
      '|> ASSERT UNIQUE BY (id) |> WHERE position = 0 |> SELECT id ' +
      "|> EXTEND 'urgent' AS text " +
      omittedInfer,
    rows: [
      {id: 7, text: 'urgent', assessment: historicalOutcome},
    ],
    columns: [{name: 'id', contract: {type: 'number', nullable: false}},
      retainedColumns[1], historicalColumn], calls: 1, inputWire: '"urgent"',
  },
  // Project away the separately asserted guard before adopting the sole id
  // proof. A nullable guard is not itself an admissible inferred item key.
  'guard-nonnull': {
    source: 'SELECT 7 AS id, CAST(1 AS FLOAT64) AS guard ' +
      '|> ASSERT UNIQUE BY (guard) |> SELECT id |> ASSERT UNIQUE BY (id) ' +
      "|> EXTEND 'urgent' AS text |> INFER `model-task:packed-risk.v1` " +
      'INPUT (text = text) KEEP (*) AS assessment',
    rows: [{id: 7, text: 'urgent', assessment: historicalOutcome}],
    columns: [{name: 'id', contract: {type: 'number', nullable: false}},
      retainedColumns[1], historicalColumn], calls: 1, inputWire: '"urgent"',
  },
};

// These are admitted Runs whose ordinary ASSERT UNIQUE guard must fail before
// Model dispatch. They must never be counted as source/admission refusals.
export const sourceRuntimeRefusals = {
  'guard-duplicate': 'FROM (SELECT 7 AS id, 0 AS position UNION ALL SELECT 7 AS id, 1 AS position) ' +
    '|> ASSERT UNIQUE BY (id) |> WHERE position = 0 |> SELECT id ' +
    "|> EXTEND 'urgent' AS text " +
    omittedInfer,
  'guard-null': 'SELECT 7 AS id, CAST(NULL AS FLOAT64) AS guard ' +
    '|> ASSERT UNIQUE BY (guard) |> SELECT id |> ASSERT UNIQUE BY (id) ' +
    "|> EXTEND 'urgent' AS text |> INFER `model-task:packed-risk.v1` " +
    'INPUT (text = text) KEEP (*) AS assessment',
};

export const sourceRefusals = {
  'historical-key-hidden-lookup': `${historicalPrefix} ${omittedInfer} |> SELECT id`,
  'historical-key-label-collision': "SELECT 'old' AS id |> EXTEND 'urgent' AS text " +
    "|> AS old |> SET id = 'key' |> ASSERT UNIQUE BY (old.id, id) " +
    `|> SET id = 'same' |> AS \`current\` ${omittedInfer}`,
  'omitted-key-unproven': "SELECT 'ticket-1' AS id |> EXTEND 'urgent' AS text " +
    '|> INFER `model-task:packed-risk.v1` INPUT (text = text) AS assessment',
  'omitted-key-ambiguous': `${prefix} |> ASSERT UNIQUE BY (text) ` +
    '|> INFER `model-task:packed-risk.v1` INPUT (text = text) AS assessment',
  'unknown-input': `${prefix} |> INFER \`model-task:packed-risk.v1\` ` +
    'ITEM KEY (id) INPUT (absent = text) AS assessment',
  'duplicate-input': `${prefix} |> INFER \`model-task:packed-risk.v1\` ` +
    'ITEM KEY (id) INPUT (text = text, TEXT = text) AS assessment',
  'unknown-member': `${source} |> SELECT assessment.VALUE.missing AS risk`,
  'folded-unproven-key': `${prefix} |> INFER \`model-task:packed-risk.v1\` ITEM KEY (text) INPUT (text = text) AS assessment |> SELECT assessment.VALUE.RISK AS risk`,
  'dropped-input': `${prefix} ${infer} KEEP (id) AS assessment |> SELECT text`,
  'old-alias': `${prefix} |> AS original ${infer} KEEP (id) AS assessment |> SELECT original.text`,
  'unproven-key': `${prefix} |> INFER \`model-task:packed-risk.v1\` ITEM KEY (text) INPUT (text = text) AS assessment`,
  'name-collision': `${prefix} ${infer} KEEP (id AS assessment) AS assessment`,
};
