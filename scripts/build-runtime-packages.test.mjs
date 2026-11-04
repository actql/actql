import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import {buildSync} from 'esbuild';
import {parse} from 'yaml';
import {readHostBundles, generateInstallations} from './connector-node-bundles.mjs';
import {localModuleGraphInputs} from './adapter-module-graph.mjs';
import {finiteRuntimeModules} from '../adapters/workers/artifact.mjs';
// Keep the deferred-initialization regressions in the ordinary cold-pack gate.
import './deferred-function-runtime.test.mjs';
import './runtime-package-pack-json.test.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

test('holder terminal facade runs after the existing prepared Remote Site CI gate', () => {
  const workflow = parse(readFileSync(join(root, '.github/workflows/ci.yml'), 'utf8'));
  const steps = Object.values(workflow.jobs).flatMap(job => job.steps ?? []);
  const selected = steps.filter(step => step.name === 'Test durable Remote Site dispatch admission');
  assert.equal(selected.length, 1);
  assert.deepEqual(selected[0].run.split(' && '), ['npm run check:remote-site-runtime',
    'node --test packages/coordinator-core/holder-terminal.test.mjs']);
  const gate = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).scripts['check:remote-site-runtime'];
  assert(gate.includes('node scripts/build-runtime-packages.mjs coordinator-core'));
});

