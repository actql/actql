import {mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {retainedMatrix} from './fixtures.mjs';
import {assessEquivalentMatrix, formatEquivalentMatrix} from
  './equivalent-matrix-assessment.mjs';

const revisionPattern = /^[0-9a-f]{40}$/;

// Download each case artifact into its own directory. The case index is a
// transport label; only the registered case ID and pair provenance can admit
// its measurements into the fixed-revision assessment.
export async function aggregateEquivalentArtifacts(partsDirectory, outputDirectory,
  revision) {
  if (typeof partsDirectory !== 'string' || !partsDirectory.length ||
      typeof outputDirectory !== 'string' || !outputDirectory.length ||
      !revisionPattern.test(revision ?? '')) {
    throw new TypeError('InvalidEquivalentArtifactAggregation');
  }
  const parts = resolve(partsDirectory);
  const output = resolve(outputDirectory);
  if (parts === output) throw new TypeError('OverlappingEquivalentArtifacts');
  const fixtures = retainedMatrix();
  const expected = fixtures.map((fixture, index) => ({
    fixture,
    artifact: `equivalent-case-${String(index).padStart(2, '0')}-${revision}`,
  }));
  const entries = await readdir(parts, {withFileTypes: true});
  const available = new Set(entries.filter(entry => entry.isDirectory()).map(entry => entry.name));
  const unexpectedArtifacts = entries.map(entry => entry.name).filter(name =>
    !expected.some(item => item.artifact === name));
  const missingArtifacts = expected.filter(item => !available.has(item.artifact))
    .map(item => item.artifact);
  const records = [];
  const invalidArtifacts = [];
  for (const item of expected) {
    if (!available.has(item.artifact)) continue;
    try {
      const record = JSON.parse(await readFile(join(parts, item.artifact,
        'case-00.json'), 'utf8'));
      if (record?.caseId !== item.fixture.id) throw new Error('ForeignCaseInArtifact');
      records.push(record);
    } catch (error) {
      invalidArtifacts.push({artifact: item.artifact,
        error: error?.message ?? String(error)});
    }
  }
  const assessment = assessEquivalentMatrix(records, revision);
  const completeArtifacts = unexpectedArtifacts.length === 0 &&
    missingArtifacts.length === 0 && invalidArtifacts.length === 0;
  const result = Object.freeze({...assessment,
    status: completeArtifacts ? assessment.status : 'incomplete',
    missingArtifacts, unexpectedArtifacts, invalidArtifacts});
  await mkdir(output, {recursive: true});
  await writeFile(join(output, 'assessment.json'), JSON.stringify(result, null, 2));
  await writeFile(join(output, 'assessment.md'), formatEquivalentMatrix(result));
  return result;
}

if (process.argv[1] && resolve(process.argv[1]) ===
    resolve(new URL(import.meta.url).pathname)) {
  const [parts, output, revision, ...extra] = process.argv.slice(2);
  if (!parts || !output || !revision || extra.length) {
    throw new TypeError('Usage: equivalent-matrix-aggregate.mjs PARTS OUTPUT REVISION');
  }
  const result = await aggregateEquivalentArtifacts(parts, output, revision);
  console.log(JSON.stringify({status: result.status,
    registeredCases: result.registeredCases,
    receivedRecords: result.receivedRecords,
    missingArtifacts: result.missingArtifacts.length,
    invalidArtifacts: result.invalidArtifacts.length}));
  if (result.status !== 'pass') process.exitCode = 1;
}
