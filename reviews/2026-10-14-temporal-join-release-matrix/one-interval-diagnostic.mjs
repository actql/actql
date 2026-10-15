// Private single-submission observation over unchanged installed packages.
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyPackageRelease} from '../../scripts/package-release.mjs';
import {auditPackedPackages} from '../../scripts/packed-package-boundaries.mjs';
const [rc, installed, fresh] = process.argv.slice(2);
const manifest = await verifyPackageRelease(rc);
assert.equal(manifest.sourceSha, 'eee74e1f254f0679e809e605cfce5bec1fbe2996');
auditPackedPackages(installed, manifest.cohort.packages);
await mkdir(fresh, {mode: 0o700});
const require = createRequire(join(installed, 'package.json'));
const {sourcefreeFixtureAuthorization} = await import(pathToFileURL(join(installed, 'scripts/fixtures/release-sourcefree-authorization.mjs')));
const {temporalJoinSourceSuccesses} = await import(pathToFileURL(join(installed, 'scripts/fixtures/temporal-join-source-input.mjs')));
const authorization = await sourcefreeFixtureAuthorization('local', 'temporal-join', {directory: fresh});
const events = [];
const allowed = new Set(['dispatch_failed', 'dispatch_reserved', 'physical_start_reserved', 'computed', 'dispatch_cleanup_completed']);
authorization.observe = (event, detail) => {
  if (!allowed.has(event) || events.length >= 32) return;
  const ownTag = name => {
    const value = Object.getOwnPropertyDescriptor(detail, name)?.value;
    return Number.isSafeInteger(value) && value >= 0 && value <= 1000 ? value : null;
  };
  events.push({event, issueTag: ownTag('issueTag'), nestedIssueTag: ownTag('nestedIssueTag')});
};
const {open} = await import(pathToFileURL(require.resolve('@actql/node')));
let client, submissionRef, runRef, state, closeComplete = false, secretCalls = 0;
let phase = 'opening', errorObserved = false;
try {
  client = await open({stateDir: join(fresh, 'state'), durability: 'durable', installation: {
    authorization, resolveSourceSecret() {secretCalls++; throw new Error('UnexpectedSourceSecret');}}});
  phase = 'submitting';
  submissionRef = client.newSubmission({nonce: 'one-original-temporal-sql-interval-left'});
  const input = temporalJoinSourceSuccesses.find(item => item.name === 'temporal-sql-interval-left');
  const execution = await client.startSource(input.text, {format: input.format, submissionRef});
  phase = 'waiting';
  runRef = execution.ref;
  state = await execution.wait();
  phase = 'observed';
} catch {
  errorObserved = true;
} finally {
  if (client !== undefined) {
    try {await client.close(); closeComplete = true;} catch {errorObserved = true;}
  }
  await writeFile(join(fresh, 'observation.json'), JSON.stringify({
    artifactSource: manifest.sourceSha, privateDiagnostic: true, normalProductE2E: 0,
    freshSubmissions: submissionRef === undefined ? 0 : 1, submissionRef, runRef, state,
    phase, errorObserved, events, secretCalls, closeComplete,
    cleanupAck: null,
  }, null, 2) + '\n', {flag: 'wx', mode: 0o600});
}
console.log(JSON.stringify({privateDiagnostic: true, phase, events, secretCalls,
  freshSubmissions: submissionRef === undefined ? 0 : 1,
  observedStatus: state?.status ?? null, closeComplete, cleanupAck: null, normalProductE2E: 0}));
