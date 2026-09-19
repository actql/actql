import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const corpusPath = 'portability/corpus/vector-numeric.json';
const fixturePath = 'src/vector_numeric/fixture.generated_wbtest.mbt';
const bitsPattern = /^[0-9a-f]{16}$/;
const metrics = new Set(['cosine', 'dot', 'l2']);
const issues = new Set(['NonFinite', 'ZeroVector']);

function checkBits(value, label) {
  assert.equal(typeof value, 'string', `${label} must be a string`);
  assert.match(value, bitsPattern, `${label} must contain 64-bit hex`);
}

function checkBitsList(value, label) {
  assert.ok(Array.isArray(value) && value.length > 0, `${label} must be nonempty`);
  value.forEach((bits, index) => checkBits(bits, `${label}[${index}]`));
}

function checkOutcome(item, successFields) {
  const success = item.issue === undefined;
  assert.equal(
    success,
    successFields.every(field => item[field] !== undefined),
    `${item.id} must define exactly one outcome`,
  );
  if (!success) assert.ok(issues.has(item.issue), `${item.id} has an unknown issue`);
}

export function checkVectorNumericCorpus(corpus) {
  assert.equal(corpus.version, 'actql-vector-numeric-vectors/0.1');
  assert.equal(corpus.encoding, 'binary64_hex_bits');
  assert.ok(Array.isArray(corpus.cases) && corpus.cases.length > 0);
  const ids = new Set();
  const kinds = new Set();
  for (const item of corpus.cases) {
    assert.match(item.id, /^[a-z][a-z0-9_]*$/);
    assert.ok(!ids.has(item.id), `duplicate vector id: ${item.id}`);
    ids.add(item.id);
    kinds.add(item.kind);
    if (item.kind === 'quantize') {
      checkBits(item.input, `${item.id}.input`);
      checkOutcome(item, ['expected']);
      if (item.expected !== undefined) checkBits(item.expected, `${item.id}.expected`);
    } else if (item.kind === 'normalize') {
      checkBitsList(item.input, `${item.id}.input`);
      if (item.sum !== undefined) checkBits(item.sum, `${item.id}.sum`);
      checkOutcome(item, ['sum', 'divisor', 'expected']);
      if (item.issue === 'ZeroVector') {
        checkBits(item.sum, `${item.id}.sum`);
      }
      if (item.divisor !== undefined) checkBits(item.divisor, `${item.id}.divisor`);
      if (item.expected !== undefined) {
        checkBitsList(item.expected, `${item.id}.expected`);
        assert.equal(item.expected.length, item.input.length);
      }
    } else if (item.kind === 'score') {
      assert.ok(metrics.has(item.metric), `${item.id} has an unknown metric`);
      checkBitsList(item.left, `${item.id}.left`);
      checkBitsList(item.right, `${item.id}.right`);
      assert.equal(item.left.length, item.right.length, `${item.id} dimensions differ`);
      checkOutcome(item, ['expected']);
      if (item.expected !== undefined) checkBits(item.expected, `${item.id}.expected`);
    } else {
      assert.fail(`${item.id} has an unknown kind`);
    }
  }
  assert.deepEqual([...kinds].sort(), ['normalize', 'quantize', 'score']);
  for (const fragment of [
    'tie_to_even',
    'subnormal',
    'overflow',
    'negative_zero',
    'sqrt_boundary',
    'dimension_order',
    'nonfinite',
  ]) {
    assert.ok([...ids].some(id => id.includes(fragment)), `missing ${fragment} vector`);
  }
}

const literal = bits => `(0x${bits}UL).reinterpret_as_double()`;
const bits = bits => `0x${bits}UL`;
const array = values => `[${values.map(literal).join(', ')}]`;
const metric = value => ({cosine: 'Cosine', dot: 'Dot', l2: 'L2'})[value];

function emitQuantize(item) {
  if (item.issue !== undefined) {
    return `  assert_eq(quantize(${literal(item.input)}), Err(${item.issue}))`;
  }
  return [
    `  let actual = quantize(${literal(item.input)}).unwrap()`,
    `  assert_eq(actual.reinterpret_as_uint64(), ${bits(item.expected)})`,
  ].join('\n');
}

function emitNormalize(item) {
  const lines = [
    `  let input = ${array(item.input)}`,
    '  let mut sum = 0.0',
    '  for component in input {',
    '    sum = squared_norm_step(sum, component).unwrap()',
    '  }',
  ];
  if (item.issue === 'NonFinite') {
    return [
      `  let input = ${array(item.input)}`,
      '  assert_eq(squared_norm_step(0.0, input[0]), Err(NonFinite))',
    ].join('\n');
  }
  lines.push(`  assert_eq(sum.reinterpret_as_uint64(), ${bits(item.sum)})`);
  if (item.issue !== undefined) {
    lines.push(`  assert_eq(normalization_divisor(sum), Err(${item.issue}))`);
    return lines.join('\n');
  }
  lines.push(
    '  let divisor = normalization_divisor(sum).unwrap()',
    `  assert_eq(divisor.reinterpret_as_uint64(), ${bits(item.divisor)})`,
  );
  item.expected.forEach((expected, index) => {
    lines.push(
      `  let output_${index} = normalize_component(input[${index}], divisor).unwrap()`,
      `  assert_eq(output_${index}.reinterpret_as_uint64(), ${bits(expected)})`,
    );
  });
  return lines.join('\n');
}

function emitScore(item) {
  const lines = [
    `  let left = ${array(item.left)}`,
    `  let right = ${array(item.right)}`,
    `  let fold = prepare_score(${metric(item.metric)})`,
  ];
  if (item.issue !== undefined) {
    lines.push(`  assert_eq(score_step(fold, left[0], right[0]), Err(${item.issue}))`);
    return lines.join('\n');
  }
  lines.push(
    '  for index in 0..<left.length() {',
    '    score_step(fold, left[index], right[index]).unwrap()',
    '  }',
    '  let actual = finish_score(fold).unwrap()',
    `  assert_eq(actual.reinterpret_as_uint64(), ${bits(item.expected)})`,
  );
  return lines.join('\n');
}

export function renderVectorNumericFixture(corpus) {
  checkVectorNumericCorpus(corpus);
  const tests = corpus.cases.map(item => {
    const body = item.kind === 'quantize'
      ? emitQuantize(item)
      : item.kind === 'normalize'
        ? emitNormalize(item)
        : emitScore(item);
    return `///|\ntest "independent vector numeric: ${item.id}" {\n${body}\n}`;
  });
  return '// Generated from independent fixed numeric vectors.\n' + tests.join('\n\n') + '\n';
}

export function readVectorNumericCorpus() {
  return JSON.parse(readFileSync(corpusPath, 'utf8'));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const corpus = readVectorNumericCorpus();
  const fixture = renderVectorNumericFixture(corpus);
  if (process.argv.includes('--write')) writeFileSync(fixturePath, fixture);
  assert.equal(readFileSync(fixturePath, 'utf8'), fixture, `stale fixture: ${fixturePath}`);
  console.log(`Vector numeric corpus verified: ${corpus.cases.length} cases.`);
}
