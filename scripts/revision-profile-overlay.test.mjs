import test from 'node:test';
import assert from 'node:assert/strict';
import { checkedProfileOverlay, legacyCompletionViewPath, legacyCompletionView } from './revision-profile-overlay.mjs';

const fixture = 'src/execution_relation/layout_numeric_cases_wbtest.mbt';
const base = () => ({
  label: 'baseline', changed: [fixture], untracked: [legacyCompletionViewPath], fixtures: [fixture],
  read: path => path === legacyCompletionViewPath ? legacyCompletionView : 'store : TableStore[Table]',
});

test('historical direct field shim is exact and recorded with shared fixtures', () => {
  assert.deepEqual(checkedProfileOverlay(base()), [fixture, legacyCompletionViewPath]);
  assert.deepEqual(checkedProfileOverlay({ ...base(), label: 'candidate', untracked: [] }), [fixture]);
});

test('product edits and unrelated untracked files cannot become profiling overlays', () => {
  for (const path of ['src/execution_relation/completion.mbt', 'src/execution_relation/expression.mbt', 'spec/contracts/actql-aoa.json']) {
    assert.throws(() => checkedProfileOverlay({ ...base(), changed: [path] }), /unauthorized/);
  }
  assert.throws(() => checkedProfileOverlay({ ...base(), untracked: ['unexpected.mbt'] }), /unauthorized/);
});

test('modified shims, candidate shims and nonlegacy layouts are rejected', () => {
  assert.throws(() => checkedProfileOverlay({ ...base(), label: 'candidate' }), /invalid legacy/);
  assert.throws(() => checkedProfileOverlay({ ...base(), read: () => legacyCompletionView + '\n' }), /invalid legacy/);
  assert.throws(() => checkedProfileOverlay({ ...base(), read: path => path === legacyCompletionViewPath
    ? legacyCompletionView : 'store : CompletedStore' }), /invalid legacy/);
});
