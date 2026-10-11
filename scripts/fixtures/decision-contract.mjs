// Independent authored contracts and answers; never use provider/product output.
const text = {type: 'string', nullable: false};
const number = {type: 'number', nullable: false};
const object = fields => ({type: 'object', nullable: false,
  additional_properties: false, fields: Object.fromEntries(fields)});
const distribution = (identity, type) => ({type: 'array', nullable: true,
  items: object([[identity, type], ['probability', number]])});

export const decisionPayload = {
  format: 'actql.decision_prompt/0.1', state_input: 'state', questions: [
    {id: '__proto__', type: 'choice', instructions: 'Choose a routing label.\r\ne\u0301',
      options: ['toString', '__proto__', 'constructor'].map(id => ({id, description: id}))},
    {id: 'constructor', type: 'score', instructions: 'Score the state.',
      levels: ['low', 'medium', 'high']},
    {id: 'enabled', type: 'boolean', instructions: 'P(true) for eligibility.'},
  ],
};
export const decisionInput = object([['state', {type: 'json', nullable: true}]]);
export const decisionOutput = object([
  ['__proto__', object([['choice', text], ['probabilities', distribution('option', text)]])],
  ['constructor', object([['score', number], ['probabilities', distribution('level', number)]])],
  ['enabled', object([['probability', number]])],
]);
export const decisionTaskCore = {
  schema: 'actql.model_task/0.2', task_id: 'model-task:decision-fixture', version: '1',
  connector_id: 'models/fixture', task_kind: 'decision', authored_model_selector: 'fixture-native',
  input_contract: decisionInput, output_contract: decisionOutput,
  decision_config: {answer_profile: 'actql.decision_answers/0.1',
    probability_source: 'native', distribution_policy: 'required_for_choice_and_score'},
  tool_policy: 'none', retrieval_policy: 'none', streaming: false,
  data_handling: {contract_cid: 'sha256:' + 'a'.repeat(64),
    accepted_classifications: ['public'], training_use: 'forbidden', retention: 'none',
    allowed_regions: ['fixture']}, max_items: 4,
};
export const goodAnswers = Object.fromEntries([
  ['__proto__', {choice: 'toString', probabilities: [
    {option: 'toString', probability: 0.33}, {option: '__proto__', probability: 0.33},
    {option: 'constructor', probability: 0.33}]}],
  ['constructor', {score: 1, probabilities: [
    {level: 0, probability: 0.33}, {level: 1, probability: 0.33},
    {level: 2, probability: 0.33}]}],
  ['enabled', {probability: 0.5}],
]);
const changed = edit => {const value = structuredClone(goodAnswers); edit(value); return value;};
export const answerCases = [
  ['rounded native distribution', goodAnswers, null],
  ['tie retains chosen member', changed(v => {v.__proto__.choice = 'constructor';}), null],
  ['zero and one', changed(v => {v.enabled.probability = 0;
    v.__proto__.probabilities.forEach((p, i) => {p.probability = i === 0 ? 1 : 0;});}), null],
  ['fractional weighted score', changed(v => {v.constructor.score = 0.75;
    v.constructor.probabilities = [{level: 0, probability: 0.5},
      {level: 1, probability: 0.25}, {level: 2, probability: 0.25}];
    v.enabled.probability = 1;}), null],
  ['unknown chosen option', changed(v => {v.__proto__.choice = 'unknown';}), 'ChoiceMaximum'],
  ['nonmaximal chosen option', changed(v => {v.__proto__.probabilities = [
    {option: 'toString', probability: 0.2}, {option: '__proto__', probability: 0.4},
    {option: 'constructor', probability: 0.4}];}), 'ChoiceMaximum'],
  ['sum too low', changed(v => {v.__proto__.probabilities[0].probability = 0.32;}), 'Distribution'],
  ['grid violation', changed(v => {v.enabled.probability = 0.501;}), 'Precision'],
  ['boolean is not probability', changed(v => {v.enabled.probability = true;}), 'InvalidAnswer'],
  ['negative probability', changed(v => {v.enabled.probability = -0.01;}), 'InvalidAnswer'],
  ['probability exceeds one', changed(v => {v.enabled.probability = 1.01;}), 'InvalidAnswer'],
  ['missing question', changed(v => {delete v.enabled;}), 'InvalidAnswer'],
  ['extra question', changed(v => {v.extra = {probability: 0};}), 'InvalidAnswer'],
  ['unknown answer member', changed(v => {v.enabled.confidence = 1;}), 'InvalidAnswer'],
  ['absent required distribution', changed(v => {delete v.__proto__.probabilities;}), 'InvalidAnswer'],
  ['NULL required distribution', changed(v => {v.__proto__.probabilities = null;}), 'InvalidAnswer'],
  ['missing option', changed(v => {v.__proto__.probabilities.pop();}), 'InvalidAnswer'],
  ['extra option', changed(v => {v.__proto__.probabilities.push({option: 'extra', probability: 0});}), 'InvalidAnswer'],
  ['duplicate option', changed(v => {v.__proto__.probabilities[1].option = 'toString';}), 'InvalidAnswer'],
  ['reordered options', changed(v => {v.__proto__.probabilities.reverse();}), 'InvalidAnswer'],
  ['level not integral', changed(v => {v.constructor.probabilities[1].level = 1.5;}), 'InvalidAnswer'],
  ['duplicate level', changed(v => {v.constructor.probabilities[1].level = 0;}), 'InvalidAnswer'],
  ['score out of range', changed(v => {v.constructor.score = 2.01;}), 'InvalidAnswer'],
  ['score inconsistent', changed(v => {v.constructor.score = 1.02;}), 'ScoreConsistency'],
  ['score precision', changed(v => {v.constructor.score = 1.001;}), 'Precision'],
  ['grid floating-error boundary', changed(v => {v.enabled.probability = 0.500000000001;}), null],
  ['next grid representation outside', changed(v => {v.enabled.probability = 0.5000000000010001;}), 'Precision'],
];
