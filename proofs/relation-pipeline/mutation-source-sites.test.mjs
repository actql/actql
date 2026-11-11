import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {variants} from './mutation-registry.mjs';
import {applyMutation} from './sites.mjs';

// Source correspondence only: these checks never establish a killed mutant.
for (const variant of variants) test(`current source has one exact mutation site for ${variant.name}`, () => {
  const source = readFileSync(new URL('../../' + variant.path, import.meta.url), 'utf8');
  assert.equal(source.split(variant.before).length, 2);
  const mutated = applyMutation(source, variant);
  assert.notEqual(mutated, source);
  assert.equal(mutated.split(variant.after).length, 2);
  assert.throws(() => applyMutation(source.replace(variant.before, ''), variant), /Mutation site must be unique/);
  assert.throws(() => applyMutation(source + source, variant), /Mutation site must be unique/);
});
