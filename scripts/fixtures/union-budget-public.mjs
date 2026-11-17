// Finite normal-package consumer. Copy with the two existing/data helpers into
// the canonical fresh tarball installation; never resolve checkout product JS.
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {connect} from '@actql/node';
import {unionBudgetCases} from './union-budget-source-input.mjs';
import {observeRecordApprovalDescriptors} from './scoped-fds.fixture.mjs';

const [phase, handoffPath] = process.argv.slice(2);
assert(['run', 'saved'].includes(phase) && handoffPath);
const directory = resolve('union-budget-state');
await mkdir(directory, {recursive: true});
const reportPath = resolve(`union-budget-${phase}.json`);
const report = {phase, complete: false, references: [], firstCloseReturned: false, firstClosePending: false,
  scopedFd0: false, compileCount: 'UNOBSERVABLE', normalPackageAcceptance: false};
await writeFile(reportPath, JSON.stringify(report) + '\n', {flag: 'wx'});
const persist = () => writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
const canonicalRows = rows => rows.map(row => JSON.stringify(row)).sort();
const assertResult = async (execution, fixture) => {
  assert.deepEqual(canonicalRows(await execution.result('main').all()),
    canonicalRows(fixture.expected), fixture.name + ': all rows and duplicates');
  assert.deepEqual((await execution.result('main').describe()).columns,
    fixture.columns, fixture.name + ': full column contracts');
};
let client, primary;
try {
  const original = phase === 'saved'
    ? JSON.parse(await readFile(handoffPath, 'utf8')) : undefined;
  if (original) {
    assert.equal(original.directory, directory);
    assert.equal(original.complete, true);
    assert.equal(original.firstCloseReturned, true);
    assert.equal(original.scopedFd0, true);
    assert.deepEqual(original.references.map(item => item.name), unionBudgetCases.map(item => item.name));
  }
  client = await connect({mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory}});
  if (phase === 'run') {
    // This ordinary public semantic refusal exercises same-Host recovery.
    // Explicit tiny-work refusal is separately proven in the Core caller test;
    // there is no invented public checking-budget option or equivalence claim.
    const invalid = await client.check('SELECT TRY_TIMESTAMP(1) AS value',
      {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(invalid.report.verdict, 'invalid');
    report.recoveryAfterKnownInvalid = true;
    for (const fixture of unionBudgetCases) {
      const submissionRef = client.newSubmission({nonce: 'union-budget-' + fixture.name});
      const execution = await client.startSource(fixture.text,
        {format: fixture.format, submissionRef});
      // Persist the original reference before wait; never recover by resubmit.
      report.references.push({name: fixture.name, ref: execution.ref, submissionRef});
      await persist();
      assert.equal((await execution.wait()).status, 'succeeded', fixture.name);
      await assertResult(execution, fixture);
    }
  } else {
    for (const [index, fixture] of unionBudgetCases.entries()) {
      const retained = original.references[index];
      const execution = await client.attach(retained.ref);
      assert.deepEqual(execution.ref, retained.ref);
      assert.equal((await execution.status()).status, 'succeeded', fixture.name);
      await assertResult(execution, fixture);
      const lookup = await client.lookupSubmission(retained.submissionRef);
      assert.equal(lookup.kind, 'ready');
      assert.deepEqual(lookup.admission.ref, retained.ref);
      report.references.push(retained);
    }
  }
} catch (cause) {
  primary = cause;
  report.primary = {name: String(cause?.name ?? 'Error'),
    code: cause?.code, message: String(cause?.message ?? cause)};
} finally {
  if (client) {
    // Keep the original primary and pending close durable BEFORE awaiting it.
    // A timeout cannot run the remainder of this finally block. A rejected
    // close still supplies no acknowledgment and leaves this pending fact.
    report.firstClosePending = true;
    try { await persist(); }
    catch (cause) { primary ??= cause; }
    // This bounded diagnostic deliberately excludes references, submission
    // tokens, rows and exception messages. The private full report stays above.
    const lastFixture = unionBudgetCases.find(item => item.name === report.references.at(-1)?.name)?.name;
    const code = typeof primary?.code === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,95}$/u.test(primary.code)
      ? primary.code : primary ? 'unclassified' : 'none';
    process.stderr.write('ACTQL_UNION_PENDING_CLOSE ' + JSON.stringify({phase,
      lastFixture: lastFixture ?? null, code, closePending: true}) + '\n');
    try {
      await client.close();
      report.firstCloseReturned = true;
      report.firstClosePending = false;
    }
    catch (cause) {
      report.closeFailure = {code: cause?.code, message: String(cause?.message ?? cause)};
      primary ??= cause;
    }
    try { await persist(); }
    catch (cause) { primary ??= cause; }
    try {
      report.descriptors = await observeRecordApprovalDescriptors([directory]);
      report.scopedFd0 = report.descriptors.openPaths.length === 0;
      assert(report.scopedFd0, 'same alive process after first awaited public close');
    } catch (cause) { primary ??= cause; }
  }
  report.complete = !primary;
  report.normalPackageAcceptance = !primary;
  try { await persist(); }
  catch (cause) { primary ??= cause; }
}
if (primary) throw primary;
if (phase === 'run') await writeFile(handoffPath,
  JSON.stringify({...report, directory}, null, 2) + '\n', {flag: 'wx'});
console.log(`Normal UNION budget ${phase}: ${report.references.length} original Results, first close returned, alive scoped FD0`);
