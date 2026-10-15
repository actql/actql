// Installed products only. The copied fixture supplies the private HTTPS
// provider and test installation; it replaces no Client, Store or Run Owner.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {readFile, realpath, writeFile} from 'node:fs/promises';
import {join, sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {connect} from '@actql/sdk';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {publishEffect} from '@actql/local-node';
import {startExplorer} from '@actql/explorer/launcher';
import {createExplorerBrowserSource} from '@actql/explorer/browser-source';
import {runInstalledEffectInventoryAcceptance} from
  './scripts/fixtures/installed-effect-inventory-acceptance.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const receipt = {cases: [], cleanup: [], productImports: [], providerSends: null,
  answers: 0, resumes: 0, complete: false};
const require = createRequire(import.meta.url);
for (const name of ['@actql/sdk', '@actql/local-node/http-host',
  '@actql/explorer/launcher', '@actql/explorer/browser-source']) {
  const path = await realpath(require.resolve(name));
  assert(path.startsWith(join(process.cwd(), 'node_modules') + sep));
  receipt.productImports.push({name, path, sha256: hash(await readFile(path))});
}
assert(process.env.ACTQL_TEST_PLAYWRIGHT_MODULE, 'explicit test-only browser tooling required');
const {chromium} = await import(pathToFileURL(process.env.ACTQL_TEST_PLAYWRIGHT_MODULE));
let browser, originalCheckpoint, originalReview;

await test('ordinary installed Explorer reads the real held Checkpoint before and after Host restart', async () => {
  try {
    browser = await chromium.launch({headless: true, executablePath: chromium.executablePath()});
    receipt.browserVersion = browser.version();
    const result = await runInstalledEffectInventoryAcceptance({connect,
      openInstalledRemoteHttpHost, publishEffect, profile: 'checkpoint-review',
      async observeWaitingCheckpoint({client, phase, original, expectedRows, expectedRunId}) {
        assert.deepEqual(expectedRows, [{node_id: 'I_ALPHA', comment: 'alpha forward'}]);
        const listed = await client.checkpoints({limit: 32});
        assert.equal(listed.items.length, 1);
        const checkpoint = listed.items[0];
        assert.equal(checkpoint.kind, 'effect_set');
        assert.equal(checkpoint.phase, 'commit');
        assert.equal(checkpoint.subject.kind, 'run_unit');
        assert.equal(checkpoint.subject.runId, expectedRunId);
        assert.equal(checkpoint.subject.runDefinitionCid, original.runRef.runDefinitionCid);
        const review = await client.reviewCheckpoint(checkpoint, {maxBytes: 65536});
        const bytes = Buffer.from(review.bytes);
        assert.equal(review.checkpointCid, checkpoint.checkpointCid);
        assert.equal(review.artifactCid, checkpoint.reviewProjectionCid);
        assert.equal(`sha256:${hash(bytes)}`, review.artifactCid);
        const text = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
        assert(text.includes('alpha forward'), 'original review must contain the independently authored intended comment');
        assert(text.includes('I_ALPHA'), 'original review must retain the independently authored target');
        if (phase === 'original') {
          originalCheckpoint = structuredClone(checkpoint);
          originalReview = bytes;
        } else {
          assert.deepEqual(checkpoint, originalCheckpoint);
          assert.deepEqual(bytes, originalReview);
        }
        const gateway = await startExplorer({client});
        let page;
        try {
          const paths = [];
          let cookie;
          const source = createExplorerBrowserSource({origin: gateway.origin,
            fetch: async (url, init) => {
              const headers = new Headers(init.headers);
              headers.set('Origin', gateway.origin);
              if (cookie) headers.set('Cookie', cookie);
              paths.push(new URL(url).pathname);
              const response = await fetch(url, {...init, headers});
              cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie;
              return response;
            }});
          const capabilities = await source.connect(gateway.issueBootstrap().bootstrap);
          assert.equal(capabilities.checkpointList, true);
          assert.equal(capabilities.checkpointReview, true);
          assert.equal(capabilities.control, false);
          const projected = await source.checkpoints();
          assert.equal(projected.items.length, 1);
          assert.deepEqual(JSON.parse(projected.items[0].metadataJson), checkpoint);
          const observed = await source.reviewCheckpoint({checkpointCid: checkpoint.checkpointCid,
            reviewProjectionCid: checkpoint.reviewProjectionCid});
          assert.deepEqual(Buffer.from(observed.contentBase64, 'base64'), bytes);
          source.close();

          page = await browser.newPage({viewport: {width: 1440, height: 1100}});
          page.setDefaultTimeout(10000);
          const pageErrors = [], foreignRequests = [];
          page.on('pageerror', error => pageErrors.push(error.name));
          page.on('request', request => {
            const url = new URL(request.url());
            if (url.pathname.startsWith('/api/')) paths.push(url.pathname);
          });
          await page.route('**/*', route => {
            if (new URL(route.request().url()).origin === gateway.origin) return route.continue();
            foreignRequests.push(new URL(route.request().url()).origin);
            return route.abort();
          });
          await page.goto(gateway.origin, {waitUntil: 'networkidle'});
          await page.getByLabel('One-use bootstrap').fill(gateway.issueBootstrap().bootstrap);
          await page.getByRole('button', {name: 'Connect', exact: true}).click();
          await page.getByRole('status').filter({hasText: 'Connected.'}).waitFor();
          await page.getByRole('button', {name: 'List waiting Checkpoints', exact: true}).click();
          const metadata = page.getByLabel('Original Checkpoint metadata');
          await metadata.waitFor();
          assert.deepEqual(JSON.parse(await metadata.innerText()), checkpoint);
          await page.getByRole('button', {name: 'Read original review', exact: true}).click();
          const displayed = page.getByLabel('Original review text');
          await displayed.waitFor();
          assert.equal(await displayed.innerText(), text);
          assert.equal(await page.getByLabel('Original Run reference JSON').inputValue(), '');
          assert.equal(await page.getByRole('button', {name: 'Approve', exact: true}).count(), 0);
          assert(paths.every(path => ['/api/session', '/api/read/launch',
            '/api/read/checkpoints', '/api/read/checkpoint-review'].includes(path)));
          assert.deepEqual(foreignRequests, []);
          assert.deepEqual(pageErrors, []);
          await page.screenshot({path: join(process.cwd(), `checkpoint-${phase}.png`), fullPage: true});
          await page.getByRole('button', {name: 'Disconnect', exact: true}).click();
          assert.equal(await page.getByLabel('Original Checkpoint metadata').count(), 0);
          assert.equal(await page.getByLabel('Original review text').count(), 0);
          const observation = {phase, original, checkpoint, artifactCid: review.artifactCid,
            reviewBytes: bytes.length, reviewSha256: hash(bytes), paths};
          receipt.cases.push(observation);
          return observation;
        } finally {
          await page?.close();
          await gateway.close();
          receipt.cleanup.push({phase, pageAndGatewayClosed: true});
        }
      }});
    assert.equal(result.observations.length, 2);
    assert.deepEqual(result.providerSends, [0, 0]);
    receipt.fixture = result;
    receipt.providerSends = result.providerSends;
    receipt.complete = true;
  } finally {
    await browser?.close();
    receipt.cleanup.push({browserClosed: true});
    receipt.driverSha256 = hash(await readFile(new URL(import.meta.url)));
    await writeFile(join(process.cwd(), 'checkpoint-installed-receipt.json'),
      JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx'});
  }
});
