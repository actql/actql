// Reuse an explicitly named successful real-service acceptance's immutable
// observations. The child has no provider credential port or replay permission.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonicalJson} from '../packages/sdk/host-port.mjs';
import {createCommandEvidence} from './packed-query-evidence.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const original = process.argv[2];
assert.ok(isAbsolute(original ?? ''), 'Explicit original acceptance record required');
const stat = await lstat(original);
assert.ok(stat.isFile() && !stat.isSymbolicLink() && stat.uid === process.getuid());
const bytes = await readFile(original);
const accepted = JSON.parse(bytes);
assert.equal(accepted.version, 'actql-real-gcs-content-acceptance/0.1');
assert.equal(accepted.complete, true, 'An unfinished acquisition cannot establish retained expectations');
const originalRoot = await realpath(dirname(original));
const evidence = createCommandEvidence({scratch: join(repository, '..', '.codex-scratch'),
  prefix: 'gcs-retained-restart-', cwd: repository});
const record = {version: 'actql-gcs-retained-restart-acceptance/0.1',
  originalRecordSha256: createHash('sha256').update(bytes).digest('hex'),
  originalSource: accepted.source, complete: false, cases: [],
  limitation: 'Source-built recovery of previously accepted Runs, not fresh packed acquisition or Model/COMMAND acceptance'};
try {
  for (const entrance of ['Local', 'HTTPS']) {
    const cases = accepted.cases.filter(value => value.entrance === entrance);
    assert.equal(cases.length, 2);
    assert.ok(cases.every(value => value.complete));
    const root = join(evidence.directory, entrance);
    await mkdir(root, {mode: 0o700});
    const configuration = join(root, 'restart.json');
    const canonical = value => canonicalJson(value, {dataKeys: true});
    await writeFile(configuration, JSON.stringify({version: 'actql-gcs-content-restart-fixture/0.1',
      entrance, evidenceDirectory: root, privateKeyPath: join(originalRoot, 'site-key.pem'),
      installation: {directory: join(originalRoot, entrance, 'host'),
        sourceProfilePath: join(originalRoot, entrance, 'source.json'),
        hostLookupExecutionPolicy: {version: 'actql-lookup-execution-policy/0.1',
          max_network_attempts_per_request: 3, max_request_bytes_per_attempt: 4096,
          max_total_request_bytes: 73728, max_total_response_bytes: 49152,
          max_total_decoded_response_bytes: 49152, max_total_duration_ms: 30000}},
      authorization: {accountConfiguration: canonical({version: 'actql-execution-account-config/0.1',
        account_id: 'gcs-public-host', entries: [{entry_id: 'run', outcome: 'allow', exclusions: [],
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['read', 'write']}}]})}, cases,
    }), {flag: 'wx', mode: 0o600});
    const {result, outcome, writeFailure} = evidence.capture(process.execPath,
      ['scripts/gcs-files-content-restart.mjs', configuration], {cwd: repository, timeout: 60000});
    if (writeFailure) throw writeFailure;
    assert.equal(result.status, 0, `Retained public restart failed: ${outcome.id}`);
    const observed = JSON.parse(result.stdout.trim().split('\n').at(-1));
    assert.equal(observed.complete, true);
    assert.notEqual(observed.pid, process.pid);
    assert.equal(observed.credentialCalls, 0);
    record.cases.push(observed);
    console.log(`GCS_RETAINED_RESTART ${entrance}: passed`);
  }
  record.complete = true;
} finally {
  await writeFile(join(evidence.directory, 'acceptance.json'), JSON.stringify(record, null, 2), {mode: 0o600});
  evidence.finish(record.complete ? 'passed' : 'failed');
  console.log(`Retained GCS restart ${record.complete ? 'passed' : 'incomplete'}: ${evidence.directory}`);
}
