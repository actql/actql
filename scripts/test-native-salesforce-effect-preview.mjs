import assert from 'node:assert/strict';
import {spawn, execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {once} from 'node:events';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {nativeResolutionFixture} from './fixtures/native-effect-resolution-fixture.mjs';
import {nativeEffectReviewFixture} from './fixtures/native-effect-review-fixture.mjs';
import {nativeEffectCheckpointReplyFixture} from './fixtures/native-effect-checkpoint-server.mjs';
import {readNativeEffectCaptureProgress} from './fixtures/native-effect-capture-progress.mjs';
import {startNativeBearerServers} from './fixtures/native-bearer-servers.mjs';
import {failedCoreDriver, diagnoseFailedCoreDriver, observeCoreChildProgress} from './native-compiler-stop-diagnostic.mjs';
import {redactCommandEvidence} from './packed-query-evidence.mjs';
const residentMappedCreate = process.argv.includes('--resident-original-mapped-create-write');
const residentApprovedRow = residentMappedCreate || process.argv.includes('--resident-approved-row-write');
const adoptedInitialHost = process.argv.includes('--adopted-initial-host-attestation');
const adoptedInitialReviewer = adoptedInitialHost || process.argv.includes('--adopted-initial-reviewer');
const originalLocalReview = adoptedInitialReviewer || process.argv.includes('--original-local-review');
const directLocalClaimCustody = process.argv.includes('--direct-local-claim-custody');
const residentOriginalHolder = residentApprovedRow || process.argv.includes('--resident-original-holder-review');
const residentCheckpoint = residentOriginalHolder || process.argv.includes('--resident-checkpoint-custody');
const residentPreview = residentCheckpoint || process.argv.includes('--resident-preview');
const residentEffectRuntimeCapture = process.argv.includes('--resident-effect-runtime-capture');
const residentProposals = residentPreview || residentEffectRuntimeCapture || process.argv.includes('--resident-proposals');
const coreIndex = process.argv.indexOf('--core-test-json');
const coreArgs = coreIndex < 0 ? undefined : JSON.parse(process.argv[coreIndex + 1]);
const countIndex = process.argv.indexOf('--core-test-count');
const coreExpectedTests = countIndex < 0 ? undefined : Number(process.argv[countIndex + 1]);
assert(coreExpectedTests === undefined || (coreArgs !== undefined &&
  Number.isSafeInteger(coreExpectedTests) && coreExpectedTests > 0), 'Invalid Native core test count');
assert(!directLocalClaimCustody || (!originalLocalReview && !residentProposals && coreArgs === undefined),
  'Direct Local claim custody requires its own finite fixture selection');
if (coreArgs !== undefined) {
  assert(Array.isArray(coreArgs) && coreArgs.every(arg => typeof arg === 'string') && !residentProposals,
    'Invalid Native core fixture invocation');
}
const corePartition = process.env.ACTQL_TEST_NATIVE_CORE_PARTITION;
assert(!corePartition || coreArgs !== undefined && (corePartition === '1/2' || corePartition === '2/2'),
  'Native Core partition requires its original selected case inventory');
// The unchanged write-oracle package belongs to exactly one ordinary
// partition. Its sibling retains the same peer but must make zero requests.
const coreTargetOracle = !corePartition ||
  coreArgs.includes('src/platform_native/salesforce_effect_preview/native_test');
// The complete file has two authored successful Provider observations: the
// proposal case and Checkpoint custody. Its revoked-permission case sends none.
const completeRetainedProposals = residentProposals && !residentPreview && !residentEffectRuntimeCapture;

const scratch = process.env.ACTQL_TEST_SCRATCH_ROOT ?? (coreArgs === undefined ? undefined :
  join(process.cwd(), '_build', 'native-core-physical'));
assert(typeof scratch === 'string' && scratch.length > 0,
  'ACTQL_TEST_SCRATCH_ROOT is required');
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch, 'native-salesforce-target-'));
const openssl = (...args) => execFileSync('openssl', args,
  {cwd: root, stdio: 'ignore', timeout: 10_000});
openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout',
  'ca.key', '-out', 'ca.crt', '-days', '1', '-subj', '/CN=ActQL Target Test CA');
