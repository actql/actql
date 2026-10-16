// Project inputs from the public Quickstart. These files select no Host
// authority, signers, credential grants or runtime implementation.
const json = value => JSON.stringify(value, null, 2) + '\n';

export function projectTemplateFiles(template) {
  if (template !== undefined && template !== 'churn-risk-mock') {
    throw Object.assign(new Error('Unknown project template.'), {code: 'ACTQL_E_TEMPLATE', exitCode: 2});
  }
  const configuration = {version: 'actql-config/0.1', connectors: './connectors.json',
    model_tasks: './model-tasks.json', state_dir: './.actql'};
  if (template === undefined) return Object.freeze({
    'actql.config.json': json(configuration),
    'connectors.json': json({version: 'actql-connectors/0.1', connections: {}}),
    'model-tasks.json': json({version: 'actql-model-tasks/0.1', tasks: {}, providers: {}}),
  });
  return Object.freeze({
    'actql.config.json': json({...configuration, profile: 'mock', mock: {
      data: './mock/data.json',
      answers: {'model-task:churn-risk.v1': './mock/churn-risk.v1.answers.yaml'},
    }}),
    'connectors.json': json({version: 'actql-connectors/0.1', connections: {
      salesforce: {connector: 'salesforce'}, snowflake: {connector: 'snowflake'},
    }}),
    'model-tasks.json': json({version: 'actql-model-tasks/0.1',
      tasks: {'model-task:churn-risk.v1': './model-tasks/churn-risk.v1.yaml'},
      providers: {openai: {type: 'openai', api_key_env: 'OPENAI_API_KEY'}}, default_provider: 'openai'}),
    'model-tasks/churn-risk.v1.yaml': `task: model-task:churn-risk.v1
input:
  notes: string
  active_users: int64
  trend: string
instructions: |
  From the account notes, the number of active users and the usage trend,
  rate the churn risk as low, medium or high and explain why in one line.
  Do not assume facts that are not in the input.
output:
  level: {type: string, enum: [low, medium, high]}
  reason: string
`,
    'mock/data.json': json({salesforce: {Account: {key: ['id'], rows: [
      {id: '001Acme', name: 'Acme Corp', description: 'Evaluating a competitor; usage down since June.',
        Churn_Risk__c: 'low', Risk_Reason__c: null},
      {id: '001Globex', name: 'Globex Inc', description: 'Several support tickets about the new pricing.',
        Churn_Risk__c: 'medium', Risk_Reason__c: null},
    ]}}, snowflake: {usage_30d: {key: ['account_id'], rows: [
      {account_id: '001Acme', active_users: 4, trend: 'down'},
      {account_id: '001Globex', active_users: 12, trend: 'flat'},
    ]}}}),
    'mock/churn-risk.v1.answers.yaml': `task: model-task:churn-risk.v1
answers:
  default: { level: low, reason: "stable usage" }
  by_key:
    "001Acme":   { level: high, reason: "falling usage and a competitor evaluation" }
    "001Globex": { level: high, reason: "support tickets about pricing" }
`,
    'churn-risk.aql': `SELECT a.id AS id, a.description AS notes,
       u.active_users, u.trend
FROM salesforce.accounts AS a
JOIN snowflake.usage_30d AS u ON a.id = u.account_id
|> INFER \`model-task:churn-risk.v1\`
     INPUT (notes, active_users, trend) AS risk
|> WHERE risk.outcome = 'ok' AND risk.value.level = 'high'
|> RESULT updates
|> EFFECT UPDATE salesforce.Account
     ID id SET (
       Churn_Risk__c = risk.value.level,
       Risk_Reason__c = risk.value.reason
     );
`,
  });
}
