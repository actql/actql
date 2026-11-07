// Independent common IR and public obligations for immutable Pipe ranges.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const sourceRows = [{id: 2, amount: 20}, {id: 1, amount: null}, {id: 2, amount: 20}];
const columns = [{name: 'current', contract: number}, {name: 'original', contract: number},
  {name: 'amount', contract: nullable}, {name: 'matched', contract: number}];
const expected = [{current: 12, original: 2, amount: 20, matched: 2},
  {current: 12, original: 2, amount: 20, matched: 2}];
export const pipeJoinRangesProgram = {version: 'actql/0.1', id: 'fixture.pipe_join_ranges',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {replacement: {add: [{field: 'id'}, {literal: 10}]}}, as: 'lefts'},
      {values: {schema: {k: number}, rows: [{k: 2}]}, as: 'rights'},
      {from: 'lefts', join: {with: 'rights', kind: 'inner', on: [{left: 'id', right: 'k'}],
        max_output_rows: 10, select: {current: 'left.replacement', original: 'left.id',
          amount: 'left.amount', matched: 'right.k'}}, as: 'joined'},
      {sort: [{field: 'original', dir: 'asc', nulls: 'first'}], as: 'out'}],
    results: {rows: {from: 'out', fields: ['current', 'original', 'amount', 'matched']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const prefix = 'FROM records |> AS l |> SET id = id + 10 ';
const join = '|> JOIN (SELECT 2 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 ';
const originalProjection = '|> SELECT id AS current, l.id AS original, amount, r.k AS matched |> ORDER BY original';
const projection = '|> SELECT id AS `current`, l.id AS original, amount, r.k AS matched |> ORDER BY original';
const source = prefix + join + projection;
const originalSource = prefix + join + originalProjection;
// Independent post-JOIN control: the authored edit changes a current column
// while the range's original id still denotes the evaluated JOIN input slot.
export const postJoinSetProgram = {version: 'actql/0.1', id: 'fixture.post_join_set',
  stages: [structuredClone(pipeJoinRangesProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{values: {schema: {k: number}, rows: [{k: 2}]}, as: 'rights'},
        {from: 'records', join: {with: 'rights', kind: 'inner', on: [{left: 'id', right: 'k'}],
          max_output_rows: 10, select: {old_id: 'left.id', amount: 'left.amount',
            matched: 'right.k'}}, as: 'joined'},
        {from: 'joined', derive: {current: {add: [{field: 'old_id'}, {literal: 10}]}}},
        {sort: [{field: 'old_id', dir: 'asc', nulls: 'first'}]},
        {select: ['current', {original: 'old_id'}, 'amount', 'matched'], as: 'out'}],
      results: {rows: {from: 'out', fields: ['current', 'original', 'amount', 'matched']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const postJoinDropProgram = {version: 'actql/0.1', id: 'fixture.post_join_drop',
  stages: [structuredClone(pipeJoinRangesProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{values: {schema: {k: number}, rows: [{k: 2}]}, as: 'rights'},
        {from: 'records', join: {with: 'rights', kind: 'inner', on: [{left: 'id', right: 'k'}],
          max_output_rows: 10, select: {old_id: 'left.id', amount: 'left.amount',
            matched: 'right.k'}}, as: 'joined'},
        {from: 'joined', sort: [{field: 'old_id', dir: 'asc', nulls: 'first'}]},
        {select: [{current: 'matched'}, {original: 'old_id'}, 'amount', 'matched'], as: 'out'}],
      results: {rows: {from: 'out', fields: ['current', 'original', 'amount', 'matched']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const postJoin = 'FROM records AS l |> JOIN (SELECT 2 AS k) AS r '
  + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 ';
const postJoinProjection = '|> SELECT id AS `current`, l.id AS original, l.amount AS amount, r.k AS matched '
  + '|> ORDER BY original';
const postJoinSetSource = postJoin + '|> SET id = id + 10 ' + postJoinProjection;
// Ordinary EXTEND changes the current row without extending an old range.
export const extendRangeProgram = {version: 'actql/0.1', id: 'fixture.extend_range_snapshot',
  stages: [structuredClone(pipeJoinRangesProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', derive: {z: {add: [{field: 'id'}, {literal: 10}]}}},
        {filter: {gt: [{field: 'z'}, {literal: 0}]}},
        {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
        {select: [{original: 'id'}, {current: 'z'}, 'amount'], as: 'out'}],
      results: {rows: {from: 'out', fields: ['original', 'current', 'amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const extendSource = 'FROM records AS old |> EXTEND id + 10 AS z |> WHERE z > 0 '
  + '|> SELECT old.id AS original, z AS `current`, old.amount AS amount |> ORDER BY original';
const extendColumns = [{name: 'original', contract: number}, {name: 'current', contract: number},
  {name: 'amount', contract: nullable}];
const extendRows = [{original: 1, current: 11, amount: null},
  {original: 2, current: 12, amount: 20}, {original: 2, current: 12, amount: 20}];
const success = (name, text, extra = {}) => ({name: 'pipe-join-ranges-' + name,
  format: 'aql-text', text, sourceRows, sourceReadSessionCount: 1, columns, expected, ...extra});
export const pipeJoinRangesSuccesses = [
  success('post-set-independent-json', JSON.stringify(postJoinSetProgram), {format: 'json'}),
  success('post-set-original-slot', postJoinSetSource),
  success('post-set-parameter', postJoinSetSource.replace('id + 10', 'id + @increment'),
    {parameterDeclarations: {increment: number}, parameters: {increment: 10}}),
  success('post-set-quoted-ranges', postJoinSetSource.replace('AS l', 'AS `L`')
    .replaceAll('l.id', '`L`.`ID`').replaceAll('l.amount', '`L`.`AMOUNT`')),
  success('post-set-typed-empty', postJoinSetSource, {sourceRows: [], expected: []}),
  success('post-set-left-nullable', postJoinSetSource.replace('|> JOIN', '|> LEFT JOIN'),
    {columns: [...columns.slice(0, 3), {name: 'matched', contract: nullable}],
      expected: [{current: 11, original: 1, amount: null, matched: null}, ...expected]}),
  success('post-extend-current-slot', postJoin + '|> EXTEND id + 10 AS `current` '
    + postJoinProjection.replace('id AS `current`', 'current')),
  success('post-extend-fresh-range', postJoin + '|> EXTEND id + 10 AS `current` |> AS fresh '
    + '|> SELECT fresh.current AS `current`, fresh.id AS original, fresh.amount AS amount, fresh.k AS matched '
    + '|> ORDER BY original'),
  success('post-drop-independent-json', JSON.stringify(postJoinDropProgram), {format: 'json',
    expected: [{current: 2, original: 2, amount: 20, matched: 2},
      {current: 2, original: 2, amount: 20, matched: 2}]}),
  success('post-drop-original-slot', postJoin + '|> DROP id '
    + postJoinProjection.replace('id AS `current`', 'r.k AS `current`'),
    {expected: [{current: 2, original: 2, amount: 20, matched: 2},
      {current: 2, original: 2, amount: 20, matched: 2}]}),
  success('independent-json', JSON.stringify(pipeJoinRangesProgram), {format: 'json'}),
  success('set-original-key', source),
  success('parameter-slot', source.replace('id + 10', 'id + @increment'),
    {parameterDeclarations: {increment: number}, parameters: {increment: 10}}),
  success('star-visible-row', prefix + join + '|> SELECT * |> ORDER BY id',
    {columns: [{name: 'amount', contract: nullable}, {name: 'id', contract: number},
      {name: 'k', contract: number}],
    expected: [{amount: 20, id: 12, k: 2}, {amount: 20, id: 12, k: 2}]}),
  success('drop-original-key', 'FROM records |> AS l |> DROP id ' + join
    + projection.replace('id AS `current`', 'amount AS `current`'),
  {columns: [{name: 'current', contract: nullable}, ...columns.slice(1)],
    expected: [{current: 20, original: 2, amount: 20, matched: 2},
      {current: 20, original: 2, amount: 20, matched: 2}]}),
  success('rename-original-key', 'FROM records |> AS l |> RENAME id AS current ' + join
    + projection.replace('id AS `current`', 'current'),
  {expected: [{current: 2, original: 2, amount: 20, matched: 2},
    {current: 2, original: 2, amount: 20, matched: 2}]}),
  success('quoted-range', source.replaceAll('AS l', 'AS `L`').replaceAll('l.id', '`L`.id')),
  success('empty-typed', source, {sourceRows: [], expected: []}),
  ...[
    ['extend-independent-json', JSON.stringify(extendRangeProgram), {format: 'json'}],
    ['extend-original-range', extendSource, {}],
    ['extend-quoted-range', extendSource.replace('AS old', 'AS `old`')
      .replaceAll('old.id', '`OLD`.`ID`').replaceAll('old.amount', '`old`.`AMOUNT`'), {}],
    ['extend-fresh-range', extendSource.replace('|> WHERE', '|> AS fresh |> WHERE')
      .replace('old.id', 'fresh.id').replace('z AS `current`', 'fresh.z AS `current`')
      .replace('old.amount', 'fresh.amount'), {}],
    ['extend-empty-typed', extendSource, {sourceRows: [], expected: []}],
  ].map(([name, text, extra]) => success(name, text,
    {columns: extendColumns, expected: extendRows, ...extra})),
  success('nullable-left', prefix + join.replace('|> JOIN', '|> LEFT JOIN') + projection,
  {columns: [...columns.slice(0, 3), {name: 'matched', contract: nullable}],
    expected: [{current: 11, original: 1, amount: null, matched: null}, ...expected]}),
  success('multiple-ranges', 'FROM records AS l '
    + '|> JOIN (SELECT 2 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 '
    + '|> SET id = id + 10 |> JOIN (SELECT 2 AS k) AS s ON r.k = s.k MAX_OUTPUT_ROWS 10 '
    + projection),
  success('shared-source', 'FROM records |> AS l |> SET id = id + 10 '
    + '|> WHERE l.id = 2 |> CROSS JOIN (SELECT id AS k FROM records) AS r MAX_OUTPUT_ROWS 10 '
    + '|> SELECT id AS `current`, l.id AS original, l.amount AS amount, r.k AS matched '
    + '|> ORDER BY matched', {expected: [
    {current: 12, original: 2, amount: 20, matched: 1}, {current: 12, original: 2, amount: 20, matched: 1},
    {current: 12, original: 2, amount: 20, matched: 2}, {current: 12, original: 2, amount: 20, matched: 2},
    {current: 12, original: 2, amount: 20, matched: 2}, {current: 12, original: 2, amount: 20, matched: 2}]}),
];
export const pipeJoinRangesRefusals = [
  {name: 'post-drop-current', text: postJoin + '|> DROP id |> SELECT id'},
  {name: 'post-extend-old-range', text: postJoin + '|> EXTEND id + 10 AS current |> SELECT l.current'},
  {name: 'post-set-missing-target', text: postJoin + '|> SET missing = 1 |> SELECT l.id'},
  {name: 'post-extend-duplicate', text: postJoin + '|> EXTEND id + 10 AS amount |> SELECT l.id'},
  {name: 'dropped-current', text: 'FROM records |> AS l |> DROP id ' + join.replace('l.id', 'id') + originalProjection},
  {name: 'renamed-current', text: 'FROM records |> AS l |> RENAME id AS current ' + join.replace('l.id', 'id') + originalProjection},
  {name: 'displaced-range', text: originalSource.replace('SET id = id + 10', 'SET id = id + 10 |> AS fresh')},
  {name: 'authored-cte-range', text: 'WITH chosen AS (FROM records |> AS l |> SET id = id + 10) FROM chosen ' + join + originalProjection},
].map(item => ({format: 'aql-text', expectedCode: 'ClientProgramInvalidInput', ...item,
  name: 'pipe-join-ranges-refuse-' + item.name}));
pipeJoinRangesRefusals.push(...[
  ['select', 'SELECT old.z'],
  ['quoted-select', 'SELECT `OLD`.`Z`'],
  ['where', 'WHERE old.z > 0 |> SELECT z'],
  ['extend', 'EXTEND old.z + 1 AS another |> SELECT another'],
  ['order', 'ORDER BY old.z |> SELECT z'],
].map(([name, tail]) => ({name: 'pipe-join-ranges-refuse-extend-' + name,
  format: 'aql-text', expectedCode: 'ClientProgramInvalidInput',
  text: 'FROM records AS old |> EXTEND id + 10 AS z |> ' + tail})));

// RENAME changes the current names only. Intermediate duplicate logical names
// retain separate physical values until the authored projection resolves them.
export const renameTargetProgram = {version: 'actql/0.1', id: 'fixture.rename_target_scope',
  stages: [structuredClone(pipeJoinRangesProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{values: {schema: {id: number}, rows: [{id: 2}]}, as: 'rights'},
        {from: 'records', join: {with: 'rights', kind: 'inner',
          on: [{left: 'id', right: 'id'}], max_output_rows: 10,
          select: {current: 'left.amount', original: 'left.id', matched: 'right.id'}}},
        {sort: [{field: 'original', dir: 'asc', nulls: 'first'}], as: 'out'}],
      results: {rows: {from: 'out', fields: ['current', 'original', 'matched']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const renameJoin = 'FROM records AS l |> JOIN (SELECT 2 AS id) AS r '
  + 'ON l.id = r.id MAX_OUTPUT_ROWS 10 ';
const renameProjection = '|> SELECT current, l.id AS original, r.id AS matched |> ORDER BY original';
const renameColumns = [{name: 'current', contract: nullable},
  {name: 'original', contract: number}, {name: 'matched', contract: number}];
const renameRows = [{current: 20, original: 2, matched: 2},
  {current: 20, original: 2, matched: 2}];
pipeJoinRangesSuccesses.push(...[
  ['rename-independent-json', JSON.stringify(renameTargetProgram), {format: 'json'}],
  ['rename-unrelated-duplicates', renameJoin + '|> RENAME amount AS current ' + renameProjection, {}],
  ['rename-quoted-target', renameJoin + '|> RENAME `AMOUNT` AS current ' + renameProjection, {}],
  ['rename-new-ambiguity', renameJoin + '|> RENAME amount AS id '
    + renameProjection.replace('SELECT current', 'SELECT l.amount AS `current`'), {}],
  ['rename-empty-typed', renameJoin + '|> RENAME amount AS current ' + renameProjection,
    {sourceRows: [], expected: []}],
  ['rename-nullable', 'FROM records AS old |> RENAME id AS amount '
    + '|> SELECT old.amount AS `current`, old.id AS original, old.id AS matched |> ORDER BY original',
  {expected: [{current: null, original: 1, matched: 1}, ...renameRows]}],
].map(([name, text, extra]) => success(name, text,
  {columns: renameColumns, expected: renameRows, ...extra})));
pipeJoinRangesRefusals.push(...[
  ['ambiguous-target', renameJoin + '|> RENAME id AS current |> SELECT l.id AS original'],
  ['quoted-ambiguous-target', renameJoin + '|> RENAME `ID` AS current |> SELECT l.id AS original'],
  ['ambiguous-current-read', renameJoin + '|> RENAME amount AS id |> SELECT id'],
  ['duplicate-result', 'FROM records |> RENAME id AS amount'],
  ['missing-target', 'FROM records |> RENAME missing AS current |> SELECT id'],
  ['repeated-target', 'FROM records |> RENAME id AS current, `ID` AS other |> SELECT amount'],
].map(([name, text]) => ({name: 'pipe-join-ranges-refuse-rename-' + name,
  format: 'aql-text', expectedCode: 'ClientProgramInvalidInput', text})));

// Same-name SET/DROP removes only that range, after sibling resolution.
const replacement = {type: 'object', nullable: false, fields: {id: number}};
export const editCollisionProgram = {version: 'actql/0.1', id: 'fixture.pipe_edit_collision',
  params: {replacement},
  stages: [structuredClone(pipeJoinRangesProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', derive: {updated: {$param: 'replacement'}}},
        {derive: {current: {property: {value: {field: 'updated'}, name: 'id'}}}},
        {sort: [{field: 'amount', dir: 'asc', nulls: 'first'}]},
        {select: ['current', 'amount'], as: 'out'}],
      results: {rows: {from: 'out', fields: ['current', 'amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const editColumns = [{name: 'current', contract: number}, {name: 'amount', contract: nullable}];
const editRows = [{current: 99, amount: null}, {current: 99, amount: 20}, {current: 99, amount: 20}];
const editSource = 'FROM records AS id |> SET id = @replacement, amount = id.amount '
  + '|> SELECT id.id AS `current`, amount |> ORDER BY amount';
pipeJoinRangesSuccesses.push(...[
  ['edit-independent-json', JSON.stringify(editCollisionProgram), {format: 'json'}],
  ['edit-object-current', editSource, {parameterDeclarations: {replacement}}],
  ['edit-quoted-current', editSource.replace('AS id', 'AS `ID`')
    .replace('SET id', 'SET `id`').replace('id.amount', '`ID`.`amount`')
    .replace('id.id', '`ID`.`id`'), {parameterDeclarations: {replacement}}],
  ['edit-rename-after-set', editSource.replace('|> SELECT id.id', '|> RENAME id AS updated |> SELECT updated.id'),
    {parameterDeclarations: {replacement}}],
  ['edit-empty-typed', editSource, {parameterDeclarations: {replacement}, sourceRows: [], expected: []}],
].map(([name, text, extra]) => success(name, text,
  {columns: editColumns, expected: editRows, parameters: {replacement: {id: 99}}, ...extra})));
pipeJoinRangesSuccesses.push(success('edit-drop-current',
  'FROM records AS id |> DROP id |> SELECT amount |> ORDER BY amount',
  {columns: [{name: 'amount', contract: nullable}],
    expected: [{amount: null}, {amount: 20}, {amount: 20}]}));
pipeJoinRangesRefusals.push(...[
  ['rename-hidden-target', 'FROM records AS id |> RENAME id AS current |> SELECT current'],
  ['rename-quoted-hidden-target', 'FROM records AS `ID` |> RENAME `id` AS current |> SELECT current'],
  ['drop-hidden-range', 'FROM records AS id |> DROP id |> SELECT id.amount'],
  ['drop-quoted-hidden-range', 'FROM records AS `ID` |> DROP `id` |> SELECT `ID`.`amount`'],
  ['set-removed-range-member', 'FROM records AS id |> SET id = @replacement |> SELECT id.amount'],
].map(([name, text]) => ({name: 'pipe-join-ranges-refuse-edit-' + name,
  format: 'aql-text', expectedCode: 'ClientProgramInvalidInput', text,
  ...(text.includes('@replacement')
    ? {parameterDeclarations: {replacement}, parameters: {replacement: {id: 99}}} : {})})));