openssl('req', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server.key',
  '-out', 'server.csr', '-subj', '/CN=localhost');
await writeFile(join(root, 'server.ext'),
  'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n');
openssl('x509', '-req', '-in', 'server.csr', '-CA', 'ca.crt', '-CAkey',
  'ca.key', '-CAcreateserial', '-out', 'server.crt', '-days', '1',
  '-extfile', 'server.ext');
await writeFile(join(root, 'credential.secret'), 'native-target-test\n',
  {mode: 0o600});
const paths = [];
const reviewFixture = nativeEffectReviewFixture('Bearer native-target-test');
let localRejectionRequests = 0;
let writes = 0;
let rejectedWrites = 0;
const writeBodies = [];
const effectCurrentReports = [];
const expected = '/services/data/v66.0/sobjects/ActQL_Test_Record__c/';
const server = createServer({key: await readFile(join(root, 'server.key')),
  cert: await readFile(join(root, 'server.crt'))}, (request, response) => {
  if (request.method === 'POST' && request.url === '/fixture/native-local-effect-rejection') {
    if (request.headers.authorization !== 'Bearer native-target-test') {
      response.writeHead(403); response.end(); return;
    }
    const chunks = []; let bytes = 0;
    request.on('data', chunk => {bytes += chunk.length;
      if (bytes > 262144) request.destroy(); else chunks.push(chunk);});
    request.on('end', () => {
      try {
        const fixture = nativeResolutionFixture(Buffer.concat(chunks).toString('utf8'),
          {decision: 'rejected'});
        localRejectionRequests++;
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify(fixture));
      } catch {response.writeHead(422); response.end();}
    });
    return;
  }
  if (residentMappedCreate && request.method === 'POST' && request.url === '/fixture/effect-current') {
    if (request.headers.authorization !== 'Bearer native-target-test' ||
        request.headers['content-type'] !== 'application/json') {
      response.writeHead(403); response.end(); return;
    }
    const chunks = []; let bytes = 0;
    request.on('data', chunk => {bytes += chunk.length; if (bytes > 65536) request.destroy(); else chunks.push(chunk);});
    request.on('end', async () => {
      try {
        const {checkpointReportRequests, checkpointReportWire} = reviewFixture.facts();
        assert.equal(checkpointReportRequests, 2);
        assert.notEqual(checkpointReportWire, undefined);
        const body = Buffer.concat(chunks);
        const reply = JSON.parse(body.toString('utf8'));
        const original = JSON.parse(nativeEffectCheckpointReplyFixture(checkpointReportWire));
        assert.equal(reply.version, 'actql-remote-effect-current-reply/0.1');
        for (const field of ['report_cid', 'checkpoint_cid', 'dispatch_request_cid']) {
          assert.equal(reply[field], original[field]);
        }
        assert.equal(typeof reply.response_saved, 'boolean');
        effectCurrentReports.push({queryId: reply.query_id, queryCid: reply.query_cid,
          reportCid: reply.report_cid, ledgerHeadCid: reply.ledger_head_cid,
          recoveryAction: reply.recovery_action, responseSaved: reply.response_saved,
          bodySha256: createHash('sha256').update(body).digest('hex')});
        if (reply.query_id === 'native-current-revoked') {
          // Revoke this fixture's independent evidence-read authority after
          // receiving the bytes, before returning its transport receipt.
          await writeFile(join(root, 'current-evidence-revoked'), 'revoked');
        }
        // A transport refusal retains the original review. This peer does not
        // issue an Effect ACK, durable Cloud commit or authority to retry a write.
        response.writeHead(effectCurrentReports.length === 1 ? 503 : 200);
        response.end();
      } catch { response.writeHead(422); response.end(); }
    });
    return;
  }
  if (residentOriginalHolder && reviewFixture.handle(request, response)) return;
  if (request.method === 'PATCH' &&
      [expected + '001000000000001', expected + '001000000000002',
        expected + '001000000000003'].includes(request.url)) {
    if (request.headers.authorization !== 'Bearer native-target-test' ||
        request.headers['content-type'] !== 'application/json') {
      response.writeHead(403); response.end(); return;
    }
    const chunks = []; let bytes = 0;
    request.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > 1024) request.destroy(); else chunks.push(chunk);
    });
    request.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      assert.equal(body, '{"Optional_Value__c":"new"}');
      paths.push({method: request.method, path: request.url});
      if (request.url === expected + '001000000000003') {
        rejectedWrites++;
        response.writeHead(409, {'content-type': 'application/json'});
        response.end('{"refused":"e\\u0301\\r\\n"}');
        return;
      }
      writes++;
      writeBodies.push(body);
      if (request.url === expected + '001000000000002') {
        // The Provider accepted the write; the caller loses the response.
        request.socket.destroy();
      } else {
        response.writeHead(200, {'content-type': 'application/json'});
        response.end('{"saved":"e\\u0301\\r\\n"}');
      }
    });
    return;
  }
  if (request.method !== 'GET') writes++;
  paths.push({method: request.method, path: request.url});
  if (request.headers.authorization !== 'Bearer native-target-test' ||
      request.method !== 'GET' ||
      ![expected + '001000000000001', expected + '001000000000002']
        .includes(request.url)) {
    response.writeHead(403); response.end(); return;
  }
  // An actual physical fixture record, independent of the proposed update.
  // The second path deliberately returns a foreign record for the refusal case.
  response.writeHead(200, {'content-type': 'application/json'});
  response.end(JSON.stringify({Id: '001000000000001AAA',
    Optional_Value__c: 'e\u0301\r\n'}));
});
let child;
let bearer;
try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = `https://127.0.0.1:${server.address().port}`;
  const hash = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
  // Independent wire fixture, admitted and signature-checked by the real
  // credential Owner. No Cloud materials or Preview success are synthesized.
  const body = JSON.stringify({connector_registration: 'salesforce',
    connector_revision: 'salesforce/0.1',
    dispatch_request_cid: 'sha256:' + 'c'.repeat(64), environment: 'test',
    expires_unix_ms: '2000000000000', issuer_authority: 'credential-authority-a',
    max_uses: 1, namespace_id: 'namespace-a', operation: 'salesforce:record:observe',
    principal: 'principal-a', resource_origin: origin,
    run_invocation_cid: 'sha256:' + 'b'.repeat(64),
    runtime_bundle_cid: 'sha256:' + 'a'.repeat(64), site_generation: 4,
    site_key: 'site-a', task_attempt: 3, version: 'actql-remote-credential-grant/0.1'});
  const cid = hash(body);
  const keys = generateKeyPairSync('ed25519');
  const signature = sign(null,
    Buffer.from('actql-remote-credential-grant-signature/0.1\0' + cid + '\0' + body),
    keys.privateKey).toString('base64url');
  const writeBody = JSON.stringify({...JSON.parse(body), operation: 'salesforce:record:update'});
  const writeCid = hash(writeBody);
  const writeSignature = sign(null,
    Buffer.from('actql-remote-credential-grant-signature/0.1\0' + writeCid + '\0' + writeBody),
    keys.privateKey).toString('base64url');
  const testEnv = {...process.env, ...nativeResolutionFixture(),
    ACTQL_TEST_EFFECT_RESOLUTION_FIXTURE_URL:origin+'/fixture/effect-resolution',
    ACTQL_TEST_EFFECT_REVIEW_UPLOAD_FIXTURE_URL:origin+'/fixture/effect-review',
    ACTQL_TEST_EFFECT_REVIEW_REPORT_FIXTURE_URL:origin+'/fixture/effect-review-report',
    ACTQL_TEST_NATIVE_HTTP_URL: origin,
    ACTQL_TEST_NATIVE_HTTP_CA: join(root, 'ca.crt'),
    ACTQL_TEST_NATIVE_HTTP_SECRET: join(root, 'credential.secret'),
    ACTQL_TEST_NATIVE_HTTP_LIBRARY: process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
      (process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4'),
    ACTQL_TEST_NATIVE_SQLITE_LIBRARY: process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
      (process.platform === 'darwin' ? '/usr/lib/libsqlite3.dylib' : 'libsqlite3.so.0'),
    ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
      (process.platform === 'darwin' ? '/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib' : 'libcrypto.so.3'),
    ACTQL_TEST_NATIVE_TARGET_ROOT: root,
    ACTQL_TEST_NATIVE_SALESFORCE_WRITE_GRANT_BODY: writeBody,
    ACTQL_TEST_NATIVE_SALESFORCE_WRITE_GRANT_CID: writeCid,
    ACTQL_TEST_NATIVE_SALESFORCE_WRITE_SIGNATURE: writeSignature,
    ACTQL_TEST_NATIVE_CREDENTIAL_GRANT_BODY: body,
    ACTQL_TEST_NATIVE_CREDENTIAL_GRANT_CID: cid,
    ACTQL_TEST_NATIVE_CREDENTIAL_SIGNATURE: signature,
    ACTQL_TEST_NATIVE_CREDENTIAL_PUBLIC_KEY:
      keys.publicKey.export({type: 'spki', format: 'pem'}),
  };
  if (originalLocalReview) {
    assert(!residentProposals && coreArgs === undefined,
      'Original Local review selects its own focused Native caller');
    assert(testEnv.ACTQL_TEST_DUCKDB_LIBRARY, 'Native DuckDB library is required');
    const retainedRoot = join(root, 'retained');
    await mkdir(retainedRoot, {mode: 0o700});
    Object.assign(testEnv, {ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT: retainedRoot,
      ACTQL_TEST_NATIVE_SQLITE_ROOT: retainedRoot, ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS: '1'});
  }
  if (residentProposals) {
    assert(testEnv.ACTQL_TEST_DUCKDB_LIBRARY, 'Native DuckDB library is required');
    const target = process.platform === 'darwin' && process.arch === 'arm64'
      ? 'aarch64-apple-darwin'
      : process.platform === 'linux' && process.arch === 'x64'
        ? 'x86_64-unknown-linux-gnu' : undefined;
    assert(target, 'Unsupported Native fixture target');
    // Independent signed test bundle, admitted by the existing runtime Owner.
    // Its placeholder component is not a formal production Site binary.
    const component = Buffer.from('native-runtime');
    const runtimeBody = JSON.stringify({bundle_name: 'native-runtime',
      components: [{bytes: String(component.length), cid: hash(component),
        role: 'runtime_executable'}], connector_registration: 'local',
      connector_revision: 'local/1', issuer_authority: 'bundle-authority-a',
      revision: 'native/1', strategy_revision: 'strategy/1', target_triple: target,
      version: 'actql-remote-runtime-bundle/0.1'});
    const runtimeCid = hash(runtimeBody);
    const runtimeKeys = generateKeyPairSync('ed25519');
    bearer = await startNativeBearerServers({host: '127.0.0.1',
      key: await readFile(join(root, 'server.key')),
      cert: await readFile(join(root, 'server.crt')), root, allowEffectWrite: residentApprovedRow && !residentMappedCreate,
      allowEffectCreate: residentMappedCreate});
    await mkdir(join(root, 'retained'), {recursive: true});
    Object.assign(testEnv, {
      ACTQL_TEST_NATIVE_EFFECT_APPROVED_ROW: residentApprovedRow ? '1' : '0',
      ACTQL_TEST_NATIVE_HTTP_BEARER_URL: bearer.origin,
      ACTQL_TEST_NATIVE_HTTP_BEARER_ROOT: bearer.directory,
      ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT: join(root, 'retained'),
      ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS: '1',
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: target,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: runtimeCid,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: runtimeBody,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
        runtimeKeys.publicKey.export({type: 'spki', format: 'pem'}),
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: sign(null,
        Buffer.from('actql-remote-runtime-bundle-signature/0.1\0' +
          runtimeCid + '\0' + runtimeBody), runtimeKeys.privateKey)
        .toString('base64url'),
    });
  }
  if (residentMappedCreate) testEnv.ACTQL_TEST_EFFECT_CURRENT_FIXTURE_URL = origin + '/fixture/effect-current';
  // Only this package consumes the target fixture. A full Core run must not
  // accidentally activate unrelated optional HTTP tests with this endpoint.
  for (const suffix of ['HTTP_URL', 'HTTP_CA', 'HTTP_SECRET', 'HTTP_LIBRARY', 'TARGET_ROOT',
    'CREDENTIAL_GRANT_BODY', 'CREDENTIAL_GRANT_CID', 'CREDENTIAL_SIGNATURE', 'CREDENTIAL_PUBLIC_KEY']) {
    const key = 'ACTQL_TEST_NATIVE_' + suffix;
    testEnv['ACTQL_TEST_NATIVE_SALESFORCE_' + suffix] = testEnv[key];
    if (coreArgs !== undefined) {
      if (process.env[key] === undefined) delete testEnv[key];
      else testEnv[key] = process.env[key];
    }
  }
  // The ordinary target fixture also executes this refusal case in its same
  // Native selection. The dedicated flag narrows execution; it adds no job or
  // successful writes to the existing Provider expectations.
  if (!residentProposals && !originalLocalReview) testEnv.ACTQL_TEST_NATIVE_DIRECT_LOCAL_CLAIM_CUSTODY = '1';
  else delete testEnv.ACTQL_TEST_NATIVE_DIRECT_LOCAL_CLAIM_CUSTODY;
  const selection = adoptedInitialHost
    ? 'src/platform_native/remote_resident_source_compute_tests/initial_host_attestation_paired_signing_wbtest.mbt'
    : adoptedInitialReviewer
    ? 'src/platform_native/remote_resident_source_compute_tests/initial_reviewer_paired_signing_wbtest.mbt'
    : directLocalClaimCustody
    ? 'src/platform_native/credential_resource/guarded_write_native_wbtest.mbt'
    : originalLocalReview
    ? 'src/platform_native/remote_resident_source_compute_tests/local_client_effect_source_wbtest.mbt'
    : residentOriginalHolder
    ? 'src/platform_native/remote_resident_source_compute_tests/acquisition_runtime_wbtest.mbt'
    : residentProposals
    ? 'src/platform_native/remote_resident_source_compute_tests/retained_compute_wbtest.mbt'
    : 'src/platform_native/salesforce_effect_preview/native_test/target_test.mbt';
  const moonArgs = coreArgs === undefined ? ['--target', 'native', ...(!originalLocalReview ? ['--strip'] : []), selection,
    ...(!residentProposals && !originalLocalReview && !directLocalClaimCustody ? ['src/platform_native/salesforce_effect_preview/native_test/resolution_test.mbt',
      'src/platform_native/salesforce_effect_preview/native_test/credential_write_test.mbt',
      'src/platform_native/credential_resource/guarded_write_native_wbtest.mbt'] : []),
    ...(directLocalClaimCustody ? ['--filter', 'Native retained credential claim never repairs*']
      : residentMappedCreate ? ['--filter', 'original completion-free mapped-create approval retains one physical write through response custody loss']
      : residentOriginalHolder ? ['--filter', 'Effect original holders retain physical Provider review*']
      : residentCheckpoint ? ['--filter', 'Native Checkpoint custody*']
      : residentPreview ? ['--filter', 'Native retained consumer*']
      : residentEffectRuntimeCapture ? ['--filter', 'Effect retained consumer completes through Runtime*'] : [])]
    : ['--target', 'native', ...coreArgs];
  const compilerDriver = coreArgs !== undefined && process.platform === 'darwin' &&
      process.env.ACTQL_TEST_NATIVE_COMPILER_DIAGNOSTIC === '1'
    ? failedCoreDriver(process.cwd(), process.env.MOON_HOME) : undefined;
  // The full Core child includes cold Native compilation and every selected
  // test. Its finite budget is separate from the ordinary fixture oracles.
  child = spawn(process.execPath, ['--input-type=module', '-e',
    "import {runFocusedTests} from './scripts/test-execution.mjs'; " +
    "process.exitCode = runFocusedTests('moon', " + JSON.stringify(moonArgs) + ", " +
    "{timeout: " + (originalLocalReview ? 600000 : coreArgs === undefined ? 180000 : 3600000) +
    ", expectedTests: " + JSON.stringify(coreExpectedTests) + ", evidenceScratch: " + JSON.stringify(root) + "});"],

  {env: testEnv, stdio: compilerDriver ? ['inherit', 'pipe', 'pipe'] : 'inherit'});
  if (compilerDriver) {
    child.stdout.on('data', chunk => {
      process.stdout.write(chunk);
      compilerDriver.write(chunk, 'stdout');
    });
    child.stderr.on('data', chunk => {
      process.stderr.write(chunk);
      compilerDriver.write(chunk, 'stderr');
    });
  }
  // This observer reads only the original live process tree. Keep buffered
  // nonzero-test evidence and all selected tests/deadlines unchanged.
  const stopProgress = compilerDriver
    ? observeCoreChildProgress(child, {root: process.cwd()}) : () => {};
  const [code, signal] = await once(child, 'close');
  stopProgress();
  child = undefined;
  if (code !== 0 && compilerDriver) {
    let diagnostic;
    try {
      diagnostic = diagnoseFailedCoreDriver({driver: compilerDriver, root: process.cwd(),
        namespace: root, env: testEnv});
    } catch {
      // A failed observation must never replace the original test failure.
      diagnostic = {attempted: true, cause: 'unobserved', cleanup: 'unobserved'};
    }
    console.error('ACTQL_COMPILER_FAILURE_DIAGNOSTIC ' +
      redactCommandEvidence(JSON.stringify(diagnostic), testEnv));
  }
  const {resolutionRequests, reviewUploads, checkpointReportRequests,
    checkpointReportWire, reviewUploadBodies} = reviewFixture.facts();
  await writeFile(join(root, 'physical-receipt.json'), JSON.stringify({
    code, signal, requests: paths, writes, rejectedWrites, writeBodies, resolutionRequests, localRejectionRequests, reviewUploads, reviewUploadBodies,
    effectCurrentReports,
    checkpointReportRequests, checkpointReportSha256: checkpointReportWire === undefined ? undefined :
      createHash('sha256').update(checkpointReportWire).digest('hex'),
    provider: bearer?.effectTargets(), providerValue: bearer?.effectTargetValue(),
    providerCreated: residentMappedCreate ? bearer.effectCreatedValues() : undefined,
    captureProgress: residentOriginalHolder ? await readNativeEffectCaptureProgress(join(root, 'retained')) : undefined,
    scope: adoptedInitialHost
      ? 'Actual adopted Host/Source/computation/Preview/Checkpoint -> same initial Reviewer candidate -> explicit independent Account Sign -> first full unsigned Host wrapper/time durable before claim -> actual independent Host signature -> same stored wrapper restore -> original Native Resolution admission/rejection/cleanup; component only, no public CLI approval/whole-engine backing/performance acceptance'
      : adoptedInitialReviewer
      ? 'Actual adopted Local Host journal/epoch/Account scope -> original Source/computation/Preview/Checkpoint -> same initial Reviewer physical signing and current candidate restore; existing independent fixture rejection retires review; no Local Host attestation, CLI approval, whole-engine backing or performance acceptance'
      : directLocalClaimCustody
      ? 'Native credential adapter original ordinal/use custody refusal for Local and Remote types; no adopted Local Host, public CLI, approval or Provider write acceptance'
      : originalLocalReview
      ? 'Actual accepted original Local Run -> acquired Source and imported Result -> checked protocol Preview -> encrypted capture/Preview/Checkpoint -> original journal waiting -> signed explicit rejection -> retryable cleanup; no public CLI or Provider write or separate-process recovery'
      : residentMappedCreate
      ? 'Actual original completion-free Source/consumer -> mapped-create Preview without target read -> locally signed original Resolution -> one physical POST -> raw response custody loss/retry -> common row terminal; local trusted claim only; no Cloud approval, Host restart or formal Run release'
      : residentApprovedRow
      ? 'Actual original Source/consumer holder -> signed original Resolution -> common Ledger claim -> one physical Provider write -> raw response retention/retry -> admitted common row terminal; local trusted resume fixture; no Cloud claim, public Effect apply, restart or formal Run release'
      : residentOriginalHolder
      ? 'Actual original producer and consumer holders -> physical HTTPS Provider Preview -> encrypted capture and original Checkpoint and signed Resolution admission boundary; live Ledger retained; no Cloud waiting commit, resume claim or Provider write'
      : residentEffectRuntimeCapture
      ? 'Actual retained Native computation, dependency capture and encrypted Store custody; protocol target metadata only; no approval, apply or Cloud'
      : residentProposals
      ? 'Actual retained Native consumer -> physical HTTPS target observation -> checked Preview plan -> computation capture and encrypted Store custody; live Ledger retained; no waiting, approval, apply or Cloud'
      : 'Native HTTPS target observation, signed credential admission and exact bounded Provider write transport; no signed Effect approval, Effect Ledger, Source capture, whole Preview or Cloud apply'}, null, 2) + '\n');
  assert.equal(code, 0, `Native target observation failed: ${signal ?? code}`);
  const expectedWrites = residentProposals || originalLocalReview || directLocalClaimCustody || !coreTargetOracle ? 0 : 2;
  assert.equal(writes, expectedWrites);
  assert.equal(rejectedWrites, residentProposals || originalLocalReview || directLocalClaimCustody || !coreTargetOracle ? 0 : 1);
  assert.deepEqual(writeBodies, Array(expectedWrites).fill('{"Optional_Value__c":"new"}'));
  assert.equal(resolutionRequests,residentOriginalHolder?1:0);
  assert.equal(reviewUploads,residentOriginalHolder?6:0);
  assert.equal(checkpointReportRequests,residentOriginalHolder?2:0);
  if(residentOriginalHolder){for(const body of reviewUploadBodies.slice(1))assert.deepEqual(body,reviewUploadBodies[0]);}
  if (residentMappedCreate) {
    assert.equal(effectCurrentReports.length, 5, 'Denied or foreign queries reached the transport');
    assert.deepEqual(effectCurrentReports.map(value => [value.queryId, value.recoveryAction, value.responseSaved]), [
      ['native-current-before-send', 0, false], ['native-current-before-send', 0, false],
      ['native-current-revoked', 0, false],
      ['native-current-pending', 3, true], ['native-current-terminal', 5, true],
    ]);
    assert.deepEqual(effectCurrentReports[0], effectCurrentReports[1], 'Explicit retry changed the original current snapshot before the write');
  }
  if (directLocalClaimCustody) {
    assert.equal(localRejectionRequests, 0);
    assert.deepEqual(paths, []);
  } else if (originalLocalReview) {
    assert.equal(localRejectionRequests, adoptedInitialHost ? 0 : 1);
    assert.deepEqual(paths, []);
  } else if (residentProposals) {
    assert.deepEqual(paths, []);
    assert.deepEqual(bearer.effectTargets(), {reads: completeRetainedProposals ? 2 : residentMappedCreate || residentEffectRuntimeCapture ? 0 : 1, writes: residentApprovedRow ? 1 : 0});
    assert.equal(bearer.effectTargetValue(), residentApprovedRow && !residentMappedCreate ? 3 : 7);
    if (residentMappedCreate) assert.deepEqual(bearer.effectCreatedValues(),
      [{Id: '001000000000001AAA', Count__c: 3}]);
  } else if (coreTargetOracle) {
    assert.deepEqual(paths.filter(value => value.method === 'GET'), [
      {method: 'GET', path: expected + '001000000000001'},
      {method: 'GET', path: expected + '001000000000001'},
      {method: 'GET', path: expected + '001000000000002'},
    ]);
    assert.deepEqual(paths.filter(value => value.method === 'PATCH'), [
      {method: 'PATCH', path: expected + '001000000000001'},
      {method: 'PATCH', path: expected + '001000000000002'},
      {method: 'PATCH', path: expected + '001000000000003'},
    ]);
  } else {
    assert.deepEqual(paths, []);
  }
  console.log(`Native Salesforce target observation receipt: ${join(root, 'physical-receipt.json')}`);
} finally {
  if (child !== undefined) {
    const closing = once(child, 'close');
    child.kill('SIGKILL');
    await closing;
  }
  if (bearer !== undefined) await bearer.close();
  server.closeAllConnections();
  await new Promise((resolve, reject) => server.close(error =>
    error ? reject(error) : resolve()));
}
