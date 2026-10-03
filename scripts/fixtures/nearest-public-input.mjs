// Independent expectations and a public-Client acceptance consumer. The caller
// installs typed sources through the ordinary Host; this module never supplies
// a Catalog, checker, schema override or VecA provider.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {exercisePublicQueryInput} from './public-query-input.mjs';

const nearest = `NEAREST candidates AS c
  QUERY KEY (q.request_id) VECTOR q.embedding
  CANDIDATE KEY (c.item_id) VECTOR c.embedding
  METRIC dot K 2`;

export async function nearestPublicInputFixtures(directory) {
  const json = async file => JSON.parse(await readFile(join(directory, file), 'utf8'));
  const program = await json('common-minimal.program.json');
  const rows = await json('expected-rows.json');
  const {columns} = await json('expected-schema.json');
  const keptSource = await readFile(join(directory, 'kept.ordered.aql'), 'utf8');
  // These transformations use authored independent fixtures, never product
  // output. An empty Values input retains its declared schema; omitted KEEP
  // projects only the independently specified result object.
  const emptyProgram = structuredClone(program);
  emptyProgram.id += '.empty';
  emptyProgram.stages[0].steps[0].values.rows = [];
  const result = (rows, columns, unordered = false) => ({
    answer: {rows, columns, unordered},
  });
  const successes = [
    {name: 'nearest-json-control', format: 'json', text: JSON.stringify(program),
      results: result(rows, columns, true)},
    {name: 'nearest-json-empty', format: 'json', text: JSON.stringify(emptyProgram),
      results: result([], columns)},
    {name: 'nearest-source-keep', format: 'aql-text', text: keptSource,
      results: result(rows, columns)},
    {name: 'nearest-source-omitted-keep', format: 'aql-text',
      text: `FROM queries AS q |> ${nearest} AS neighbor |> ORDER BY neighbor.rank`,
      results: result(rows.map(({neighbor}) => ({neighbor})), [columns[2]])},
    {name: 'nearest-source-empty', format: 'aql-text',
      text: `FROM queries AS q |> WHERE FALSE |> ${nearest}
        KEEP (q.note, c.label) AS neighbor |> ORDER BY neighbor.rank`,
      results: result([], columns)},
  ];
  const refusals = [
    {name: 'nearest-dropped-input', format: 'aql-text',
      text: `FROM queries AS q |> ${nearest} AS neighbor |> SELECT q.note`},
    {name: 'nearest-result-name-collision', format: 'aql-text',
      text: `FROM queries AS q |> ${nearest} KEEP (q.note AS neighbor) AS neighbor`},
    {name: 'nearest-unknown-alias', format: 'aql-text',
      text: `FROM missing_nearest_queries AS q |> ${nearest} AS neighbor`},
    {name: 'nearest-missing-query-key', format: 'aql-text',
      text: `FROM queries AS q |> NEAREST candidates AS c
        QUERY KEY (q.missing_key) VECTOR q.embedding
        CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 AS neighbor`},
  ];
  return {successes, refusals};
}

// Use this unchanged consumer with installed Local and HTTP connect options.
// observe is the existing acceptance counter boundary: acceptedRuns/sourceIo
// and, when supplied, sourceReads/sourceReadSessions. It is not a product API.
export async function exerciseNearestPublicInput(connect, options,
  {directory, requestPrefix, observe}) {
  const {successes, refusals} = await nearestPublicInputFixtures(directory);
  const expected = new Map(successes.map(test => [test.name, test.results.answer]));
  return exercisePublicQueryInput(connect, options, {
    requestPrefix, observe, successes, refusals,
    async completedCase({name, execution, beforeSubmit, beforeRead}) {
      if (name.startsWith('nearest-json-')) {
        assert.equal(beforeRead.sourceIo, beforeSubmit.sourceIo,
          'closed Values control must not acquire an installed source');
      }
      const before = await observe();
      const contract = expected.get(name);
      const result = execution.result('answer');
      const description = await result.describe();
      assert.deepEqual(description.ref, execution.ref);
      assert.equal(description.resultName, 'answer');
      assert.equal(description.serialization.format, 'jsonl');
      assert.equal(description.serialization.version, 'actql-jsonl/0.1');
      assert.deepEqual(description.columns, contract.columns);
      const reader = result.rows({signal: AbortSignal.timeout(60_000)});
      const rows = [];
      for await (const row of reader) rows.push(row);
      assert.equal(reader.state(), 'complete');
      if (contract.unordered) {
        // Sort only the test copy by the independently specified unique ranks;
        // the un-ordered JSON control promises a multiset, not delivery order.
        rows.sort((left, right) => left.neighbor.rank - right.neighbor.rank);
      }
      assert.deepEqual(rows, contract.rows);
      assert.deepEqual(await observe(), before,
        'metadata and streamed rereads must not accept or acquire again');
    },
  });
}
