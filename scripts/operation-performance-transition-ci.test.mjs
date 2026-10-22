import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';

test('ordinary priority assessment reuses both platform reports without replacing release assessment', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs['ordinary-priority-assessment'];
  assert(job, 'The controlled lane must assess the ordinary Node/Python priority transition separately');
  assert.deepEqual(job.needs, ['ordinary-operations', 'ordinary-python']);
  assert(job.if.includes('always()'), 'Missing or failed collectors must still produce a failed/incomplete assessment');
  const expression = job.if.slice(3, -2).trim();
  for (const [enabled, visibility, privateFlag, expected] of [
    [undefined, 'public', false, false], ['false', 'public', false, false],
    ['true', 'private', true, false], ['true', 'public', true, false],
    ['true', 'public', undefined, false], ['true', 'public', false, true],
  ]) {
    assert.equal(runInNewContext(expression, {
      vars: {ACTQL_MAIN_CI_ENABLED: enabled},
      github: {event: {repository: {visibility, private: privateFlag}}},
      toJSON: JSON.stringify, always: () => true,
    }, {timeout: 100}), expected);
  }
  assert.deepEqual(workflow.jobs['ordinary-platform-assessment'].needs,
    ['ordinary-operations', 'ordinary-native', 'ordinary-python']);
  for (const name of ['ordinary-operations', 'ordinary-native', 'ordinary-python']) {
    const assessments = workflow.jobs[name].steps.filter(step =>
      step.run?.includes('scripts/operation-performance.mjs --input'));
    assert.equal(assessments.length, 1, `${name} must retain its full-release assessment`);
    assert.equal(assessments[0].if, 'always()');
    assert.equal(assessments[0]['continue-on-error'], undefined);
  }
});
