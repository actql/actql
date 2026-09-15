import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import test from 'node:test';

// A dependency-shape guard, not evidence of semantic or ownership conformance.
// Those properties are checked through the operation and Program tests.
function historyAccess(source) {
  return /\brequirements\s*\.\s*expressions\s*\.\s*identity\s*\.\s*sources\s*\.\s*operations\s*\.\s*preparation\s*\.\s*profiles\s*\.\s*context\s*\.\s*selected\s*\.\s*context\s*\.\s*wired\s*\.\s*stages\b/u.test(source);
}

test('operation consumers do not recover stages from preparation history', () => {
  const root = 'src/pipeline_check_context';
  for (const name of readdirSync(root)) {
    if (!name.endsWith('.mbt') || name.endsWith('test.mbt')) continue;
    assert.equal(historyAccess(readFileSync(`${root}/${name}`, 'utf8')), false, name);
  }
});

test('the dependency guard detects nested owners and wrapped access', () => {
  const chain = 'requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages';
  for (const prefix of ['', 'owner.', 'items.owner.']) {
    assert.equal(historyAccess(prefix + chain), true);
    assert.equal(historyAccess(prefix + chain.replaceAll('.', '\n  . ')), true);
  }
  assert.equal(historyAccess('owner.requirements.stages'), false);
  // The producer may establish a shared owner from its validated input once.
  assert.equal(historyAccess(chain.replace('requirements.', '')), false);
});

test('aggregate guards consume retained resolution slots, not profile history', () => {
  for (const name of ['group_array_limit', 'group_string_limit']) {
    const source = readFileSync(`src/pipeline_check_context/${name}.mbt`, 'utf8');
    assert.doesNotMatch(source, /\bowner\s*\.\s*profiles\b/u);
    assert.match(source, /owner\.states\[first \+ offset\]/u);
  }
});
