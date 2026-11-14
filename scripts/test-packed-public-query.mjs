// Install outside the checkout, then run B's unchanged public acceptance
// against Embedded Local and HTTP without a MoonBit toolchain at runtime.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, readFile, rename, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readmeQuickstart} from './readme-quickstart.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {packedClientPackage, packedNpmCache, pinnedDuckDBPackage} from './packed-client-packages.mjs';
import {exercisePackedInferSource} from './packed-infer-source-acceptance.mjs';
import {graphPublicHostCases, graphPublicHostPattern} from './fixtures/graph-host-cases.mjs';
import {validatePackedPublicQueryArguments} from './packed-public-query-options.mjs';
import {selectAcceptanceTimeout} from './fixtures/packed-query-transport-owner.mjs';

validatePackedPublicQueryArguments(process.argv.slice(2));
const unionBudgetOnly = process.argv.includes('--union-budget-only');
const ciPart = process.argv.find(argument => argument.startsWith('--ci-part='))?.slice('--ci-part='.length);
const portablePart = /^portable-[123]$/u.test(ciPart ?? '') ? Number(ciPart.at(-1)) : undefined;
const portableExtras = portablePart === undefined || portablePart === 1;
const portableCi = ciPart === 'portable' || portablePart !== undefined;
const portableReceiptPrefixes = portablePart === undefined ? undefined : JSON.parse(await readFile(
  new URL('./fixtures/public-query-portable-parts.json', import.meta.url), 'utf8')).parts[ciPart].receiptPrefixes;
const acceptanceTimeout = selectAcceptanceTimeout(process.env);

const repository = fileURLToPath(new URL('../', import.meta.url));
const scratch = join(repository, '..', '.codex-scratch');
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: repository,
  encoding: 'utf8'});
