// Inject loss into one test-owned physical journal, preserving its original
// row first. This is neither an expiry policy nor a request cleanup API.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';

export async function loseRequestRecord(directory, requestId) {
  const database = new DatabaseSync(join(directory, 'requests/client-requests.sqlite3'));
  try {
    const rows = database.prepare('SELECT * FROM client_requests WHERE caller_request_id = ?').all(requestId);
    assert.equal(rows.length, 1);
    const original = {...rows[0]};
    await writeFile(join(directory, 'original-request-record.json'), JSON.stringify(original));
    const removed = database.prepare('DELETE FROM client_requests WHERE authority_scope_cid = ? AND caller_request_id = ?')
      .run(original.authority_scope_cid, requestId);
    assert.equal(Number(removed.changes), 1);
    assert.equal(database.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
    return original;
  } finally {database.close();}
}
