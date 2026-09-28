import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {installedEffectIdentity} from './installed-effect.mjs';
import {installedSourceIdentity} from './installed-source.mjs';

test('embedded Host reuses equivalent installation options, not object identity',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-embedded-owner-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const first = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory}});
    const second = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory}});
    assert.equal(first.profile.version, second.profile.version);
    await first.close();
    await second.close();

    const foreign = join(directory, 'different-source.json');
    await writeFile(foreign,
      '{"version":"actql-installed-duckdb-source/0.1"}');
    await assert.rejects(connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, sourceProfilePath: foreign}}),
    {name: 'TypeError', message: 'InstalledHostConfigurationMismatch'});
  });

test('installed Effect identity compares declarations and generation semantics',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-effect-identity-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const siteProfilePath = join(directory, 'site.json');
    const publicationPath = join(directory, 'publication.json');
    const profilePath = join(directory, 'effect.json');
    await writeFile(siteProfilePath, '{"siteGeneration":1,"siteKey":"site-a"}');
    await writeFile(publicationPath, '{"generation":"a"}');
    await writeFile(profilePath, JSON.stringify({
      version: 'actql-installed-salesforce-effect/0.1', siteProfilePath,
      publicationPath, connectorId: 'crm-main',
      accountConfigurationWire: '{"account_id":"a"}',
      writes: [{resource: 'Test_Record__c', kind: 'update',
        fields: ['Name']}],
    }));
    const first = await installedEffectIdentity(profilePath);
    await writeFile(siteProfilePath,
      '{\n  "siteKey": "site-a", "siteGeneration": 1\n}');
    assert.equal(await installedEffectIdentity(profilePath), first);
    await writeFile(siteProfilePath,
      '{"siteKey":"site-a","siteGeneration":2}');
    assert.notEqual(await installedEffectIdentity(profilePath), first);
    await writeFile(siteProfilePath,
      '{"siteKey":"site-a","siteGeneration":1}');
    await writeFile(publicationPath, '{"generation":"b"}');
    assert.notEqual(await installedEffectIdentity(profilePath), first);
  });

test('installed source identity includes the published generation',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-source-identity-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const siteProfilePath = join(directory, 'site.json');
    const publicationPath = join(directory, 'publication.json');
    const profilePath = join(directory, 'source.json');
    await writeFile(siteProfilePath, '{"siteGeneration":1}');
    await writeFile(publicationPath, '{"generation":"a"}');
    await writeFile(profilePath, JSON.stringify({
      version: 'actql-installed-salesforce-source/0.1', siteProfilePath,
      publicationPath, connectorId: 'crm-main',
      accountConfigurationWire: '{"account_id":"a"}',
      resources: ['Test_Record__c'],
    }));
    const first = await installedSourceIdentity(profilePath);
    await writeFile(publicationPath, '{\n "generation": "a"\n}');
    assert.equal(await installedSourceIdentity(profilePath), first);
    await writeFile(publicationPath, '{"generation":"b"}');
    assert.notEqual(await installedSourceIdentity(profilePath), first);
  });
