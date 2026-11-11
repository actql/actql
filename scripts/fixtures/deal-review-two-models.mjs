// A test-only continuation of the unchanged public deal-review Project.
// Both original Mock Tasks run through the installed Host; this fixture only
// authors their inputs and answers, never invokes a Model or an Effect itself.
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../adapters/host-node/local-account-config.mjs';
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
  files['deal-review.program.json'] = JSON.stringify(twoModelDealReviewProgram(files), null, 2) + '\n';
  return Object.freeze(files);
}

// A distinct ordinary consumer: the first Model imports a real completed
// Whole Source Unit, while its files/Content reads remain in the Model Unit.
// Public roots expose both original Models and the separate producer so the
// consumer must read every declared Result, including on cold Saved recovery.
export function twoModelWholeDealReviewFiles() {
  const files = {...twoModelDealReviewFiles()};
  const program = JSON.parse(files['deal-review.program.json']);
  const fields = ['id', 'name', 'StageName', 'NextStep'];
  program.id = 'fixture.deal-review-dependent-models-whole';
  program.stages[0].inputs.opportunities = {result: {stage: 'source_opportunities', result: 'rows'}};
  program.stages.unshift({id: 'source_opportunities', inputs: {
    opportunities: {connector: 'salesforce', resource: 'Opportunity'},
  }, from: 'opportunities', steps: [{select: fields, as: 'original'}],
  results: {rows: {from: 'original', fields}}});
  program.results = {
    answer: {from: {stage: 'source_opportunities', result: 'rows'}},
    main: {from: {stage: 'review', result: 'rows'}},
    ...program.results,
  };
  files['deal-review.program.json'] = JSON.stringify(program, null, 2) + '\n';
  return Object.freeze(files);
}

// Independently authored structured Program. A Pipe does not create a Unit:
// the second Model consumes the retained first Stage Result in the SAME Run.
// The MappingRef is closed declaration DATA under the existing mapping
// request preimage; it selects no installation, authority or accepted write.
export function twoModelDealReviewProgram(files) {
  const catalog = JSON.parse(files['mock/catalog.json']);
  const view = catalog.connections.salesforce.views.find(value => value.resource === 'Opportunity');
  const targetSchema = {type: 'object', nullable: false, additional_properties: false, fields: view.schema};
  const request = {resource: 'Opportunity', kind: 'update', key: null, target_schema: targetSchema,
    write_fields: ['NextStep', 'StageName'], row_mapping: {
      StageName: {field: 'StageName', null_behavior: 'reject'},
      NextStep: {field: 'NextStep', null_behavior: 'reject'}}};
  const mapping = 'mapping:salesforce/Opportunity/update-' +
    createHash('sha256').update(canonicalJson(request)).digest('hex').slice(0, 16) + '.v1';
  const field = name => ({field: name});
  const property = (name, key) => ({property: {value: field(name), name: key}});
  const fields = ['id', 'StageName', 'NextStep', 'review'];
  return {version: 'actql/0.1', id: 'fixture.deal-review-dependent-models', stages: [
    {id: 'review', inputs: {
      opportunities: {connector: 'salesforce', resource: 'Opportunity'},
      files: {connector: 'drive', resource: 'files', request: {paths: null, glob: null}},
      contents: {connector: 'drive', resource: 'contents'},
    }, from: 'opportunities', steps: [
      {join: {with: 'files', kind: 'inner', on: [{left: 'name', right: 'name'}], select: {
        id: 'left.id', StageName: 'left.StageName', NextStep: 'left.NextStep',
        resource: 'right.resource', version: 'right.version'}}},
      {join: {with: 'contents', kind: 'inner', on: [{left: 'resource', right: 'resource'},
        {left: 'version', right: 'version'}], select: {
        id: 'left.id', StageName: 'left.StageName', NextStep: 'left.NextStep', notes: 'right.content'}}},
      {assert_rows: {unique_by: ['id']}, as: 'original'},
      {infer: {contract: 'model-task:deal-review.v1', key: 'id', input: {
        StageName: field('StageName'), NextStep: field('NextStep'), notes: field('notes')}}, as: 'assessment'},
      {join: {with: 'original', kind: 'inner', cardinality: 'one_to_one', on: [{left: 'id', right: 'id'}],
        select: {id: 'right.id', StageName: 'right.StageName', NextStep: 'right.NextStep',
          outcome: 'left.outcome', value: 'left.value'}}},
      {derive: {review: {object: {outcome: field('outcome'), value: field('value')}}}},
      {filter: {and: [{eq: [field('outcome'), {literal: 'ok'}]}, property('value', 'changed')]}},
      {select: fields, as: 'reviewed'},
    ], results: {rows: {from: 'reviewed', fields}}},
    {id: 'confirm', inputs: {reviewed: {result: {stage: 'review', result: 'rows'}}}, steps: [
      {assert_rows: {unique_by: ['id']}, as: 'original'},
      {infer: {contract: 'model-task:deal-review-confirm.v1', key: 'id', input: {
        changed: {property: {value: property('review', 'value'), name: 'changed'}},
        stage: {property: {value: property('review', 'value'), name: 'stage'}},
        next_step: {property: {value: property('review', 'value'), name: 'next_step'}}}}, as: 'assessment'},
      {join: {with: 'original', kind: 'inner', cardinality: 'one_to_one', on: [{left: 'id', right: 'id'}],
        select: {id: 'right.id', StageName: 'right.StageName', NextStep: 'right.NextStep', review: 'right.review',
          outcome: 'left.outcome', value: 'left.value'}}},
      {derive: {confirmation: {object: {outcome: field('outcome'), value: field('value')}}}},
      {filter: {and: [{eq: [field('outcome'), {literal: 'ok'}]}, property('value', 'confirmed')]}},
      {select: [...fields, 'confirmation'], as: 'confirmed'},
    ], results: {rows: {from: 'confirmed', fields: [...fields, 'confirmation']}}},
    {id: 'apply', inputs: {confirmed: {result: {stage: 'confirm', result: 'rows'}}},
      steps: [
        {derive: {
          next_stage: {property: {value: property('review', 'value'), name: 'stage'}},
          next_step: {property: {value: property('review', 'value'), name: 'next_step'}}}},
        {select: [...fields, 'confirmation', 'next_stage', 'next_step'], as: 'effect_input'},
        {select: [...fields, 'confirmation'], as: 'updates'},
      ], results: {
        rows: {from: 'updates', fields: [...fields, 'confirmation']},
        effect_input: {from: 'effect_input', fields: [...fields, 'confirmation', 'next_stage', 'next_step']},
      }, effects: {save: {update: {target: 'connector://salesforce/Opportunity', mapping,
        from: {result: 'effect_input'}, id: 'id', set: {
          StageName: field('next_stage'), NextStep: field('next_step')}}}}},
  ], results: {updates: {from: {stage: 'apply', result: 'rows'}}}};
}
