// An installed consumer of the existing common ModelTask owner, not an executor.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {sourceCases, sourceRefusals} from './fixtures/infer-source-expectation.mjs';

export async function exercisePackedInferSource({root, directory, run, environment,
  sourceSha}) {
  await writeFile(join(directory, 'infer-source-provenance.json'), JSON.stringify({
    sourceSha,
    commonConnectionSha: 'f9e6dbe36d263ef7baf4799646a1c53ebca47df9',
    positiveCases: Object.keys(sourceCases), refusalCases: Object.keys(sourceRefusals),
  }, null, 2) + '\n');
  for (const transport of ['local', 'remote']) {
    for (const caseName of Object.keys(sourceCases)) {
      console.log(run(process.execPath,
        ['packed-infer-source.mjs', transport, 'success', caseName],
        root, environment, 120_000).trimEnd());
    }
    for (const caseName of Object.keys(sourceRefusals)) {
      console.log(run(process.execPath,
        ['packed-infer-source.mjs', transport, 'refusal', caseName],
        root, environment, 120_000).trimEnd());
    }
    for (const phase of ['capture', 'replay']) {
      console.log(run(process.execPath,
        ['packed-infer-source.mjs', transport, phase, 'minimal'],
        root, environment, 120_000).trimEnd());
    }
  }
  const calls = (await readFile(join(root, 'source-provider-calls.jsonl'), 'utf8'))
    .trim().split('\n').map(line => {
      const {transport, phase, caseName} = JSON.parse(line);
      return `${transport}:${phase}:${caseName}`;
    });
  const expectedCalls = ['local', 'remote'].flatMap(transport => [
    ...Object.entries(sourceCases).flatMap(([name, fixture]) =>
      Array.from({length: fixture.calls}, () => `${transport}:success:${name}`)),
    `${transport}:capture:minimal`,
  ]);
  assert.deepEqual(calls, expectedCalls,
    'empty input, refused source, reread, resend and retained capture must not dispatch');
  console.log(JSON.stringify({sourceSha, acceptance: 'source-infer',
    transports: ['local', 'remote'], positiveCases: Object.keys(sourceCases),
    refusalCases: Object.keys(sourceRefusals), calls}));
}
