import { oracle } from './engine.mjs';
import { expectedContracts } from './evidence.mjs';
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const onlyRename = c => c.steps.filter(s => s.op === 'rename').length === 1;
const emptyContractDomain = c => onlyRename(c) && c.rows.length === 0 &&
  c.steps.every(s => ['rename', 'select', 'take'].includes(s.op));
function contractMismatch(c, observed, anchor) {
  if (!emptyContractDomain(c) || !observed?.checked || !observed.registered || observed.kind !== 'complete') return false;
  const index = c.steps.findIndex(s => s.id === anchor.step && s.op === 'rename');
  if (index < 0) return false;
  const expected = expectedContracts(c, anchor.registry);
  const field = anchor.field;
  const actual = observed.contracts?.[index];
  return expected[index].checked[field]?.[anchor.property] === anchor.expected &&
    actual?.checked[field]?.[anchor.property] === anchor.wrong &&
    actual?.kernel[field]?.[anchor.property] === anchor.wrong;
}
function contractVariant(name, property, expected, wrong, expression) {
  return { name, path: 'src/relation_typing/check.mbt',
    before: '(p.output, visible.get(@schema.reference_name(p.input)).unwrap().0),',
    after: `(p.output, if operation is Rename { ${expression} } else { visible.get(@schema.reference_name(p.input)).unwrap().0 }),`,
    eligible: emptyContractDomain,
    anchor: (c, o, registry) => {
      const index = c.steps.findIndex(s => s.op === 'rename');
      if (index < 0) return null;
      const contracts = expectedContracts(c, registry);
      for (const field of Object.keys(contracts[index].checked)) {
        const anchor = { kind: name, step: c.steps[index].id, field, property, expected, wrong };
        if (contractMismatch(c, o, { ...anchor, registry })) return anchor;
      }
      return null;
    },
    preserves: (c, o, a, registry) => contractMismatch(c, o, { ...a, registry }),
  };
}
export const renameMutations = [
  contractVariant('rename-nullability-widened', 'nullable', false, true, '@contract.primitive(NumberType, nullable=true)'),
  contractVariant('rename-type-changed', 'type', 'number', 'string', '@contract.primitive(StringType, nullable=true)'),
  { name: 'rename-swap-wrong-input', path: 'src/execution_relation/bounded_binding_rows.mbt',
    before: 'guard input_ordinals.get(@schema.reference_name(field.input))\n          is Some(index) &&',
    after: 'guard input_ordinals.get(if input_ordinals.contains(output_name) { output_name } else { @schema.reference_name(field.input) })\n          is Some(index) &&',
    eligible: onlyRename,
    anchor: (c, o, registry) => {
      const step = c.steps.find(s => s.op === 'rename');
      if (!step) return null;
      const expected = oracle(c, registry);
      const stage = expected.stages[c.steps.indexOf(step)];
      for (const [input, output] of Object.entries(step.args.mapping)) {
        if (input === output || step.args.mapping[output] !== input) continue;
        for (const row of stage.input) if (row.values[input] !== row.values[output]) {
          const a = { kind: 'rename swap reads output column', step: step.id, input, output, row: row.id };
          if (swapMismatch(c, o, a, registry)) return a;
        }
      }
      return null;
    },
    preserves: swapMismatch,
  },
];
function swapMismatch(c, observed, a, registry) {
  if (!onlyRename(c) || !observed?.checked || !observed.registered || observed.kind !== 'complete') return false;
  const step = c.steps.find(s => s.id === a.step && s.op === 'rename');
  if (!step || step.args.mapping[a.input] !== a.output || step.args.mapping[a.output] !== a.input) return false;
  const expected = oracle(c, registry);
  const stage = expected.stages[c.steps.indexOf(step)];
  const row = stage.input.find(r => r.id === a.row);
  if (!row || row.values[a.input] === row.values[a.output] || !expected.ids.includes(a.row)) return false;
  // Independently calculate this specific wrong-input rule. Requiring its
  // exact observed result preserves the same defect rather than any mismatch.
  const wrong = registry.map(d => d.name !== 'rename' ? d : { ...d, oracle: (rows, args) => rows.map(r => ({ ...r,
    values: Object.fromEntries(Object.keys(r.values).sort().map(input => {
      const output = Object.hasOwn(args.mapping, input) ? args.mapping[input] : input;
      return [output, Object.hasOwn(r.values, output) ? r.values[output] : r.values[input]];
    })),
  })) });
  const wrongExpected = oracle(c, wrong);
  return same(observed.columns, expected.columns) && !same(expected.rows, wrongExpected.rows) && same(observed.rows, wrongExpected.rows);
}
