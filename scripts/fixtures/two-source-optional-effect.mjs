import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read = name => readFileSync(new URL(name, import.meta.url), 'utf8');
export const optionalEffectExpectations = JSON.parse(read('./two-source-optional-effect.expected.json'));
export const optionalEffectFixtureFiles = [
  'two-source-optional-effect.mjs', 'two-source-optional-effect.expected.json',
  'two-source-without-effect.program.json', 'two-source-with-effect.program.template.json',
  'two-source-without-effect.aql', 'two-source-with-effect.aql.template',
];

// Two complete, independently authored inputs. Submission binds only the
// installed MappingRef; it never adds an Effect to lowered or executed JSON.
export function optionalEffectSubmission(kind, enabled, mappingRef) {
  assert.ok(['native-json', 'broad-text'].includes(kind));
  assert.equal(typeof enabled, 'boolean');
  const text = kind === 'broad-text';
  const file = enabled
    ? text ? './two-source-with-effect.aql.template' : './two-source-with-effect.program.template.json'
    : text ? './two-source-without-effect.aql' : './two-source-without-effect.program.json';
  let document = read(file);
  if (enabled) {
    assert.equal(typeof mappingRef, 'string');
    assert.ok(mappingRef.length > 0 && !/[`\\\r\n]/u.test(mappingRef));
    assert.equal(document.split('__PUBLICATION_MAPPING_REF__').length, 2);
    document = document.replace('__PUBLICATION_MAPPING_REF__',
      text ? mappingRef : JSON.stringify(mappingRef).slice(1, -1));
  }
  return {document, format: text ? 'aql-text' : 'json'};
}

export function optionalEffectCases(argv) {
  const focused = ['--composed-text', '--composed-infer', '--two-source-effect'];
  return argv.includes('--optional-effect-only') || !focused.some(flag => argv.includes(flag))
    ? ['native-json', 'broad-text'] : [];
}
