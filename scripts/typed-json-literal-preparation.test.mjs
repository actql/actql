import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {inspect} from 'node:util';
import {test} from 'node:test';
import * as moon from '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {readmeQuickstart} from './readme-quickstart.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {checked} from '../adapters/host-common/runtime-result.mjs';
import {typedJsonLiteralSuccesses} from './fixtures/typed-json-literal-input.mjs';

test('typed JSON roots and ordinary README use the same preparation and compilation', () => {
  const {evidence_bundle_cid: ignored, ...selected} = JSON.parse(
    readFileSync('spec/local-check-environment.json', 'utf8'));
  void ignored;
  // Match the existing installed Local Graph-construction policy, rather
  // than asking the checker to execute a Graph without its declared ceilings.
  Object.assign(selected.host_policy_profile.capacity, {
    max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000,
    max_graph_construction_nodes: 1000,
  });
  const body = canonicalText({...selected, evidence_bundle_cid: machineCid(selected)});
  const environment = moon.clientProgramCheckEnvironmentWithPropertyGraphProfile(body,
    JSON.parse(body).evidence_bundle_cid,
    false, true, true, true, true, false, false,
    machineCid(JSON.parse(readFileSync('spec/contracts/actql-numeric-reduction.json'))),
    machineCid(JSON.parse(readFileSync('spec/dependencies/actql-property-graph-laws.json'))));
  assert.ok(environment);
  const cases = [{text: readmeQuickstart(readFileSync('README.md', 'utf8')).program,
    format: 'yaml'}, ...typedJsonLiteralSuccesses];
  for (const input of cases) {
    const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
      input.text, input.format, environment, undefined);
    const prepared = moon.clientProgramPreparationReady(outcome);
    assert.ok(prepared, `${input.name ?? 'README'}: ` +
      moon.clientProgramPreparationIssueCode(outcome) + ': ' +
      inspect(moon.clientProgramPreparationIssue(outcome),
        {depth: 6, maxArrayLength: 2, maxStringLength: 120}));
    assert.ok(checked(input.graphSnapshots
      ? moon.clientProgramCompileLocalTasks(prepared)
      : moon.clientProgramCompileLocalValues(prepared)));
  }
});
