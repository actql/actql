// A failed operation and the usability of its connection are independent.
// Only DatabaseSync's transaction state, never a probe query or error text,
// can establish that a connection has left a transaction.
export function createSqliteTransaction(database, prefix) {
  let unusable = false;
  const failure = (code, cause, details = {}) => Object.assign(
    new Error(code, {cause}), {code, ...details});
  const assertUsable = () => {
    if (unusable) throw failure(`${prefix}ConnectionUnusable`);
  };
  const inspect = () => {
    try {
      const active = database.isTransaction;
      if (typeof active !== 'boolean') {
        throw new TypeError('DatabaseSync transaction state is unavailable');
      }
      return {active};
    } catch (stateCause) {
      unusable = true;
      return {active: undefined, stateCause};
    }
  };
  const run = body => {
    assertUsable();
    try { database.exec('BEGIN IMMEDIATE'); }
    catch (cause) {
      const state = inspect();
      if (state.active === false) throw cause;
      unusable = true;
      throw failure(`${prefix}ConnectionUnusable`, cause, {
        operation: 'begin', outcome: 'unknown',
        stateCause: state.stateCause, connectionUsable: false,
      });
    }
    let phase = 'body';
    try {
      const value = body();
      phase = 'commit';
      database.exec('COMMIT');
      return value;
    } catch (cause) {
      let rollbackCause;
      let state = inspect();
      if (state.active === true) {
        try { database.exec('ROLLBACK'); }
        catch (error) { rollbackCause = error; }
        state = inspect();
      }
      if (state.active !== false) unusable = true;
      const outcome = phase === 'commit' || state.active !== false ?
        'unknown' : 'failed';
      if (outcome === 'failed' && rollbackCause === undefined &&
          state.stateCause === undefined) throw cause;
      throw failure(phase === 'commit' ? `${prefix}CommitOutcomeUnknown` :
        `${prefix}RollbackFailed`, cause, {
        operation: phase, outcome, rollbackCause,
        stateCause: state.stateCause, connectionUsable: !unusable,
      });
    }
  };
  return Object.freeze({run, assertUsable,
    get connectionUsable() { return !unusable; }});
}