// Independent command inventory: runtime preparation keeps its build, type,
// unit and asset checks. Moving packed acceptance to another CI job also
// requires the fixed scheduling assertions in client-ci.test.mjs.
const expectedGates = {
  "check:remote-site-runtime": [
    "moon build --target js --release src/connectors_builtin_node src/connectors/github/host_node src/connectors/notion/host_node src/connectors/slack/host_node src/connectors/calendar/host_node src/connectors/gmail/host_node src/connectors/sheets/host_node src/connectors/hubspot/host_node",
    "node scripts/build-runtime-packages.mjs coordinator-core",
    "node --test packages/coordinator-core/payload.test.mjs packages/coordinator-core/cancellation.test.mjs packages/coordinator-core/bundle-retention.test.mjs adapters/host-common/remote-bundle-control.test.mjs adapters/host-common/remote-coordinator-abi.test.mjs adapters/host-common/remote-credential-control.test.mjs adapters/host-common/remote-dispatch-wire.test.mjs adapters/host-common/remote-transfer-control.test.mjs adapters/host-node/sqlite-coordinator-journal.test.mjs adapters/host-node/remote-site-coordinator.test.mjs adapters/host-node/outbound-site-gateway.test.mjs adapters/site-node/runtime-bundle-operations.test.mjs adapters/site-node/runtime-bundle-store.test.mjs adapters/site-node/sqlite-credential-journal.test.mjs adapters/site-node/sqlite-dispatch-journal.test.mjs adapters/site-node/sqlite-transfer-journal.test.mjs adapters/site-node/sqlite-transfer-store-journal.test.mjs adapters/site-node/sqlite-transaction-custody.test.mjs adapters/site-node/https-credential-resource.test.mjs adapters/site-node/https-credential-response-accounting.test.mjs adapters/connectors/slack/test/remaining-row-requests.test.mjs adapters/connectors/slack/test/slack-source-read.test.mjs adapters/connectors/slack/test/slack-source-reader-join.test.mjs adapters/connectors/slack/test/installed-slack-source.test.mjs adapters/connectors/slack/test/installed-slack-channels.test.mjs adapters/connectors/slack/test/installed-slack-messages.test.mjs adapters/connectors/slack/test/installed-slack-message-parameters.test.mjs adapters/connectors/slack/test/installed-slack-limit-parameters.test.mjs adapters/connectors/notion/test/remaining-row-requests.test.mjs adapters/connectors/notion/test/user-list-read.test.mjs adapters/connectors/notion/test/installed-notion-source.test.mjs adapters/connectors/hubspot/test/hubspot-remaining-row-requests.test.mjs adapters/connectors/hubspot/test/hubspot-account-response-facts.test.mjs adapters/connectors/calendar/test/calendar-list-read.test.mjs adapters/connectors/gmail/test/gmail-label-shared-pages.actual.test.mjs adapters/connectors/calendar/test/calendar-events-pages.test.mjs adapters/connectors/calendar/test/calendar-events-request-pages.test.mjs adapters/connectors/calendar/test/calendar-original-profile.test.mjs adapters/connectors/calendar/test/calendar-free-busy-pages.test.mjs adapters/connectors/calendar/test/calendar-free-busy-request.actual.test.mjs adapters/connectors/sheets/test/sheets-grid-pages.test.mjs adapters/connectors/sheets/test/sheets-grid-pages.actual.test.mjs adapters/connectors/sheets/test/sheets-tabs-pages.test.mjs adapters/connectors/sheets/test/sheets-tabs-pages.actual.test.mjs adapters/connectors/github/test/github-issue-read.test.mjs adapters/connectors/github/test/github-comment-read.test.mjs adapters/connectors/github/test/github-installed-comment-source.test.mjs adapters/connectors/github/test/github-installed-comment-outcome.test.mjs adapters/connectors/github/test/github-comment-marker.test.mjs adapters/site-node/https-direct-transfer.test.mjs adapters/site-node/https-transfer-store.test.mjs adapters/site-node/remote-dispatch-runtime.test.mjs adapters/site-node/remote-standard-direct-execution.test.mjs adapters/site-node/https-agent.test.mjs adapters/site-node/https-agent-authorization.test.mjs adapters/host-node/embedded-source-identity-initialization.test.mjs adapters/host-node/rest-source-initial-material.test.mjs adapters/host-node/installed-source-authorization-cleanup.test.mjs adapters/host-node/installed-whole-source-row-run.test.mjs adapters/host-node/installed-reader-binding-retirement.test.mjs adapters/host-node/installation-metadata-configuration-reader.test.mjs adapters/host-node/installed-source-reader-page-demand.test.mjs adapters/host-node/installed-credential-source-reader-modes.test.mjs adapters/host-node/installed-credential-source-reader.test.mjs adapters/host-node/installed-source-child-use.test.mjs adapters/host-node/installed-source-credential-constructor.test.mjs",
    "node scripts/test-packed-coordinator-core.mjs"
  ],
  "check:transfer-core": [
    "moon build --target js --release src/connectors_builtin_node",
    "node scripts/build-runtime-packages.mjs transfer-core",
    "node --test packages/transfer-core/index.test.mjs"
  ],
  "check:distribution-client": [
    "node scripts/build-runtime-packages.mjs local-node run-host-core",
    "node scripts/build-local-node-adapters.mjs",
    "node scripts/generate-client-publication-wire.mjs",
    "node scripts/generate-client-host-wire.mjs",
    "node --test adapters/host-common/file-media-type-consumers.test.mjs adapters/host-common/source-response-custody.test.mjs adapters/host-node/installed-family-content.test.mjs scripts/packed-public-query-profile.test.mjs scripts/node-local-compile-cache.test.mjs scripts/node-local-owner-selection.test.mjs scripts/node-initial-control-open-routing.test.mjs adapters/host-node/initial-control-package-custody.test.mjs adapters/host-node/initial-control-image-source.test.mjs adapters/host-node/client-full-join-refusal.test.mjs adapters/host-node/installed-composed-infer-run.test.mjs adapters/host-common/strategy-usage.test.mjs adapters/host-node/ledger-usage-consumers.test.mjs adapters/host-node/composed-infer-provider.test.mjs adapters/host-node/infer-evaluation-evidence.test.mjs examples/infer-evaluation/evaluate.test.mjs examples/infer-evaluation/compare-source-instructions.test.mjs examples/infer-evaluation/capture-sink.test.mjs scripts/typed-json-literal-preparation.test.mjs scripts/typed-json-literal-public.test.mjs scripts/owned-scratch.test.mjs scripts/packed-client-packages.test.mjs scripts/packed-graph-host-dependencies.test.mjs scripts/packed-package-boundaries.test.mjs scripts/graph-composition-fixture.test.mjs scripts/dbt-compat-judge.test.mjs scripts/sga-surface-checker.test.mjs scripts/infer-owner-checker.test.mjs scripts/graph-surface-checker.test.mjs scripts/graph-public-host.test.mjs scripts/generate-client-publication-wire.test.mjs scripts/generate-client-host-wire.test.mjs packages/client-wire/index.test.mjs packages/client-wire/submission-check-semantics.test.mjs packages/client-wire/submission-check-observations.test.mjs packages/sdk/structured-program-check-observations.test.mjs packages/sdk/scoped-authoring-check.test.mjs packages/client-wire/cancel-identity.test.mjs packages/sdk/index.test.mjs packages/sdk/cancel-identity.test.mjs packages/sdk/read-progress.test.mjs packages/sdk/host-port.test.mjs packages/sdk/result-description.test.mjs packages/sdk/http-redirect.test.mjs packages/sdk/checkpoints.test.mjs packages/sdk/model-checkpoints.test.mjs adapters/host-node/installed-check-environment.test.mjs adapters/host-node/installed-host-policy.test.mjs adapters/host-node/remote-checkpoint-host.test.mjs adapters/host-node/client-effect-checkpoints.test.mjs adapters/host-node/client-effect-query-time.test.mjs adapters/host-node/installed-effect-site.test.mjs adapters/host-node/installed-effect-plan-current.test.mjs adapters/host-node/installed-effect-plan-consumer.test.mjs adapters/host-node/installed-effect-plan.test.mjs adapters/host-node/installed-row-effect-create-occurrence.test.mjs adapters/host-node/installed-row-write.test.mjs adapters/host-node/installed-effect-model-plan-consumer.test.mjs adapters/host-node/ordinary-node-resource-runtime.test.mjs adapters/connectors/notion/test/source-configuration-reader.test.mjs adapters/connectors/notion/test/installed-notion-standard-reader.test.mjs adapters/connectors/calendar/test/installed-calendar-standard-reader.test.mjs adapters/connectors/gmail/test/installed-gmail-standard-reader.test.mjs adapters/connectors/gmail/test/installed-gmail-thread-standard-reader.test.mjs adapters/connectors/gmail/test/gmail-thread-sequence.test.mjs adapters/host-node/installed-update-targets.test.mjs adapters/host-node/recovered-command-content.test.mjs adapters/connectors/local/host/local-file-store-declaration.actual.test.mjs adapters/connectors/local/host/local-file-store-driver.test.mjs adapters/connectors/local/host/local-file-store-authorization.test.mjs adapters/connectors/local/host/local-file-store-authorization-physical.test.mjs adapters/host-node/requested-effect-checkpoints.test.mjs adapters/connectors/local/host/local-file-store-target.test.mjs adapters/host-node/acquired-effect-computation.test.mjs adapters/host-node/acquired-effect-installed-capacity.test.mjs adapters/host-node/acquired-effect-source-binding.test.mjs adapters/host-node/remote-acquisition-checkpoint.test.mjs adapters/host-node/acquired-chain-capacity.test.mjs adapters/host-node/duckdb-import-boundary.test.mjs adapters/host-node/embedded-installation.test.mjs adapters/host-node/installed-infer.test.mjs adapters/host-node/installed-infer-capture.test.mjs adapters/host-node/model-resume-public.test.mjs adapters/host-node/model-resume-effect-public.test.mjs adapters/local-node/model-pause.test.mjs adapters/host-common/result-access-snapshot.test.mjs adapters/host-common/result-description.test.mjs adapters/host-node/client-check.test.mjs adapters/host-node/client-publication-limit-projection.test.mjs adapters/local-node/managed-failure-public.test.mjs adapters/host-node/client-result-alias-routing.test.mjs adapters/host-node/client-result-publication-envelope.test.mjs adapters/host-node/source-selector-check.test.mjs adapters/host-node/client-http.test.mjs adapters/host-node/in-process-client.test.mjs adapters/host-node/client-workspace-binding.test.mjs adapters/host-node/client-workspace-installed.test.mjs adapters/host-node/client-read-progress.test.mjs adapters/host-node/client-read-opening.test.mjs adapters/host-node/client-read-run-capacity.test.mjs adapters/host-node/client-values-row-limit.test.mjs adapters/host-node/client-values-join-profile.test.mjs adapters/host-node/client-sql-array-struct.test.mjs adapters/host-node/client-values-fragment-capacity.test.mjs adapters/host-node/client-values-capacity-custody.test.mjs adapters/host-node/client-submission-input.test.mjs adapters/host-node/client-cancel-response-loss.test.mjs adapters/host-node/client-cancellation-attempt-public.test.mjs adapters/host-node/client-cancellation-operation.test.mjs adapters/host-node/client-cancellation-public.test.mjs adapters/host-node/client-cancellation-attempt-installed.test.mjs adapters/host-node/client-effect-cancellation-public.test.mjs adapters/host-node/client-effect-uncertainty.test.mjs adapters/host-node/client-owner-cursor.test.mjs adapters/host-node/client-owner-observations.test.mjs adapters/host-node/client-owner-observations-public.test.mjs adapters/host-node/sqlite-effect-history-page.test.mjs packages/client-wire/owner-observations.test.mjs packages/sdk/owner-observations.test.mjs adapters/host-node/client-dispatch-owner.test.mjs adapters/host-node/infer-operation-approval.test.mjs adapters/host-node/client-confirmed-cancellation.test.mjs adapters/host-node/infer-dispatch-waiting.test.mjs adapters/host-node/installed-host-cleanup.test.mjs adapters/host-node/installed-effect-profile-cleanup.test.mjs adapters/host-node/installed-duckdb-source-owner.test.mjs adapters/host-node/client-request-journal.test.mjs adapters/host-node/ordinary-source-binding.test.mjs adapters/host-node/installed-row-source-binding-originals.test.mjs adapters/host-node/ordinary-project-source-managed.test.mjs adapters/connectors/local/host/installed-project-files-managed.test.mjs adapters/host-node/client-mock-source-occurrences.test.mjs adapters/host-node/embedded-values-cleanup.test.mjs adapters/local-node/managed-output-custody.test.mjs adapters/host-node/client-request-lookup.test.mjs adapters/host-node/client-run-attach.test.mjs adapters/host-node/client-run-state-fallback.test.mjs adapters/host-node/client-program-bridge.test.mjs adapters/host-node/public-source-preparation.test.mjs adapters/host-node/public-store-source-preparation.test.mjs adapters/host-node/local-values-plan.test.mjs adapters/host-node/local-values-plan-policy.test.mjs packages/sdk/delivery-observation.test.mjs adapters/host-node/client-delivery-observation.test.mjs adapters/host-node/effect-partial-refusal.test.mjs packages/sdk/request-observation.test.mjs packages/sdk/response-capture.test.mjs adapters/host-node/client-submission-epoch.test.mjs adapters/host-node/client-submitted-intent.test.mjs adapters/host-node/client-submission.test.mjs adapters/host-node/source-request-lineage.test.mjs adapters/host-node/journal-lifecycle-limits.test.mjs adapters/host-node/client-pre-admission-refusal.test.mjs adapters/host-node/client-submission-attempt.test.mjs adapters/host-node/client-submission-operation.test.mjs adapters/host-node/submission-epoch-public.test.mjs adapters/host-node/synthetic-held-values-public.test.mjs packages/sdk/submission-identity.test.mjs packages/sdk/submission-attempt.test.mjs scripts/connector-authoring.cli.test.mjs adapters/host-node/rest-source-metadata.test.mjs scripts/fixtures/external-rest/preparation.test.mjs scripts/fixtures/external-rest/marker-publication.test.mjs",
    "node scripts/test-packed-read-opening.mjs",
    "node scripts/check-read-row-mutations.mjs",
    "node scripts/check-submission-input-mutations.mjs",
    "node scripts/check-submission-check-observation-mutations.mjs",
    "node scripts/check-effect-uncertainty-mutations.mjs",
    "node scripts/test-packed-local-without-duckdb.mjs",
    "node scripts/test-node-client-package.mjs",
    "node scripts/test-packed-workspace-connection.mjs",
    "node scripts/test-packed-graph.mjs",
    "node scripts/test-packed-client-checkpoint.mjs",
    "moon build --target native --release src/cmd/native_client",
    "node scripts/test-native-client.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-null-context.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/public-text-time.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-relational-composition.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-right-join.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-audited-capabilities.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-publication-capacity.test.mjs adapters/host-node/grouped-count-capacity-public.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/local-preparation-custody.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-preparation-custody-public.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-result-schema-budget.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-publication-plan-original.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/ordinary-source-producer-lifetime.test.mjs",
    "node scripts/local-checks.mjs test node -- scripts/verify-local-source-runtime.test.mjs",
    "node scripts/local-checks.mjs test node -- scripts/preparation-context-carrier-layout.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/preparation-root-bridge.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/submission-snapshot-publication.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/local-preparation-registry.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/preparation-host-custody.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-large-input-public.test.mjs adapters/host-node/local-values-policy-original.test.mjs adapters/host-node/host-result-extent.test.mjs adapters/host-node/ordinary-host-result.test.mjs adapters/host-node/client-join-scale-public.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/preparation-journal-failure-public.test.mjs adapters/host-node/preparation-initial-failure-public.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/ordinary-preparation-cut-retry.test.mjs",
    "node scripts/local-checks.mjs test node -- scripts/preparation-closed-values-plan-controls.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/store-local/publication-contract-node-bound.test.mjs",
    "node scripts/local-checks.mjs test node -- scripts/preparation-closed-values-layout.test.mjs",
    "node scripts/local-checks.mjs test node -- scripts/preparation-closed-values-graph-layout.test.mjs",
    "node scripts/local-checks.mjs test node -- scripts/preparation-closed-values-contract-layout.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/client-numeric-scale-public.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/preparation-capacity-refusal.test.mjs",
    "node scripts/local-checks.mjs test node -- scripts/preparation-intent-lifetime.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/installed-sequence-infer-subset.test.mjs adapters/host-node/client-compilation-original.test.mjs adapters/host-node/preparation-compilation-cold-open-public.test.mjs scripts/preparation-compilation-call-controls.test.mjs scripts/preparation-compilation-projector-controls.test.mjs adapters/host-node/client-snapshot-output-envelope.test.mjs adapters/host-node/client-captured-context-original.test.mjs",
    "node scripts/local-checks.mjs test node -- scripts/scalar-snapshot-projector-layout.test.mjs scripts/capture-projector-layout.test.mjs adapters/host-node/publication-currentness-boundary.test.mjs adapters/host-node/client-publication-preparation-phase.test.mjs adapters/host-node/publication-validation-close-public.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/publication-snapshot-original-public.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/finalization-scratch-cut-public.test.mjs adapters/connectors/calendar/test/installed-calendar-source.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/managed-output-mode.test.mjs adapters/host-node/request-program-module-body-callers.test.mjs adapters/host-node/request-domain-preparation.test.mjs adapters/host-node/request-model-plan.test.mjs adapters/host-node/request-model-source-ledger.test.mjs adapters/host-node/request-model-caller-lifetime.test.mjs adapters/host-node/request-content-caller.test.mjs adapters/host-node/content-pre-record-retirement.test.mjs adapters/host-node/effect-capture-connection.test.mjs adapters/host-node/effect-capture-resources.test.mjs adapters/host-node/request-content-graph-resources.test.mjs adapters/host-node/request-keyed-prefix-execution.test.mjs adapters/host-node/request-model-material-resources.test.mjs adapters/store-local/private-evidence-consumer-lifetime.test.mjs adapters/host-node/request-domain-source-preflight.test.mjs adapters/host-node/content-execution-alias-retirement.test.mjs adapters/host-node/request-keyed-content-caller.test.mjs adapters/host-node/content-preparation-retirement.test.mjs adapters/host-node/installed-infer-compilation-selection.test.mjs adapters/host-node/request-preparation-parent.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-common/source-response-custody.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/installed-source-service-capture.test.mjs adapters/host-node/host-deferred-publication-startup.test.mjs adapters/host-node/source-profile-json.test.mjs",
    "node scripts/local-checks.mjs test node -- adapters/host-node/installed-content-family-custody.test.mjs adapters/host-node/table-owned-site-retirement.test.mjs adapters/host-node/table-original-metadata.test.mjs"
  ],
  "check:run-host-core": [
    "node scripts/build-runtime-packages.mjs run-host-core coordinator-core",
    "npm run check:run-host-types",
    "node --test packages/run-host-core/index.test.mjs packages/run-host-core/schema-field-order.test.mjs packages/run-host-core/checkpoints.test.mjs adapters/host-common/publication-action.test.mjs adapters/host-common/result-access-clock.test.mjs adapters/host-common/result-delivery.test.mjs packages/run-host-core/effect-checkpoint-retention.test.mjs packages/run-host-core/effect-checkpoint-binding.test.mjs packages/run-host-core/effect-publication.test.mjs packages/run-host-core/effect-publication.runtime.test.mjs packages/run-host-core/review-binding-facts.test.mjs packages/run-host-core/source-preparation.test.mjs",
    "node scripts/test-packed-run-host-core.mjs"
  ],
  "check:local-node-assets": [
    "node scripts/build-runtime-packages.mjs local-node",
    "node scripts/build-local-node-adapters.mjs",
    "node scripts/build-local-node-adapters.mjs --check",
    "node --test scripts/local-node-package-inputs.test.mjs scripts/local-node-external-package-inputs.test.mjs scripts/local-node-table-assets.test.mjs",
    "tsc --noEmit --strict --module NodeNext --moduleResolution NodeNext --target ES2022 packages/local-node/connector-installation.typecheck.mts",
    "node scripts/test-packed-local-node-assets.mjs",
    "node scripts/test-packed-installed-connectors.mjs",
    "node scripts/test-packed-external-connector.mjs",
    "node scripts/test-packed-external-installed.mjs"
  ]
};
const packages = {
  'run-host-core': {builder: 'build-run-host-core-package', args: ['--runtime-only'],
    sources: ['client_values_host_abi', 'checkpoint_runtime_node',
      'connectors_workers_bridge'],
    destination: 'packages/run-host-core/dist/client_values_host_abi.js',
    stale: 'StaleRunHostCorePackage'},
  'coordinator-core': {builder: 'build-remote-coordinator-package', args: [],
    sources: ['remote_coordinator_abi'],
    destination: 'packages/coordinator-core/dist/remote_coordinator_abi.js',
    stale: 'StaleRemoteCoordinatorPackage'},
  'transfer-core': {builder: 'build-remote-transfer-package', args: [],
    sources: ['remote_transfer_abi'],
    destination: 'packages/transfer-core/dist/remote_transfer_abi.js',
    stale: 'StaleRemoteTransferPackage'},
  'local-node': {builder: 'build-local-node-assets', args: [],
    sources: ['connectors_builtin_node', 'connectors/duckdb/host_node',
      'retained_host_bridge', 'process_host_bridge', 'checkpoint_runtime_node',
      'connectors/calendar/host_node', 'connectors/gcs/host_node',
      'connectors/github/host_node', 'connectors/gmail/host_node',
      'connectors/hubspot/host_node', 'connectors/notion/host_node',
      'connectors/salesforce/host_node', 'connectors/sheets/host_node',
      'connectors/slack/host_node'],
    destination: 'packages/local-node/_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
    stale: 'StaleLocalNodeAsset'},
};

