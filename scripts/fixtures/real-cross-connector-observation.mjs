// Test-only pass-through observation of the actual installed transports. It
// provides no data, token, credential, Source evidence or result replacement.
import assert from 'node:assert/strict';
import https from 'node:https';
import {syncBuiltinESMExports} from 'node:module';

export function gcsMetadataRequestObserver({request, manifest, now = Date.now, forbidden = false, signal}) {
  let requests = 0, responses = 0, responseBytes = 0;
  const started = now();
  const active = new Set();
  const observed = function(options, callback) {
    if (options?.hostname !== 'storage.googleapis.com') return Reflect.apply(request, this, arguments);
    assert(!forbidden, 'Restoration must not reopen GCS');
    signal?.throwIfAborted();
    assert.equal(options.protocol, 'https:');
    assert.equal(options.method, 'GET');
    const target = new URL(options.path, 'https://storage.googleapis.com');
    assert.equal(target.pathname, `/storage/v1/b/${manifest.bucket}/o`, 'Only metadata listing is authorized');
    assert.equal(target.searchParams.get('prefix'), manifest.prefix);
    assert.equal(target.searchParams.get('projection'), 'noAcl');
    assert([...target.searchParams.keys()].every(key => ['prefix', 'maxResults', 'projection', 'pageToken'].includes(key)));
    assert(now() - started < manifest.limits.maxDurationMs);
    assert(requests < manifest.limits.maxRequests);
    requests++;
    const physical = Reflect.apply(request, this, [options, function(response) {
      responses++;
      response.on('data', chunk => { responseBytes += chunk.byteLength; });
      return Reflect.apply(callback, this, arguments);
    }]);
    if (signal) {
      // This is the explicit external test-window cancellation, separate from
      // product fuel/capacity. The original Site observes this same error.
      const abort = () => physical.destroy(Object.assign(new Error('GcsTestWindowExpired'),
        {code: 'GcsTestWindowExpired'}));
      active.add(physical);
      physical.once('close', () => { active.delete(physical); signal.removeEventListener('abort', abort); });
      signal.addEventListener('abort', abort, {once: true});
      if (signal.aborted) abort();
    }
    return physical;
  };
  return Object.freeze({request: observed,
    observation: () => Object.freeze({requests, responses, responseBytes}),
    assertClosed() { assert.equal(active.size, 0, 'Original GCS request custody remains active'); },
    assertBounds() { assert(requests <= manifest.limits.maxRequests);
      assert(responseBytes <= manifest.limits.maxResponseBytes); },
  });
}

export function observeInstalledGcsMetadata(manifest, {forbidden = false, signal} = {}) {
  const original = https.request;
  const observer = gcsMetadataRequestObserver({request: original, manifest, forbidden, signal});
  https.request = observer.request;
  syncBuiltinESMExports();
  return Object.freeze({...observer, close() {
    observer.assertClosed();
    assert.equal(https.request, observer.request);
    https.request = original;
    syncBuiltinESMExports();
  }});
}

export function observeInstalledDuckDbReads(duckdb, {forbidden = false} = {}) {
  const {DuckDBConnection, DuckDBExtractedStatements, DuckDBPreparedStatement} = duckdb;
  const owners = new WeakMap(), prepared = new WeakMap(), sessions = new WeakSet();
  const original = {extract: DuckDBConnection.prototype.extractStatements,
    prepare: DuckDBExtractedStatements.prototype.prepare, stream: DuckDBPreparedStatement.prototype.stream};
  let sourceReadSessions = 0, sourceReadStatements = 0;
  const extract = async function(sql) {
    const value = await Reflect.apply(original.extract, this, [sql]);
    owners.set(value, {sql, connection: this}); return value;
  };
  const prepare = async function(index) {
    const value = await Reflect.apply(original.prepare, this, [index]);
    prepared.set(value, owners.get(this)); return value;
  };
  const stream = function(...args) {
    const entry = prepared.get(this);
    if (/\bFROM\s+(?:"main"\.)?"records"(?=\s|$)/iu.test(entry?.sql ?? '')) {
      assert(!forbidden, 'Restoration must not reacquire DuckDB');
      sourceReadStatements++;
      if (!sessions.has(entry.connection)) { sessions.add(entry.connection); sourceReadSessions++; }
    }
    return Reflect.apply(original.stream, this, args);
  };
  DuckDBConnection.prototype.extractStatements = extract;
  DuckDBExtractedStatements.prototype.prepare = prepare;
  DuckDBPreparedStatement.prototype.stream = stream;
  return Object.freeze({observation: () => Object.freeze({sourceReadSessions, sourceReadStatements}),
    close() {
      assert.equal(DuckDBConnection.prototype.extractStatements, extract);
      assert.equal(DuckDBExtractedStatements.prototype.prepare, prepare);
      assert.equal(DuckDBPreparedStatement.prototype.stream, stream);
      DuckDBConnection.prototype.extractStatements = original.extract;
      DuckDBExtractedStatements.prototype.prepare = original.prepare;
      DuckDBPreparedStatement.prototype.stream = original.stream;
    }});
}
