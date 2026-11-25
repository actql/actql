// Fixture DATA only. Registered metadata is distinct from selected Model work.
import assert from 'node:assert/strict';
import {twoModelDealReviewFiles} from './deal-review-two-models.mjs';
import type {ModelTaskRegistry} from './deal-review-two-models.mjs';

export const modelRegistryCount = 129;
export function modelRegistrationProjectFiles() {
  const files = {...twoModelDealReviewFiles()};
  const registry = JSON.parse(files['model-tasks.json']) as ModelTaskRegistry;
  for (let index = 0; index < modelRegistryCount - 2; index++) {
    const name = `model-task:registration-${String(index).padStart(3, '0')}.v1`;
    const path = `model-tasks/registration-${index}.yaml`;
    registry.tasks[name] = './' + path;
    files[path] = `task: ${name}\ninput:\n  text: string\noutput:\n  enabled: boolean\ninstructions: Read only the supplied text.\n`;
  }
  files['model-tasks.json'] = JSON.stringify(registry, null, 2) + '\n';
  assert.equal(Object.keys(registry.tasks).length, modelRegistryCount);
  return Object.freeze(files);
}
