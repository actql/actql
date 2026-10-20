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


test('installed Gmail threads selector rejects foreign resources and malformed bounds without label fallback', () => {
  const profile={version:'actql-installed-gmail-source/0.1',connectorId:'mailbox',resource:'threads',
    mailbox:'support@example.test',siteProfilePath:'/unused/site.json',accountConfigurationWire:'{}',limits:installedThreadLimits};
  for(const wrong of [null,undefined,'messages','Threads',''])
    assert.throws(()=>checkInstalledGmailSourceProfile({...profile,resource:wrong}),{code:'InvalidInstalledGmailSourceProfile'});
  for(const patch of [{maxThreads:0},{maxThreads:-1},{pageSize:501},{maxPages:2147483647},
    {maxTotalResponseBytes:0},{maxResponseBytes:0},{maxMessages:-1},{maxHeaders:null},{maxCaBytes:0}])
    assert.throws(()=>checkInstalledGmailSourceProfile({...profile,limits:{...installedThreadLimits,...patch}}));
  const emptyExtents=checkInstalledGmailSourceProfile({...profile,limits:{...installedThreadLimits,
    maxMessages:0,maxLabels:0,maxHeaders:0,maxHeaderUnits:0,maxCommentDepth:0,maxValueTextBytes:0}});
  assert.equal(emptyExtents.limits.maxMessages,0);
  assert.throws(()=>checkInstalledGmailSourceProfile({...profile,limits:{...installedThreadLimits,extra:1}}));
});