function put(directory, path, contents) {
  mkdirSync(dirname(join(directory, path)), {recursive: true});
  writeFileSync(join(directory, path), contents);
}

function run(t, requested, {fail, stalePayload, wrapper, version, additionalProvider = false,
  refuseInterfaces = false, normalCli = false, missingInterfaceOwner = false, temporaryParent = tmpdir()} = {}) {
  const directory = realpathSync(mkdtempSync(join(temporaryParent, 'runtime-build-check-')));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  mkdirSync(join(directory, 'scripts'));
  // Resolve actual transitive builder imports instead of maintaining a partial
  // helper list. The one deliberately omitted checker is replaced only by the
  // explicit scheduling port below; normal CLI selection must still refuse it.
  const builderModules = localModuleGraphInputs(root, ['scripts/build-runtime-packages.mjs',
    ...Object.values(packages).map(item => `scripts/${item.builder}.mjs`)]);
  assert(builderModules.includes('scripts/check-interface-owners.mjs'));
  for (const path of builderModules) {
    assert.ok(!path.startsWith('../') && !path.startsWith('/'));
    // The unowned fixture publishes plain JS only, with no generated compiler
    // bindings. It has no generator inputs or compiler-interface approvals.
    if (missingInterfaceOwner && path === 'scripts/generate-js-compiler-bindings.mjs') continue;
    if (path !== 'scripts/check-interface-owners.mjs') {
      put(directory, path, readFileSync(join(root, path)));
    }
  }
  // Only this distinct negative uses the original real checker; the ordinary
  // scheduling controls keep their explicit port and missing-checker oracle.
  if (missingInterfaceOwner) symlinkSync(join(root, 'scripts/check-interface-owners.mjs'),
    join(directory, 'scripts/check-interface-owners.mjs'));
  put(directory, 'adapters/host-common/installed-connector-declaration.mjs',
    readFileSync(join(root, 'adapters/host-common/installed-connector-declaration.mjs')));
  put(directory, 'adapters/host-common/http-exchange.mjs',
    readFileSync(join(root, 'adapters/host-common/http-exchange.mjs'), 'utf8'));
  // Copy the actual reviewed product JS closure. Only the compiler output
  // below is synthetic; the producer still audits and bundles real adapters.
  for (const path of [...finiteRuntimeModules.filter(path => !path.startsWith('_build/')),
    'adapters/workers/build.mjs', 'adapters/workers/artifact.mjs',
    'adapters/workers/moon-runtime.mjs']) {
    put(directory, path, readFileSync(join(root, path)));
  }
  for (const entry of readHostBundles(root)) {
    for (const path of [`src/connectors/${entry.name}/host-bundle.json`,
      ...(entry.providerBundle === undefined ? [] : [`src/${entry.providerBundle}/moon.pkg`]),
      ...[entry.source, entry.effect].filter(Boolean).map(role => role.module), ...entry.assets]) {
      put(directory, path, readFileSync(join(root, path)));
    }
  }
  // Implementation inventories now resolve real transitive imports. This
  // scheduling fixture needs their complete source inputs before generation,
  // not only the installation entry file. No provider code is executed here;
  // the independently authored compiled payloads below still test each builder.
  const fixtureGraph = buildSync({
    entryPoints: readHostBundles(root).flatMap(entry => [entry.source, entry.effect]
      .filter(Boolean).map(role => role.module)),
    bundle: true, packages: 'external', platform: 'node', format: 'esm',
    metafile: true, write: false, absWorkingDir: root,
    outdir: join(root, '_build/runtime-preparation-fixture-graph'),
  });
  for (const path of Object.keys(fixtureGraph.metafile.inputs)) {
    assert.ok(!path.startsWith('../') && !path.startsWith('/'));
    put(directory, path, readFileSync(join(root, path)));
  }
  // Package import maps are part of the actual adapter source closure.
  put(directory, 'packages/sdk/package.json',
    readFileSync(join(root, 'packages/sdk/package.json')));
  if (additionalProvider) {
    put(directory, 'src/connectors/third/host-bundle.json', JSON.stringify({installation: {
      registration: 'third', revision: 'third/0.1', responseHeaders: [],
      providerBundle: 'connectors/third/host_node',
      source: {profileVersion: 'actql-installed-third-source/0.1',
        module: 'adapters/connectors/third/host/source.mjs',
        exports: {check: 'check', identityParts: 'identity', load: 'load'}}}}));
    put(directory, 'src/connectors/third/host_node/moon.pkg',
      'supported_targets = "js"\npkgtype(kind: "foreign_library")\n');
    put(directory, 'adapters/connectors/third/host/source.mjs',
      'export function check() {}\nexport function identity() {}\nexport function load() {}\n');
    put(directory, '_build/js/release/build/connectors/third/host_node/host_node.js',
      'export const third = "independent-provider-fixture";\n');
  }
  put(directory, 'adapters/connectors-builtin/installations.generated.mjs',
    generateInstallations(readHostBundles(directory),
      join(directory, 'adapters/connectors-builtin/installations.generated.mjs'), directory));
  put(directory, 'scripts/owned-contract-version-legacy.json',
    readFileSync(join(root, 'scripts/owned-contract-version-legacy.json')));
  put(directory, '.gitignore', '_build/\npackages/*/dist/\nnode_modules/\n');
  const initialized = spawnSync('git', ['init', '--quiet'], {cwd: directory});
  assert.equal(initialized.status, 0);
  // Use the real package builders and installed esbuild; only the MoonBit
  // compiler is replaced with independent tiny compiled-source fixtures.
  symlinkSync(join(root, 'node_modules'), join(directory, 'node_modules'), 'dir');
  if (missingInterfaceOwner) {
    // Independent, valid JS entrances deliberately have no Owner sidecar.
    // The normal checker must refuse them before any compiler or builder.
    for (const name of Object.keys(packages)) {
      put(directory, `packages/${name}/package.json`, JSON.stringify({
        name: `@fixture/${name}`, type: 'module', exports: './fixture-interface.mjs',
      }));
      put(directory, `packages/${name}/fixture-interface.mjs`,
        'export function runtimePreparationInput(value) { return value; }\n');
    }
  }
  for (const [name, item] of Object.entries(packages)) {
    for (const source of item.sources) {
      if (source === 'connectors_workers_bridge') continue;
      put(directory, `_build/js/release/build/${source}/${source.split('/').at(-1)}.js`,
        `export function payload() { return ${JSON.stringify(version === name
          ? 'actql-fixture/' + ['0', '2'].join('.') : `fixture-${source}`)}; }\n`);
    }
  }
  // Exact audited pinned builtin spelling, with an independent tiny ABI.
  // This fixture tests producer scheduling, not execution conformance.
  put(directory, '_build/js/release/build/connectors_workers_bridge/connectors_workers_bridge.js',
    `const _M0FPB12random__seed = () => {
  if (globalThis.crypto?.getRandomValues) {
    const array = new Uint32Array(1);
    globalThis.crypto.getRandomValues(array);
    return array[0] | 0; // Convert to signed 32
  } else {
    return Math.floor(Math.random() * 0x100000000) | 0; // Fallback to Math.random
  }
};
function payload() { return 'fixture-connectors-workers-bridge'; }
export {payload};\n`);
  const wrappers = {
    'result-access.mjs': ["export {value} from '../../packages/client-wire/index.mjs';\n",
      "export {value} from '@actql/client-wire';\n"],
    'result-delivery.mjs': ['export const delivery = 1;\n', 'export const delivery = 1;\n'],
    'managed-failure.mjs': [readFileSync(join(root, 'adapters/host-common/managed-failure.mjs'), 'utf8'),
      readFileSync(join(root, 'adapters/host-common/managed-failure.mjs'), 'utf8')],
    'publication-action.mjs': [
      'export const action = 1;\nexport const publicationAction = () => action;\n',
      'export const action = 1;\nexport const publicationAction = () => action;\n'],
  };
  for (const [path, [source, tracked]] of Object.entries(wrappers)) {
    put(directory, `adapters/host-common/${path}`, source);
    put(directory, `packages/run-host-core/${path}`, wrapper === path ? 'stale wrapper\n' : tracked);
  }
  put(directory, 'driver.mjs', `
import childProcess from 'node:child_process';
import {appendFileSync, writeFileSync} from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
const original = childProcess.execFileSync;
const record = value => appendFileSync('calls.jsonl', JSON.stringify(value) + '\\n');
childProcess.execFileSync = (command, args, options) => {
  if (command === 'git') return original(command, args, options);
  record({command: command === process.execPath ? 'node' : command, args,
    cwd: options.cwd, stdio: options.stdio});
  if (command === 'moon') return Buffer.alloc(0);
  if (command === 'python3' && ${JSON.stringify(missingInterfaceOwner)}) return original(command, args, options);
  if (command !== process.execPath) throw new Error('Unexpected subprocess');
  if (args[0] === ${JSON.stringify(fail ? `scripts/${packages[fail].builder}.mjs` : null)} &&
      args.includes('--check')) {
    writeFileSync(${JSON.stringify(fail ? stalePayload ?? packages[fail].destination : '')}, 'stale runtime\\n');
  }
  return original(command, args, options);
};
syncBuiltinESMExports();
const refusal = new Error('Original fixture interface admission refused');
try {
  if (${JSON.stringify(normalCli || missingInterfaceOwner)}) {
    record({normalCli: true});
    process.argv = [process.execPath, 'scripts/build-runtime-packages.mjs', ...${JSON.stringify(requested)}];
    await import('./scripts/build-runtime-packages.mjs');
  } else {
    const {prepareRuntimePackages} = await import('./scripts/build-runtime-packages.mjs');
    await prepareRuntimePackages(${JSON.stringify(requested)}, {
      checkInterfaces: async (root, {manifests}) => {
        record({command: 'fixture-interface-admission', root, manifests});
        await Promise.resolve();
        if (${JSON.stringify(refuseInterfaces)}) throw refusal;
        record({fixtureInterfacesAdmitted: true});
      },
    });
  }
} catch (error) {
  if (${JSON.stringify(refuseInterfaces)}) record({originalInterfaceRefusal: error === refusal});
  throw error;
}
record({done: true});
`);
  const result = spawnSync(process.execPath, ['driver.mjs'], {
    cwd: directory, encoding: 'utf8', timeout: 30000,
  });
  assert.ok(existsSync(join(directory, 'calls.jsonl')),
    result.error?.message ?? result.stderr);
  const calls = readFileSync(join(directory, 'calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  return {result, calls, directory};
}

function expectedCalls(names, directory) {
  return [{command: 'fixture-interface-admission', root: directory + '/',
    manifests: names.map(name => `packages/${name}/package.json`)},
  {fixtureInterfacesAdmitted: true},
  {command: 'moon', args: ['build', '--target', 'js', '--release',
    ...new Set(names.flatMap(name => packages[name].sources.map(source => `src/${source}`)))],
  cwd: directory + '/', stdio: 'inherit'}, ...names.flatMap(name => {
    const item = packages[name];
    return [item.args, ['--check']].map(args => ({command: 'node',
      args: [`scripts/${item.builder}.mjs`, ...args], cwd: directory + '/', stdio: 'inherit'}));
  }), {done: true}];
}



test('explicit fixture interface admission is awaited for the physical root and selected manifests', t => {
  const {result, calls, directory} = run(t, ['coordinator-core', 'transfer-core', 'coordinator-core']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls, expectedCalls(['coordinator-core', 'transfer-core'], directory));
  assert.equal(realpathSync(calls[0].root), directory);
});

test('original interface refusal prevents every compiler and builder call', t => {
  const {result, calls, directory} = run(t, ['local-node', 'run-host-core'], {refuseInterfaces: true});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Original fixture interface admission refused/u);
  assert.deepEqual(calls, [expectedCalls(['local-node', 'run-host-core'], directory)[0],
    {originalInterfaceRefusal: true}]);
});

test('normal runtime CLI selects its real interface checker instead of fixture admission', t => {
  const {result, calls} = run(t, ['transfer-core'], {normalCli: true});
  assert.notEqual(result.status, 0);
  // The isolated scheduling fixture deliberately has no real Owner checker
  // or approvals. Normal CLI selection must load that missing dependency.
  assert.match(result.stderr, /ERR_MODULE_NOT_FOUND/u);
  assert.match(result.stderr, /scripts\/check-interface-owners\.mjs/u);
  assert.deepEqual(calls, [{normalCli: true}]);
});

test('runtime preparation preserves physical cwd and output through a symlinked temporary parent', t => {
  const scratch = realpathSync(mkdtempSync(join(tmpdir(), 'runtime-build-alias-')));
  // Both the link and its target belong to this test. Recursive removal of
  // scratch unlinks directory symlinks rather than following their targets.
  t.after(() => rmSync(scratch, {recursive: true, force: true}));
  const physicalParent = join(scratch, 'physical'), logicalParent = join(scratch, 'logical');
  mkdirSync(physicalParent);
  symlinkSync(physicalParent, logicalParent, 'dir');
  assert.notEqual(logicalParent, realpathSync(logicalParent));
  const {result, calls, directory} = run(t, ['transfer-core'], {temporaryParent: logicalParent});
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls, expectedCalls(['transfer-core'], directory));
  assert.equal(dirname(directory), physicalParent);
  const output = packages['transfer-core'].destination;
  const physicalOutput = join(physicalParent, basename(directory), output);
  const logicalOutput = join(logicalParent, basename(directory), output);
  assert.equal(realpathSync(logicalOutput), physicalOutput);
  assert.deepEqual(readFileSync(physicalOutput), readFileSync(logicalOutput));
  const consumer = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {payload} from ${JSON.stringify(pathToFileURL(physicalOutput).href)};
     if (payload() !== 'fixture-remote_transfer_abi') throw new Error('Wrong original payload');`],
  {encoding: 'utf8', timeout: 30000});
  assert.equal(consumer.status, 0, consumer.stderr);
});

test('runtime preparation refuses missing fixture ownership before compiling', t => {
  const {result, calls} = run(t, ['transfer-core'], {missingInterfaceOwner: true});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Unregistered distributed interfaces/);
  assert.equal(calls.some(value => value.command === 'moon'), false);
  assert.equal(calls.some(value => value.done), false);
});

for (const [gate, commands] of Object.entries(expectedGates)) {
  test(`${gate} retains its exact registered commands without duplicate checks`, () => {
    const actual = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).scripts[gate];
    assert.deepEqual(actual.split(' && '), commands);
  });
}

for (const names of [[], ...Object.keys(packages).map(name => [name]),
  ['local-node', 'run-host-core'], ['run-host-core', 'coordinator-core'],
  ['local-node', 'local-node']]) {
  test(`runtime preparation generates and checks each selected builder exactly once: ${names.join(',') || 'all'}`, t => {
    const {result, calls, directory} = run(t, names);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(calls, expectedCalls([...new Set(names.length ? names : Object.keys(packages))], directory));
  });
}

for (const name of Object.keys(packages)) {
  test(`${name} internal check rejects stale output and stops subsequent work`, t => {
    const {result, calls, directory} = run(t, [], {fail: name});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, new RegExp(packages[name].stale));
    const expected = expectedCalls(Object.keys(packages), directory);
    const stop = expected.findIndex(call => call.args?.[0] === `scripts/${packages[name].builder}.mjs` &&
      call.args.includes('--check'));
    assert.deepEqual(calls, expected.slice(0, stop + 1));
  });
}

for (const wrapper of ['result-access.mjs', 'result-delivery.mjs', 'publication-action.mjs', 'managed-failure.mjs']) {
  test(`runtime-only build refuses the old tracked ${wrapper} without repairing it`, t => {
    const {result, calls, directory} = run(t, [], {wrapper});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /StaleRunHostResultAccessService/);
    assert.deepEqual(calls, expectedCalls(Object.keys(packages), directory).slice(0, 5));
    assert.equal(readFileSync(join(directory, `packages/run-host-core/${wrapper}`), 'utf8'), 'stale wrapper\n');
  });
}

test('run-host-core includes the unchanged canonical cleanup dependency as a private package member', () => {
  const manifest = JSON.parse(readFileSync(join(root, 'packages/run-host-core/package.json')));
  assert(manifest.files.includes('managed-failure.mjs'));
  assert(!Object.hasOwn(manifest.exports, './managed-failure'));
  assert.deepEqual(readFileSync(join(root, 'packages/run-host-core/managed-failure.mjs')),
    readFileSync(join(root, 'adapters/host-common/managed-failure.mjs')));
  assert.deepEqual(readFileSync(join(root, 'packages/run-host-core/result-delivery.mjs')),
    readFileSync(join(root, 'adapters/host-common/result-delivery.mjs')));
});

test('run-host-core refuses a stale Checkpoint payload before subsequent work', t => {
  const {result, calls, directory} = run(t, ['run-host-core', 'coordinator-core'], {
    fail: 'run-host-core',
    stalePayload: 'packages/run-host-core/dist/checkpoint_runtime_node.js',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /StaleRunHostCheckpointPackage/);
  assert.deepEqual(calls, expectedCalls(['run-host-core', 'coordinator-core'], directory).slice(0, 5));
});

for (const file of ['workers_finite.js', 'workers_finite_payload.js']) {
  test(`run-host-core refuses stale finite Worker ${file} before subsequent work`, t => {
    const {result, calls, directory} = run(t, ['run-host-core', 'coordinator-core'], {
      fail: 'run-host-core', stalePayload: `packages/run-host-core/dist/${file}`,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /StaleRunHostWorkersFinitePackage/);
    assert.deepEqual(calls, expectedCalls(['run-host-core', 'coordinator-core'], directory).slice(0, 5));
  });
}

for (const name of Object.keys(packages)) {
  test(`${name} still rejects a generated nonbaseline contract version`, t => {
    const {result, calls} = run(t, [name], {version: name});
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Generated owned contracts require admitted production source/);
    assert.equal(calls.some(call => call.done), false);
  });
}

for (const name of Object.keys(packages)) {
  test(`${name} retains its real prepack runtime preparation`, () => {
    const manifest = JSON.parse(readFileSync(join(root, 'packages', name, 'package.json'), 'utf8'));
    assert.equal(manifest.scripts.prepack, (name === 'local-node' ? 'node ../../scripts/generate-credential-scope-binding.mjs --check && ' : '') +
      `node ../../scripts/build-runtime-packages.mjs ${name}` +
      (name === 'local-node' ? ' && node ../../scripts/build-local-node-adapters.mjs' : ''));
  });
}

test('a new Host manifest drives both the actual build command and copied runtime', t => {
  const {result, calls, directory} = run(t, ['local-node'], {additionalProvider: true});
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(calls[2].args, ['build', '--target', 'js', '--release',
    ...packages['local-node'].sources.map(source => `src/${source}`),
    'src/connectors/third/host_node']);
  assert.match(readFileSync(join(directory,
    'packages/local-node/_build/js/release/build/connectors/third/host_node/host_node.js'),
  'utf8'), /independent-provider-fixture/);
});

test('the existing cold pack runner executes this regression and still packs all four packages', () => {
  const source = readFileSync(join(root, 'scripts/test-runtime-package-build.mjs'), 'utf8');
  assert.match(source, /'dist\/workers_finite\.js'/);
  assert.match(source, /'dist\/workers_finite_payload\.js'/);
  assert.match(source, /execFileSync\(process\.execPath, \['--test', 'scripts\/build-runtime-packages\.test\.mjs'\]/);
  assert.match(source, /for \(const \[name, paths\] of Object\.entries\(expected\)\)/);
  assert.match(source, /execFileSync\('npm', normalNpmPackJsonArgs\(\['pack', '--json', '--pack-destination', destination\]\)/);
  assert.match(source, /const metadata = parseNpmPackJson\(output\)/);
  assert.doesNotMatch(source, /--ignore-scripts/);
});
