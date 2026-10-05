import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {inspect} from 'node:util';
import {test} from 'node:test';
import * as moon from '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {readmeQuickstart} from './readme-quickstart.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {checked} from '../adapters/host-common/runtime-result.mjs';

test('typed JSON contract preserves ordinary README Program preparation and compilation', () => {
  const body = readFileSync('spec/local-check-environment.json', 'utf8').trimEnd();
  const environment = moon.clientProgramCheckEnvironmentWithPropertyGraphProfile(body,
    JSON.parse(body).evidence_bundle_cid,
    false, true, true, true, true, false, false,
    machineCid(JSON.parse(readFileSync('spec/contracts/actql-numeric-reduction.json'))),
    machineCid(JSON.parse(readFileSync('spec/dependencies/actql-property-graph-laws.json'))));
  assert.ok(environment);
  const source = readmeQuickstart(readFileSync('README.md', 'utf8')).program;
  const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
    source, 'yaml', environment, undefined);
  const prepared = moon.clientProgramPreparationReady(outcome);
  assert.ok(prepared, moon.clientProgramPreparationIssueCode(outcome) + ': ' +
    inspect(moon.clientProgramPreparationIssue(outcome),
      {depth: 4, maxArrayLength: 3, maxStringLength: 200}));
  const compiled = moon.clientProgramCompileLocalValues(prepared);
  assert.ok(checked(compiled));
});
