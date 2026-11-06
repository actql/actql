// A test-only continuation of the unchanged public deal-review Project.
// Both original Mock Tasks run through the installed Host; this fixture only
// authors their inputs and answers, never invokes a Model or an Effect itself.
import assert from 'node:assert/strict';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';

export function twoModelDealReviewFiles() {
  const files = {...projectTemplateFiles('deal-review-mock')};
  const task = 'model-task:deal-review-confirm.v1';
  const config = JSON.parse(files['actql.config.json']);
  config.mock.answers[task] = './mock/deal-review-confirm.v1.answers.yaml';
  files['actql.config.json'] = JSON.stringify(config, null, 2) + '\n';
  const registry = JSON.parse(files['model-tasks.json']);
  registry.tasks[task] = './model-tasks/deal-review-confirm.v1.yaml';
  files['model-tasks.json'] = JSON.stringify(registry, null, 2) + '\n';
  files['model-tasks/deal-review-confirm.v1.yaml'] = `task: ${task}
input:
  changed: {type: boolean, nullable: true}
  stage: {type: string, nullable: true}
  next_step: {type: string, nullable: true}
instructions: |
  Check only the first review's proposed change, stage and next step supplied
  in this input. Confirm it and repeat the exact stage and next step.
output:
  confirmed: boolean
  stage: string
  next_step: string
`;
  files['mock/deal-review-confirm.v1.answers.yaml'] = `task: ${task}
answers:
  default: {confirmed: false, stage: "", next_step: ""}
  by_key:
    "006Acme": {confirmed: true, stage: Negotiation, next_step: "Send revised pricing by Friday"}
    "006Globex": {confirmed: true, stage: "Closed Lost", next_step: "Revisit next fiscal year"}
`;
  const boundary = "|> WHERE review.outcome = 'ok' AND review.value.changed\n";
  assert.equal(files['deal-review.aql'].split(boundary).length, 2);
  files['deal-review.aql'] = files['deal-review.aql'].replace(boundary, boundary +
    `|> INFER \`${task}\`
     INPUT (changed = review.value.changed, stage = review.value.stage,
            next_step = review.value.next_step) AS confirmation
|> WHERE confirmation.outcome = 'ok' AND confirmation.value.confirmed
`);
  return Object.freeze(files);
}
