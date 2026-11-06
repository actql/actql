import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync, cpSync, rmSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {generateComputeAssembly, checkComputeAssembly} from './connector-compute-bundles.mjs';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';

const entry = name => ({name, manifest: JSON.parse(readFileSync(`src/connectors/${name}/compute-bundle.json`, 'utf8'))});

test('the packed external Compute declaration supplies its original binding validator', t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const fixtures = join(root, 'scripts/fixtures/external-compute');
  const external = mkdtempSync(join(realpathSync(tmpdir()), 'actql-packed-compute-declaration-'));
  t.after(() => rmSync(external, {recursive: true, force: true}));
  for (const name of ['external-numeric', 'compute-host']) cpSync(join(fixtures, name), join(external, name), {recursive: true});
  const buildInputs = resolveConnectorBuildInputs({target: 'js',
    modules: [
      {namespace: 'actql/actql', version: '0.0.1', root},
      {namespace: 'fixture/external_numeric', version: '0.0.1', root: join(external, 'external-numeric')},
      {namespace: 'fixture/compute_host', version: '0.0.1', root: join(external, 'compute-host')},
    ], host: 'fixture/compute_host',
    connectors: [{name: 'external_numeric', module: 'fixture/external_numeric', directory: 'src'}]});
  const generated = generateComputeAssembly(buildInputs.computeEntries, {buildInputs});
  assert.match(generated.source, /\.validate_binding\(installed, driver, registry\)/u);
  // The packed builder copies this shared helper into its foreign runtime and
  // merges the scenario imports. Keep the helper's actual typed dependency.
  const sharedFixture=readFileSync(join(root,'src/node_host_conformance/fixture.generated.mbt'),'utf8');
  assert.match(sharedFixture,/@pipeline\.Step\(index\)/u);
  assert.match(readFileSync(join(external,'compute-host/src/scenario/moon.pkg'),'utf8'),
    /"actql\/actql\/pipeline_typing"\s+@pipeline\s*,/u);
});

test('explicit composition never reads an unselected broken connector manifest', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-explicit-composition-'));
  mkdirSync(join(root, 'src/connectors/local/driver'), {recursive:true});
  mkdirSync(join(root, 'src/connectors/duckdb'), {recursive:true});
  writeFileSync(join(root, 'src/connectors/local/compute-bundle.json'), JSON.stringify(entry('local').manifest));
  writeFileSync(join(root, 'src/connectors/local/driver/moon.pkg'), '');
  writeFileSync(join(root, 'src/connectors/duckdb/compute-bundle.json'), 'invalid unselected declaration');
  const options = {names:['local'], directory:'connectors_workers'};
  assert.equal(checkComputeAssembly(root, true, options), 1);
  assert.equal(checkComputeAssembly(root, false, options), 1);
  assert.doesNotMatch(readFileSync(join(root, 'src/connectors_workers/moon.pkg'), 'utf8'), /duckdb|reference_compute/);
  assert.throws(() => checkComputeAssembly(root, false), /JSON|Unexpected/);
  assert.throws(() => checkComputeAssembly(root, true, {...options, names:['missing']}), /Missing selected/);
  assert.throws(() => checkComputeAssembly(root, true, {...options, names:['local', 'local']}), /Invalid explicit/);
});

test('typed assembly is reproducible from connector declarations', () => {
  assert.equal(checkComputeAssembly(process.cwd()), 3);
  const generated = generateComputeAssembly([entry('duckdb'), entry('local')]);
  assert.match(generated.source, /with_local\?.*= None/);
  assert.match(generated.source, /registry_order=true/);
  assert.doesNotMatch(generated.source, /numeric|reference_compute|SQL|session|\.name/);
});

