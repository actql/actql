import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {checkBackendSemanticBoundary, semanticBoundaryViolations} from './backend-semantic-boundary.mjs';

test('connectors and Local execution/preparation use resolved lowering contracts', () => {
  assert.ok(checkBackendSemanticBoundary() > 150);
});

test('isolated Local evaluator and preparation violations fail the complete gate', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-local-semantic-boundary-'));
  try {
    for (const name of [
      'physical_host', 'connector_sdk', 'connectors/duckdb/compute',
      'connectors/duckdb/driver', 'connectors/reference_compute',
      'connectors/reference_compute/driver', 'execution_relation',
      'local_sga', 'local_veca', 'local_tea', 'local_bridge',
      'local_sga_provider', 'local_veca_provider', 'local_tea_provider',
    ]) {
      const path = join(root, 'src', name);
      mkdirSync(path, {recursive: true});
      writeFileSync(join(path, 'pkg.generated.mbti'), '// neutral fixture API\n');
    }
    const engine = join(root, 'src/execution_relation');
    writeFileSync(join(engine, 'moon.pkg'), 'import { "actql/actql/lowering_relation" @semantic, "actql/actql/relation_typing" @front }');
    writeFileSync(join(engine, 'rows.mbt'), 'let fields = @semantic.kernel_dedupe_key_at(k, 0)');
    assert.equal(checkBackendSemanticBoundary(root), 1);
    writeFileSync(join(engine, 'rows.mbt'), 'let fields = @front.dedupe_key_at(@semantic.kernel_checked(k), 0)');
    assert.throws(() => checkBackendSemanticBoundary(root), /rows\.mbt: frontend semantic traversal/);
    writeFileSync(join(engine, 'rows.mbt'), '// normal evaluator');
    writeFileSync(join(engine, 'fragment_execution.mbt'), 'let op = @semantic.count_group_checked(group)');
    assert.throws(() => checkBackendSemanticBoundary(root), /fragment_execution\.mbt: frontend semantic traversal/);
  } finally {
    rmSync(root, {recursive: true, force: true});
  }
});

test('Local ownership exception cannot hide operation or schema reconstruction', () => {
  const aliases = new Map([['lower', 'lowering_relation'], ['pipeline', 'pipeline_typing'], ['op', 'relation_typing'], ['join', 'relation_join_shape']]);
  const owner = '@lower.pipeline(@lower.bound_preparation(receiver))';
  assert.deepEqual(semanticBoundaryViolations(owner, aliases, true), []);
  assert.deepEqual(semanticBoundaryViolations(owner, aliases), ['lower.pipeline']);
  assert.deepEqual(semanticBoundaryViolations(`${owner}; @op.dedupe_key_at(c, 0); @pipeline.step_at(p, 0); @join.assertion(j)`, aliases, true),
    ['op.dedupe_key_at', 'pipeline.step_at', 'join.assertion']);
  assert.deepEqual(semanticBoundaryViolations('@lower.kernel_dedupe_key_at(k, 0); @lower.projection_fields(p); @op.InputField(f)', aliases), []);
});

test('family kernels cannot re-read checked Carrier or operation semantics', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-family-semantic-boundary-'));
  try {
    for (const name of [
      'physical_host', 'connector_sdk', 'connectors/duckdb/compute',
      'connectors/duckdb/driver', 'connectors/reference_compute',
      'connectors/reference_compute/driver', 'execution_relation',
      'connectors', 'local_sga', 'local_veca', 'local_tea', 'local_bridge',
      'local_sga_provider', 'local_veca_provider', 'local_tea_provider',
    ]) {
      const directory = join(root, 'src', name);
      mkdirSync(directory, {recursive: true});
      writeFileSync(join(directory, 'pkg.generated.mbti'), '// fixture API\n');
      writeFileSync(join(directory, 'moon.pkg'),
        'import { "actql/actql/pipeline_typing" @checked, ' +
        '"actql/actql/lowering_relation" @typed }');
    }
    for (const name of [
      'local_sga', 'local_veca', 'local_tea', 'local_bridge',
      'local_sga_provider', 'local_veca_provider', 'local_tea_provider',
    ]) {
      const file = join(root, 'src', name, 'operation.mbt');
      writeFileSync(file,
        'let carrier = @typed.preparation_carrier_at(prepared, @checked.Step(0))');
      assert.ok(checkBackendSemanticBoundary(root) >= 1);
      writeFileSync(file,
        'let carrier = @checked.carrier_at(pipeline, @checked.Step(0))');
      assert.throws(() => checkBackendSemanticBoundary(root),
        /frontend semantic traversal: checked\.carrier_at/);
      writeFileSync(file, 'let pipeline = @typed.pipeline(prepared)');
      assert.throws(() => checkBackendSemanticBoundary(root),
        /frontend semantic traversal: typed\.pipeline/);
      writeFileSync(file, '// neutral family kernel');
    }
  } finally {
    rmSync(root, {recursive: true, force: true});
  }
});

test('renamed frontend imports and checked escape hatches are rejected', () => {
  const aliases = new Map([['other', 'pipeline_typing'], ['view', 'lowering_relation'], ['query', 'sourceview_resolution']]);
  assert.deepEqual(semanticBoundaryViolations('@other.step_at(p, 0); @view.kernel_checked(k); @query.query_acquisition_pipeline(q)', aliases),
    ['other.step_at', 'view.kernel_checked', 'query.query_acquisition_pipeline']);
  assert.deepEqual(semanticBoundaryViolations('// @other.step_at(p, 0)\nlet description = "@other.step_at(p, 0)"\n@view.node_output_schema(n)', aliases), []);
  assert.deepEqual(semanticBoundaryViolations('@other.Step(1); @view.kernel_body(k); @view.node_input_target(n, 0)', aliases), []);
});
