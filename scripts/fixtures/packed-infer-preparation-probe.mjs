// Failure-boundary probe only: it calls the same installed checker/Frontend.
// Compiler output here is diagnostic material, never a golden expectation.
import {readFile, writeFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import * as moon from '@actql/local-node/runtime';
import {openInferTestHost} from './infer-host-setup.mjs';
import {composeInstalledCheckEnvironment} from
  './node_modules/@actql/local-node/adapters/host-node/installed-check-environment.mjs';
import {installedModelEnvironment} from
  './node_modules/@actql/local-node/adapters/host-node/installed-model.mjs';
import {canonicalJson, contentCid} from
  './node_modules/@actql/local-node/adapters/host-node/local-account-config.mjs';

const fixture = JSON.parse(await readFile('infer-acceptance.json', 'utf8'));
const configuration = await openInferTestHost({mode: 'local', fixture});
const base = await readFile('base-environment.json', 'utf8');
let wire = installedModelEnvironment(moon, base,
  composeInstalledCheckEnvironment(moon, base), configuration.modelInstallation);
const {evidence_bundle_cid: ignored, ...body} = JSON.parse(wire);
void ignored;
// These are the installed Host's existing ceilings, copied solely to inspect
// its effective environment. The probe never dispatches or admits a Run.
Object.assign(body.host_policy_profile.capacity, {
  max_graph_construction_edges: 1000,
  max_graph_construction_input_rows: 1000,
  max_graph_construction_nodes: 1000});
wire = canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
const numeric = JSON.parse(await readFile(
  './node_modules/@actql/local-node/spec/contracts/actql-numeric-reduction.json', 'utf8'));
const environment = moon.clientProgramCheckEnvironmentWithNumericProfile(
  wire, contentCid(body), false, false, true, true, false, false, false,
  contentCid(numeric));
if (environment === undefined) throw new Error('ProbeEnvironmentRejected');
for (const name of ['json-control', 'json-projected', 'source-as']) {
  const outcome = name === 'source-as'
    ? moon.clientProgramPrepareSourceWithParameters(fixture.source,
      'aql-text', environment, JSON.stringify({
        environmentCid: moon.clientProgramCheckingEnvironmentCid(environment),
        aliases: []}), undefined, undefined)
    : moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(
      name === 'json-control' ? fixture.control_program : fixture.projected_program),
    'json', environment, undefined);
  const prepared = moon.clientProgramPreparationReady(outcome);
  const result = {name, checked: prepared !== undefined};
  if (prepared === undefined) {
    result.issueCode = moon.clientProgramPreparationIssueCode(outcome);
    result.issue = inspect(moon.clientProgramPreparationIssue(outcome), {depth: 12});
  } else {
    result.terminalInferStep = moon.clientProgramTerminalInferStep(prepared) ?? null;
    result.ordinaryTaskCompilation = inspect(
      moon.clientProgramCompileLocalTasks(prepared), {depth: 12});
    const semantic = moon.clientProgramSemanticDocumentJson(prepared);
    if (semantic.$tag === 1) {
      await writeFile(`probe-${name}.program.json`, semantic._0 + '\n');
    }
  }
  console.log(JSON.stringify(result));
}
