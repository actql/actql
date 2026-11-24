// Actual publication/Account/Common/key/SQLite ownership. These synthetic
// installation targets do not supply provider authority, egress or funding.
import assert from 'node:assert/strict';
import fsPromises from 'node:fs/promises';
import {writeFile} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installationMetadataSiteFixture as fixture, metadataSiteNow as now}
  from './fixtures/installation-metadata-site.fixture.mjs';

const code = value => ({code: value});

test('same publication, Account and original issuer sign two exact metadata scopes into the original Journal', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    assert.equal(site.issueReadGrant, undefined);
    assert.throws(() => site.credential(), code('RowSourceMetadataGrantUnavailable'));
    for (const [index, target] of [f.target, f.selected].entries()) {
      const signed = await site.issueMetadataGrant(f.request(target, `occurrence-${index}`));
      const {control, journal, binding} = site.credential();
      assert.equal(control.kind, 'installation-metadata'); assert.ok(binding);
      assert.equal(control.subjectFields().accountId, 'original-account');
      assert.equal(control.scopeFields(signed.scope).requestPath, target.path);
      const grantCid = control.identity(signed.grant);
      const claim = journal.claim(grantCid, signed.useId, BigInt(now), signed.scope, control);
      assert.equal(claim.replayed, false);
      assert.equal(journal.authorize(claim.use, BigInt(now), signed.scope, control).outcome, 'claimed');
      journal.finish(control.useIdentity(claim.use), 'succeeded');
      assert.throws(() => runtimeCore(moon).remoteCredentialControl.admitJson(
        control.json(signed.grant), grantCid));
    }
    assert.equal(site.credential().journal.recover().length, 2);
    assert.equal(f.counters().resolutions, 0);
    site.close(); site.close();
    assert.equal(f.counters().closes, 1);
    assert.equal(site.cleanupPending(), false);
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceSiteClosed'));
  });
  await f.run();
});

test('copied Host request and mixed checked profile refuse before opening an issuer Journal', async t => {
  for (const mutate of [value => {value.publicationRequest = {...value.publicationRequest};},
    value => {value.originals.profile = {...value.originals.profile};}]) {
    const f = await fixture(t, async f => {
      await assert.rejects(f.open(), error => /ForeignInstalledSourcePublication/u.test(error.code));
      assert.equal(f.counters().opens, 0);
    }, {input: mutate});
    await f.run();
  }
});

test('actual Account deny and copied dispatch cannot issue a metadata grant', async t => {
  for (const options of [{outcome: 'deny'}, {authorization: original => ({...original,
    async authorize(...args) {return {...await original.authorize(...args)};}})}]) {
    const f = await fixture(t, async f => {
      const site = await f.open();
      await assert.rejects(site.issueMetadataGrant(f.request()));
      assert.equal(f.counters().accepted, 0); assert.equal(f.counters().resolutions, 0);
    }, options);
    await f.run();
  }
});

test('Account file revoked across await remains stopped even after identical configuration returns', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.beforeObserve(() => writeFile(f.accountPath, sourceReadAccountConfiguration({
      connection: 'fixture:records', resource: 'records', accountId: 'original-account', outcome: 'deny'})));
    let failure;
    await assert.rejects(site.issueMetadataGrant(f.request()), error => {failure = error; return true;});
    await writeFile(f.accountPath, f.accountWire);
    await assert.rejects(site.issueMetadataGrant(f.request(f.target, 'no-revival')), error => error === failure);
    assert.equal(site.referenceCurrent(), false);
    assert.equal(f.counters().accepted, 0); assert.equal(f.counters().resolutions, 0);
  });
  await f.run();
});

test('same Site profile changed during await refuses without selecting a replacement issuer', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.beforeObserve(async () => {f.profile.credentialKeyId = 'replacement-key';});
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceInstallationMetadataSiteChanged'));
    assert.equal(f.counters().accepted, 0);
  });
  await f.run();
});

test('a replacement profile accessor cannot impersonate the captured Site generation', async t => {
  let reads = 0;
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.beforeObserve(async () => {Object.defineProperty(f.profile, 'siteGeneration', {
      get() {reads++; return 1;}, configurable: true});});
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceInstallationMetadataSiteChanged'));
    assert.equal(reads, 0); assert.equal(f.counters().accepted, 0);
  });
  await f.run();
});

