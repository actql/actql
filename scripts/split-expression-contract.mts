import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const splitLaw = {
  signature: 'One STRING value expression and an optional ordinary STRING delimiter expression. The result is Array(String) with non-null String elements, nullable exactly when any supplied operand is nullable. Untyped NULL takes the unique STRING signature at either position. No implicit conversion, BYTES, regular-expression or collation overload is admitted. The domain is the existing finite, bounded String domain.',
  value: 'Split at non-overlapping literal delimiter matches in input order, preserving leading, adjacent and trailing empty parts. Omitted delimiter is U+002C COMMA. Empty input produces one empty String, including with an empty delimiter. An empty delimiter on nonempty input produces one String per Unicode scalar, not UTF-8 byte, UTF-16 code unit or grapheme cluster. Preserve all remaining scalars exactly, including astral characters, combining marks, NUL and line breaks, without normalization, case folding or trimming. Literal matching does not restrict the delimiter expression to a literal or parameter. Any supplied NULL operand produces NULL after all demanded children succeed.',
  typing: 'Retain known input max_codepoints and max_utf8_bytes on the non-null String element contract and drop min_length. The scalar-count ceiling n is the smaller of both known maxima, or the sole known maximum; a UTF-8 byte ceiling is conservative for scalar count. Set max_items to n + 1 only when representable in the existing safe-integer bound domain; otherwise omit max_items. Do not evaluate either child to derive a type or invent minimum bounds.',
  evaluation: 'Evaluate every supplied child exactly once in authored order, value before delimiter, before strict NULL propagation. NULL does not suppress a later demanded child failure. Preserve the first child failure and enclosing lazy demand. The common expression continuation retains operand roots, logical operand/result charges, control work, live-value/output-byte limits, node/depth limits, workspace and cooperative cancellation throughout literal search, exact sizing and construction. No secondary evaluator or Host splitting helper replaces this owner.',
  identity: 'The closed source is {split: [value, delimiter?]} and the machine node is {op: split, body: [value, delimiter?]}. Retain an ordered one-element array for omission and a two-element array for an explicit delimiter. Omission stays distinct from explicit NULL and explicit comma. Preserve the node and all ordered children without folding, sorting or duplication. SQL SPLIT selects this common operation. Earlier pinned contract bodies retain their original meaning and identities.',
  admission: 'SPLIT is an ordinary common expression, with no split-specific text-time profile, policy or envelope. Nested profile calls retain their own obligations and input preflight. Admit the complete Array wire bytes, node/depth shape, String storage and Array slots before allocating output builders or storage. No eager whole-input split or retained boundary array substitutes for bounded continuation work. Existing Array ownership, String admission, retained-root cleanup and cancellation rules remain in force; split_part retains its separately owned text-time law.',
};

type Kind = 'source' | 'node';
type Scope = [owner: 'expressions' | 'protocol', path: string, kind: Kind, reference: string];
export type SplitSchema = {$ref?: string; type?: string; additionalProperties?: boolean;
  required?: string[]; properties?: Record<string, SplitSchema>; const?: unknown;
  oneOf?: SplitSchema[]; minItems?: number; maxItems?: number; items?: SplitSchema};
type Expressions = {schemas: Record<string, unknown>; laws: Record<string, unknown>; grammar_sha256: string};
type Protocol = {artifact_schemas: Record<string, unknown>; artifact_schema_cids: Record<string, string>;
  artifact_registry_cid: string};

// These are the declared common-expression embeddings, not a global spelling
// replacement. Each child reference remains local to its owning schema scope.
const scopes: Scope[] = [
  ['expressions', 'schemas/expression/$defs/expression', 'source', 'expression'],
  ['expressions', 'schemas/expression_node/$defs/expression', 'node', 'expression'],
  ['expressions', 'schemas/fragment/$defs/source_expression', 'source', 'source_expression'],
  ['expressions', 'schemas/fragment/$defs/machine_expression', 'node', 'machine_expression'],
  ['expressions', 'schemas/predicate_consumer/$defs/source_expression', 'source', 'source_expression'],
  ['expressions', 'schemas/predicate_consumer/$defs/machine_expression', 'node', 'machine_expression'],
  ...['executable_plan', 'plan_document'].flatMap(artifact => {
    const prefix = artifact === 'plan_document' ? 'properties/plan/' : '';
    return ['predicate', 'value_expression'].map<Scope>(definition => ['protocol',
      `artifact_schemas/${artifact}/${prefix}properties/execution_material/properties/program/$defs/${definition}`,
      'source', 'value_expression']);
  }),
];
const named = (shape: SplitSchema, name: string, kind: Kind) => kind === 'source'
  ? shape.required?.includes(name) || Object.hasOwn(shape.properties ?? {}, name)
  : shape.properties?.op?.const === name;
