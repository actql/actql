import test from 'node:test';
import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {ClientError, connect as connectSdk} from './index.mjs';
import {connect as connectNode} from '../node/index.mjs';

const secret = 'CONNECTION_DIAGNOSTIC_CANARY:+/@?#%';
const safe = error => {
  assert(error instanceof ClientError);
  assert.equal(error.message, error.code);
  assert.equal(error.cause, undefined);
  for (const value of [JSON.stringify(error), inspect(error, {showHidden: true, depth: 20}), error.stack]) {
    assert(!value.includes(secret));
    assert(!value.includes(encodeURIComponent(secret)));
  }
  assert.equal(typeof error.hint, 'string');
};
const noFetch = t => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = () => {calls++; throw new Error('UnexpectedFetch');};
  t.after(() => {globalThis.fetch = original; assert.equal(calls, 0);});
};

test('public SDK and Node report missing Remote fields without changing error codes', async t => {
  noFetch(t);
  for (const connect of [connectSdk, connectNode]) {
    for (const [options, fields] of [[{}, 'mode, endpoint, token'],
      [{mode: 'remote'}, 'endpoint, token'],
      [{mode: 'remote', endpoint: 'https://host.example/'}, 'token']]) {
      await assert.rejects(connect(options), error => {
        safe(error); assert.equal(error.code, 'InvalidConnectionOptions');
        assert(error.hint.includes(`Missing connection options: ${fields}.`));
        assert(error.hint.includes("endpoint: 'https://host.example/'"));
        assert(error.hint.includes('token: getAccessToken'));
        return true;
      });
    }
  }
});

test('credential-free DSNs explain the separate token option before any request', async t => {
  noFetch(t);
  for (const connect of [connectSdk, connectNode]) {
    await assert.rejects(connect('actql://host.example/workspace-id'), error => {
      safe(error); assert.equal(error.code, 'InvalidConnectionOptions');
      assert(error.hint.includes('Missing connection options: token.'));
      assert(error.hint.includes("connect('actql://host.example/workspace-id', {token: getAccessToken})"));
      return true;
    });
  }
});

test('malformed DSN userinfo and query are replaced by a fixed format example', async t => {
  noFetch(t);
  for (const connect of [connectSdk, connectNode]) {
    for (const input of [`actql://token:${encodeURIComponent(secret)}@host.example/workspace-id?token=${encodeURIComponent(secret)}`,
      `actql://person:${encodeURIComponent(secret)}@host.example/workspace-id`,
      `https://host.example/?credential=${encodeURIComponent(secret)}`]) {
      await assert.rejects(connect(input), error => {
        safe(error); assert.equal(error.code, 'InvalidConnectionString');
        assert(error.hint.includes('one workspace-id'));
        assert(error.hint.includes('Only ?transport=http'));
        return true;
      });
    }
  }
});

test('endpoint diagnostics never echo URL userinfo, path, query or fragment', async t => {
  noFetch(t);
  for (const endpoint of [`https://user:${encodeURIComponent(secret)}@host.example/`,
    `https://host.example/${encodeURIComponent(secret)}`,
    `https://host.example/?token=${encodeURIComponent(secret)}`,
    `https://host.example/#${encodeURIComponent(secret)}`, secret]) {
    await assert.rejects(connectSdk({mode: 'remote', endpoint, token: secret}), error => {
      safe(error); assert.equal(error.code, 'InvalidConnectionEndpoint');
      assert(error.hint.includes('HTTPS origin'));
      return true;
    });
  }
});

test('unknown connection-string option names and conflicting credentials remain private', async t => {
  noFetch(t);
  const dsn = `actql://token:${encodeURIComponent(secret)}@host.example/workspace-id`;
  await assert.rejects(connectSdk(dsn, {[secret]: secret}), error => {
    safe(error); assert.equal(error.code, 'InvalidConnectionOptions');
    assert(error.hint.includes('accept only token, durability, consentRefs and traceContext'));
    return true;
  });
  await assert.rejects(connectSdk(dsn, {token: secret}), error => {
    safe(error); assert.equal(error.code, 'ConflictingConnectionCredentials');
    assert(error.hint.includes('never both'));
    return true;
  });
});

test('public option getter failures discard secret-bearing borrowed errors', async t => {
  noFetch(t);
  for (const connect of [connectSdk, connectNode]) {
    for (const field of ['mode', 'endpoint', 'token']) {
      const options = {mode: 'remote', endpoint: 'https://host.example/', token: secret};
      Object.defineProperty(options, field, {get() {
        throw new ClientError('BorrowedError', {hint: secret, cause: new Error(secret)});
      }});
      await assert.rejects(connect(options), error => {
        safe(error); assert.equal(error.code, 'InvalidConnectionOptions'); return true;
      });
    }
  }
});

test('embedded Local advice retains its distinct code and requires no Host credentials', async t => {
  noFetch(t);
  await assert.rejects(connectSdk({mode: 'local', owner: 'local'}), error => {
    safe(error); assert.equal(error.code, 'LocalProviderNotInstalled');
    assert(error.hint.includes('@actql/node'));
    assert(error.hint.includes('use open() without a Host or token'));
    return true;
  });
});

test('initial token provider failures omit borrowed secret-bearing exceptions', async t => {
  noFetch(t);
  for (const connect of [connectSdk, connectNode]) {
    await assert.rejects(connect({mode: 'remote', endpoint: 'https://host.example/',
      token() {throw new ClientError('BorrowedSecret', {cause: new Error(secret), hint: secret});}}), error => {
      safe(error); assert.equal(error.code, 'ClientCredentialUnavailable');
      assert(error.hint.includes('without logging its result or exception'));
      return true;
    });
  }
});

test('initial transport failures retain their classification without a credential-bearing cause', async t => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = () => {calls++; throw new Error(secret);};
  t.after(() => {globalThis.fetch = original; assert.equal(calls, 2);});
  for (const connect of [connectSdk, connectNode]) {
    await assert.rejects(connect({mode: 'remote', endpoint: 'https://host.example/', token: secret}), error => {
      assert(error instanceof ClientError); assert.equal(error.code, 'ClientTransportUnknown');
      assert.equal(error.cause, undefined);
      assert(!inspect(error, {showHidden: true}).includes(secret));
      return true;
    });
  }
});
