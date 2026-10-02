// Source registration for the unchanged helper used by the pack-once consumer.
// The calling gate prepares runtime artifacts; this test never builds or packs.
import {execFileSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import test from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {connect as connectRemote} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {installPlannerSelectionFixture, exercisePlannerSelectionPublicQuery,
  plannerSelectionPlanningFor} from '../../scripts/fixtures/planner-selection-public-query.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const duckdb = createRequire(new URL('../connectors/duckdb/node/package.json', import.meta.url))('@duckdb/node-api');
const connect = options => options.mode === 'local'
  ? connectEmbeddedLocal(options) : connectRemote(options);

test('public Local/HTTPS route the same Program through the common acquisition choice',
  {timeout: 180_000}, async () => {
    const scratch = await createOwnedScratch({parent: resolve(repository, '_build'),
      prefix: 'planner-selection-', label: 'planner candidate selection',
      digests: () => ['planner-selection-report.json']});
    const root = scratch.path;
    execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
      '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
    {cwd: root, stdio: 'ignore'});
    const tls = {key: await readFile(resolve(root, 'remote.key')),
      cert: await readFile(resolve(root, 'remote.crt'))};
    const originalCAs = getCACertificates('default');
    setDefaultCACertificates([...originalCAs, tls.cert.toString('utf8')]);
    try {
      const environment = JSON.parse(await readFile(new URL(
        './fixtures/two-source/left.environment.json', import.meta.url), 'utf8'));
      const installation = await installPlannerSelectionFixture({root, duckdb, environment,
        acquisitionPlanningFor: plannerSelectionPlanningFor});
      const observations = await exercisePlannerSelectionPublicQuery({
        connect, openInstalledRemoteHttpHost, root, installation, duckdb, tls});
      await writeFile(resolve(root, 'planner-selection-report.json'),
        JSON.stringify({status: 'passed', cases: observations.length, observations}, null, 2) + '\n');
    } finally { setDefaultCACertificates(originalCAs); }
    scratch.passed();
  });