function shape(name: string, kind: Kind, reference: string, minimum: number, maximum: number): SplitSchema {
  const body = {type: 'array', minItems: minimum, maxItems: maximum,
    items: {$ref: `#/$defs/${reference}`}};
  return kind === 'source'
    ? {type: 'object', additionalProperties: false, required: [name], properties: {[name]: body}}
    : {type: 'object', additionalProperties: false, required: ['op', 'body'],
      properties: {op: {const: name}, body}};
}
function walk(value: unknown, visit: (value: SplitSchema) => void) {
  if (!value || typeof value !== 'object') return;
  visit(value as SplitSchema);
  for (const child of Object.values(value)) walk(child, visit);
}
function requireGrammar(grammar: string) {
  // Comments or a similarly named function do not register a function token.
  const source = grammar.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const productions = [...source.matchAll(/\bfunction_name\s*=([^;]+);/gu)];
  assert.equal(productions.length, 1, 'one common function_name production');
  const body = productions[0]?.[1];
  assert.ok(body);
  assert.equal([...body.matchAll(/"split"/gu)].length, 1,
    'split missing or duplicated in common function_name production');
}

export function updateSplitContracts(expressions: Expressions, protocol: Protocol, grammar: string, write = false) {
  requireGrammar(grammar);
  const roots = {expressions, protocol};
  const counts = {source: 0, node: 0};
  // Preflight every scope and duplicate before mutating even in write mode.
  const plans = scopes.map(([owner, path, kind, reference]) => {
    const scope = path.split('/').reduce<unknown>((value, key) =>
      value && typeof value === 'object' ? (value as Record<string, unknown>)[key] : undefined,
    roots[owner]) as SplitSchema | undefined;
    assert.ok(scope && Array.isArray(scope.oneOf), `missing ${owner}/${path} expression scope`);
    const choices = scope.oneOf;
    const templates = choices.filter(candidate => named(candidate, 'replace', kind));
    assert.equal(templates.length, 1, `unique local replace template at ${owner}/${path}`);
    assert.deepEqual(templates[0], shape('replace', kind, reference, 3, 3),
      `closed local replace template at ${owner}/${path}`);
    const matches = choices.filter(candidate => named(candidate, 'split', kind));
    assert.ok(matches.length <= 1, `duplicate ${kind} split shape at ${owner}/${path}`);
    counts[kind]++;
    return {scope, choices, kind, previous: matches[0], expected: shape('split', kind, reference, 1, 2)};
  });
  assert.deepEqual(counts, {source: 7, node: 3}, 'SPLIT schema embedding count');
  const ownedScopes = new Set(plans.map(plan => plan.scope));
  for (const root of [expressions.schemas, protocol.artifact_schemas]) walk(root, value => {
    if (!Array.isArray(value.oneOf)) return;
    for (const kind of ['source', 'node'] as const) {
      if (value.oneOf.some(candidate => named(candidate, 'replace', kind) || named(candidate, 'split', kind))) {
        assert.ok(ownedScopes.has(value), `unregistered ${kind} expression scope`);
      }
    }
  });
  assert.ok(expressions.laws && protocol.artifact_schema_cids,
    'existing expression law and protocol identity owners');
  for (const {choices, kind, previous, expected} of plans) {
    if (write) {
      if (previous) choices[choices.indexOf(previous)] = expected;
      else choices.push(expected);
    } else assert.deepEqual(previous, expected, `stale ${kind} split shape`);
  }
  const grammarHash = createHash('sha256').update(grammar).digest('hex');
  if (write) {
    expressions.laws.split = structuredClone(splitLaw);
    expressions.grammar_sha256 = grammarHash;
  } else {
    assert.deepEqual(expressions.laws.split, splitLaw, 'stale SPLIT law');
    assert.equal(expressions.grammar_sha256, grammarHash, 'stale expression grammar pin');
  }
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(schema), `stale ${name} schema CID`);
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas), 'stale artifact registry CID');
  return counts;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const expressionPath = 'spec/contracts/actql-expressions.json';
  const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
  const expressions: Expressions & {grammar: string} = JSON.parse(readFileSync(expressionPath, 'utf8'));
  const protocol: Protocol = JSON.parse(readFileSync(protocolPath, 'utf8'));
  const grammar = readFileSync(expressions.grammar, 'utf8');
  if (process.argv.includes('--write')) {
    updateSplitContracts(expressions, protocol, grammar, true);
    writeFileSync(expressionPath, JSON.stringify(expressions, null, 2) + '\n');
    writeFileSync(protocolPath, JSON.stringify(protocol, null, 2) + '\n');
  }
  console.log('GoogleSQL STRING SPLIT contracts verified:', updateSplitContracts(expressions, protocol, grammar));
}
