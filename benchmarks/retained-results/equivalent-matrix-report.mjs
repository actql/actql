import {readFile} from 'node:fs/promises';
import {assessEquivalentMatrix, formatEquivalentMatrix} from
  './equivalent-matrix-assessment.mjs';

const [path, revision, format, ...extra] = process.argv.slice(2);
if (!path || !revision || extra.length ||
    (format !== undefined && format !== '--markdown')) {
  throw new TypeError('Usage: equivalent-matrix-report.mjs PAIRS.json REVISION [--markdown]');
}
const records = JSON.parse(await readFile(path, 'utf8'));
const assessment = assessEquivalentMatrix(records, revision);
process.stdout.write(format === '--markdown'
  ? formatEquivalentMatrix(assessment)
  : JSON.stringify(assessment, null, 2) + '\n');
if (assessment.status !== 'pass') process.exitCode = 1;
