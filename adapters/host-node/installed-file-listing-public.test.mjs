// Public Client diagnostic against the real installed Host and common row
// owner. The deterministic Site returns physical pages, not captured Results.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import test from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {connect} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {createInstalledRowSource, installRowSourceAuthorization} from './installed-row-source.mjs';
import {fileListingDeclaration, item, token} from './fixtures/file-listing-source.fixture.mjs';
const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

const scratch = fileURLToPath(new URL('../../_build/file-listing-public/', import.meta.url));
const accountConfiguration = JSON.stringify({version: 'actql-execution-account-config/0.1',
  account_id: 'file-fixture', entries: [{entry_id: 'read-files', outcome: 'allow',
    principal: {all: true}, connection: {all: true}, resource: {all: true},
    operation: {any_of: ['read']}, exclusions: []}]});

for (const mode of ['local', 'https']) {
  test(`${mode} public LIST_FILES completes nonmatching pages and publishes the actual capture`, async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, `${mode}-`));
    let client, host, server, passed = false;
    const savedCAs = getCACertificates('default');
    t.after(async () => {
      await client?.close();
      if (server !== undefined) {
        server.closeAllConnections?.();
        await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      }
      await host?.close();
      setDefaultCACertificates(savedCAs);
      if (passed) await rm(root, {recursive: true, force: true});
      else t.diagnostic(`Retained failed file-listing fixture: ${root}`);
    });
    const counters = {requests: 0, returned: 0, grant: 0};
    const events = [];
    let cancelContent = false, entered;
    const contentEntered = new Promise(resolve => { entered = resolve; });
    const connectorTable = createInstalledConnectorTable([{
      name: 'fixture', registration: 'fixture', revision: 'fixture/0.1',
      source: {profileVersion: 'actql-installed-file-fixture/0.1', load: async () => ({
        check: profile => profile,
        identityParts: profile => [profile],
        async load(_profile, {moon, root: stateRoot, principalId, baseEnvironmentWire}) {
          const fixture = fileListingDeclaration(moon, baseEnvironmentWire);
          const authorization = await installRowSourceAuthorization({accountConfiguration,
            principalId, root: stateRoot, connectorRegistration: 'fixture'});
          return createInstalledRowSource({moon, declaration: fixture.declaration,
            declared: fixture.declared, environmentWire: fixture.environment.wire,
            connectorId: 'fixture', connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
            referenceIssuer: fixture.issuer, bindingCid: token('c'), authorization,
            readOperation: 'read', physicalTarget: (resource, fields) => ({resource, fields}),
            site: {connection: 'fixture:files', close() {},
              issueReadGrant({decision}) {
                assert.equal(authorization.issued(decision), true);
                assert.equal(decision.action, 'dispatch');
                counters.grant++;
                return {};
              }},
            limits: {maxPages: 4, maxPageBytes: 8192, maxPageRows: 9, maxCaptureRows: 3},
            async readPages({listing, requestWire, authorizationFor, chargePage}) {
              assert.deepEqual(JSON.parse(requestWire), {glob: '**/*.csv', paths: null});
              assert.ok(listing);
              for (const [index, [requestToken, nextToken, items]] of [
                [undefined, 'next', [item('f', 'ignored.txt')]],
                ['next', 'empty', [item('e', 'b/z.csv'), item('d', 'a.csv')]],
                ['empty', null, []],
              ].entries()) {
                await listing.beginRequest(requestToken);
                await authorizationFor(index);
                counters.requests++;
                const body = Buffer.from(JSON.stringify({items,
                  request_token: requestToken ?? null, next_token: nextToken}));
                counters.returned += await listing.consumePage(body, {charge: chargePage(body)});
              }
            }});
        },
      })},
    }]);
    // The actual published alias pins are read from the same authored finite
    // declaration; expected Result rows below do not come from this metadata.
    const moon = await import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
    const base = await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8');
    const {aliases} = fileListingDeclaration(moon, base);
    const sourceProfilePath = join(root, 'source-profile.json');
    await writeFile(sourceProfilePath, JSON.stringify({version: 'actql-installed-file-fixture/0.1',
      name: 'fixture', queryAliases: aliases}));
    const keys = generateKeyPairSync('ed25519');
    const installation = {directory: join(root, 'host'), connectorTable, sourceProfilePath,
      authorization: {accountConfiguration: JSON.stringify({...JSON.parse(accountConfiguration),
        entries: JSON.parse(accountConfiguration).entries.map(entry => ({...entry,
          operation: {all: true}}))}),
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
        observe: (event, detail) => events.push({event, detail}),
        faultInjection: async (step, detail) => {
          if (!cancelContent || step !== 'content_input_identified') return;
          assert.ok(detail.work > 0n);
          entered();
          if (!detail.signal.aborted) await new Promise(resolve => {
            detail.signal.addEventListener('abort', resolve, {once: true});
          });
          detail.signal.throwIfAborted();
        }}};
    if (mode === 'local') {
      client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation});
    } else {
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
      const cert = await readFile(join(root, 'host.crt'));
      setDefaultCACertificates([...savedCAs, cert.toString('utf8')]);
      host = await openInstalledRemoteHttpHost({...installation,
        authenticate: () => userInfo().username,
      });
      server = createServer({key: await readFile(join(root, 'host.key')), cert}, host.handler);
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
        token: 'fixture-token', durability: 'durable'});
    }
    const execution = await client.startSource(
      "SELECT name FROM LIST_FILES(docs.invoices, glob => '**/*.csv')", {format: 'sql'}).catch(error => {
        t.diagnostic(inspect({error, events}, {depth: 10}));
        throw error;
      });
    assert.equal((await execution.wait()).status, 'succeeded');
    assert.deepEqual((await execution.result('answer').all()).map(row => row.name).sort(),
      ['a.csv', 'b/z.csv']);
    const attached = await client.attach(execution.ref);
    assert.deepEqual((await attached.result('answer').all()).map(row => row.name).sort(),
      ['a.csv', 'b/z.csv']);
    assert.deepEqual(counters, {requests: 3, returned: 2, grant: 1});
    const empty = await client.startSource(
      'FROM LIST_FILES(docs.invoices, paths => ARRAY<STRING>[]) |> SELECT name',
      {format: 'aql-text'});
    assert.equal((await empty.wait()).status, 'succeeded');
    assert.deepEqual((await empty.result('answer').describe()).columns,
      [{name: 'name', contract: {type: 'string', nullable: false}}]);
    assert.deepEqual(await empty.result('answer').all(), []);
    assert.deepEqual(counters, {requests: 3, returned: 2, grant: 1},
      'typed empty paths issue no new grant or physical request');
    // This is an acquired Relation, not VALUES or Result delivery reused as
    // a file. Arrival order is reversed by the original common prefix sort.
    const contentRun = await client.startSource(
      "SELECT name, media_type FROM LIST_FILES(docs.invoices, glob => '**/*.csv') " +
      "|> SERIALIZE FORMAT JSONL ORDER BY name OPTIONS (name = 'listed.jsonl', max_rows = 3, max_bytes = 256) |> RESULT file",
      {format: 'sql'}).catch(error => {
        t.diagnostic(inspect({error, events: events.filter(event => /rejected|failed/u.test(event.event))}, {depth: 12}));
        throw error;
      });
    const contentState = await contentRun.wait({signal: AbortSignal.timeout(15000)});
    assert.equal(contentState.status, 'succeeded', JSON.stringify(contentState));
    const files = await contentRun.result('file').all();
    const expectedBytes = Buffer.from('{"name":"a.csv","media_type":null}\n{"name":"b/z.csv","media_type":null}\n');
    assert.equal(files.length, 1);
    assert.equal(files[0].row_count, 2);
    assert.equal(files[0].size_bytes, expectedBytes.byteLength);
    assert.equal(files[0].content.metadata.content_cid, hash(expectedBytes));
    assert.deepEqual(await (await client.attach(contentRun.ref)).result('file').all(), files);
    assert.deepEqual(counters, {requests: 6, returned: 4, grant: 2},
      'Content generation borrows one real capture; attach neither rereads nor regenerates');
    assert.deepEqual(await readFile(join(installation.directory, 'publication', 'objects',
      hash(expectedBytes).slice('sha256:'.length))), expectedBytes);
    const assertReleased = run => {
      const cleaned = events.findLast(event => event.event === 'dispatch_cleanup_completed' &&
        event.detail.ref.runDefinitionCid === run.ref.runDefinitionCid);
      assert.ok(cleaned, 'the same Run ledger must confirm physical cleanup');
      // Attempts/holding creations are cumulative work, not refundable slots.
      assert.equal(cleaned.detail.resourceUsage.attempts, '2');
      for (const field of ['reservedTransferBytes', 'heldBytes',
        'reservedRetentionBytes', 'reservedExecutionBytes', 'uncertainTransferBytes']) {
        assert.equal(cleaned.detail.resourceUsage[field], '0', field);
      }
    };
    assertReleased(contentRun);
    const csvRun = await client.startSource(
      "SELECT name, media_type FROM LIST_FILES(docs.invoices, glob => '**/*.csv') " +
      "|> SERIALIZE FORMAT CSV ORDER BY name OPTIONS (name = 'listed.csv', max_rows = 3, max_bytes = 256, " +
      String.raw`header = TRUE, null_marker = r'\N', line_ending = 'CRLF') |> RESULT file`,
      {format: 'sql'});
    assert.equal((await csvRun.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
    const csvFiles = await csvRun.result('file').all();
    // The Content profile always quotes string data cells, including ordinary
    // filenames, while its header quotes only special cells. NULL is unquoted.
    const csvBytes = Buffer.from('name,media_type\r\n"a.csv",\\N\r\n"b/z.csv",\\N\r\n');
    assert.equal(csvFiles.length, 1);
    assert.equal(csvFiles[0].row_count, 2);
    assert.equal(csvFiles[0].size_bytes, csvBytes.byteLength);
    assert.equal(csvFiles[0].content.metadata.content_cid, hash(csvBytes));
    assert.deepEqual(await readFile(join(installation.directory, 'publication', 'objects',
      hash(csvBytes).slice('sha256:'.length))), csvBytes);
    assertReleased(csvRun);
    const emptyContent = await client.startSource(
      'FROM LIST_FILES(docs.invoices, paths => ARRAY<STRING>[]) |> SELECT name, media_type ' +
      "|> SERIALIZE FORMAT JSONL ORDER BY name OPTIONS (name = 'empty.jsonl', max_rows = 3, max_bytes = 256) |> RESULT file",
      {format: 'aql-text'});
    assert.equal((await emptyContent.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
    const emptyFiles = await emptyContent.result('file').all();
    assert.equal(emptyFiles.length, 1);
    assert.equal(emptyFiles[0].row_count, 0);
    assert.equal(emptyFiles[0].size_bytes, 0);
    assert.equal(emptyFiles[0].content.metadata.content_cid, hash(Buffer.alloc(0)));
    assert.deepEqual(counters, {requests: 9, returned: 6, grant: 3});
    assertReleased(emptyContent);
    cancelContent = true;
    const cancelled = await client.startSource(
      "SELECT name, media_type FROM LIST_FILES(docs.invoices, glob => '**/*.csv') " +
      "|> SERIALIZE FORMAT JSONL ORDER BY name OPTIONS (name = 'cancelled.jsonl', max_rows = 3, max_bytes = 256) |> RESULT file",
      {format: 'sql'});
    const timeout = AbortSignal.timeout(15000);
    await Promise.race([contentEntered, new Promise((_, reject) => {
      timeout.addEventListener('abort', () => reject(timeout.reason), {once: true});
    })]);
    await cancelled.cancel();
    const cancelledState = await cancelled.wait({signal: timeout});
    assert.equal(cancelledState.status, 'cancelled', inspect({cancelledState, events}, {depth: 8}));
    assert.equal(cancelledState.result_availability.file.state, 'unavailable');
    assert.equal(cancelledState.result_availability.file.reason, 'not_published');
    assert.deepEqual(counters, {requests: 12, returned: 8, grant: 4});
    assertReleased(cancelled);
    passed = true;
  });
}