test('independent Compute declaration extends composition without a generator branch', () => {
  const base = [entry('duckdb'), entry('local')];
  const generated = generateComputeAssembly([...base, entry('reference_compute')]);
  assert.match(generated.source, /with_reference_compute\?/);
  assert.match(generated.source, /\.numeric_compute_contribution\(/);
  assert.match(generated.source, /\.configure_numeric_compute\(/);
  assert.match(generated.source, /configured_reference_compute_module/);
  assert.match(generated.source, /dispatch_reference_compute/);
  assert.match(generated.source, /\.execute_numeric_contribution\(/);
  assert.match(generated.source, /MissingImplementation/);
  assert.match(generated.source, /prepare_local_estimate_policy/);
  assert.match(generated.source, /prepare_duckdb_resource_policy/);
  assert.doesNotMatch(generated.source, /prepare_reference_compute_estimate_policy/);
  assert.match(generated.manifest, /connectors\/reference_compute\/driver/);
  const code = readFileSync('scripts/connector-compute-bundles.mjs', 'utf8');
  assert.doesNotMatch(code, /duckdb|reference_compute|LocalDispatch|NumericCompute/);
  assert.deepEqual(base.map(value => value.name), ['duckdb', 'local']);
});

test('asynchronous dispatch and optional no-I/O dispatch remain separate typed entrypoints', () => {
  const local = entry('local');
  const both = generateComputeAssembly([local]).source;
  assert.match(both, /LocalDispatchOperations/);
  assert.match(both, /\.start_local_dispatch\(/);
  assert.match(both, /\.execute_local_dispatch\(/);
  const manifest = {...local.manifest};
  delete manifest.synchronous_dispatch;
  const asynchronous = generateComputeAssembly([{...local, manifest}]).source;
  assert.match(asynchronous, /\.start_local_dispatch\(/);
  assert.doesNotMatch(asynchronous, /\.execute_local_dispatch\(/);
});

test('declarations cannot inject code or move implementation ownership into core', () => {
  const good = entry('local');
  for (const update of [
    {package: 'actql/actql/physical_host'},
    {package: 'actql/actql/connectors/duckdb/driver'},
    {module: 'LocalDispatchModule); abort()'},
    {contribution: 'prepare(); execute'},
    {configure: 'prepare(); execute'},
    {validate_binding: 'validate(); execute'},
    {validate_binding: null},
    {configuration: 'Any[Unsafe]'},
    {dispatch: 'execute(); abort'},
    {synchronous_dispatch: 'execute(); abort'},
    {synchronous_dispatch: null},
    {dispatch_result: 'Any'},
    {dispatch_result: []},
    {dispatch_result: [{package: good.manifest.package, type: 'Result'}]},
    {dispatch_result: {package: good.manifest.package, type: 'Result); abort()'}},
    {extra: true},
    {estimate_policy: {configuration: 'Settings', prepare: 'prepare', install: 'install(); execute', work_slots: 'slots'}},
    {resource_policy: {configuration: 'Settings', prepare: 'prepare', install: 'install', work_slots: 'slots', extra: true}},
    {dispatch_error: {package: '../../elsewhere', type: 'Issue'}},
    {estimate_error: {package: good.manifest.package, type: 'Issue', extra: true}},
    {managed_start_error: {package: '../../elsewhere', type: 'Issue'}},
    {managed_start_error: {package: good.manifest.package, type: 'Issue); abort()'}},
    {managed_start_error: {package: good.manifest.package, type: 'Issue', extra: true}},
  ]) {
    assert.throws(() => generateComputeAssembly([{...good, manifest: {...good.manifest, ...update}}]));
  }
  assert.throws(() => generateComputeAssembly([good, good]));
});

test('managed start has an explicit error type independent of dispatch', () => {
  const reference = entry('reference_compute');
  assert.notDeepEqual(reference.manifest.managed_start_error,
    reference.manifest.dispatch_error);
  assert.doesNotThrow(() => generateComputeAssembly([reference]));
  for (const key of ['managed_start', 'managed_start_result', 'managed_start_error']) {
    const manifest = {...reference.manifest};
    delete manifest[key];
    assert.throws(() => generateComputeAssembly([{...reference, manifest}]),
      /declaration/);
  }
});


test('prepared assembly validates original bindings and reuses the common wrapper without a second configure', () => {
  const source = generateComputeAssembly([entry('local'), entry('reference_compute')]).source;
  const start = source.indexOf('pub fn[E] assemble_configured_compute_modules(');
  const end = source.indexOf('pub fn[E] configure_compute_modules(', start);
  assert(start >= 0 && end > start);
  const prepared = source.slice(start, end);
  assert.match(prepared, /validate_local_dispatch_binding\(installed, driver, registry\)/);
  assert.match(prepared, /validate_numeric_contribution_binding\(installed, driver, registry\)/);
  assert.match(prepared, /assemble_compute_contributions\(/);
  assert.doesNotMatch(prepared, /configure_local_compute|configure_numeric_compute|prepare_local/);
  assert.match(source.slice(end), /assemble_configured_compute_modules\(driver, registry, max_entries, installation_issue,/);
});
