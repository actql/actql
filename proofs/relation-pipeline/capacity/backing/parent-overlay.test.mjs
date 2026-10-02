import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { parentOverlay, helper } from '../parent-control/overlay.mjs';
import { parentCase } from '../parent-control/audit.mjs';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
const read = path => readFileSync(join(root, path));
test('one existing two-child registered case fixes the native startup scope', () => {
  assert.equal(parentCase().id, 'pair:filter/distinct');
  assert.deepEqual(parentCase().steps.map(s => s.op), ['filter', 'distinct']);
});
test('the parent observation borrows source roots and rejects a missing constructor site', () => {
  const overlay = parentOverlay(read);
  assert(overlay[helper].includes('#borrow(parent, children, previous, current'));
  const provider = 'src/connectors/local/selected_relation_provider.mbt';
  assert.equal(overlay[provider].split('println(parent_control_probe(').length, 2);
  assert.throws(() => parentOverlay(path => path === provider ? '' : read(path)), /Missing exact chain constructor/);
});
