import test from 'node:test';
import assert from 'node:assert/strict';
import {tmpdir} from 'node:os';
import * as sdk from '../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {exerciseWorkspaceConnection} from '../../scripts/fixtures/workspace-dsn-acceptance.mjs';

test('DSN reaches real installed HTTPS owners and preserves Workspace and Run boundaries',
  {timeout: 30000}, async () => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-workspace-dsn-',
      label: 'Workspace DSN installed HTTPS acceptance'});
    // The packed acceptance supplies @actql/node as well; source execution
    // uses the same SDK facade without adding a repository-local dependency.
    const evidence = await exerciseWorkspaceConnection({directory: scratch.path,
      sdk, node: sdk, openHost: openInstalledRemoteHttpHost});
    assert.deepEqual(evidence.counts, {A: 1, B: 1});
    console.log('WORKSPACE_DSN_ACCEPTANCE', JSON.stringify(evidence));
    scratch.passed();
  });

for (const address of ['127.0.0.1', '::1']) {
  test(`HTTP DSN reaches real loopback ${address} owners without global Fetch or Workspace drift`,
    {timeout: 30000}, async () => {
      const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-loopback-dsn-',
        label: 'Workspace DSN installed loopback HTTP acceptance'});
      const evidence = await exerciseWorkspaceConnection({directory: scratch.path,
        sdk, node: sdk, openHost: openInstalledRemoteHttpHost, loopbackHttp: true, address});
      assert.deepEqual(evidence.counts, {A: 1, B: 1});
      console.log('WORKSPACE_DSN_ACCEPTANCE', JSON.stringify(evidence));
      scratch.passed();
    });
}
