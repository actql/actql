import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';


// Mutable views over the registered build-time JSON and its unary branches.
type Schema = {
  oneOf?: Schema[];
  required?: string[];
  additionalProperties?: unknown;
  properties?: Record<string, Schema>;
  const?: unknown;
  type?: string;
  $ref?: string;
};
export type ExpressionRegistry = {
  schemas: Record<string, Schema>;
  laws: {abs?: typeof absLaw};
  grammar_sha256: string;
};
export type ArtifactRegistry = {
  artifact_schemas: Record<string, Schema>;
  artifact_schema_cids: Record<string, string>;
  artifact_registry_cid?: string;
};

export const absLaw = {
  signature: 'Exactly one number operand; the result is number with the operand nullability. Untyped NULL takes the unique number signature. No implicit conversion, decimal overload or non-finite value is admitted.',
  value: 'Return the exact binary64 magnitude, including subnormals and the largest finite value. Both zero signs produce canonical positive zero. NULL produces NULL.',
  evaluation: 'Evaluate the sole child exactly once when demanded, then apply the value rule. Preserve the child failure, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. ABS introduces no secondary evaluation or value-domain failure for an admitted finite number.',
  identity: 'The closed source form is {abs: expression}; the closed machine node is {op: abs, body: expression_node}. Retain the ABS node and its child in canonical lowering. The changed expression contract has its own CID; earlier contract CIDs retain their earlier meaning.',
};

// Reuse only the unary schema shape, never SQRT's value or domain semantics.
// Each embedded schema keeps its own local expression reference.
function visit(value: unknown, write: boolean, counts: {source: number; node: number}) {
  if (!value || typeof value !== 'object') return;
  const schema: Schema = value;
  const {oneOf} = schema;
  if (Array.isArray(oneOf)) {
    for (const kind of ['source', 'node'] as const) {
      const named = (candidate: Schema, name: string) => kind === 'source'
        ? candidate.additionalProperties === false &&
          candidate.required?.length === 1 && candidate.required[0] === name
        : candidate.properties?.op?.const === name;
      const templates: Schema[] = oneOf.filter(candidate => named(candidate, 'sqrt'));
      if (!templates.length) continue;
      assert.equal(templates.length, 1, 'ambiguous unary expression schema');
      const expected = structuredClone(templates[0]);
      assert(expected.properties, 'missing unary expression properties');
      if (kind === 'source') {
        expected.required = ['abs'];
        expected.properties = {abs: expected.properties.sqrt};
      } else expected.properties.op.const = 'abs';
      const matches: Schema[] = oneOf.filter(candidate => named(candidate, 'abs'));
      assert.ok(matches.length <= 1, 'duplicate ABS schema');
      if (write) {
        if (matches.length) oneOf[oneOf.indexOf(matches[0])] = expected;
        else oneOf.splice(oneOf.indexOf(templates[0]) + 1, 0, expected);
      } else assert.deepEqual(matches[0], expected, `stale ${kind} ABS schema`);
      counts[kind]++;
    }
  }
  for (const child of Object.values(value)) visit(child, write, counts);
}

export function updateAbsContracts(expressions: ExpressionRegistry, protocol: ArtifactRegistry, grammar: string, write = false) {
  assert.match(grammar, /\| "abs"(?:\s|\|)/u, 'ABS missing from expression grammar');
  const counts = {source: 0, node: 0};
  visit(expressions.schemas, write, counts);
  visit(protocol.artifact_schemas, write, counts);
  assert.ok(counts.source > 0 && counts.node > 0, 'missing unary expression schemas');
  const grammarSha256 = createHash('sha256').update(grammar).digest('hex');
  if (write) {
    expressions.laws.abs = structuredClone(absLaw);
    expressions.grammar_sha256 = grammarSha256;
  } else {
    assert.deepEqual(expressions.laws.abs, absLaw, 'stale ABS law');
    assert.equal(expressions.grammar_sha256, grammarSha256, 'stale expression grammar pin');
  }
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(schema));
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
  return counts;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const expressionPath = 'spec/contracts/actql-expressions.json';
  const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
  const expressions: ExpressionRegistry & {grammar: string} =
    JSON.parse(readFileSync(expressionPath, 'utf8'));
  const protocol: ArtifactRegistry = JSON.parse(readFileSync(protocolPath, 'utf8'));
  const grammar = readFileSync(expressions.grammar, 'utf8');
  if (process.argv.includes('--write')) {
    updateAbsContracts(expressions, protocol, grammar, true);
    writeFileSync(expressionPath, JSON.stringify(expressions, null, 2) + '\n');
    writeFileSync(protocolPath, JSON.stringify(protocol, null, 2) + '\n');
  }
  const counts = updateAbsContracts(expressions, protocol, grammar);
  console.log(`ABS finite-number law and ${counts.source} source/${counts.node} node schema alternatives verified.`);
}
