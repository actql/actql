import assert from 'node:assert/strict';
import test from 'node:test';
import {checkBackendSemanticBoundary, semanticBoundaryViolations} from './backend-semantic-boundary.mjs';

test('all connector semantic readers use resolved lowering contracts', () => {
  assert.ok(checkBackendSemanticBoundary() > 50);
});

test('renamed frontend imports and checked escape hatches are rejected', () => {
  const aliases = new Map([['other', 'pipeline_typing'], ['view', 'lowering_relation'], ['query', 'sourceview_resolution']]);
  assert.deepEqual(semanticBoundaryViolations('@other.step_at(p, 0); @view.kernel_checked(k); @query.query_acquisition_pipeline(q)', aliases),
    ['other.step_at', 'view.kernel_checked', 'query.query_acquisition_pipeline']);
  assert.deepEqual(semanticBoundaryViolations('// @other.step_at(p, 0)\nlet description = "@other.step_at(p, 0)"\n@view.node_output_schema(n)', aliases), []);
  assert.deepEqual(semanticBoundaryViolations('@other.Step(1); @view.kernel_body(k); @view.node_input_target(n, 0)', aliases), []);
});
