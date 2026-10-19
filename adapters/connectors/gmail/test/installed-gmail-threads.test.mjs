import assert from 'node:assert/strict';
import test from 'node:test';
import {checkInstalledGmailSourceProfile} from '../host/installed-gmail-source.mjs';

export const installedThreadLimits = Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:131072,
  maxNodes:2048,maxDepth:16,pageSize:100,maxPages:3,maxThreads:10,
  maxMailboxBytes:256,maxTargetBytes:2048,maxIdBytes:128,maxTokenBytes:128,
  maxMessages:20,maxLabels:100,maxHeaders:100,maxHeaderUnits:1024,maxCommentDepth:8,
  maxValueNodes:100,maxValueTextBytes:8192,maxRowsWireBytes:16384,maxRowsWireNodes:100,maxRowsWireDepth:8,
  maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384});

test('installed Gmail explicitly selects threads through the same closed original profile', () => {
  const profile = {version:'actql-installed-gmail-source/0.1',connectorId:'mailbox',resource:'threads',
    mailbox:'support@example.test',siteProfilePath:'/unused/selected-site.json',
    accountConfigurationWire:'{}',limits:installedThreadLimits};
  const checked = checkInstalledGmailSourceProfile(profile);
  assert.equal(checked.resource,'threads');
  assert(Object.isFrozen(checked) && Object.isFrozen(checked.limits));
  assert.deepEqual(checked,profile);
});
