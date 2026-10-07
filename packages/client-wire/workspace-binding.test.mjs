import test from 'node:test';
import assert from 'node:assert/strict';
import {clientWorkspaceMatches, validClientConnection, validClientProfile} from './index.mjs';

const connection = {mode: 'remote', owner: 'remote', consentRefs: [], runners: []};
const profile = {version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
  durability: 'durable', scopeRef: 'opaque-owner-scope', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};

test('Workspace assertion is bounded and separate from an authorization decision', () => {
  assert.equal(validClientConnection(connection), true);
  assert.equal(clientWorkspaceMatches(connection, undefined), true);
  const asserted = {...connection, workspaceId: 'workspace-A'};
  assert.equal(validClientConnection(asserted), true);
  assert.equal(clientWorkspaceMatches(asserted, 'workspace-A'), true);
  for (const trusted of [undefined, '', 'workspace-B', 'workspace-a']) {
    assert.equal(clientWorkspaceMatches(asserted, trusted), false);
  }
  for (const workspaceId of [null, '', 1, 'a\u0000b', 'a\u007fb', 'a'.repeat(257)]) {
    assert.equal(validClientConnection({...connection, workspaceId}), false);
  }
});

test('profile echo requires both Workspace fields absent or exactly equal', () => {
  assert.equal(validClientProfile(profile, connection), true);
  assert.equal(validClientProfile({...profile, workspaceId: 'workspace-A'}, connection), false);
  const asserted = {...connection, workspaceId: 'workspace-A'};
  assert.equal(validClientProfile(profile, asserted), false);
  assert.equal(validClientProfile({...profile, workspaceId: 'workspace-B'}, asserted), false);
  assert.equal(validClientProfile({...profile, workspaceId: 'workspace-A'}, asserted), true);
});
