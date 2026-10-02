const atDistinct = (t, predicate) => t.expected.stages.some((s, i) => s.operation === 'distinct' && predicate(s, i));
const tuple = r => JSON.stringify(Object.keys(r.values).sort().map(f => r.values[f]));
export const distinctAcceptance = {
  variant: 'whole-row distinct true; admitted input occurrence order', route: 'DistinctRows', obligations: [
    { id: 'equal first column but different complete row survives', holds: t => atDistinct(t, s => s.input.some((a, i) =>
      s.input.slice(i + 1).some(b => a.values[s.columns[0]] === b.values[s.columns[0]] && tuple(a) !== tuple(b) &&
        s.output.some(r => tuple(r) === tuple(a)) && s.output.some(r => tuple(r) === tuple(b))))) },
    { id: 'NULL-containing equal rows collapse', holds: t => atDistinct(t, s => s.input.some((a, i) =>
      Object.values(a.values).includes(null) && s.input.slice(i + 1).some(b => tuple(a) === tuple(b)) &&
      s.output.filter(r => tuple(r) === tuple(a)).length === 1)) },
    { id: 'interleaved duplicate retains first order through take', holds: t => atDistinct(t, (s, i) =>
      t.testCase.steps.slice(i + 1).some(step => step.op === 'take') &&
      t.testCase.steps.slice(i + 1).every(step => step.op !== 'sort') &&
      s.input.some((a, j) => s.input.slice(j + 2).some((last, offset) => tuple(a) === tuple(last) &&
        s.input.slice(j + 1, j + 2 + offset).some(b => {
          const finalA = t.expected.occurrences.find(r => r.id === a.id);
          const finalB = t.expected.occurrences.find(r => r.id === b.id);
          return tuple(a) !== tuple(b) && finalA && finalB && tuple(finalA) !== tuple(finalB) &&
            t.expected.ids.indexOf(a.id) < t.expected.ids.indexOf(b.id);
        })))) },
    { id: 'empty input', holds: t => atDistinct(t, s => s.input.length === 0) },
  ],
};
