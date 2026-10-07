import assert from 'node:assert/strict';
import {graphAbbreviatedSuccesses} from './graph-abbreviated-edge-source-input.mjs';

// Reuse only independent authored inputs/controls. No compiler or product
// evaluator supplies the expected bounds, multiplicities or result contracts.
const base = mode => graphAbbreviatedSuccesses.find(item =>
  item.name === 'graph-abbreviated-bounded-' + mode.toLowerCase());
const results = depths => ({matched: {rows: depths.map(depth => ({depth})),
  columns: [{name: 'depth', contract: {type: 'number', nullable: false}}]}});
function sourceCase(name, quantifier, depths, mode = 'WALK', edge = '-') {
  const fixture = base(mode);
  assert.ok(fixture);
  assert.equal(fixture.text.split('-{0,2}').length, 2);
  return {...fixture, name: 'graph-quantifier-' + name,
    text: fixture.text.replace('-{0,2}', edge + quantifier), results: results(depths)};
}
function machineCase(name, minimum, maximum, depths) {
  const control = graphAbbreviatedSuccesses.find(item => item.name === 'graph-abbreviated-json-bounded-trail');
  const program = JSON.parse(control.text);
  const traversal = program.stages[0].steps[5].traverse;
  traversal.path_mode = 'walk';
  traversal.min_hops = minimum;
  traversal.max_hops = maximum;
  return {...control, name: 'graph-quantifier-json-' + name, text: JSON.stringify(program), results: results(depths)};
}
export const graphQuantifierFormsSuccesses = [
  machineCase('fixed', 2, 2, [2, 2, 2, 2]),
  machineCase('omitted-lower', 0, 2, [0, 1, 1, 2, 2, 2, 2]),
  sourceCase('explicit-fixed-control', '{2,2}', [2, 2, 2, 2]),
  sourceCase('fixed-walk', '{2}', [2, 2, 2, 2]),
  sourceCase('fixed-trail', '{2}', [2, 2], 'TRAIL'),
  sourceCase('fixed-acyclic-empty', '{2}', [], 'ACYCLIC'),
  sourceCase('omitted-lower-walk', '{,2}', [0, 1, 1, 2, 2, 2, 2]),
  sourceCase('omitted-lower-trail', '{,2}', [0, 1, 1, 2, 2], 'TRAIL'),
  sourceCase('omitted-lower-acyclic-zero', '{,2}', [0], 'ACYCLIC'),
  sourceCase('fixed-incoming', '{2}', [2, 2, 2, 2], 'WALK', '<-'),
  // The full filler selects R alone, unlike the two-label empty-edge cases.
  sourceCase('full-label-fixed', '{2}', [2], 'WALK', '-[:R]->'),
];
export const graphQuantifierFormsRefusals = [
  ...['{0}', '{,0}', '{}', '{,}', '{1,}', '{2,1}', '{9007199254740992}'].map((bounds, index) => {
    const fixture = sourceCase('invalid-' + index, bounds, []);
    const {results: ignored, ...input} = fixture;
    return input;
  }),
  (() => {
    const fixture = sourceCase('named-quantified-edge', '{2}', [], 'WALK', '-[e]-');
    const {results: ignored, ...input} = fixture;
    return input;
  })(),
  (() => {
    const fixture = sourceCase('terminal-only-predicate', '{2}', []);
    const {results: ignored, ...input} = fixture;
    return {...input, text: input.text.replace('(b:Node)', '(b:Node WHERE payload.score > 10)')};
  })(),
];
