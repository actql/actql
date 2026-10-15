// Read only installed code/static artifacts; never open a Host, Run or Store.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {dirname, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyPackageRelease} from '../../scripts/package-release.mjs';
import {auditPackedPackages} from '../../scripts/packed-client-packages.mjs';
import {temporalJoinSourceSuccesses} from '../../scripts/fixtures/temporal-join-source-input.mjs';
const [rc, installed, destination] = process.argv.slice(2);
const manifest = await verifyPackageRelease(rc);
assert.equal(manifest.sourceSha, 'efb566b7e4d5d84255856436b20364eab1b18868');
auditPackedPackages(installed, manifest.cohort.packages);
const require = createRequire(join(installed, 'package.json'));
const moon = await import(pathToFileURL(require.resolve('@actql/local-node/runtime')));
const {canonicalJson} = await import(pathToFileURL(require.resolve('@actql/sdk/host-port')));
const root = dirname(require.resolve('@actql/local-node'));
const read = async path => JSON.parse(await readFile(join(root, path), 'utf8'));
const contentCid = value => 'sha256:' + createHash('sha256').update(canonicalJson(value)).digest('hex');
const {evidence_bundle_cid: original, ...body} = await read('spec/local-check-environment.json');
assert.equal(typeof original, 'string');
body.host_policy_profile.capacity = {max_graph_construction_edges: 1000,
  max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000,
  ...body.host_policy_profile.capacity};
const cid = contentCid(body);
const environment = moon.clientProgramCheckEnvironmentWithGraphProfile(
  canonicalJson({...body, evidence_bundle_cid: cid}), cid,
  false, true, true, true, true, false, false,
  contentCid(await read('spec/contracts/actql-numeric-reduction.json')),
  contentCid(await read('spec/dependencies/actql-graph-laws.json')));
assert.notEqual(environment, undefined);
const publication = JSON.stringify({environmentCid: moon.clientProgramCheckingEnvironmentCid(environment), aliases: []});
assert.equal(moon.clientProgramSourcePublicationValid(environment, publication), true);
const observations = [];
for (const name of ['temporal-json-interval-left', 'temporal-sql-interval-left']) {
  const input = temporalJoinSourceSuccesses.find(value => value.name === name);
  const outcome = input.format === 'json'
    ? moon.clientProgramPrepareEffectFreeWithParameters(input.text, 'json', environment, undefined)
    : moon.clientProgramPrepareSourceWithParameters(input.text, input.format, environment, publication, undefined, undefined);
  const prepared = moon.clientProgramPreparationReady(outcome);
  assert.notEqual(prepared, undefined, moon.clientProgramPreparationIssueCode(outcome));
  const compiled = moon.clientProgramCompileLocalTasks(prepared);
  assert.equal(compiled.$tag, 1, 'original public task compilation');
  const view = moon.clientProgramTaskStaticPlanView(prepared, compiled._0, 1000000, 100000, 100);
  assert.equal(view.$tag, 1, 'original read-only static task view');
  observations.push({name, plan: JSON.parse(view._0)});
}
await writeFile(destination, JSON.stringify({artifactSource: manifest.sourceSha,
  compilerOnly: true, Host: 0, Run: 0, Source: 0, DB: 0, observations}, null, 2) + '\n', {flag: 'wx', mode: 0o600});
console.log(JSON.stringify({compilerControls: observations.length, artifactSource: manifest.sourceSha,
  Host: 0, Run: 0, Source: 0, DB: 0, complete: true}));
