// Issue #1350's independent Program is deliberately operation-free in main.
// Expected rows and columns are authored here, never read from a compiler.
export const inputStageResultProgram = {
  version: 'actql/0.1', id: 'fixture.identity_stage_result',
  stages: [
    {id: 'producer', inputs: {}, steps: [{values: {
      schema: {A: {type: 'number', nullable: false}}, rows: [{A: 0}],
    }, as: 'out'}], results: {rows: {from: 'out', fields: ['A']}}},
    {id: 'main', inputs: {source: {result: {stage: 'producer', result: 'rows'}}},
      steps: [], results: {rows: {from: 'source', fields: ['A']}}},
  ], results: {answer: {from: {stage: 'main', result: 'rows'}}},
};
const columns = [{name: 'A', contract: {type: 'number', nullable: false}}];
const empty = structuredClone(inputStageResultProgram);
empty.id = 'fixture.identity_stage_empty';
empty.stages[0].steps[0].values.rows = [];
const shared = structuredClone(inputStageResultProgram);
shared.id = 'fixture.identity_stage_shared';
shared.stages[0].steps[0].values.rows = [{A: 2}, {A: 0}, {A: 2}];
shared.stages.push({...structuredClone(shared.stages[1]), id: 'other'});
shared.results.second = {from: {stage: 'other', result: 'rows'}};
export const inputStageResultSuccesses = [
  {name: 'input-stage-result-issue-1350', format: 'json',
    text: JSON.stringify(inputStageResultProgram), sourceReadCount: 0,
    results: {answer: {rows: [{A: 0}], columns}}},
  {name: 'input-stage-result-empty', format: 'json', text: JSON.stringify(empty),
    sourceReadCount: 0, results: {answer: {rows: [], columns}}},
  {name: 'input-stage-result-shared-two-consumers', format: 'json',
    text: JSON.stringify(shared), sourceReadCount: 0,
    results: Object.fromEntries(['answer', 'second'].map(name =>
      [name, {rows: [{A: 0}, {A: 2}, {A: 2}], columns}]))},
];
