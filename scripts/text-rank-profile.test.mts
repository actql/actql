import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { canonicalText } from './check-canonical-json.mjs';

test('selected lexical profile bytes match independent canonical serialization', () => {
  const bytes = readFileSync(new URL('../portability/profiles/text-rank-unicode16.json', import.meta.url));
  const profile = JSON.parse(bytes.toString('utf8'));
  assert.equal(bytes.toString('utf8'), canonicalText(profile));
  assert.equal(profile.version, 'actql-text-rank-profile/0.1');
  assert.equal(profile.tokenizer_law.version, 'actql-text-rank-tokenizers/0.1');
  assert.equal(profile.numeric_law.version, 'actql-bm25-binary64/0.1');
});
