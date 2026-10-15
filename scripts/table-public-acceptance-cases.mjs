import assert from 'node:assert/strict';

export const tablePublicFixturePaths = Object.freeze([
  'adapters/host-node/table-public-commit.test.mjs',
  'adapters/host-node/fixtures/table-physical-fixture.mjs',
  'adapters/host-node/fixtures/table-test-modules.mjs',
  'adapters/host-node/fixtures/table-text-restart.mjs',
  'adapters/host-node/fixtures/table-ctas-result-control.mjs',
  'adapters/host-common/connector-manifest.fixture.mjs',
  'adapters/host-common/publication-contract-control.fixture.mjs',
  'adapters/connectors/local/iceberg/fixtures/presence-mapping.json',
  'adapters/connectors/local/iceberg/fixtures/presence-schema.json',
  'scripts/check-canonical-json.mjs', 'scripts/actql-spec-family.mjs',
  'scripts/actql-requirement-extraction.mjs',
  'scripts/fixtures/graph-presence.program.json',
  'spec/local-check-environment.json',
  'spec/contracts/actql-table-effect.json',
  'spec/contracts/actql-run-publication.json',
  'spec/contracts/actql-protocol-schemas.json',
  'spec/contracts/actql-numeric-reduction.json',
  'spec/dependencies/actql-graph-laws.json',
]);

// Retain the original twenty cases; add the independently authored retained
// Result counterexample as a separate, nonzero physical group.
const original = [
  {name: 'text Effect-only create and fresh-process recovery', expected: 4,
    pattern: '^Table text Effect-only CTAS through (Local|HTTPS)'},
  {name: 'conflict and uncertain commit', expected: 7,
    pattern: '^Table public (concurrent replace|precommit crash|lost commit reply)'},
  {name: 'sparse structured input', expected: 2,
    pattern: '^Table sparse private input.*\\(json\\)'},
  {name: 'sparse text input', expected: 2,
    pattern: '^Table sparse private input.*\\(aql-text\\)'},
  {name: 'text cleanup retry', expected: 2,
    pattern: '^Table text Effect-only cleanup retry'},
  {name: 'typed input and durable read', expected: 3,
    pattern: '^Table (installed HTTP Host|public (nonempty create and replace|empty create))'},
];
const retained = {name: 'retained Result before filtered Table write', expected: 6,
  pattern: '^Table retained Result before filtered CTAS through (Local|HTTPS) \\((json|sql|aql)\\)$'};

export function tablePublicTestGroups(selection = 'all') {
  assert(['all', 'ctas'].includes(selection), 'Unknown Table public case group');
  return Object.freeze((selection === 'all' ? [...original, retained]
    : [original[0], retained]).map(value => Object.freeze({...value})));
}
