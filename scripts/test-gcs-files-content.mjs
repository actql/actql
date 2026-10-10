// Explicitly authorized read-only real-service acceptance. No object setup,
// writes, deletes, IAM mutation, alternate acquisition or reference issuer.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {isAbsolute, join} from 'node:path';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import * as moon from '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from '../adapters/host-node/embedded-local.mjs';
import {connect as connectRemote} from '../packages/sdk/index.mjs';
import {canonicalJson} from '../packages/sdk/host-port.mjs';
import {restoreGcsSourceDeclaration} from '../adapters/connectors/gcs/host/gcs-source-declaration.mjs';
import {fixtureCertificates} from '../adapters/site-node/https-exchange-fixture.mjs';
import {createCommandEvidence} from './packed-query-evidence.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {checkGcsAcceptanceEnvironment, gcsAcceptancePrograms} from './gcs-files-content-environment.mjs';
import {createGcsAcceptanceCredential} from './gcs-files-content-credential.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const configurationPath = process.argv[2];
assert.ok(isAbsolute(configurationPath ?? ''), 'Explicit absolute authorized environment manifest required');
const configuration = checkGcsAcceptanceEnvironment(JSON.parse(await readFile(configurationPath, 'utf8')));
const pageBytes = 8192;
assert.ok(configuration.expectedObjects.length <= 3 &&
  configuration.expectedObjects.every(object => object.sizeBytes <= pageBytes),
'This finite acceptance profile supports at most three objects of at most 8192 bytes');
const source = checkoutState(repository);
const runtimeUrl = new URL('../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const runtimeSha256 = createHash('sha256').update(await readFile(runtimeUrl)).digest('hex');
const evidence = createCommandEvidence({scratch: join(repository, '..', '.codex-scratch'),
  prefix: 'gcs-real-content-', revision: source.revision, cwd: repository});
const scratch = {path: evidence.directory};
const record = {version: 'actql-real-gcs-content-acceptance/0.1', source,
  runtimeSha256, environment: configuration, startedAt: new Date().toISOString(),
  complete: false, cases: [], limitations: [
    'source-built public diagnostic, not clean packed distribution acceptance',
    'no GCS writes, deletion, version-change injection or typed INFER/COMMAND in this campaign',
    'response budget is a pre-send upper reservation, not measured response bytes',
  ]};
record.harnessInputs = [];
for (const path of ['scripts/test-gcs-files-content.mjs',
  'scripts/gcs-files-content-credential.mjs', 'scripts/gcs-files-content-environment.mjs']) {
  const bytes = await readFile(join(repository, path));
  record.harnessInputs.push({path, bytes: bytes.length,
    sha256: createHash('sha256').update(bytes).digest('hex')});
}
const save = () => writeFile(join(scratch.path, 'acceptance.json'), JSON.stringify(record, null, 2) + '\n', {mode: 0o600});
await save();
const credential = createGcsAcceptanceCredential(configuration, {maxResponseBytesPerCall: pageBytes});
const signal = AbortSignal.timeout(configuration.limits.maxDurationMs);
const principalId = userInfo().username;
const keys = generateKeyPairSync('ed25519');
const privateKeyPath = join(scratch.path, 'site-key.pem');
await writeFile(privateKeyPath, keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
const canonical = value => canonicalJson(value, {dataKeys: true});
const account = (accountId, connection, operations) => canonical({version: 'actql-execution-account-config/0.1',
  account_id: accountId, entries: [{entry_id: 'authorized-fixture', outcome: 'allow', exclusions: [],
    principal: {all: true}, connection, resource: {any_of: ['contents', 'files']},
    operation: {any_of: operations}}]});
const baseEnvironmentWire = await readFile(join(repository, 'spec/local-check-environment.json'), 'utf8');
const hostLookupExecutionPolicy = {version: 'actql-lookup-execution-policy/0.1',
  max_network_attempts_per_request: 3, max_request_bytes_per_attempt: 4096,
  max_total_request_bytes: 73728, max_total_response_bytes: 49152,
  max_total_decoded_response_bytes: 49152, max_total_duration_ms: 30000};
try {
  for (const entrance of ['Local', 'HTTPS']) {
    signal.throwIfAborted();
    const root = join(scratch.path, entrance);
    await mkdir(root, {mode: 0o700});
    const siteProfilePath = join(root, 'site.json');
    await writeFile(siteProfilePath, JSON.stringify({version: 'actql-installed-gcs-site/0.1',
      credentialAuthorityId: 'gcs-acceptance', credentialKeyId: 'gcs-acceptance',
      credentialPrivateKeyPath: privateKeyPath, environment: 'authorized-gcs-acceptance',
      journalRoot: join(root, 'credential-journal'), namespaceId: 'gcs-acceptance',
      siteGeneration: 1, siteKey: entrance, tokenEnvironment: 'ACTQL_GCS_UNUSED_TOKEN'}), {mode: 0o600});
    const profile = {version: 'actql-installed-gcs-source/0.1', connectorId: 'gcs-acceptance',
      project: configuration.project, bucket: configuration.bucket, prefix: configuration.prefix,
      mediaType: configuration.expectedObjects[0].mediaType, siteProfilePath,
      accountConfigurationWire: account('gcs-read',
        {any_of: [`gcs:${configuration.project}/${configuration.bucket}`]}, ['read']),
      limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
        maxListingBytes: 32768, maxDurationMs: 30000, maxPathBytes: 1024,
        maxPageBytes: pageBytes, maxPageItems: 1, maxRequestBytes: 4096,
        maxContentBytes: Math.min(pageBytes, configuration.limits.maxObjectBytes)}};
    const {declared} = restoreGcsSourceDeclaration(moon, profile);
    const queryAliases = declared.views.map(view => ({name: `docs.${view.resource}`,
      sourceRef: view.source_ref, sourceViewContractCid: view.view_cid,
      schemaContractCid: view.carrier_schema_cid}));
    const sourceProfilePath = join(root, 'source.json');
    await writeFile(sourceProfilePath, JSON.stringify({...profile, queryAliases}), {mode: 0o600});
    const installation = {directory: join(root, 'host'), sourceProfilePath,
      resolveSourceSecret: credential.resolveSecret, hostLookupExecutionPolicy,
      authorization: {observe(event, detail) {
        if (!event.endsWith('_preparation_rejected') && event !== 'dispatch_failed') return;
        record.preparationDiagnostics ??= [];
        if (record.preparationDiagnostics.length < 16) record.preparationDiagnostics.push({event,
          boundary: detail?.boundary, task: detail?.task, code: detail?.code,
          issueTag: detail?.issueTag, requirementTag: detail?.requirementTag,
          nestedIssueTag: detail?.nestedIssueTag});
      }, accountConfiguration: canonical({version: 'actql-execution-account-config/0.1',
        account_id: 'gcs-public-host', entries: [{entry_id: 'run', outcome: 'allow', exclusions: [],
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['read', 'write']}}]}),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}}};
    let client, host, server, previousCertificates;
    try {
      if (entrance === 'Local') {
        client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
      } else {
        const {key, cert, ca} = await fixtureCertificates(root);
        previousCertificates = getCACertificates('default');
        setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
        host = await openInstalledRemoteHttpHost({...installation,
          authenticate: header => header === 'Bearer gcs-fixture-only' ? principalId : undefined});
        server = createServer({key, cert}, host.handler);
        await new Promise((resolve, reject) => {
          server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
        });
        client = await connectRemote({mode: 'remote', durability: 'durable',
          endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'gcs-fixture-only'});
      }
      for (const [name, program] of Object.entries(gcsAcceptancePrograms(configuration))) {
        const before = credential.observation();
        const checked = await client.check(program, {kind: 'program', scope: 'bound_input'});
        assert.equal(checked.report?.verdict, 'verified', 'Public Program Check must succeed before provider I/O');
        assert.deepEqual(credential.observation(), before, 'Check must not resolve credentials');
        await writeFile(join(root, `${name}-program.json`), JSON.stringify(program, null, 2), {mode: 0o600});
        const run = await client.start(program);
        const state = await run.wait({signal});
        const observed = {entrance, name, runRef: run.ref, state, complete: false};
        record.cases.push(observed);
        await save();
        assert.equal(state.status, 'succeeded', 'Real keyed capture must complete');
        const description = await run.result('files').describe();
        const rows = await run.result('files').all();
        assert.deepEqual(description.columns.map(column => column.name), ['name', 'content']);
        assert.equal(description.columns[1].contract.type, 'content_ref');
        const expected = name === 'empty' ? [] : configuration.expectedObjects;
        assert.deepEqual(rows.map(row => row.name), expected.map(object => object.name), 'Independent name order');
        for (const [index, row] of rows.entries()) {
          assert.equal(row.content.$actql_ref, 'content');
          assert.equal(row.content.media_type, expected[index].mediaType);
          assert.equal(row.content.metadata.content_cid, expected[index].contentCid);
          assert.equal(row.content.metadata.size_bytes, expected[index].sizeBytes);
          assert.equal(row.content.metadata.truncated, false);
          assert.equal(row.content.metadata.issuer_evidence.issuer_kind, 'connector_capture');
        }
        const attached = await client.attach(run.ref);
        assert.deepEqual(await attached.result('files').all(), rows);
        const after = credential.observation();
        if (name === 'empty') assert.deepEqual(after, before, 'Empty selection sends nothing');
        Object.assign(observed, {complete: true, rows, description, credential: after});
        await save();
        console.log(`REAL_GCS_CASE ${entrance}/${name}: passed`);
      }
    } finally {
      await client?.close();
      if (server?.listening) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
      await host?.close();
      if (previousCertificates !== undefined) setDefaultCACertificates(previousCertificates);
    }
  }
  record.complete = true;
} catch (error) {
  record.failure = {code: error.code ?? error.name, issue: error.issue,
    outcome: error.outcome,
    message: error.code === 'ERR_ASSERTION'
    ? error.message.split('\n')[0] : 'Real GCS campaign failed; custody and original Run retained'};
  process.exitCode = 1;
} finally {
  record.credential = credential.observation();
  credential.close();
  record.endedAt = new Date().toISOString();
  await save();
  evidence.finish(record.complete ? 'passed' : 'failed');
  console.log(`Real GCS ${record.complete ? 'passed' : 'incomplete'}; evidence and custody: ${scratch.path}`);
}
