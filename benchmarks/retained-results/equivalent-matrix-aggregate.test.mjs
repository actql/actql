import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {retainedMatrix} from './fixtures.mjs';
import {aggregateEquivalentArtifacts} from './equivalent-matrix-aggregate.mjs';

const revision = 'a'.repeat(40);
const equivalent = 'direct-duckdb-with-identical-obligations-and-independent-holding';
const digest = value => createHash('sha256').update(value).digest('hex');
const registrationSha256 = digest(readFileSync(new URL('experiment.json', import.meta.url)));

function passingRecord(fixture) {
  const provenance = {revision, sourceContentSha256: 'b'.repeat(64),
    releaseArtifactSha256: 'd'.repeat(64), runtime: 'v22.23.2',
    registrationSha256, programSha256: digest(JSON.stringify(fixture.program())),
    sourceDefinitionSha256: digest(fixture.createSourceSql)};
  return {caseId: fixture.id,
    pairs: Array.from({length: 7}, (_, index) => ({
      index, caseId: fixture.id, status: 'diagnostic-completed',
      acceptanceEligible: true, provenance: {...provenance},
      equivalentObligationAdmission: {accepted: true},
      transferWorkComparison: {terminalReleaseConfirmed: true},
      logicalAccountingEquivalent: true,
      acquisitionMetadataEquivalent: true,
      transferWorkAccountingEquivalent: true,
      order: index % 2 ? ['retained-actql', equivalent] :
        [equivalent, 'retained-actql'],
      samples: {
        [equivalent]: {status: 'diagnostic-completed',
          warmMs: 100, coldMs: 200, executionMs: 100, cleanupMs: 1},
        'retained-actql': {status: 'completed', acceptanceEligible: true,
          warmMs: 105, coldMs: 250, executionMs: 120, cleanupMs: 1},
      },
    }))};
}

test('separate artifacts retain every registered case in the denominator', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-equivalent-aggregate-'));
  try {
    const parts = join(root, 'parts'), output = join(root, 'output');
    await mkdir(parts);
    const fixtures = retainedMatrix();
    for (const [index, fixture] of fixtures.entries()) {
      const artifact = join(parts,
        `equivalent-case-${String(index).padStart(2, '0')}-${revision}`);
      await mkdir(artifact);
      await writeFile(join(artifact, 'case-00.json'),
        JSON.stringify(passingRecord(fixture)));
    }
    const full = await aggregateEquivalentArtifacts(parts, output, revision);
    assert.equal(full.receivedRecords, 27);
    assert.deepEqual(full.missingArtifacts, []);
    assert.equal(full.status, 'pass');
    assert.equal(JSON.parse(await readFile(join(output, 'assessment.json'), 'utf8'))
      .cases.length, 27);

    await rm(join(parts, `equivalent-case-01-${revision}`), {recursive: true});
    const missing = await aggregateEquivalentArtifacts(parts, output, revision);
    assert.equal(missing.receivedRecords, 26);
    assert.deepEqual(missing.missingArtifacts,
      [`equivalent-case-01-${revision}`]);
    assert.equal(missing.status, 'incomplete');
  } finally {
    await rm(root, {recursive: true, force: true});
  }
});

test('a misplaced or foreign case cannot be admitted from an artifact', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-equivalent-aggregate-'));
  try {
    const parts = join(root, 'parts'), output = join(root, 'output');
    const artifact = join(parts, `equivalent-case-00-${revision}`);
    await mkdir(artifact, {recursive: true});
    await writeFile(join(artifact, 'case-00.json'), JSON.stringify({
      caseId: retainedMatrix()[1].id, pairs: [],
    }));
    await writeFile(join(parts, 'foreign-artifact'), 'not a registered case');
    const result = await aggregateEquivalentArtifacts(parts, output, revision);
    assert.equal(result.receivedRecords, 0);
    assert.equal(result.invalidArtifacts[0].error, 'ForeignCaseInArtifact');
    assert.deepEqual(result.unexpectedArtifacts, ['foreign-artifact']);
    assert.equal(result.status, 'incomplete');
  } finally {
    await rm(root, {recursive: true, force: true});
  }
});
