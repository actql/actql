import type {DatabaseSync} from 'node:sqlite';

export function checkpointJournalClose(database: Pick<DatabaseSync, 'close' | 'isOpen'>) {
  let closed = false;
  let databaseClosed = false;
  return {
    get closed() { return closed; },
    close() {
      if (databaseClosed) return;
      // A previous close may have completed without returning. Confirm the
      // same private connection before attempting another physical close.
      if (closed && database.isOpen === false) {
        databaseClosed = true;
        return;
      }
      closed = true;
      database.close();
      databaseClosed = true;
    },
  };
}
