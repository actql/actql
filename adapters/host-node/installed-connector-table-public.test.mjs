import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {runInstalledConnectorTableAcceptance} from
  '../../scripts/fixtures/installed-connector-table-acceptance.mjs';

test('explicit tables retain shared Host ownership and source-free execution', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-table-host-',
    label: 'explicit installed Connector tables'});
  await runInstalledConnectorTableAcceptance({connect: connectEmbeddedLocal,
    createInstalledConnectorTable, openInstalledRemoteHttpHost, directory: scratch.path,
    program: await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8')});
  scratch.passed();
});
