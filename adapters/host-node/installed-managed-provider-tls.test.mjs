import assert from 'node:assert/strict';
import test from 'node:test';
import {userListFixture} from '../connectors/notion/test/user-list-read.fixture.mjs';
import {calendarFixture} from '../connectors/calendar/test/calendar-list.fixture.mjs';

// Uses the selected canonical Common/provider URL and matching original
// contract tree. The compiler Source is recorded by the invocation; this is
// not a matching current-source package or normal installer acceptance.
for(const family of ['notion','calendar']) test(`${family} actual compiled pages signed Credential Account SQLite TLS RowRun and Host release`,async t=>{
  const f=family === 'notion' ? await userListFixture(t) : await calendarFixture(t);
  const reader=f.create(),result=await reader.read();
  assert.equal(result.pages,2);assert.equal(result.rowCount,2);
  assert.equal(f.state.rows.length,2);assert.equal(f.state.requests.length,2);
  assert.equal(f.state.resolutions,2);assert.equal(f.state.charges,2);
  f.row.finish();assert.equal(f.row.captureCount(),2);
  assert.equal(reader.observe().transportClosed,true);
  assert.equal(reader.observe().cleanupConfirmed,false);
  reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);
  reader.retry();assert.equal(f.state.requests.length,2);
  assert.deepEqual(f.journal.recover().map(r=>r.outcome),['succeeded','succeeded']);
  // The original fixture's after hook closes this same RowRun and verifies
  // transfer/held/retention/execution reservations are all actually zero.
});