test('bounded issuer-key close failure stays with the original initialization cleanup Owner', async t => {
  const originalOpen = fsPromises.open;
  let closes = 0, originalFile;
  const failure = new Error('OriginalIssuerKeyCloseFailure');
  const f = await fixture(t, async f => {
    fsPromises.open = async (...args) => {
      const file = await originalOpen(...args);
      if (args[0] !== f.profile.credentialPrivateKeyPath) return file;
      assert.equal(originalFile, undefined); originalFile = file;
      return {read: file.read.bind(file), async close() {
        if (++closes === 1) throw failure;
        return file.close();
      }};
    };
    syncBuiltinESMExports();
    try {
      await assert.rejects(f.open(), error => {
        assert.equal(error.code, 'InstalledHostInitializationFailed');
        assert.equal(error.primaryFailure, failure);
        assert.equal(error.cleanupHandle.status().pending, false);
        return true;
      });
      assert.equal(closes, 2);
      assert.equal(f.counters().opens, 0);
      await assert.rejects(originalFile.stat(), {code: 'EBADF'});
    } finally {fsPromises.open = originalOpen; syncBuiltinESMExports();}
  });
  t.after(() => {fsPromises.open = originalOpen; syncBuiltinESMExports();});
  await f.run();
});

test('post-sign current fence retains the signed occurrence and performs no claim or secret resolution', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.afterAccept(f.deactivate);
    await assert.rejects(site.issueMetadataGrant(f.request()), {message: 'Original Site current'});
    assert.equal(f.counters().accepted, 1); assert.equal(f.counters().resolutions, 0);
    await assert.rejects(site.issueMetadataGrant(f.request()));
    assert.equal(f.counters().accepted, 1);
  });
  await f.run();
});

test('original target, method receivers and current callbacks are retained across awaits', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    const captured = f.targetAuthority.project;
    f.beforeObserve(async () => {
      f.targetAuthority.project = () => assert.fail('Replacement target projection');
      f.siteCurrent.assertCurrent = () => assert.fail('Replacement current callback');
    });
    const signed = await site.issueMetadataGrant(f.request());
    assert.equal(site.credential().control.scopeFields(signed.scope).requestPath, '/v1/original');
    assert.equal(captured.call(f.targetAuthority, f.target, f.declaration).bodyBytes, 0);
    await assert.rejects(site.issueMetadataGrant(f.request({...f.target}, 'foreign-target')),
      code('ForeignMetadataTarget'));
  });
  await f.run();
});

test('duplicate occurrence and exhausted finite operation inventory never accept another grant', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    await site.issueMetadataGrant(f.request());
    await assert.rejects(site.issueMetadataGrant({...f.request(), useId: 'different-use'}),
      code('RowSourceMetadataOccurrenceAlreadyPrepared'));
    await site.issueMetadataGrant(f.request(f.selected, 'second'));
    await assert.rejects(site.issueMetadataGrant(f.request(f.target, 'third')),
      code('RowSourceMetadataOperationLimit'));
    assert.equal(f.counters().accepted, 2); assert.equal(f.counters().resolutions, 0);
  });
  await f.run();
});

test('failed original Journal close keeps the same Site pending and skips a later acknowledged close', async t => {
  const failure = new Error('OriginalJournalCloseFailure');
  const f = await fixture(t, async f => {
    const site = await f.open();
    await site.issueMetadataGrant(f.request());
    f.beforeClose(() => {throw failure;});
    assert.throws(() => site.close(), error => error === failure);
    assert.equal(site.cleanupPending(), true);
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceSiteClosed'));
    f.beforeClose(() => {}); site.close(); site.close();
    assert.equal(site.cleanupPending(), false); assert.equal(f.counters().closes, 2);
  });
  await f.run();
});

test('closing during the original current await cannot sign into the retired Journal', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.beforeObserve(async () => {site.close();});
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceSiteClosed'));
    assert.equal(f.counters().accepted, 0);
    assert.equal(f.counters().resolutions, 0);
    assert.equal(f.counters().closes, 1);
    assert.equal(site.referenceCurrent(), false);
  });
  await f.run();
});

test('a retained original target with changed projected facts refuses before signing', async t => {
  let altered = false;
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.beforeObserve(async () => {altered = true;});
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceMetadataTargetChanged'));
    assert.equal(f.counters().accepted, 0);
    assert.equal(f.counters().resolutions, 0);
  }, {input(value) {
    const project = value.targetAuthority.project;
    value.targetAuthority.project = function (...args) {
      const facts = Reflect.apply(project, this, args);
      return altered ? {...facts, path: '/v1/replacement'} : facts;
    };
  }});
  await f.run();
});

test('unsafe mutable Journal admission returns its existing initialization Owner and original close receiver', async t => {
  let replacement = 0;
  const f = await fixture(t, async f => {
    let failure;
    await assert.rejects(f.open(), error => {failure = error; return error.code === 'InstalledHostInitializationFailed';});
    assert.equal(failure.primaryFailure.code, 'InvalidInstallationMetadataJournal');
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(f.counters().closes, 1); assert.equal(replacement, 0);
  }, {journal(wrapped) {
    const close = wrapped.close;
    Object.defineProperty(wrapped, 'close', {value: function () {
      assert.equal(this, wrapped);
      wrapped.close = () => {replacement++; return true;};
      return close();
    }, writable: true, enumerable: true, configurable: true});
    return wrapped;
  }});
  await f.run();
});
