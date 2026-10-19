import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import recipeModule from './host-journal-service-recipe.cjs';
import nativeImage from './host-journal-native-image.cjs';
import {createHostJournalDirectoryInspector} from './host-journal-directory.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody,
  assertOriginalClientRequestJournalFacilityCurrent} from './client-request-journal.mjs';

const shared = Object.freeze({explicitUnaccountedControlFixture: true});
const recipe = recipeModule.declareHostJournalServiceRecipe(shared);
const temporaryDirectory = tmpdir();
const error = {code: 'HostJournalServiceArgumentsUnavailable'};
const noCurrent = () => {};

test('fixed Journal selection retains original callbacks and cannot receive caller limits', () => {
  const control = Object.freeze({explicitControlAlias: true});
  const directory = () => {};
  const options = {updateOriginalControl: control, submissionEpochNow: undefined,
    submissionEpochTtlMs: undefined};
  const selected = recipe.selectArguments(options, directory, temporaryDirectory, noCurrent);
  assert.strictEqual(selected.updateOriginalControl, control);
  assert.strictEqual(selected.primaryCurrent, noCurrent);
  assert.strictEqual(selected.primaryDirectoryInspection, directory);
  assert.strictEqual(selected.primarySqlLimits, recipe.journal.primarySqlLimits);
  assert.equal(selected.inspectionTemporaryDirectory, temporaryDirectory);
  assert.equal(Object.getPrototypeOf(selected), null);
  assert.ok(Object.isFrozen(selected));
  options.updateOriginalControl = {};
  assert.strictEqual(selected.updateOriginalControl, control);
  assert.throws(() => recipe.selectArguments({...options, maxDatabaseBytes: 1},
    directory, temporaryDirectory, noCurrent), error);
  assert.strictEqual(recipe.sharedControl, shared);
  assert.equal(recipe.numericalBackingClaim, false);
  assert.equal(recipe.allocationSuccessGuaranteed, false);
});

test('selected Journal arguments refuse accessors, proxies and clock closures without calling them', () => {
  let observed = 0;
  for (const options of [
    {get updateOriginalControl() { observed++; }},
    {get submissionEpochNow() { observed++; }},
    {submissionEpochNow() { observed++; }},
    new Proxy({}, {ownKeys() { observed++; return []; }}),
  ]) {
    assert.throws(() => recipe.selectArguments(options, () => {}, temporaryDirectory, noCurrent), error);
  }
  assert.equal(observed, 0);
  assert.throws(() => recipe.selectArguments({}, () => {}, 'relative', noCurrent), error);
  const original = new Error('same original current refusal');
  assert.throws(() => recipe.selectArguments({}, () => {}, temporaryDirectory,
    () => { throw original; }), value => value === original);
});

test('current callbacks cannot replace fixed argument construction or unknown-name refusal', () => {
  const originalCreate = Object.create, originalAssign = Object.assign;
  const originalIncludes = Array.prototype.includes;
  let entered = 0;
  const poison = () => {
    Object.create = () => { entered++; throw new Error('ReplacedCreate'); };
    Object.assign = () => { entered++; throw new Error('ReplacedAssign'); };
    Array.prototype.includes = () => true;
  };
  let selected, failure;
  try {
    selected = recipe.selectArguments({}, () => {}, temporaryDirectory, poison);
    try { recipe.selectArguments({maxDatabaseBytes: 1}, () => {}, temporaryDirectory, poison); }
    catch (cause) { failure = cause; }
  } finally {
    Object.create = originalCreate;
    Object.assign = originalAssign;
    Array.prototype.includes = originalIncludes;
  }
  assert.equal(entered, 0);
  assert.equal(Object.getPrototypeOf(selected), null);
  assert.strictEqual(selected.primarySqlLimits, recipe.journal.primarySqlLimits);
  assert.equal(failure?.code, error.code);
});

// Real retained Darwin directory module and SQLite/FS. The selected recipe and
// Host/control below remain explicit unaccounted fixtures, not a production
// operational issuer, full namespace or normal installed N0 qualification.
const packageRoot = process.env.ACTQL_DIRECTORY_NATIVE_DIAGNOSTIC_ROOT;
function selectedArguments(current) {
  assert.equal(typeof packageRoot, 'string', 'the matching retained native package is required');
  const fact = JSON.parse(readFileSync(join(packageRoot,
    '_build/native/directory-original.json'), 'utf8')).binary;
  const limits = Object.freeze({...recipe.directoryLimits, temporaryDirectory});
  const image = nativeImage.loadHostJournalDirectoryNative(packageRoot, fact, limits, noCurrent);
  const inspection = createHostJournalDirectoryInspector(image.operations, limits, current);
  return recipe.selectArguments({}, inspection, temporaryDirectory, current);
}
async function fixture(label) {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-selected-service-', label,
  });
  return {scratch, directory: join(scratch.path, 'requests')};
}

test('fixed service arguments construct both actual Journal connections and inspect their same saved bytes', async () => {
  const {scratch, directory} = await fixture('fixed Journal recipe actual constructor and cold inspection');
  let fences = 0;
  const current = () => {
    fences++;
    assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync);
  };
  const selected = selectedArguments(current);
  const first = openClientRequestJournal(directory, selected);
  first.observationStorage();
  first.close();
  assert.equal(observeOriginalClientRequestJournalCustody(first).databaseClosed, true);
  assert.equal(observeOriginalClientRequestJournalCustody(first).observationDatabaseClosed, true);
  const second = openClientRequestJournal(directory, selected);
  second.observationStorage();
  second.close();
  assert.equal(observeOriginalClientRequestJournalCustody(second).databaseClosed, true);
  assert.equal(observeOriginalClientRequestJournalCustody(second).observationDatabaseClosed, true);
  assert.ok(fences > 1);
  scratch.passed();
});

test('same fixed current reaches native operations while original Journal close remains reachable', async () => {
  const {scratch, directory} = await fixture('fixed Journal recipe same current and physical close');
  let changed = false;
  const original = new Error('same selected facility changed');
  const current = () => {
    if (changed) throw original;
    assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync);
  };
  const selected = selectedArguments(current);
  const journal = openClientRequestJournal(directory, selected);
  changed = true;
  assert.throws(() => journal.observationStorage(), value => value === original);
  journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  assert.equal(observeOriginalClientRequestJournalCustody(journal).observationAttempted, false);
  scratch.passed();
});
