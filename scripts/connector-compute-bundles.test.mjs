import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {generateComputeAssembly, checkComputeAssembly} from './connector-compute-bundles.mjs';

const entry = name => ({name, manifest: JSON.parse(readFileSync(`src/connectors/${name}/compute-bundle.json`, 'utf8'))});

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
  assert.match(generated.source, /\.start_numeric_contribution\(/);
  assert.match(generated.source, /MissingImplementation/);
  assert.match(generated.manifest, /connectors\/reference_compute\/driver/);
  const code = readFileSync('scripts/connector-compute-bundles.mjs', 'utf8');
  assert.doesNotMatch(code, /duckdb|reference_compute|LocalDispatch|NumericCompute/);
  assert.deepEqual(base.map(value => value.name), ['duckdb', 'local']);
});

test('declarations cannot inject code or move implementation ownership into core', () => {
  const good = entry('local');
  for (const update of [
    {package: 'actql/actql/physical_host'},
    {package: 'actql/actql/connectors/duckdb/driver'},
    {module: 'LocalDispatchModule); abort()'},
    {contribution: 'prepare(); execute'},
    {configure: 'prepare(); execute'},
    {configuration: 'Any[Unsafe]'},
    {dispatch: 'execute(); abort'},
    {dispatch_result: 'Any'},
    {dispatch_result: []},
    {dispatch_result: [{package: good.manifest.package, type: 'Result'}]},
    {dispatch_result: {package: good.manifest.package, type: 'Result); abort()'}},
    {extra: true},
    {dispatch_error: {package: '../../elsewhere', type: 'Issue'}},
    {estimate_error: {package: good.manifest.package, type: 'Issue', extra: true}},
  ]) {
    assert.throws(() => generateComputeAssembly([{...good, manifest: {...good.manifest, ...update}}]));
  }
  assert.throws(() => generateComputeAssembly([good, good]));
});
