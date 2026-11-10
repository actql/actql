// Project inputs from the public examples. These files select no Host
// authority, signers, credential grants or runtime implementation.
const json = value => JSON.stringify(value, null, 2) + '\n';

export function projectTemplateFiles(template) {
  if (template !== undefined && !['churn-risk-mock', 'deal-review-mock'].includes(template)) {
    throw Object.assign(new Error('Unknown project template.'), {code: 'ACTQL_E_TEMPLATE', exitCode: 2});
  }
  const configuration = {version: 'actql-config/0.1', connectors: './connectors.json',
    model_tasks: './model-tasks.json', state_dir: './.actql'};
  if (template === undefined) return Object.freeze({
    'actql.config.json': json(configuration),
    'connectors.json': json({version: 'actql-connectors/0.1', connections: {}}),
    'model-tasks.json': json({version: 'actql-model-tasks/0.1', tasks: {}, providers: {}}),
  });
  if (template === 'deal-review-mock') return Object.freeze({
    'actql.config.json': json({...configuration, profile: 'mock', mock: {
      catalog: './mock/catalog.json', data: './mock/data.json',
      answers: {'model-task:deal-review.v1': './mock/deal-review.v1.answers.yaml'},
    }}),
    'connectors.json': json({version: 'actql-connectors/0.1', connections: {
      salesforce: {connector: 'salesforce'}, drive: {connector: 'drive'},
    }}),
    'model-tasks.json': json({version: 'actql-model-tasks/0.1',
      tasks: {'model-task:deal-review.v1': './model-tasks/deal-review.v1.yaml'},
      providers: {openai: {type: 'openai', api_key_env: 'OPENAI_API_KEY'}}, default_provider: 'openai'}),
    // Raw fixture documents only. Resource and ContentRef issuance remains in
    // the selected Source/Content Owners; file names are not declared keys.
    'model-tasks/deal-review.v1.yaml': "task: model-task:deal-review.v1\ninput:\n  StageName: string\n  NextStep: {type: string, nullable: true}\n  notes: {type: content_ref, nullable: false}\ninstructions: |\n  Review only the current stage, current next step and the captured meeting\n  notes supplied for this deal. State whether the notes establish a change.\n  When they do, return the new stage and one specific next step supported by\n  those notes. Do not invent facts, external context or another document.\noutput:\n  changed: boolean\n  stage: string\n  next_step: string\n",
    'mock/catalog.json': json({connections: {
      salesforce: {
        views: [{resource: 'Opportunity', resource_kind: 'record', data_classification: 'internal', schema: {
          id: {type: 'string', nullable: false}, name: {type: 'string', nullable: false},
          StageName: {type: 'string', nullable: false}, NextStep: {type: 'string', nullable: true},
        }, facts: {relation_keys: {candidate_keys: [['id']]}}}],
        query_aliases: [{name: 'salesforce.opportunities', resource: 'Opportunity'}],
        data: [{resource: 'Opportunity', items_path: ['salesforce', 'Opportunity', 'rows'],
          key_path: ['salesforce', 'Opportunity', 'key'], primary_identity: 'id'}],
        writes: [{resource: 'Opportunity', primary_identity: 'id',
          writable_fields: ['StageName', 'NextStep'], permission: 'salesforce:record:update',
          observe_permission: 'salesforce:record:observe', approval: 'required',
          aliases: ['salesforce.Opportunity']}],
      },
      drive: {
        views: [{resource: 'files', resource_kind: 'file', data_classification: 'internal', schema: {
          resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
          version: {type: 'string', nullable: false}, name: {type: 'string', nullable: false},
          path: {type: 'string', nullable: true}, media_type: {type: 'string', nullable: true},
          size_bytes: {type: 'number', nullable: true}, modified_at: {type: 'timestamp', nullable: true},
        }, request_schema: {type: 'object', nullable: false, additional_properties: false, fields: {
          paths: {type: 'array', nullable: true, items: {type: 'string', nullable: false}},
          glob: {type: 'string', nullable: true},
        }}, acquisition: {kind: 'scan', authority: 'read_metadata'}},
        {resource: 'contents', resource_kind: 'file', data_classification: 'internal', schema: {
          resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
          version: {type: 'string', nullable: false},
          content: {type: 'content_ref', media_type: 'text/plain', nullable: false},
        }, request_schema: {type: 'object', nullable: false, additional_properties: false, fields: {
          resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
          version: {type: 'string', nullable: false},
        }}, acquisition: {kind: 'fetch', authority: 'read_content', correlation: {
          request_fields: ['resource', 'version'], response_fields: ['resource', 'version'],
          identity: ['resource', 'version'], cardinality: 'one',
        }}}],
        query_aliases: [{name: 'drive.files', resource: 'files', request: {paths: null, glob: null}},
          {name: 'drive.contents', resource: 'contents'}],
        data: [{resource: 'files', items_path: ['drive', 'files', 'rows'],
          key_path: ['drive', 'files', 'key'], primary_identity: 'id', schema: {
            id: {type: 'string', nullable: false}, name: {type: 'string', nullable: false},
            version: {type: 'string', nullable: false}, media_type: {type: 'string', nullable: false},
            content_utf8: {type: 'string', nullable: false},
          }}],
        file_bindings: [{listing_resource: 'files', content_resource: 'contents', data_resource: 'files',
          identity_field: 'id', name_field: 'name', version_field: 'version',
          media_type_field: 'media_type', content_utf8_field: 'content_utf8'}],
      },
    }}),
    'mock/data.json': json({"salesforce":{"Opportunity":{"key":["id"],"rows":[{"id":"006Acme","name":"Acme Corp - Renewal","StageName":"Proposal","NextStep":null},{"id":"006Globex","name":"Globex - Expansion","StageName":"Negotiation","NextStep":"Legal review"}]}},"drive":{"files":{"key":["id"],"rows":[{"id":"file-acme-notes","name":"Acme Corp - Renewal","version":"mock-revision-acme-1","media_type":"text/plain","content_utf8":"Acme renewal meeting: move the deal to Negotiation. Send revised pricing by Friday.\n"},{"id":"file-globex-notes","name":"Globex - Expansion","version":"mock-revision-globex-1","media_type":"text/plain","content_utf8":"Globex expansion meeting: the deal is Closed Lost for this year. Revisit next fiscal year.\n"}]}}}),
    'mock/deal-review.v1.answers.yaml': "task: model-task:deal-review.v1\nanswers:\n  default: {changed: false, stage: Proposal, next_step: \"\"}\n  by_key:\n    \"006Acme\": {changed: true, stage: Negotiation, next_step: \"Send revised pricing by Friday\"}\n    \"006Globex\": {changed: true, stage: \"Closed Lost\", next_step: \"Revisit next fiscal year\"}\n",
    'deal-review.aql': "SELECT o.id AS id, o.StageName, o.NextStep,\n       c.content AS notes\nFROM salesforce.opportunities AS o\nJOIN drive.files AS f ON f.name = o.name\nJOIN drive.contents AS c USING (resource, version)\n|> ASSERT UNIQUE BY (id)\n|> INFER `model-task:deal-review.v1`\n     INPUT (StageName, NextStep, notes) AS review\n|> WHERE review.outcome = 'ok' AND review.value.changed\n|> RESULT updates\n|> EFFECT UPDATE salesforce.Opportunity\n     ID id SET (\n       StageName = review.value.stage,\n       NextStep = review.value.next_step\n     );\n",
  });
  return Object.freeze({
    'actql.config.json': json({...configuration, profile: 'mock', mock: {
      catalog: './mock/catalog.json', data: './mock/data.json',
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
    'mock/catalog.json': json({connections: {
      salesforce: {
        views: [{resource: 'Account', resource_kind: 'record', data_classification: 'internal', schema: {
          id: {type: 'string', nullable: false}, name: {type: 'string', nullable: false},
          description: {type: 'string', nullable: false},
          Churn_Risk__c: {type: 'string', nullable: false}, Risk_Reason__c: {type: 'string', nullable: true},
        }, facts: {relation_keys: {candidate_keys: [['id']]}}}],
        query_aliases: [{name: 'salesforce.accounts', resource: 'Account'}],
        data: [{resource: 'Account', items_path: ['salesforce', 'Account', 'rows'],
          key_path: ['salesforce', 'Account', 'key'], primary_identity: 'id'}],
        writes: [{resource: 'Account', primary_identity: 'id',
          writable_fields: ['Churn_Risk__c', 'Risk_Reason__c'], permission: 'salesforce:record:update',
          observe_permission: 'salesforce:record:observe', approval: 'required',
          aliases: ['salesforce.Account']}],
      },
      snowflake: {
        views: [{resource: 'usage_30d', resource_kind: 'table', data_classification: 'internal', schema: {
          account_id: {type: 'string', nullable: false}, active_users: {type: 'int64', nullable: false},
          trend: {type: 'string', nullable: false},
        }, facts: {relation_keys: {candidate_keys: [['account_id']]}}}],
        query_aliases: [{name: 'snowflake.usage_30d', resource: 'usage_30d'}],
        data: [{resource: 'usage_30d', items_path: ['snowflake', 'usage_30d', 'rows'],
          key_path: ['snowflake', 'usage_30d', 'key'], primary_identity: 'account_id'}],
      },
    }}),
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
