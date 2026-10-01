import { oracle } from './engine.mjs';
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export function connectionAnchor(testCase) {
  return { kind: 'wrong checked handoff port', producer: testCase.steps[0].id, consumer: testCase.steps[1].id };
}
export function connectionMismatch(testCase, observed, anchor) {
  const event = observed?.faults?.[0];
  return observed?.checked && observed.registered && observed.kind === 'failed' &&
    event?.kind === 'wrong checked handoff port' && event.expectedPort === 0 && event.usedPort === 1 &&
    testCase.steps[event.receiver - 1]?.id === anchor.producer &&
    testCase.steps[event.receiver]?.id === anchor.consumer;
}
function pairPositions(expected, observed, ids) {
  const values = ids.map(id => expected.occurrences.find(row => row.id === id));
  if (values.some(v => !v)) return null;
  const keys = values.map(row => JSON.stringify(expected.columns.map(field => row.values[field])));
  if (keys[0] === keys[1]) return null; // Indistinguishable rows cannot witness an order error.
  const observedKeys = observed.rows.map(row => JSON.stringify(row));
  if (keys.some(key => observedKeys.filter(k => k === key).length !== 1)) return null;
  return keys.map(key => observedKeys.indexOf(key));
}
export function orderAnchor(testCase, observed, registry) {
  const sorts = testCase.steps.filter(step => step.op === 'sort');
  if (sorts.length !== 1 || observed?.kind !== 'complete') return null;
  const step = sorts[0];
  const expected = oracle(testCase, registry);
  const stage = expected.stages[testCase.steps.indexOf(step)];
  const keyIndex = stage.columns.indexOf(step.args.field);
  for (let i = 0; i < stage.ids.length; i++) for (let j = i + 1; j < stage.ids.length; j++) {
    if (stage.rows[i][keyIndex] !== stage.rows[j][keyIndex]) continue;
    const anchor = { kind: 'owned equal-key occurrence pair inverted', sort: step.id,
      field: step.args.field, rows: [stage.ids[i], stage.ids[j]] };
    if (orderMismatch(testCase, observed, anchor, registry)) return anchor;
  }
  return null;
}
export function orderMismatch(testCase, observed, anchor, registry) {
  if (!observed?.checked || !observed.registered || observed.kind !== 'complete') return false;
  const step = testCase.steps.find(s => s.id === anchor.sort);
  if (!step || step.op !== 'sort' || step.args.field !== anchor.field ||
      testCase.steps.filter(s => s.op === 'sort').length !== 1) return false;
  const expected = oracle(testCase, registry);
  if (!same(observed.columns, expected.columns)) return false;
  if (!same(observed.rows.map(row => JSON.stringify(row)).sort(), expected.rows.map(row => JSON.stringify(row)).sort())) return false;
  const stage = expected.stages[testCase.steps.indexOf(step)];
  const key = stage.columns.indexOf(anchor.field);
  const positions = anchor.rows.map(id => stage.ids.indexOf(id));
  if (positions.some(p => p < 0) || stage.rows[positions[0]][key] !== stage.rows[positions[1]][key]) return false;
  const expectedPositions = anchor.rows.map(id => expected.ids.indexOf(id));
  const actualPositions = pairPositions(expected, observed, anchor.rows);
  return expectedPositions[0] >= 0 && expectedPositions[0] < expectedPositions[1] &&
    actualPositions && actualPositions[0] > actualPositions[1];
}
