// Unchanged compiled-boundary case, separated from SQLite-only selections.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

test('compiled invalidation boundary rejects fabricated port before Core or caller callbacks', () => {
  let called = 0;
  const fake = {kind: 'original-model-journal-port', current() {called++; return true;}};
  for (const port of [undefined, fake, true, () => {called++; return true;}, 'sha256:' + '0'.repeat(64)]) {
    assert.throws(() => moon.clientProgramCompleteInferOriginalJournalInvalidation(
      undefined, undefined, port, {}, {}, {}, {}), {code: 'ForeignModelOriginalJournalPort'});
  }
  assert.equal(called, 0);
  assert.equal('clientProgramConsumeInferOriginalResourceInvalidation' in moon, false);
});