if (revision.status !== 0) throw new Error('PackedQueryRevisionUnavailable');
await withPackedQueryEvidence({scratch, revision: revision.stdout.trim(),
  githubOutput: process.env.GITHUB_OUTPUT,
  // The finite original-reference fixture keeps its pending/failed close report
  // inside this existing owned evidence scope, including a killed child.
  keepArtifacts: unionBudgetOnly || process.argv.includes('--keep-artifacts')},
async ({root, directory, run: capture, recordTarball}) => {
const environment = {...process.env, npm_config_cache: packedNpmCache(root)};
function run(command, args, cwd = root, env = environment,
  timeout = 240_000) {
  return capture(command, args, {cwd, env, timeout});
}
console.log(`Packed public-query evidence: ${directory}`);
if (!unionBudgetOnly && ciPart !== 'native' && portableExtras) console.log(run(process.execPath, ['--test', 'scripts/analytic-offset-profiles.test.mjs',
  'scripts/distinct-join-order-source-input.test.mjs',
  'scripts/graph-difference-source-input.test.mjs',
  'scripts/graph-relation-join-source-input.test.mjs',
  'scripts/public-query-profiles.test.mjs', 'scripts/packed-query-transports.test.mjs',
  'scripts/graph-argument-check.test.mjs', 'scripts/graph-argument-origin-literals.test.mjs'],
  repository).trimEnd());
const packages = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
for (const name of packages) {
  await packedClientPackage({repository, name, destination: root,
    pack: () => run('npm', ['pack', '--pack-destination', root, '--json'],
      join(repository, 'packages', name))});
  recordTarball(join(root, `actql-${name}-0.0.0-development.tgz`));
}
const quickstart = readmeQuickstart(await readFile(join(repository, 'docs', 'development.md'), 'utf8'));
run('bash', ['-eu', '-c', quickstart.install], root,
  {...environment, ACTQL_PACKED_CLIENT_PACKAGES: root});
if (unionBudgetOnly) {
  // Reuse this exact canonical five-tar install and evidence owner. This branch
  // has no provider, new compiler producer, alternate install or Source rewrite.
  for (const [source, destination] of [
    ['scripts/fixtures/union-budget-source-input.mjs', 'union-budget-source-input.mjs'],
    ['scripts/fixtures/union-budget-public.mjs', 'union-budget-public.mjs'],
    ['scripts/fixtures/record-approval/scoped-fds.fixture.mjs', 'scoped-fds.fixture.mjs'],
  ]) await writeFile(join(root, destination), await readFile(join(repository, source)));
  auditPackedPackages(root, packages);
  const normalEnvironment = {...environment, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`};
  const handoff = join(root, 'union-budget-originals.json');
  for (const phase of ['run', 'saved']) console.log(run(process.execPath,
    ['union-budget-public.mjs', phase, handoff], root, normalEnvironment,
    acceptanceTimeout).trimEnd());
  return;
}
for (const [source, destination] of [
  ['scripts/fixtures/vector-scalar-source-input.mjs', 'vector-scalar-source-input.mjs'],
  ['scripts/fixtures/vector-scalar-installed-source.mjs', 'vector-scalar-installed-source.mjs'],
  ['scripts/fixtures/packed-vector-scalar-source.mjs', 'packed-vector-scalar-source.mjs'],
  ['scripts/fixtures/time-series-primary-source-input.mjs', 'time-series-primary-source-input.mjs'],
  ['scripts/fixtures/carrier-continuation-source-input.mjs', 'carrier-continuation-source-input.mjs'],
  ['scripts/fixtures/temporal-join-source-input.mjs', 'temporal-join-source-input.mjs'],
  ['scripts/fixtures/ranking-fusion-source-input.mjs', 'ranking-fusion-source-input.mjs'],
  ['scripts/fixtures/window-group-source-input.mjs', 'window-group-source-input.mjs'],
  ['scripts/fixtures/sequence-source-input.mjs', 'sequence-source-input.mjs'],
  ['scripts/fixtures/lag-source-input.mjs', 'lag-source-input.mjs'],
  ['scripts/fixtures/row-watermark-source-input.mjs', 'row-watermark-source-input.mjs'],
  ['scripts/fixtures/event-dedupe-source-input.mjs', 'event-dedupe-source-input.mjs'],
  ['scripts/fixtures/pipe-pivot-source-input.mjs', 'pipe-pivot-source-input.mjs'],
  ['scripts/fixtures/match-with-producer-source-input.mjs', 'match-with-producer-source-input.mjs'],
  ['scripts/fixtures/unaliased-column-origin.mjs', 'unaliased-column-origin.mjs'],
  ['scripts/fixtures/graph-argument-check.mjs', 'graph-argument-check.mjs'],
  ['scripts/fixtures/graph-argument-origin-literals.json', 'graph-argument-origin-literals.json'],
  ['scripts/fixtures/countif-distinct-source-input.mjs', 'countif-distinct-source-input.mjs'],
  ['scripts/fixtures/min-max-distinct-source-input.mjs', 'min-max-distinct-source-input.mjs'],
  ['scripts/fixtures/negated-predicate-reuse-source-input.mjs', 'negated-predicate-reuse-source-input.mjs'],
  ['scripts/fixtures/membership-expression-reuse-source-input.mjs', 'membership-expression-reuse-source-input.mjs'],
  ['scripts/fixtures/in-unnest-literal-array-source-input.mjs', 'in-unnest-literal-array-source-input.mjs'],
  ['scripts/fixtures/in-unnest-source-input.mjs', 'in-unnest-source-input.mjs'],
  ['scripts/fixtures/array-literal-source-input.mjs', 'array-literal-source-input.mjs'],
  ['scripts/fixtures/unnest-source-input.mjs', 'unnest-source-input.mjs'],
  ['scripts/fixtures/pipe-unpivot-source-input.mjs', 'pipe-unpivot-source-input.mjs'],
  ['scripts/fixtures/unpivot-multicolumn-source-input.mjs', 'unpivot-multicolumn-source-input.mjs'],
  ['scripts/fixtures/unpivot-row-label-source-input.mjs', 'unpivot-row-label-source-input.mjs'],
  ['scripts/fixtures/from-unpivot-source-input.mjs', 'from-unpivot-source-input.mjs'],
  ['scripts/fixtures/correlated-unnest-source-input.mjs', 'correlated-unnest-source-input.mjs'],
  ['scripts/fixtures/correlated-unnest-star-source-input.mjs', 'correlated-unnest-star-source-input.mjs'],
  ['scripts/fixtures/joined-unnest-star-source-input.mjs', 'joined-unnest-star-source-input.mjs'],
  ['scripts/fixtures/unnest-join-source-input.mjs', 'unnest-join-source-input.mjs'],
  ['scripts/fixtures/unnest-parameter-path-source-input.mjs', 'unnest-parameter-path-source-input.mjs'],
  ['scripts/fixtures/unnest-checked-array-source-input.mjs', 'unnest-checked-array-source-input.mjs'],
  ['scripts/fixtures/named-window-source-input.mjs', 'named-window-source-input.mjs'],
  ['scripts/fixtures/qualify-source-input.mjs', 'qualify-source-input.mjs'],
  ['scripts/fixtures/join-star-source-input.mjs', 'join-star-source-input.mjs'],
  ['scripts/fixtures/pipe-join-input.mjs', 'pipe-join-input.mjs'],
  ['scripts/fixtures/pipe-join-ranges.mjs', 'pipe-join-ranges.mjs'],
  ['scripts/fixtures/right-join-source-input.mjs', 'right-join-source-input.mjs'],
  ['scripts/fixtures/full-join-scope-source-input.mjs', 'full-join-scope-source-input.mjs'],
  ['scripts/fixtures/star-replace-source-input.mjs', 'star-replace-source-input.mjs'],
  ['scripts/fixtures/qualified-star-source-input.mjs', 'qualified-star-source-input.mjs'],
  ['scripts/fixtures/upper-source-input.mjs', 'upper-source-input.mjs'],
  ['scripts/fixtures/abs-source-input.mjs', 'abs-source-input.mjs'],
  ['scripts/fixtures/pipe-distinct-source-input.mjs', 'pipe-distinct-source-input.mjs'],
  ['scripts/fixtures/lower-source-input.mjs', 'lower-source-input.mjs'],
  ['scripts/fixtures/replace-call-source-input.mjs', 'replace-call-source-input.mjs'],
  ['scripts/fixtures/character-length-source-input.mjs', 'character-length-source-input.mjs'],
  ['scripts/fixtures/select-all-source-input.mjs', 'select-all-source-input.mjs'],
  ['scripts/fixtures/star-exclusion-source-input.mjs', 'star-exclusion-source-input.mjs'],
  ['scripts/fixtures/analytic-partition-expression-source-input.mjs', 'analytic-partition-expression-source-input.mjs'],
  ['scripts/fixtures/grouped-rows-boundary-source-input.mjs', 'grouped-rows-boundary-source-input.mjs'],
  ['scripts/fixtures/positive-limit-source-input.mjs', 'positive-limit-source-input.mjs'],
  ['scripts/fixtures/limit-parameter-source-input.mjs', 'limit-parameter-source-input.mjs'],
  ['scripts/fixtures/having-object-property-source-input.mjs', 'having-object-property-source-input.mjs'],
  ['scripts/fixtures/aggregate-member-call-reuse-source-input.mjs', 'aggregate-member-call-reuse-source-input.mjs'],
  ['scripts/fixtures/packed-readme-quickstart.mjs', 'readme-acceptance.mjs'],
  ['scripts/fixtures/public-query-input.mjs', 'public-query-input.mjs'],
  ['scripts/fixtures/cte-value-table-source-input.mjs', 'cte-value-table-source-input.mjs'],
  ['scripts/fixtures/cte-value-table-receipts.mjs', 'cte-value-table-receipts.mjs'],
  ['scripts/fixtures/analytic-frame-parameter-source-input.mjs', 'analytic-frame-parameter-source-input.mjs'],
  ['docs/reviews/fixtures/analytic-frame-parameter.reversed-following.program.json', 'analytic-frame-parameter.reversed-following.program.json'],
  ['docs/reviews/fixtures/analytic-frame-parameter.reversed-preceding.program.json', 'analytic-frame-parameter.reversed-preceding.program.json'],
  ['scripts/fixtures/public-query-cases.mjs', 'public-query-cases.mjs'],
  ['scripts/fixtures/distinct-join-order-source-input.mjs', 'distinct-join-order-source-input.mjs'],
  ['scripts/fixtures/distinct-join-order-inventory.mjs', 'distinct-join-order-inventory.mjs'],
  ['scripts/fixtures/typed-json-literal-input.mjs', 'typed-json-literal-input.mjs'],
  ['scripts/fixtures/public-query-profiles.mjs', 'public-query-profiles.mjs'],
  ['scripts/fixtures/order-aggregate-expression-source-input.mjs', 'order-aggregate-expression-source-input.mjs'],
  ['scripts/fixtures/select-aggregate-expression-source-input.mjs', 'select-aggregate-expression-source-input.mjs'],
  ['scripts/fixtures/having-aggregate-source-input.mjs', 'having-aggregate-source-input.mjs'],
  ['scripts/fixtures/analytic-distinct-frame-source-input.mjs', 'analytic-distinct-frame-source-input.mjs'],
  ['scripts/fixtures/short-rows-source-input.mjs', 'short-rows-source-input.mjs'],
  ['scripts/fixtures/order-window-source-input.mjs', 'order-window-source-input.mjs'],
  ['scripts/fixtures/set-by-name-list-source-input.mjs', 'set-by-name-list-source-input.mjs'],
  ['scripts/fixtures/set-corresponding-source-input.mjs', 'set-corresponding-source-input.mjs'],
  ['scripts/fixtures/set-join-source-input.mjs', 'set-join-source-input.mjs'],
  ['scripts/fixtures/set-inner-by-name-source-input.mjs', 'set-inner-by-name-source-input.mjs'],
  ['scripts/fixtures/window-scalar-source-input.mjs', 'window-scalar-source-input.mjs'],
  ['scripts/fixtures/analytic-countif-source-input.mjs', 'analytic-countif-source-input.mjs'],
  ['scripts/fixtures/distinct-aggregate-order-source-input.mjs', 'distinct-aggregate-order-source-input.mjs'],
  ['scripts/fixtures/distinct-array-reference-key-source-input.mjs', 'distinct-array-reference-key-source-input.mjs'],
  ['scripts/fixtures/distinct-signed-order-source-input.mjs', 'distinct-signed-order-source-input.mjs'],
  ['scripts/fixtures/analytic-string-agg-source-input.mjs', 'analytic-string-agg-source-input.mjs'],
  ['scripts/fixtures/statistical-aggregate-source-input.mjs', 'statistical-aggregate-source-input.mjs'],
  ['scripts/fixtures/graph-subtraction-source-input.mjs', 'graph-subtraction-source-input.mjs'],
  ['scripts/fixtures/graph-union-source-input.mjs', 'graph-union-source-input.mjs'],
  ['scripts/fixtures/graph-graft-source-input.mjs', 'graph-graft-source-input.mjs'],
  ['scripts/fixtures/graph-reach-source-input.mjs', 'graph-reach-source-input.mjs'],
  ['scripts/fixtures/graph-shortest-source-input.mjs', 'graph-shortest-source-input.mjs'],
  ['scripts/fixtures/graph-mean-source-input.mjs', 'graph-mean-source-input.mjs'],
  ['scripts/fixtures/input-stage-result.mjs', 'input-stage-result.mjs'],
  ['scripts/fixtures/typed-subscript-input.mjs', 'typed-subscript-input.mjs'],
  ['scripts/graph-public-failure.test.mjs', 'graph-public-failure.test.mjs'],
  ['scripts/fixtures/graph-remaining-operation-inputs.mjs', 'graph-remaining-operation-inputs.mjs'],
  ['scripts/fixtures/retained-graph-observer.mjs', 'retained-graph-observer.mjs'],
  ['scripts/fixtures/group-order-range-alias-source-input.mjs', 'group-order-range-alias-source-input.mjs'],
  ['scripts/fixtures/group-star-source-input.mjs', 'group-star-source-input.mjs'],
  ['scripts/fixtures/aggregate-property-order-source-input.mjs', 'aggregate-property-order-source-input.mjs'],
  ['scripts/fixtures/aggregate-order-parameter-source-input.mjs', 'aggregate-order-parameter-source-input.mjs'],
  ['scripts/fixtures/aggregate-signed-order-source-input.mjs', 'aggregate-signed-order-source-input.mjs'],
  ['scripts/fixtures/aggregate-conditional-order-source-input.mjs', 'aggregate-conditional-order-source-input.mjs'],
  ['scripts/fixtures/aggregate-property-source-input.mjs', 'aggregate-property-source-input.mjs'],
  ['scripts/fixtures/group-ordinal-source-input.mjs', 'group-ordinal-source-input.mjs'],
  ['scripts/fixtures/scalar-alias-group-source-input.mjs', 'scalar-alias-group-source-input.mjs'],
  ['scripts/fixtures/group-comparison-source-input.mjs', 'group-comparison-source-input.mjs'],
  ['scripts/fixtures/order-ordinal-source-input.mjs', 'order-ordinal-source-input.mjs'],
  ['scripts/fixtures/quoted-identifier-source-input.mjs', 'quoted-identifier-source-input.mjs'],
  ['scripts/fixtures/distinct-order-source-input.mjs', 'distinct-order-source-input.mjs'],
    ['scripts/fixtures/concat-expression-reuse-source-input.mjs', 'concat-expression-reuse-source-input.mjs'],
  ['scripts/fixtures/distinct-order-member-source-input.mjs', 'distinct-order-member-source-input.mjs'],
  ['scripts/fixtures/distinct-order-receiver-source-input.mjs', 'distinct-order-receiver-source-input.mjs'],
  ['scripts/fixtures/sqrt-source-input.mjs', 'sqrt-source-input.mjs'],
  ['scripts/fixtures/ceiling-source-input.mjs', 'ceiling-source-input.mjs'],
  ['scripts/fixtures/unary-plus-source-input.mjs', 'unary-plus-source-input.mjs'],
  ['scripts/fixtures/between-source-input.mjs', 'between-source-input.mjs'],
  ['scripts/fixtures/hex-integer-source-input.mjs', 'hex-integer-source-input.mjs'],
  ['scripts/fixtures/aggregate-filter-source-input.mjs', 'aggregate-filter-source-input.mjs'],
  ['scripts/fixtures/ifnull-source-input.mjs', 'ifnull-source-input.mjs'],
  ['scripts/fixtures/ifnull-coalesce-reuse-source-input.mjs', 'ifnull-coalesce-reuse-source-input.mjs'],
  ['scripts/fixtures/grouped-in-source-input.mjs', 'grouped-in-source-input.mjs'],
  ['scripts/fixtures/order-property-source-input.mjs', 'order-property-source-input.mjs'],
  ['scripts/fixtures/analytic-order-source-input.mjs', 'analytic-order-source-input.mjs'],
  ['scripts/fixtures/analytic-partition-property-source-input.mjs', 'analytic-partition-property-source-input.mjs'],
  ['docs/reviews/fixtures/analytic-order-property-repro.program.json', 'analytic-order-property-repro.program.json'],
  ['scripts/fixtures/join-property-source-input.mjs', 'join-property-source-input.mjs'],
  ['scripts/fixtures/analytic-property-source-input.mjs', 'analytic-property-source-input.mjs'],
  ['scripts/fixtures/group-select-scope-source-input.mjs', 'group-select-scope-source-input.mjs'],
  ['scripts/fixtures/having-projection-source-input.mjs', 'having-projection-source-input.mjs'],
  ['scripts/fixtures/implicit-property-source-input.mjs', 'implicit-property-source-input.mjs'],
  ['scripts/fixtures/computed-object-property-source-input.mjs', 'computed-object-property-source-input.mjs'],
  ['scripts/fixtures/group-property-source-input.mjs', 'group-property-source-input.mjs'],
  ['scripts/fixtures/group-by-all-source-input.mjs', 'group-by-all-source-input.mjs'],
  ['scripts/fixtures/group-property-receiver-source-input.mjs', 'group-property-receiver-source-input.mjs'],
  ['scripts/fixtures/acquired-data-source-input.mjs', 'acquired-data-source-input.mjs'],
  ['scripts/fixtures/graph-source-input.mjs', 'graph-source-input.mjs'],
  ['scripts/fixtures/graph-relation-join-source-input.mjs', 'graph-relation-join-source-input.mjs'],
  ['scripts/fixtures/traversal-join-source-input.mjs', 'traversal-join-source-input.mjs'],
  ['scripts/fixtures/graph-rows-join-source-input.mjs', 'graph-rows-join-source-input.mjs'],
  ['scripts/fixtures/graph-row-source-input.mjs', 'graph-row-source-input.mjs'],
  ['scripts/fixtures/graph-match-source-input.mjs', 'graph-match-source-input.mjs'],
  ['scripts/fixtures/sga-output-name-source.mjs', 'sga-output-name-source.mjs'],
  ['scripts/fixtures/graph-property-predicate-source-input.mjs', 'graph-property-predicate-source-input.mjs'],
  ['scripts/fixtures/graph-hop-node-predicate-source-input.mjs', 'graph-hop-node-predicate-source-input.mjs'],
  ['scripts/fixtures/graph-any-direction-source-input.mjs', 'graph-any-direction-source-input.mjs'],
  ['scripts/fixtures/graph-abbreviated-edge-source-input.mjs', 'graph-abbreviated-edge-source-input.mjs'],
  ['scripts/fixtures/graph-quantifier-forms-source-input.mjs', 'graph-quantifier-forms-source-input.mjs'],
  ['scripts/fixtures/graph-edge-predicate-source-input.mjs', 'graph-edge-predicate-source-input.mjs'],
  ['scripts/fixtures/graph-traverse-source-input.mjs', 'graph-traverse-source-input.mjs'],
  ['scripts/fixtures/graph-traverse-path-source-input.mjs', 'graph-traverse-path-source-input.mjs'],
  ['scripts/fixtures/graph-diagnostics-source-input.mjs', 'graph-diagnostics-source-input.mjs'],
  ['scripts/fixtures/subgraph-source-input.mjs', 'subgraph-source-input.mjs'],
  ['scripts/fixtures/analytic-offset-source-input.mjs', 'analytic-offset-source-input.mjs'],
  ['scripts/fixtures/graph-equality-source-input.mjs', 'graph-equality-source-input.mjs'],
  ['scripts/fixtures/graph-difference-source-input.mjs', 'graph-difference-source-input.mjs'],
  ['scripts/fixtures/graph-projection-property-source-input.mjs', 'graph-projection-property-source-input.mjs'],
  ['scripts/fixtures/source-graph-member-input.mjs', 'source-graph-member-input.mjs'],
  ['scripts/fixtures/string-values-restart.mjs', 'string-values-restart.mjs'],
  ['scripts/fixtures/retained-fixture-values.mjs', 'retained-fixture-values.mjs'],
  ['scripts/fixtures/installed-infer-fixture.mjs', 'installed-infer-fixture.mjs'],
  ['scripts/fixtures/model-provider-binding-fixture.mjs', 'model-provider-binding-fixture.mjs'],
  ['scripts/fixtures/infer-source-expectation.mjs', 'infer-source-expectation.mjs'],
  ['scripts/fixtures/packed-infer-source.mjs', 'packed-infer-source.mjs'],
  ['scripts/fixtures/packed-public-query.mjs', 'acceptance.mjs'],
  ['scripts/fixtures/packed-query-transports.mjs', 'packed-query-transports.mjs'],
  ['scripts/fixtures/public-query-portable-parts.json', 'public-query-portable-parts.json'],
  ['scripts/fixtures/public-query-inventory.json', 'public-query-inventory.json'],
  ['scripts/fixtures/packed-query-worker.mjs', 'packed-query-worker.mjs'],
  ['scripts/fixtures/packed-query-restart-transports.mjs', 'packed-query-restart-transports.mjs'],
  ['scripts/fixtures/packed-query-transport-owner.mjs', 'packed-query-transport-owner.mjs'],
  ['scripts/fixtures/packed-two-source-public-query.mjs', 'packed-two-source-public-query.mjs'],
  ['scripts/fixtures/packed-two-source-example.mjs', 'packed-two-source-example.mjs'],
  ['scripts/fixtures/planner-selection-public-query.mjs', 'planner-selection-public-query.mjs'],
  ['scripts/fixtures/packed-planner-selection.mjs', 'packed-planner-selection.mjs'],
  ['scripts/fixtures/two-source-public-query.mjs', 'two-source-public-query.mjs'],
  ['scripts/fixtures/two-source-restart.mjs', 'two-source-restart.mjs'],
  ['adapters/host-node/fixtures/query-amount-environment.json', 'source-environment.json'],
  ['spec/local-check-environment.json', 'base-environment.json'],
  ['spec/frontend/fixtures/pipe-scope/cases.json', 'pipe-scope-cases.json'],
  ['spec/frontend/fixtures/join-order/cases.json', 'join-order-cases.json'],
  ['spec/frontend/fixtures/join-chain/cases.json', 'join-chain-cases.json'],
  ['spec/frontend/fixtures/group-scope/cases.json', 'group-scope-cases.json'],
  ['spec/frontend/fixtures/data-set-strategy/repro-program.json', 'data-set-strategy-program.json'],
  ['scripts/fixtures/packed-sga-cancellation.mjs', 'sga-cancellation.mjs'],
  ['scripts/graph-public-host.test.mjs', 'graph-public-host.test.mjs'],
  ['scripts/graph-source-snapshot.test.mjs', 'graph-source-snapshot.test.mjs'],
  ['scripts/check-canonical-json.mjs', 'check-canonical-json.mjs'],
  ['docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json', 'local-family-coverage.json'],
]) {
  await writeFile(join(root, destination), await readFile(join(repository, source)));
}
await mkdir(join(root, 'two-source-fixtures'));
for (const name of ['database-rows.json', 'two-source-join.program.json', 'two-source-join.aql',
  'two-source-join.expected.json', 'equal-content-join.expected.json',
  'left-only.program.json', 'left.environment.json', 'right.environment.json']) {
  await writeFile(join(root, 'two-source-fixtures', name), await readFile(join(repository,
    'adapters/host-node/fixtures/two-source', name)));
}
// Copy the exact documented example and its shared JSON fixtures.
const exampleReadme = await readFile(join(repository,
  'examples/two-source-join/README.md'), 'utf8');
const exampleCommands = [...exampleReadme.matchAll(/```bash\n([\s\S]*?)\n```/gu)];
assert.equal(exampleCommands.length, 2);
run('bash', ['-eu', '-c', exampleCommands[0][1]], root,
  {...environment, ACTQL_CHECKOUT: repository});
await mkdir(join(root, 'fixtures'));
for (const path of ['fixtures/graph-host-cases.mjs', 'fixtures/graph-delta-application.mjs',
  'fixtures/graph-snapshot-failure-store.mjs', 'fixtures/retained-graph-observer.mjs',
  'fixtures/input-stage-result.mjs',
  'fixtures/graph-union.mjs', 'fixtures/graph-subtraction.mjs', 'fixtures/graph-reach-source-input.mjs',
  'fixtures/graph-shortest-source-input.mjs', 'fixtures/graph-mean-source-input.mjs',
  'fixtures/graph-graft-source-input.mjs', 'fixtures/graph-union-source-input.mjs']) {
  await writeFile(join(root, path), await readFile(join(repository, 'scripts', path)));
}
await writeFile(join(root, 'fixtures/graph-parallel.program.json'),
  await readFile(join(repository, 'scripts/fixtures/graph-parallel.program.json')));
await writeFile(join(root, 'fixtures/graph-presence.program.json'),
  await readFile(join(repository, 'scripts/fixtures/graph-presence.program.json')));
await writeFile(join(root, 'fixtures/graph-definition-rows.program.json'),
  await readFile(join(repository, 'scripts/fixtures/graph-definition-rows.program.json')));
await writeFile(join(root, 'fixtures/graph-label-rows.program.json'),
  await readFile(join(repository, 'scripts/fixtures/graph-label-rows.program.json')));
await writeFile(join(root, 'fixtures/graph-selector-derive.program.json'),
  await readFile(join(repository, 'scripts/fixtures/graph-selector-derive.program.json')));
await writeFile(join(root, 'fixtures/graph-traverse-nodes.expected.json'),
  await readFile(join(repository, 'scripts/fixtures/graph-traverse-nodes.expected.json')));
run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
auditPackedPackages(root, packages);
run('npm', ['ls', '--omit=dev', '--all']);
await writeFile(join(root, 'query.aql'), quickstart.program);
await writeFile(join(root, 'quickstart.mjs'), quickstart.client);
let runtimeCaPath = join(root, 'remote.crt');
if (environment.NODE_EXTRA_CA_CERTS) {
  runtimeCaPath = join(root, 'remote-ca-bundle.crt');
  await writeFile(runtimeCaPath, Buffer.concat([
    await readFile(resolve(environment.NODE_EXTRA_CA_CERTS)), Buffer.from('\n'),
    await readFile(join(root, 'remote.crt')), Buffer.from('\n'),
  ]));
}
const runtimeEnvironment = {...environment,
  PATH: `${dirname(process.execPath)}:/usr/bin:/bin`,
  NODE_EXTRA_CA_CERTS: runtimeCaPath};
if (process.argv.includes('--distinct-join-order-only')) {
  runtimeEnvironment.ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY = '1';
}
if (process.argv.includes('--time-series-primary-only')) {
  runtimeEnvironment.ACTQL_TEST_TIME_SERIES_PRIMARY_ONLY = '1';
}
if (process.argv.includes('--carrier-continuation-only')) {
  runtimeEnvironment.ACTQL_TEST_CARRIER_CONTINUATION_ONLY = '1';
}
if (process.argv.includes('--countif-distinct-only')) {
  runtimeEnvironment.ACTQL_TEST_COUNTIF_DISTINCT_ONLY = '1';
}
if (process.argv.includes('--analytic-distinct-frame-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_DISTINCT_FRAME_ONLY = '1';
}
if (process.argv.includes('--upper-only')) {
  runtimeEnvironment.ACTQL_TEST_UPPER_ONLY = '1';
}
if (process.argv.includes('--abs-only')) {
  runtimeEnvironment.ACTQL_TEST_ABS_ONLY = '1';
}
if (process.argv.includes('--pipe-distinct-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_DISTINCT_ONLY = '1';
}
if (process.argv.includes('--lower-only')) {
  runtimeEnvironment.ACTQL_TEST_LOWER_ONLY = '1';
}
if (process.argv.includes('--replace-call-only')) {
  runtimeEnvironment.ACTQL_TEST_REPLACE_CALL_ONLY = '1';
}
if (process.argv.includes('--typed-json-literal-only')) {
  runtimeEnvironment.ACTQL_TEST_TYPED_JSON_LITERAL_ONLY = '1';
}
if (process.argv.includes('--having-object-property-only')) {
  runtimeEnvironment.ACTQL_TEST_HAVING_OBJECT_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--sqrt-only')) {
  runtimeEnvironment.ACTQL_TEST_SQRT_ONLY = '1';
}
if (process.argv.includes('--ceiling-only')) {
  runtimeEnvironment.ACTQL_TEST_CEILING_ONLY = '1';
}
if (process.argv.includes('--unary-plus-only')) {
  runtimeEnvironment.ACTQL_TEST_UNARY_PLUS_ONLY = '1';
}
if (process.argv.includes('--graph-source-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_SOURCE_ONLY = '1';
}
if (process.argv.includes('--graph-any-direction-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_ANY_DIRECTION_ONLY = '1';
}
if (process.argv.includes('--graph-abbreviated-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_ABBREVIATED_ONLY = '1';
}
if (process.argv.includes('--graph-quantifier-forms-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_QUANTIFIER_FORMS_ONLY = '1';
}
if (process.argv.includes('--graph-property-predicate-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_PROPERTY_PREDICATE_ONLY = '1';
}
if (process.argv.includes('--grouped-in-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUPED_IN_ONLY = '1';
}
if (process.argv.includes('--concat-expression-reuse-only')) {
  runtimeEnvironment.ACTQL_TEST_CONCAT_REUSE_ONLY = '1';
}
if (process.argv.includes('--distinct-order-receiver-only')) {
  runtimeEnvironment.ACTQL_TEST_DISTINCT_ORDER_RECEIVER_ONLY = '1';
}
if (process.argv.includes('--distinct-order-only')) {
  runtimeEnvironment.ACTQL_TEST_DISTINCT_ORDER_ONLY = '1';
}
if (process.argv.includes('--analytic-frame-parameter-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_FRAME_PARAMETER_ONLY = '1';
}
if (process.argv.includes('--analytic-property-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--source-graph-member-only')) {
  runtimeEnvironment.ACTQL_TEST_SOURCE_GRAPH_MEMBER_ONLY = '1';
}
if (process.argv.includes('--graph-projection-property-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_PROJECTION_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--graph-diagnostics-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_DIAGNOSTICS_ONLY = '1';
}
if (process.argv.includes('--match-with-producer-only')) {
  runtimeEnvironment.ACTQL_TEST_MATCH_WITH_PRODUCER_ONLY = '1';
}
if (process.argv.includes('--graph-match-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_MATCH_ONLY = '1';
}
if (process.argv.includes('--graph-relation-join-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_RELATION_JOIN_ONLY = '1';
}
if (process.argv.includes('--traversal-join-only')) {
  runtimeEnvironment.ACTQL_TEST_TRAVERSAL_JOIN_ONLY = '1';
}
if (process.argv.includes('--graph-rows-join-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_ROWS_JOIN_ONLY = '1';
}
if (process.argv.includes('--graph-rows-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_ROWS_ONLY = '1';
}
if (process.argv.includes('--subgraph-only')) {
  runtimeEnvironment.ACTQL_TEST_SUBGRAPH_ONLY = '1';
}
if (process.argv.includes('--analytic-offset-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_OFFSET_ONLY = '1';
}
if (process.argv.includes('--graph-traverse-paths-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_TRAVERSE_PATHS_ONLY = '1';
}
if (process.argv.includes('--graph-difference-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_DIFFERENCE_ONLY = '1';
}
if (process.argv.includes('--graph-equality-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_EQUALITY_ONLY = '1';
}
if (process.argv.includes('--order-ordinal-only')) {
  runtimeEnvironment.ACTQL_TEST_ORDER_ORDINAL_ONLY = '1';
}
if (process.argv.includes('--quoted-identifiers-only')) {
  runtimeEnvironment.ACTQL_TEST_QUOTED_IDENTIFIERS_ONLY = '1';
}
if (process.argv.includes('--grouped-rows-boundary-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUPED_ROWS_BOUNDARY_ONLY = '1';
}
if (process.argv.includes('--positive-limit-only')) {
  runtimeEnvironment.ACTQL_TEST_POSITIVE_LIMIT_ONLY = '1';
}
if (process.argv.includes('--limit-parameter-only')) {
  runtimeEnvironment.ACTQL_TEST_LIMIT_PARAMETER_ONLY = '1';
}
if (process.argv.includes('--graph-subtraction-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_SUBTRACTION_ONLY = '1';
}
if (process.argv.includes('--graph-union-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_UNION_ONLY = '1';
}
if (process.argv.includes('--graph-graft-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_GRAFT_ONLY = '1';
}
if (process.argv.includes('--graph-reach-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_REACH_ONLY = '1';
}
if (process.argv.includes('--graph-shortest-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_SHORTEST_ONLY = '1';
  // Reuse the existing narrow Graph transport profile and retained rereads.
  runtimeEnvironment.ACTQL_TEST_GRAPH_TRAVERSE_ONLY = '1';
}
if (process.argv.includes('--vector-scalar-only')) {
  runtimeEnvironment.ACTQL_TEST_VECTOR_SCALAR_ONLY = '1';
}
if (process.argv.includes('--window-group-only')) {
  runtimeEnvironment.ACTQL_TEST_WINDOW_GROUP_ONLY = '1';
}
if (process.argv.includes('--sequence-source-only')) {
  runtimeEnvironment.ACTQL_TEST_SEQUENCE_SOURCE_ONLY = '1';
}
if (process.argv.includes('--temporal-join-only')) {
  runtimeEnvironment.ACTQL_TEST_TEMPORAL_JOIN_ONLY = '1';
}
if (process.argv.includes('--ranking-fusion-only')) {
  runtimeEnvironment.ACTQL_TEST_RANKING_FUSION_ONLY = '1';
}
if (process.argv.includes('--lag-only')) {
  runtimeEnvironment.ACTQL_TEST_LAG_ONLY = '1';
}
if (process.argv.includes('--row-watermark-only')) {
  runtimeEnvironment.ACTQL_TEST_ROW_WATERMARK_ONLY = '1';
}
if (process.argv.includes('--event-dedupe-only')) {
  runtimeEnvironment.ACTQL_TEST_EVENT_DEDUPE_ONLY = '1';
}
if (process.argv.includes('--graph-mean-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_MEAN_ONLY = '1';
}
if (process.argv.includes('--input-stage-result-only')) {
  runtimeEnvironment.ACTQL_TEST_INPUT_STAGE_RESULT_ONLY = '1';
}
if (process.argv.includes('--typed-subscript-only')) {
  runtimeEnvironment.ACTQL_TEST_TYPED_SUBSCRIPT_ONLY = '1';
}
if (process.argv.includes('--graph-remaining-operations-only')) {
  runtimeEnvironment.ACTQL_TEST_GRAPH_REMAINING_OPERATIONS_ONLY = '1';
}
if (process.argv.includes('--min-max-distinct-only')) {
  runtimeEnvironment.ACTQL_TEST_MIN_MAX_DISTINCT_ONLY = '1';
}
if (process.argv.includes('--statistical-aggregate-only')) {
  runtimeEnvironment.ACTQL_TEST_STATISTICAL_AGGREGATE_ONLY = '1';
}
if (process.argv.includes('--order-aggregate-expression-only')) {
  runtimeEnvironment.ACTQL_TEST_ORDER_AGGREGATE_EXPRESSION_ONLY = '1';
}
if (process.argv.includes('--select-aggregate-expression-only')) {
  runtimeEnvironment.ACTQL_TEST_SELECT_AGGREGATE_EXPRESSION_ONLY = '1';
}
if (process.argv.includes('--having-aggregate-only')) {
  runtimeEnvironment.ACTQL_TEST_HAVING_AGGREGATE_ONLY = '1';
}
if (process.argv.includes('--set-corresponding-only')) {
  runtimeEnvironment.ACTQL_TEST_SET_CORRESPONDING_ONLY = '1';
}
if (process.argv.includes('--set-inner-by-name-only')) {
  runtimeEnvironment.ACTQL_TEST_SET_INNER_BY_NAME_ONLY = '1';
}
if (process.argv.includes('--set-by-name-list-only')) {
  runtimeEnvironment.ACTQL_TEST_SET_BY_NAME_LIST_ONLY = '1';
}
if (process.argv.includes('--short-rows-only')) {
  runtimeEnvironment.ACTQL_TEST_SHORT_ROWS_ONLY = '1';
}
if (process.argv.includes('--order-window-only')) {
  runtimeEnvironment.ACTQL_TEST_ORDER_WINDOW_ONLY = '1';
}
if (process.argv.includes('--window-scalar-only')) {
  runtimeEnvironment.ACTQL_TEST_WINDOW_SCALAR_ONLY = '1';
}
if (process.argv.includes('--distinct-aggregate-order-only')) {
  runtimeEnvironment.ACTQL_TEST_DISTINCT_AGGREGATE_ORDER_ONLY = '1';
}
if (process.argv.includes('--analytic-string-agg-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_STRING_AGG_ONLY = '1';
}
if (process.argv.includes('--analytic-countif-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_COUNTIF_ONLY = '1';
}
if (process.argv.includes('--negated-predicate-reuse-only')) {
  runtimeEnvironment.ACTQL_TEST_NEGATED_PREDICATE_REUSE_ONLY = '1';
}
if (process.argv.includes('--membership-expression-reuse-only')) {
  runtimeEnvironment.ACTQL_TEST_MEMBERSHIP_REUSE_ONLY = '1';
}
if (process.argv.includes('--in-unnest-literal-array-only')) {
  runtimeEnvironment.ACTQL_TEST_IN_UNNEST_LITERAL_ARRAY_ONLY = '1';
}
if (process.argv.includes('--array-literal-only')) {
  runtimeEnvironment.ACTQL_TEST_ARRAY_LITERAL_ONLY = '1';
}
if (process.argv.includes('--correlated-unnest-only')) {
  runtimeEnvironment.ACTQL_TEST_CORRELATED_UNNEST_ONLY = '1';
}
if (process.argv.includes('--unnest-checked-array-only')) {
  runtimeEnvironment.ACTQL_TEST_UNNEST_CHECKED_ARRAY_ONLY = '1';
}
if (process.argv.includes('--unnest-parameter-path-only')) {
  runtimeEnvironment.ACTQL_TEST_UNNEST_PARAMETER_PATH_ONLY = '1';
}
if (process.argv.includes('--unpivot-multicolumn-only')) {
  runtimeEnvironment.ACTQL_TEST_UNPIVOT_MULTICOLUMN_ONLY = '1';
}
if (process.argv.includes('--unpivot-row-label-only')) {
  runtimeEnvironment.ACTQL_TEST_UNPIVOT_ROW_LABEL_ONLY = '1';
}
if (process.argv.includes('--from-unpivot-only')) {
  runtimeEnvironment.ACTQL_TEST_FROM_UNPIVOT_ONLY = '1';
}
if (process.argv.includes('--pipe-unpivot-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_UNPIVOT_ONLY = '1';
}
if (process.argv.includes('--unnest-source-only')) {
  runtimeEnvironment.ACTQL_TEST_UNNEST_SOURCE_ONLY = '1';
}
if (process.argv.includes('--source-free-only')) {
  runtimeEnvironment.ACTQL_TEST_SOURCE_FREE_ONLY = '1';
}
if (process.argv.includes('--data-set-strategy-only')) {
  runtimeEnvironment.ACTQL_TEST_DATA_SET_STRATEGY_ONLY = '1';
}
if (process.argv.includes('--cte-value-table-only')) {
  runtimeEnvironment.ACTQL_TEST_CTE_VALUE_TABLE_ONLY = '1';
}
if (process.argv.includes('--query-composition-only')) {
  runtimeEnvironment.ACTQL_TEST_QUERY_COMPOSITION_ONLY = '1';
}
if (process.argv.includes('--pipe-result-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_RESULT_ONLY = '1';
}
if (process.argv.includes('--relation-data-only')) {
  runtimeEnvironment.ACTQL_TEST_RELATION_DATA_ONLY = '1';
}
if (process.argv.includes('--acquired-data-only')) {
  runtimeEnvironment.ACTQL_TEST_ACQUIRED_DATA_ONLY = '1';
}
if (process.argv.includes('--join-order-only')) {
  runtimeEnvironment.ACTQL_TEST_JOIN_ORDER_ONLY = '1';
}
if (process.argv.includes('--group-ordinal-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_ORDINAL_ONLY = '1';
}
if (process.argv.includes('--group-order-range-alias-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_ORDER_RANGE_ALIAS_ONLY = '1';
}
if (process.argv.includes('--order-grouped-subexpression-only')) {
  runtimeEnvironment.ACTQL_TEST_ORDER_GROUPED_SUBEXPRESSION_ONLY = '1';
}
if (process.argv.includes('--group-having-implicit-aliases-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_HAVING_IMPLICIT_ALIASES_ONLY = '1';
}
if (process.argv.includes('--grouped-implicit-property-names-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUPED_IMPLICIT_PROPERTY_NAMES_ONLY = '1';
}
if (process.argv.includes('--having-grouped-subexpression-only')) {
  runtimeEnvironment.ACTQL_TEST_HAVING_GROUPED_SUBEXPRESSION_ONLY = '1';
}
if (process.argv.includes('--sql-grouped-subexpression-only')) {
  runtimeEnvironment.ACTQL_TEST_SQL_GROUPED_SUBEXPRESSION_ONLY = '1';
}
if (process.argv.includes('--pipe-aggregate-expression-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_AGGREGATE_EXPRESSION_ONLY = '1';
}
if (process.argv.includes('--pipe-aggregate-order-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_AGGREGATE_ORDER_ONLY = '1';
}
if (process.argv.includes('--group-by-all-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_BY_ALL_ONLY = '1';
}
if (process.argv.includes('--group-property-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--group-star-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_STAR_ONLY = '1';
}
if (process.argv.includes('--aggregate-property-order-only')) {
  runtimeEnvironment.ACTQL_TEST_AGGREGATE_PROPERTY_ORDER_ONLY = '1';
}
if (process.argv.includes('--aggregate-property-only')) {
  runtimeEnvironment.ACTQL_TEST_AGGREGATE_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--group-scope-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_SCOPE_ONLY = '1';
}
if (process.argv.includes('--analytic-profiles-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_PROFILES_ONLY = '1';
}
if (process.argv.includes('--star-exclusion-only')) {
  runtimeEnvironment.ACTQL_TEST_STAR_EXCLUSION_ONLY = '1';
}
if (process.argv.includes('--qualified-star-only')) {
  runtimeEnvironment.ACTQL_TEST_QUALIFIED_STAR_ONLY = '1';
}
if (process.argv.includes('--full-join-scope-only')) {
  runtimeEnvironment.ACTQL_TEST_FULL_JOIN_SCOPE_ONLY = '1';
}
if (process.argv.includes('--right-join-only')) {
  runtimeEnvironment.ACTQL_TEST_RIGHT_JOIN_ONLY = '1';
}
if (process.argv.includes('--pipe-join-ranges-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_JOIN_RANGES_ONLY = '1';
}
if (process.argv.includes('--pipe-join-input-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_JOIN_INPUT_ONLY = '1';
}
if (process.argv.includes('--join-star-only')) {
  runtimeEnvironment.ACTQL_TEST_JOIN_STAR_ONLY = '1';
}
if (process.argv.includes('--star-replace-only')) {
  runtimeEnvironment.ACTQL_TEST_STAR_REPLACE_ONLY = '1';
}
if (process.argv.includes('--qualify-only')) {
  runtimeEnvironment.ACTQL_TEST_QUALIFY_ONLY = '1';
}
if (process.argv.includes('--named-window-only')) {
  runtimeEnvironment.ACTQL_TEST_NAMED_WINDOW_ONLY = '1';
}
if (process.argv.includes('--select-all-only')) {
  runtimeEnvironment.ACTQL_TEST_SELECT_ALL_ONLY = '1';
}
if (process.argv.includes('--character-length-only')) {
  runtimeEnvironment.ACTQL_TEST_CHARACTER_LENGTH_ONLY = '1';
}
if (process.argv.includes('--analytic-partition-expression-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_PARTITION_EXPRESSION_ONLY = '1';
}
if (process.argv.includes('--analytic-partition-property-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_PARTITION_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--analytic-order-only')) {
  runtimeEnvironment.ACTQL_TEST_ANALYTIC_ORDER_ONLY = '1';
}
if (process.argv.includes('--join-property-only')) {
  runtimeEnvironment.ACTQL_TEST_JOIN_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--order-property-only')) {
  runtimeEnvironment.ACTQL_TEST_ORDER_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--group-select-scope-only')) {
  runtimeEnvironment.ACTQL_TEST_GROUP_SELECT_SCOPE_ONLY = '1';
}
if (process.argv.includes('--implicit-property-only')) {
  runtimeEnvironment.ACTQL_TEST_IMPLICIT_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--computed-object-property-only')) {
  runtimeEnvironment.ACTQL_TEST_COMPUTED_OBJECT_PROPERTY_ONLY = '1';
}
if (process.argv.includes('--having-projection-only')) {
  runtimeEnvironment.ACTQL_TEST_HAVING_PROJECTION_ONLY = '1';
}
if (process.argv.includes('--pipe-pivot-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_PIVOT_ONLY = '1';
}
if (process.argv.includes('--between-only')) {
  runtimeEnvironment.ACTQL_TEST_BETWEEN_ONLY = '1';
}
if (process.argv.includes('--ifnull-coalesce-reuse-only')) {
  runtimeEnvironment.ACTQL_TEST_IFNULL_COALESCE_REUSE_ONLY = '1';
}
if (process.argv.includes('--hex-integer-only')) {
  runtimeEnvironment.ACTQL_TEST_HEX_INTEGER_ONLY = '1';
}
if (process.argv.includes('--aggregate-filter-only')) {
  runtimeEnvironment.ACTQL_TEST_AGGREGATE_FILTER_ONLY = '1';
}
if (process.argv.includes('--ifnull-only')) {
  runtimeEnvironment.ACTQL_TEST_IFNULL_ONLY = '1';
}
if (process.argv.includes('--alias-scope-only')) {
  runtimeEnvironment.ACTQL_TEST_PIPE_SCOPE_ONLY = '1';
}
if (process.argv.includes('--scoped-order-only')) {
  runtimeEnvironment.ACTQL_TEST_SCOPED_ORDER_ONLY = '1';
}
if (process.argv.includes('--infer-refusal-only')) {
  runtimeEnvironment.ACTQL_TEST_INFER_REFUSAL_ONLY = '1';
}
if (process.argv.includes('--two-source-only')) {
  runtimeEnvironment.ACTQL_TEST_TWO_SOURCE_ONLY = '1';
}
for (const name of ['NODE_PATH', 'MOON_HOME', 'ACTQL_LOCAL_SOURCE_PROFILE',
  'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) {
  delete runtimeEnvironment[name];
}
const exerciseInferSource = () => exercisePackedInferSource({root, directory,
  run, environment: runtimeEnvironment, sourceSha: revision.stdout.trim(),
  inputFieldsOnly: process.argv.includes('--infer-input-fields-only')});
if (process.argv.includes('--infer-source-only') ||
  process.argv.includes('--infer-input-fields-only')) {
  await exerciseInferSource();
  return;
}
// Execute the README's literal runtime commands, then the same Program through
// the existing public Client acceptance helper on HTTPS. No second pack/build.
// These obligations belong to the portable CI part; Native has its own complete
// public campaign below and must not repeat the portable cases.
if (ciPart !== 'native' && portableExtras) {
console.log(run('bash', ['-eu', '-c', quickstart.run], root, runtimeEnvironment).trimEnd());
assert.equal(await readFile(join(root, 'answer.jsonl'), 'utf8'), quickstart.expected);
console.log(run(process.execPath, ['readme-acceptance.mjs'], root,
  runtimeEnvironment).trimEnd());
// A fresh process must fail for a real missing generated wire asset; module
// caches and the checkout's dependency graph must not rescue this install.
// The Node facade loads the SDK lazily. Select the wire owner itself rather
// than requiring an unrelated import to eagerly load the transport graph.
const asset = join(root, 'node_modules/@actql/client-wire/publication.generated.js');
await rename(asset, asset + '.omitted');
try {
  const negative = spawnSync(process.execPath, ['--input-type=module', '-e',
    "await import('@actql/client-wire')"], {cwd: root, env: runtimeEnvironment,
    encoding: 'utf8', timeout: 30_000});
  await writeFile(join(directory, 'missing-generated-asset.json'), JSON.stringify({
    status: negative.status, signal: negative.signal, stderr: negative.stderr,
    error: negative.error?.code ?? null}, null, 2) + '\n');
  assert.equal(negative.error, undefined);
  assert.notEqual(negative.status, 0, 'Missing packaged asset must fail at runtime');
  assert.match(negative.stderr, /ERR_MODULE_NOT_FOUND/u);
  assert.match(negative.stderr, /publication\.generated\.js/u);
  console.log('Packed missing generated asset: child failed as expected');
} finally { await rename(asset + '.omitted', asset); }
}
async function exerciseNativeGraphSource(sourceOnly = false) {
  const compiler = environment.ACTQL_TEST_NATIVE_QUERY_COMPILER;
  if (compiler !== undefined && (compiler !== 'clang-19' || process.platform !== 'linux')) {
    throw new Error('PackedQueryNativeCompilerSelectionInvalid');
  }
  if (compiler !== undefined && !/\bclang version 19(?:\.|\s)/u.test(
    run('cc', ['--version'], repository, environment, 10_000))) {
    throw new Error('PackedQueryNativeCompilerMismatch');
  }
  // Selected Linux CI uses the normal Linux producer's compiler and 1800s
  // serial compilation budget. Unselected developer builds retain their route.
  run('moon', ['build', '--target', 'native', '--release',
    ...(compiler === undefined ? [] : ['-j', '1']), 'src/cmd/native_client'],
  repository, environment, compiler === undefined ? 900_000 : 1_800_000);
  const nativeClient = join(repository, '_build/native/release/build/cmd',
    'native_client/native_client.exe');
  console.log(run(process.execPath,
    [join(repository, 'scripts/test-native-sga-public-source.mjs'),
      root, nativeClient, directory, ...(sourceOnly ? ['--authored-source-only'] : [])],
    root, runtimeEnvironment).trimEnd());
}
async function installDuckDB() {
  // Keep the README's source-free run independent of this optional transport.
  // Repeat the tarballs so npm does not prune the earlier --no-save install.
  run('npm', ['install', '--ignore-scripts', '--no-save',
    ...packages.map(name => join(root, `actql-${name}-0.0.0-development.tgz`)),
    await pinnedDuckDBPackage(repository)]);
  auditPackedPackages(root, packages);
  run('npm', ['ls', '--omit=dev', '--all']);
}
if (process.argv.includes('--graph-native-only') || ciPart === 'native') {
  await installDuckDB();
  if (ciPart === 'native') console.log(run(process.execPath,
    ['acceptance.mjs', '--prepare-native-graph-fixture'], root, runtimeEnvironment).trimEnd());
  // The CI split retains the complete original Native campaign, including its
  // source-free control. The developer's authored-only selector is unchanged.
  await exerciseNativeGraphSource(ciPart !== 'native');
  return;
}
if (process.argv.includes('--quickstart-only')) return;
if (process.argv.includes('--cancellation-only')) {
  console.log(run(process.execPath, ['sga-cancellation.mjs'], root,
    runtimeEnvironment, 120000).trimEnd());
  return;
}
await installDuckDB();
const twoSourceExampleOnly = process.argv.includes('--two-source-example-only');
const plannerSelectionOnly = process.argv.includes('--planner-selection-only');
const narrowPublicQuery = process.argv.some(flag => ['--vector-scalar-only', '--window-group-only', '--sequence-source-only', '--ranking-fusion-only', '--temporal-join-only', '--time-series-primary-only', '--carrier-continuation-only', '--lag-only', '--event-dedupe-only', '--row-watermark-only', '--aggregate-filter-only', '--grouped-rows-boundary-only', '--positive-limit-only', '--hex-integer-only', '--unpivot-multicolumn-only', '--unpivot-row-label-only', '--from-unpivot-only', '--pipe-pivot-only', '--pipe-unpivot-only', '--graph-relation-join-only', '--traversal-join-only', '--graph-rows-join-only', '--between-only', '--ifnull-coalesce-reuse-only', '--negated-predicate-reuse-only', '--abs-only', '--distinct-aggregate-order-only', '--analytic-distinct-frame-only', '--countif-distinct-only', '--min-max-distinct-only', '--pipe-distinct-only', '--set-corresponding-only', '--set-inner-by-name-only', '--set-by-name-list-only', '--lower-only', '--short-rows-only', '--order-window-only', '--upper-only', '--window-scalar-only', '--analytic-string-agg-only', '--sqrt-only', '--unnest-checked-array-only', '--correlated-unnest-only', '--in-unnest-literal-array-only', '--membership-expression-reuse-only', '--array-literal-only', '--unnest-source-only', '--unnest-parameter-path-only', '--ceiling-only', '--unary-plus-only', '--replace-call-only', '--character-length-only', '--select-all-only', '--star-exclusion-only', '--typed-json-literal-only', '--analytic-partition-expression-only', '--graph-subtraction-only', '--graph-graft-only', '--graph-union-only', '--statistical-aggregate-only', '--limit-parameter-only', '--ifnull-only', '--having-object-property-only', '--analytic-partition-property-only', '--analytic-countif-only', '--analytic-frame-parameter-only', '--grouped-in-only', '--analytic-profiles-only', '--analytic-order-only', '--source-free-only',
  '--qualified-star-only',
  '--distinct-join-order-only',
  '--right-join-only',
  '--full-join-scope-only',
  '--join-star-only',
  '--pipe-join-input-only', '--pipe-join-ranges-only',
  '--star-replace-only',
  '--qualify-only',
  '--named-window-only',
  '--analytic-offset-only',
  '--join-property-only', '--aggregate-property-order-only', '--aggregate-property-only', '--analytic-property-only', '--match-with-producer-only', '--graph-match-only',
  '--graph-diagnostics-only',
  '--graph-reach-only',
  '--graph-shortest-only',
  '--graph-mean-only',
  '--input-stage-result-only',
  '--typed-subscript-only',
  '--graph-remaining-operations-only',
  '--graph-projection-property-only',
  '--source-graph-member-only',
  '--graph-property-predicate-only',
  '--graph-any-direction-only',
  '--graph-abbreviated-only',
  '--graph-quantifier-forms-only',
  '--group-order-range-alias-only', '--distinct-order-receiver-only', '--group-by-all-only', '--group-property-only', '--pipe-aggregate-order-only', '--pipe-aggregate-expression-only', '--sql-grouped-subexpression-only', '--having-grouped-subexpression-only', '--order-grouped-subexpression-only', '--grouped-implicit-property-names-only', '--group-having-implicit-aliases-only',
  '--quoted-identifiers-only', '--order-property-only', '--order-ordinal-only', '--distinct-order-only', '--concat-expression-reuse-only', '--cte-value-table-only', '--query-composition-only', '--pipe-result-only', '--join-order-only', '--group-scope-only', '--group-select-scope-only', '--having-projection-only', '--implicit-property-only', '--computed-object-property-only', '--group-star-only', '--group-ordinal-only',
  '--alias-scope-only', '--scoped-order-only', '--infer-refusal-only', '--two-source-only',
  '--relation-data-only', '--acquired-data-only',
  '--data-set-strategy-only', '--graph-source-only', '--graph-rows-only', '--subgraph-only', '--graph-equality-only', '--graph-difference-only', '--graph-traverse-paths-only'].includes(flag));
async function retainTransportReports(names, succeeded, primary, indexName) {
  const availability = [];
  let evidenceFailure;
  const failed = (name, error) => {
    if (primary === undefined) evidenceFailure ??= error;
    else (primary.transportEvidenceErrors ??= []).push({name, code: error.code});
  };
  for (const name of names) {
    try {
      await writeFile(join(directory, name), await readFile(join(root, name)));
      availability.push({name, available: true});
    } catch (error) {
      if (error.code !== 'ENOENT' || succeeded) failed(name, error);
      availability.push({name, available: false, error: error.code});
    }
  }
  try {
    await writeFile(join(directory, indexName), JSON.stringify({succeeded, availability}, null, 2) + '\n');
  } catch (error) { failed(indexName, error); }
  if (evidenceFailure !== undefined) throw evidenceFailure;
}
const graphArgumentChecksSelected = portableExtras && (runtimeEnvironment.ACTQL_TEST_GRAPH_DIAGNOSTICS_ONLY === '1' ||
  !process.argv.some(flag => flag.endsWith('-only')));
let acceptanceStarted = false, acceptanceSucceeded = false, packedFailure;
try {
  if (!plannerSelectionOnly && !twoSourceExampleOnly) {
    acceptanceStarted = true;
    const acceptanceDeadline = Date.now() + acceptanceTimeout;
    const output = run(process.execPath, ['packed-query-transports.mjs'], root,
      {...runtimeEnvironment, ...(portablePart === undefined ? {} : {ACTQL_TEST_QUERY_CI_PART: ciPart}), ACTQL_TEST_QUERY_TIMEOUT_MS: String(acceptanceTimeout),
        ACTQL_TEST_QUERY_DEADLINE: String(acceptanceDeadline),
        ACTQL_TEST_QUERY_EXPECT_FULL_CORPUS: process.argv.some(flag => flag.endsWith('-only')) ? '0' : '1'}, acceptanceTimeout);
    acceptanceSucceeded = true;
    console.log(output.trimEnd());
    // Reuse this exact installation and its producer artifact. Source INFER
    // is a separate authored corpus; narrow non-INFER selections stay narrow.
    if (portableExtras && !process.argv.some(flag => flag.endsWith('-only'))) await exerciseInferSource();
  }
  // The same packed installation executes this bounded candidate corpus once.
  // Cost inputs go to the Host profile; the public Program never chooses a route.
  if (portableExtras && (plannerSelectionOnly || !narrowPublicQuery && !twoSourceExampleOnly)) {
    console.log(run(process.execPath, ['packed-planner-selection.mjs'], root,
      runtimeEnvironment, 180_000).trimEnd());
  }
  if (portableExtras && (twoSourceExampleOnly || !plannerSelectionOnly && !narrowPublicQuery)) {
    console.log(run(process.execPath, ['packed-two-source-example.mjs'], root,
      runtimeEnvironment, 180_000).trimEnd());
  }
} catch (error) {
  packedFailure = error;
  throw error;
} finally {
  if (acceptanceStarted) {
    const reports = ['transport-processes.json',
      ...(graphArgumentChecksSelected
        ? ['graph-argument-check.local.json', 'graph-argument-check.remote.json'] : []),
      ...(process.argv.includes('--vector-scalar-only')
        ? ['vector-scalar-receipts.local.json', 'vector-scalar-receipts.remote.json'] : []),
      ...((process.argv.includes('--window-group-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['window-group-receipts.local.json', 'window-group-receipts.remote.json'] : []),
      ...((process.argv.includes('--sequence-source-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['sequence-source-receipts.local.json', 'sequence-source-receipts.remote.json'] : []),
      ...((process.argv.includes('--temporal-join-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['temporal-join-receipts.local.json', 'temporal-join-receipts.remote.json'] : []),
      ...((process.argv.includes('--time-series-primary-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['time-series-primary-receipts.local.json', 'time-series-primary-receipts.remote.json'] : []),
      ...((process.argv.includes('--ranking-fusion-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['ranking-fusion-receipts.local.json', 'ranking-fusion-receipts.remote.json'] : []),
      ...((process.argv.includes('--quoted-identifiers-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['quoted-identifier-receipts.local.json', 'quoted-identifier-receipts.remote.json'] : []),
      ...((process.argv.includes('--carrier-continuation-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['carrier-continuation-receipts.local.json', 'carrier-continuation-receipts.remote.json'] : []),
      ...(process.argv.includes('--two-source-only') ? [] :
        ['transport-completion.local.json', 'transport-completion.remote.json']),
      ...((process.argv.includes('--lag-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['lag-receipts.local.json', 'lag-receipts.remote.json'] : []),
      ...((process.argv.includes('--cte-value-table-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['cte-value-table-receipts.local.json', 'cte-value-table-receipts.remote.json'] : []),
      ...((process.argv.includes('--from-unpivot-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['from-unpivot-receipts.local.json', 'from-unpivot-receipts.remote.json'] : []),
      ...((process.argv.includes('--unpivot-multicolumn-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['unpivot-multicolumn-receipts.local.json', 'unpivot-multicolumn-receipts.remote.json'] : []),
      ...((process.argv.includes('--unpivot-row-label-only') ||
        (!narrowPublicQuery && !twoSourceExampleOnly && !plannerSelectionOnly))
        ? ['unpivot-row-label-receipts.local.json', 'unpivot-row-label-receipts.remote.json'] : [])];
    await retainTransportReports(reports.filter(name => portableReceiptPrefixes === undefined ||
      !name.includes('-receipts.') || portableReceiptPrefixes.some(prefix => name.startsWith(prefix + '-receipts.'))),
    acceptanceSucceeded, packedFailure, 'transport-evidence-index.json');
  }
  try {
    await writeFile(join(directory, 'two-source-example.json'),
      await readFile(join(root, 'two-source-example-report.json')));
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  // Preserve two-source observations beside existing command/tarball evidence
  // before the harness removes its installed consumer, including on failure.
  try {
    await writeFile(join(directory, 'two-source-acceptance.json'),
      await readFile(join(root, 'two-source-packed-report.json')));
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  try {
    await writeFile(join(directory, 'planner-selection-acceptance.json'),
      await readFile(join(root, 'planner-selection-packed-report.json')));
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
async function exerciseRetainedQueryRestart(extraEnvironment = {}) {
  let succeeded = false, primary;
  try {
    console.log(run(process.execPath, ['packed-query-restart-transports.mjs'], root,
      {...runtimeEnvironment, ...extraEnvironment,
        ...(portablePart !== undefined && portablePart !== 1 ? {ACTQL_TEST_RETAINED_COHORT_ONLY: '1'} : {}),
        ACTQL_TEST_QUERY_RESTART_DEADLINE: String(Date.now() + 120_000)}, 120_000).trimEnd());
    succeeded = true;
  } catch (error) { primary = error; throw error; }
  finally {
    await retainTransportReports(['transport-restart-processes.json',
      'transport-restart.local.json', 'transport-restart.remote.json'],
    succeeded, primary, 'transport-restart-evidence-index.json');
  }
}
if (process.argv.includes('--time-series-primary-only') ||
    process.argv.includes('--carrier-continuation-only') ||
    process.argv.includes('--graph-graft-only') || process.argv.includes('--graph-reach-only') ||
    process.argv.includes('--input-stage-result-only') ||
    process.argv.includes('--typed-subscript-only') ||
    process.argv.includes('--graph-mean-only') ||
    process.argv.includes('--graph-remaining-operations-only') ||
    process.argv.includes('--graph-shortest-only')) {
  // The Local and HTTPS producers have exited. Read the original retained
  // selected Results in new processes; no String fixture was selected.
  await exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'});
  if (process.argv.includes('--input-stage-result-only')) {
    await mkdir(join(root, 'tls'));
    await writeFile(join(root, 'tls/site.key'), await readFile(join(root, 'remote.key')));
    await writeFile(join(root, 'tls/site.crt'), await readFile(join(root, 'remote.crt')));
    await writeFile(join(root, 'tls/ca.crt'), await readFile(join(root, 'remote.crt')));
    // Reuse the existing real-Store failure harness, not a second custody owner.
    console.log(run(process.execPath, ['--test', 'graph-public-failure.test.mjs'], root,
      {...runtimeEnvironment, ACTQL_GRAPH_PACKED: '1', ACTQL_TEST_INPUT_STAGE_RESULT_ONLY: '1'},
      180000).trimEnd());
  }
  return;
}
if (process.argv.includes('--vector-scalar-only')) return;
if (process.argv.includes('--distinct-join-order-only')) return;
if (process.argv.includes('--window-group-only')) return;
if (process.argv.includes('--sequence-source-only')) return;
if (process.argv.includes('--temporal-join-only')) return;
if (process.argv.includes('--ranking-fusion-only')) return;
if (process.argv.includes('--lag-only')) return;
if (process.argv.includes('--row-watermark-only')) return;
if (process.argv.includes('--event-dedupe-only')) return;
if (process.argv.includes('--grouped-rows-boundary-only')) return;
if (process.argv.includes('--positive-limit-only')) return;
if (process.argv.includes('--source-graph-member-only')) return;
if (process.argv.includes('--negated-predicate-reuse-only')) return;
if (process.argv.includes('--membership-expression-reuse-only')) return;
if (process.argv.includes('--in-unnest-literal-array-only')) return;
if (process.argv.includes('--array-literal-only')) return;
if (process.argv.includes('--correlated-unnest-only')) return;
if (process.argv.includes('--unpivot-multicolumn-only')) return;
if (process.argv.includes('--unpivot-row-label-only')) return;
if (process.argv.includes('--from-unpivot-only')) return;
if (process.argv.includes('--pipe-unpivot-only')) return;
if (process.argv.includes('--unnest-source-only')) return;
if (process.argv.includes('--unnest-checked-array-only')) return;
if (process.argv.includes('--unnest-parameter-path-only')) return;
if (process.argv.includes('--sqrt-only')) return;
if (process.argv.includes('--ceiling-only')) return;
if (process.argv.includes('--upper-only')) return;
if (process.argv.includes('--abs-only')) return;
if (process.argv.includes('--pipe-distinct-only')) return;
if (process.argv.includes('--lower-only')) return;
if (process.argv.includes('--unary-plus-only')) return;
if (process.argv.includes('--qualified-star-only')) return;
if (process.argv.includes('--right-join-only')) return;
if (process.argv.includes('--full-join-scope-only')) return;
if (process.argv.includes('--join-star-only')) return;
if (process.argv.includes('--pipe-join-input-only')) return;
if (process.argv.includes('--pipe-join-ranges-only')) return;
if (process.argv.includes('--star-replace-only')) return;
if (process.argv.includes('--qualify-only')) return;
if (process.argv.includes('--named-window-only')) return;
if (process.argv.includes('--group-order-range-alias-only')) return;
if (process.argv.includes('--distinct-order-receiver-only')) return;
if (process.argv.includes('--group-by-all-only')) return;
if (process.argv.includes('--having-object-property-only')) return;
if (process.argv.includes('--min-max-distinct-only')) return;
if (process.argv.includes('--graph-relation-join-only')) return;
if (process.argv.includes('--traversal-join-only')) return;
if (process.argv.includes('--graph-rows-join-only')) return;
if (process.argv.includes('--pipe-pivot-only')) return;
if (process.argv.includes('--between-only')) return;
if (process.argv.includes('--countif-distinct-only')) return;
if (process.argv.includes('--select-all-only')) return;
if (plannerSelectionOnly || twoSourceExampleOnly || process.argv.includes('--distinct-aggregate-order-only') || process.argv.includes('--analytic-distinct-frame-only') || process.argv.includes('--set-corresponding-only') || process.argv.includes('--set-inner-by-name-only') || process.argv.includes('--set-by-name-list-only') || process.argv.includes('--short-rows-only') || process.argv.includes('--order-window-only') || process.argv.includes('--window-scalar-only') || process.argv.includes('--analytic-string-agg-only') || process.argv.includes('--order-aggregate-expression-only') || process.argv.includes('--select-aggregate-expression-only') || process.argv.includes('--having-aggregate-only') || process.argv.includes('--replace-call-only') || process.argv.includes('--character-length-only') || process.argv.includes('--select-all-only') || process.argv.includes('--star-exclusion-only') || process.argv.includes('--analytic-partition-expression-only') || process.argv.includes('--graph-subtraction-only') || process.argv.includes('--graph-graft-only') || process.argv.includes('--graph-union-only') || process.argv.includes('--statistical-aggregate-only') || process.argv.includes('--analytic-countif-only') ||
    process.argv.includes('--grouped-in-only') || process.argv.includes('--ifnull-coalesce-reuse-only') || process.argv.includes('--ifnull-only') || process.argv.includes('--hex-integer-only') || process.argv.includes('--aggregate-filter-only')) return;
// The first Host process has exited: no live Local installation still owns
// its Store. Restore retained Results in a new process without resubmission.
// Narrow selections without the String fixture have no retained String Run.
// Keep restart acceptance for full/source-free selections that create it.
if (!process.argv.some(flag => ['--select-all-only', '--typed-json-literal-only', '--limit-parameter-only', '--analytic-frame-parameter-only', '--analytic-profiles-only', '--analytic-order-only', '--analytic-partition-property-only', '--join-property-only', '--aggregate-property-order-only', '--aggregate-property-only', '--analytic-property-only', '--quoted-identifiers-only', '--alias-scope-only', '--scoped-order-only', '--infer-refusal-only',
  '--analytic-offset-only',
  '--match-with-producer-only',
  '--graph-match-only',
  '--graph-diagnostics-only',
  '--graph-projection-property-only',
  '--graph-property-predicate-only',
  '--graph-any-direction-only',
  '--graph-abbreviated-only',
  '--graph-quantifier-forms-only',
  '--group-order-range-alias-only', '--distinct-order-receiver-only', '--group-by-all-only', '--group-property-only', '--pipe-aggregate-order-only', '--pipe-aggregate-expression-only', '--sql-grouped-subexpression-only', '--having-grouped-subexpression-only', '--order-grouped-subexpression-only', '--grouped-implicit-property-names-only', '--group-having-implicit-aliases-only',
  '--order-property-only', '--order-ordinal-only', '--join-order-only', '--group-scope-only', '--group-select-scope-only', '--having-projection-only', '--implicit-property-only', '--computed-object-property-only', '--group-star-only', '--group-ordinal-only', '--distinct-order-only', '--concat-expression-reuse-only', '--cte-value-table-only', '--query-composition-only', '--pipe-result-only',
  '--relation-data-only', '--acquired-data-only', '--data-set-strategy-only', '--two-source-only',
  '--graph-source-only', '--graph-rows-only', '--subgraph-only', '--graph-equality-only', '--graph-difference-only', '--graph-traverse-paths-only'].includes(flag))) {
  await exerciseRetainedQueryRestart();
}
if (process.argv.includes('--select-all-only') || process.argv.includes('--typed-json-literal-only') || process.argv.includes('--limit-parameter-only') || process.argv.includes('--analytic-frame-parameter-only') ||
    process.argv.includes('--analytic-profiles-only') ||
    process.argv.includes('--analytic-order-only') ||
    process.argv.includes('--analytic-partition-property-only') ||
    process.argv.includes('--order-ordinal-only') ||
    process.argv.includes('--analytic-offset-only') ||
    process.argv.includes('--subgraph-only') ||
    process.argv.includes('--match-with-producer-only') ||
    process.argv.includes('--graph-match-only') ||
    process.argv.includes('--join-property-only') ||
    process.argv.includes('--graph-diagnostics-only') ||
    process.argv.includes('--analytic-property-only') ||
    process.argv.includes('--quoted-identifiers-only') ||
    process.argv.includes('--order-property-only') ||
    process.argv.includes('--graph-projection-property-only') ||
    process.argv.includes('--graph-property-predicate-only') ||
    process.argv.includes('--graph-any-direction-only') ||
    process.argv.includes('--graph-abbreviated-only') ||
    process.argv.includes('--graph-quantifier-forms-only') ||
    process.argv.includes('--group-by-all-only') ||
    process.argv.includes('--group-property-only') ||
    process.argv.includes('--pipe-aggregate-order-only') ||
    process.argv.includes('--pipe-aggregate-expression-only') ||
    process.argv.includes('--sql-grouped-subexpression-only') ||
    process.argv.includes('--having-grouped-subexpression-only') ||
    process.argv.includes('--order-grouped-subexpression-only') ||
    process.argv.includes('--grouped-implicit-property-names-only') ||
    process.argv.includes('--group-having-implicit-aliases-only') ||
    process.argv.includes('--distinct-order-only') ||
    process.argv.includes('--concat-expression-reuse-only') ||
    process.argv.includes('--implicit-property-only') ||
    process.argv.includes('--computed-object-property-only') ||
  process.argv.includes('--source-free-only') ||
  process.argv.includes('--data-set-strategy-only') ||
  process.argv.includes('--cte-value-table-only') ||
  process.argv.includes('--query-composition-only') ||
  process.argv.includes('--pipe-result-only') ||
  process.argv.includes('--relation-data-only') ||
  process.argv.includes('--acquired-data-only') ||
  process.argv.includes('--alias-scope-only') ||
  process.argv.includes('--scoped-order-only') ||
  process.argv.includes('--infer-refusal-only') ||
  process.argv.includes('--two-source-only') ||
  process.argv.includes('--join-order-only') ||
  process.argv.includes('--group-scope-only') ||
  process.argv.includes('--group-select-scope-only') ||
  process.argv.includes('--having-projection-only') ||
  process.argv.includes('--group-star-only') ||
  process.argv.includes('--aggregate-property-order-only') ||
  process.argv.includes('--aggregate-property-only') ||
  process.argv.includes('--group-ordinal-only') ||
  process.argv.includes('--graph-equality-only') ||
  process.argv.includes('--graph-difference-only') ||
  process.argv.includes('--graph-rows-only') ||
  process.argv.includes('--graph-traverse-paths-only')) return;
if (!portableExtras) return;
if (!process.argv.includes('--graph-source-only')) {
  console.log(run(process.execPath, ['sga-cancellation.mjs'], root,
    runtimeEnvironment, 120000).trimEnd());
}
await mkdir(join(root, 'tls'));
await writeFile(join(root, 'tls/site.key'), await readFile(join(root, 'remote.key')));
await writeFile(join(root, 'tls/site.crt'), await readFile(join(root, 'remote.crt')));
await writeFile(join(root, 'tls/ca.crt'), await readFile(join(root, 'remote.crt')));
// Each independent family retains its original 60s case / 180s process bound.
// The shared registration selects every Local and HTTPS family exactly once.
for (const {name} of graphPublicHostCases) {
  console.log(run(process.execPath, ['--test', '--test-name-pattern',
    graphPublicHostPattern(name), 'graph-public-host.test.mjs'], root,
    {...runtimeEnvironment, ACTQL_GRAPH_PACKED: '1'}, 180000).trimEnd());
}
console.log(run(process.execPath, ['--test', 'graph-source-snapshot.test.mjs'], root,
  {...runtimeEnvironment, ACTQL_GRAPH_PACKED: '1'}, 180000).trimEnd());
if (process.argv.includes('--graph-source-only')) return;
if (!portableCi) await exerciseNativeGraphSource();
});
