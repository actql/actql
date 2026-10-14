// An installed consumer of the existing common ModelTask owner, not an executor.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {sourceCases, sourceRefusals} from './fixtures/infer-source-expectation.mjs';

export async function exercisePackedInferSource({root, directory, run, environment,
  sourceSha, inputFieldsOnly = false}) {
  // The default CI cohort retains every case. This selector narrows a local
  // boundary check without substituting another install or execution path.
  const positiveCases = inputFieldsOnly ? ['minimal', 'folded-input', 'quoted-input'] :
    Object.keys(sourceCases);
  const refusalCases = inputFieldsOnly ? ['unknown-input', 'duplicate-input'] :
    Object.keys(sourceRefusals);
  const captureCases = inputFieldsOnly ? ['minimal'] :
    ['minimal', 'historical-key-frozen'];
  await writeFile(join(directory, 'infer-source-provenance.json'), JSON.stringify({
    sourceSha,
    commonConnectionSha: 'f9e6dbe36d263ef7baf4799646a1c53ebca47df9',
    positiveCases, refusalCases, captureCases,
  }, null, 2) + '\n');
  for (const transport of ['local', 'remote']) {
    for (const caseName of positiveCases) {
      console.log(run(process.execPath,
        ['packed-infer-source.mjs', transport, 'success', caseName],
        root, environment, 120_000).trimEnd());
    }
    for (const caseName of refusalCases) {
      console.log(run(process.execPath,
        ['packed-infer-source.mjs', transport, 'refusal', caseName],
        root, environment, 120_000).trimEnd());
    }
    for (const caseName of captureCases) {
      for (const phase of ['capture', 'replay']) {
        console.log(run(process.execPath,
          ['packed-infer-source.mjs', transport, phase, caseName],
          root, environment, 120_000).trimEnd());
      }
    }
  }
  const calls = (await readFile(join(root, 'source-provider-calls.jsonl'), 'utf8'))
    .trim().split('\n').map(line => {
      const {transport, phase, caseName} = JSON.parse(line);
      return `${transport}:${phase}:${caseName}`;
    });
  const expectedCalls = ['local', 'remote'].flatMap(transport => [
    ...positiveCases.flatMap(name =>
      Array.from({length: sourceCases[name].calls}, () => `${transport}:success:${name}`)),
    ...captureCases.map(name => `${transport}:capture:${name}`),
  ]);
  assert.deepEqual(calls, expectedCalls,
    'empty input, refused source, reread, resend and retained capture must not dispatch');
  console.log(JSON.stringify({sourceSha, acceptance: 'source-infer',
    transports: ['local', 'remote'], positiveCases, refusalCases, captureCases, calls}));
}
