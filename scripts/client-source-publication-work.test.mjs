import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {tokens} from './portable-core.mjs';

// Construction topology of the actual portable caller, not runtime call or
// validation counts. The Common tests exercise the original typed bindings.
const source = tokens(readFileSync(new URL('../src/run_publication_host/client_source_preparation.mbt', import.meta.url), 'utf8'), true);
const start = source.findIndex((token, index) => token.value === 'fn' && source[index + 1]?.value === 'prepare_client_source_computation');
assert(start >= 0);
let at = start + 2;
while (source[at]?.value !== '{') {assert(at < source.length); at++;}
let depth = 1;
const body = [];
while (++at < source.length) {
  if (source[at].value === '{') depth++;
  if (source[at].value === '}' && --depth === 0) break;
  body.push(source[at]);
}
assert.equal(depth, 0);
const calls = name => body.filter((token, index) => token.kind === 'word' && token.value === name && body[index + 1]?.value === '(').length;

test('portable Source preparation binds all publication parts once', () => {
  assert.equal(calls('bind_published_query_parts_with_catalog'), 1);
  assert.equal(calls('bind_published_query_parts'), 0);
  for (const name of ['bind_published_query_context', 'published_table_writes',
    'published_update_targets', 'published_store_targets', 'published_command_targets']) {
    assert.equal(calls(name), 0, name);
  }
});

test('portable pure and Effect preparation consume the same original Catalog', () => {
  for (const name of ['prepare_parsed_effect_free_client_program', 'prepare_parsed_client_effect_computation']) {
    const start = body.findIndex((token, index) => token.value === name && body[index + 1]?.value === '(');
    assert(start >= 0, name);
    const arguments_ = [];
    let depth = 1;
    for (let at = start + 2; at < body.length; at++) {
      if (body[at].value === '(') depth++;
      if (body[at].value === ')' && --depth === 0) break;
      arguments_.push(body[at].value);
    }
    assert.equal(depth, 0, name);
    const expected = ['source_catalog', '=', 'catalog'];
    assert.equal(arguments_.filter((_, index) => expected.every((value, offset) => arguments_[index + offset] === value)).length, 1, name);
  }
  assert.equal(calls('prepare_source_catalog'), 0, 'The publication Owner already supplied the original Catalog');
});

test('portable Source preparation retains its parsed computation and original intake', () => {
  assert.equal(calls('lower'), 1);
  assert.equal(calls('parse_json_bytes_preserving'), 1);
  assert.equal(calls('prepare_parsed_effect_free_client_program'), 1);
  assert.equal(calls('prepare_parsed_client_effect_computation'), 1);
  assert.equal(calls('parse'), 0, 'Do not reparse the lowerer emitted Program JSON');
});
