// Independently fixed received-response cases. Only request identity is echoed
// by the transport harness; no expectation is derived from a Client or checker.
const revision = 'rev:' + '4'.repeat(64);
const otherRevision = 'rev:' + '5'.repeat(64);
const declarationRevision = 'rev:' + '6'.repeat(64);
const location = {kind: 'text', document_id: 'source', revision,
  start_byte: 6, end_byte: 6, precision: 'exact'};
const observation = {version: 'actql-check-outcome/0.1',
  reason_schema_cid: 'sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5',
  outcome_schema_cid: 'sha256:abc1f9da9c6394f61d780139fe10ce220a25f6579ef80ed043a46c5704cf5f3b',
  outcome: 'completed', report: {context_ref: 'ctx:independent', scope: {kind: 'bound_input'},
    runnable: {verdict: 'no', reasons: [{code: 'query_syntax_invalid'}]},
    verdict: 'invalid', inputs: [{document_id: 'source', kind: 'text', revision, byte_length: 6}],
    reasons: [{code: 'query_syntax_invalid', location}], requirements: [],
    coverage: {limits: [], unresolved: []}}};
const fixed = (name, expected, change = () => {}, options = {}) => {
  const checked = structuredClone(observation);
  change(checked.report, checked);
  return {name: `submission check: ${name}`, expected, kind: 'submission', operation: 'aql',
    failureCode: 'SubmissionUnknown', source: 'SELECT', ...options,
    value: {kind: options.phase ?? 'not_accepted', problem: options.problem ??
      {code: 'ClientProgramInvalidInput', classification: 'invalid_input'},
      checkObservation: checked}};
};
const comment = report => {
  report.runnable = {verdict: 'no', reasons: [{code: 'query_lexical_invalid'}]};
  report.inputs[0].byte_length = 2;
  report.reasons = [{code: 'query_lexical_invalid', facts: {issue: 'unterminated_comment'},
    location: {...location, start_byte: 0, end_byte: 0},
    fixes: [{code: 'close_block_comment', applicability: 'requires_review', risk: 'syntax_structure',
      target: {document_id: 'source', revision},
      edits: [{start_byte: 2, end_byte: 2, replacement: '*/'}]}]}];
};
const missing = report => {
  report.runnable = {verdict: 'no', reasons: [
    {code: 'bound_values_missing'}, {code: 'parameter_value_required'}]};
  report.verdict = 'undetermined'; report.inputs[0].byte_length = 14;
  report.inputs.push({document_id: 'parameter_declarations', kind: 'structured',
    revision: declarationRevision, byte_length: 23});
  report.reasons = [];
  report.requirements = [{code: 'parameter_value_required', facts: {parameter: 'x', expected_type: 'number'},
    location: {kind: 'structured', document_id: 'parameter_declarations',
      revision: declarationRevision, pointer: '/x'}}];
  report.coverage.limits = [{code: 'bound_values_missing'}];
};
const limit = report => {
  report.runnable = {verdict: 'no', reasons: [{code: 'implementation_limit'}]};
  report.verdict = 'undetermined'; report.reasons = [];
  report.coverage.limits = [{code: 'implementation_limit',
    facts: {issue: 'function_lowering_unresolved'}, location: {...location}}];
};
const aliasSource = 'SELECT 1 AS n FROM `e\u0301/~🧭`';
const aliasOptions = {source: aliasSource};
const aliasAbsence = report => {
  report.runnable = {verdict: 'no', reasons: [{code: 'query_alias_absent'}]};
  // Independently fixed UTF-8 length of the original SQL above.
  report.inputs[0].byte_length = 30;
  report.reasons = [{code: 'query_alias_absent', facts: {namespace: 'queries',
    reference: [{value: 'e\u0301/~🧭', quoted: true}]}}];
};
export const submissionCheckWireCorpus = [
  fixed('authorized query alias absence', true, aliasAbsence, aliasOptions),
  fixed('query alias absence requires owned facts', false, report => {
    aliasAbsence(report); delete report.reasons[0].facts;
  }, aliasOptions),
  fixed('query alias absence cannot expose private revision', false, report => {
    aliasAbsence(report); report.reasons[0].facts.configuration_revision = 'private';
  }, aliasOptions),
  fixed('query alias absence cannot invent an empty reference', false, report => {
    aliasAbsence(report); report.reasons[0].facts.reference = [];
  }, aliasOptions),
  fixed('query alias absence preserves typed quoting', false, report => {
    aliasAbsence(report); report.reasons[0].facts.reference[0].quoted = 'true';
  }, aliasOptions),
  fixed('query alias absence cannot borrow a structured location', false, report => {
    aliasAbsence(report); report.reasons[0].location = {kind: 'structured',
      document_id: 'source', revision, pointer: '/missing'};
  }, aliasOptions),
  fixed('query alias absence grants no edit', false, report => {
    aliasAbsence(report); report.reasons[0].fixes = [{code: 'close_block_comment',
      applicability: 'requires_review', risk: 'syntax_structure',
      target: {document_id: 'source', revision},
      edits: [{start_byte: 30, end_byte: 30, replacement: '*/'}]}];
  }, aliasOptions),
  fixed('previous reason schema is explicitly rejected', false, (_, checked) => {
    checked.reason_schema_cid = 'sha256:3d0c78252f42ea8b2edc7a8bbea8d7ccf27ee4d2980b5889c9c191d5f0f3476a';
  }),
  fixed('previous outcome schema is explicitly rejected', false, (_, checked) => {
    checked.outcome_schema_cid = 'sha256:dbc59a5b3911315f28f04a4eb93808f56a85338cdb514c4a0546fedff0f1d6c9';
  }),
  fixed('exact syntax EOF', true),
  fixed('accepted preparation failure retains checking', true, () => {}, {phase: 'preparation_failed'}),
  fixed('submission cannot borrow template scope', false, report => {report.scope.kind = 'template_only';}),
  fixed('location revision mismatch', false, report => {report.reasons[0].location.revision = otherRevision;}),
  fixed('location beyond original byte bound', false, report => {report.reasons[0].location.end_byte = 7;}),
  fixed('reversed location range', false, report => {report.reasons[0].location.start_byte = 7;}),
  fixed('duplicate source documents', false, report => {report.inputs.push({...report.inputs[0]});}),
  fixed('source must be text', false, report => {report.inputs[0].kind = 'structured';}),
  fixed('non-source must be structured', false, report => {
    report.inputs.push({document_id: 'parameters', kind: 'text', revision: otherRevision, byte_length: 1});
  }),
  fixed('missing source document', false, report => {report.inputs[0].document_id = 'parameters'; report.inputs[0].kind = 'structured';}),
  fixed('exact EOF fix', true, comment, {source: '/*'}),
  fixed('fix target revision mismatch', false, report => {comment(report); report.reasons[0].fixes[0].target.revision = otherRevision;}, {source: '/*'}),
  fixed('fix begins before EOF', false, report => {comment(report); report.reasons[0].fixes[0].edits[0].start_byte = 1;}, {source: '/*'}),
  fixed('fix ends beyond EOF', false, report => {comment(report); report.reasons[0].fixes[0].edits[0].end_byte = 3;}, {source: '/*'}),
  fixed('known missing value', true, missing, {source: 'SELECT @x AS n', declarations: {x: {type: 'number'}}}),
  fixed('Requirement revision mismatch', false, report => {missing(report); report.requirements[0].location.revision = otherRevision;}, {source: 'SELECT @x AS n', declarations: {x: {type: 'number'}}}),
  fixed('Requirement has no input document', false, report => {missing(report); report.inputs.pop();}, {source: 'SELECT @x AS n', declarations: {x: {type: 'number'}}}),
  fixed('duplicate declaration documents', false, report => {missing(report); report.inputs.push({...report.inputs[1]});}, {source: 'SELECT @x AS n', declarations: {x: {type: 'number'}}}),
  fixed('implementation location', true, limit),
  fixed('implementation location revision mismatch', false, report => {limit(report); report.coverage.limits[0].location.revision = otherRevision;}),
  fixed('implementation location byte overflow', false, report => {limit(report); report.coverage.limits[0].location.end_byte = 7;}),
  fixed('failed partial location revision mismatch', false, (report, checked) => {
    report.reasons[0].location.revision = otherRevision;
    delete checked.report; checked.outcome = 'failed'; checked.partial_report = report;
    checked.problem = {code: 'reporting_failed'}; checked.correlation_ref = 'corr:partial';
  }),
];

// Program cases are fixed independently of either checker or response producer.
const programFixed = (name, expected, change = () => {}, options = {}) => {
  const checked = structuredClone(observation);
  const program = options.program ?? {version: 'actql/0.1', id: 'p'};
  checked.report.inputs = [{document_id: 'program', kind: 'structured', revision,
    byte_length: Buffer.byteLength(JSON.stringify(program), 'utf8')}];
  checked.report.reasons = [{code: 'program_structure_invalid', facts: {issue: 'missing_field'},
    location: {kind: 'structured', document_id: 'program', revision, pointer: ''}}];
  checked.report.runnable = {verdict: 'no', reasons: [{code: 'program_structure_invalid'}]};
  change(checked.report, checked);
  return {name: `submission Program check: ${name}`, expected, kind: 'submission', operation: 'start',
    failureCode: 'SubmissionUnknown', program,
    value: {kind: options.phase ?? 'not_accepted', problem:
      {code: 'ClientProgramInvalidInput', classification: 'invalid_input'}, checkObservation: checked}};
};
const selectorProgram = {version: 'actql/0.1', id: 'p', inputs: {
  'e\u0301/~': {kind: 'Source', connector: 'fixture', resource: 'absent', view: 'records'}}};
const unregisteredSelector = report => {
  report.runnable = {verdict: 'no', reasons: [{code: 'source_selector_unregistered'}]};
  report.reasons = [{code: 'source_selector_unregistered',
    facts: {namespace: 'test', connector: 'fixture', resource: 'absent', view: 'records'},
    location: {kind: 'structured', document_id: 'program', revision,
      pointer: '/inputs/e\u0301~1~0/view'}}];
};
export const submissionProgramCheckWireCorpus = [
  programFixed('unregistered selector original Unicode pointer', true, unregisteredSelector,
    {program: selectorProgram}),
  programFixed('unregistered selector omitted view uses parent', true, report => {
    unregisteredSelector(report); delete report.reasons[0].facts.view;
    report.reasons[0].location.pointer = '/inputs/e\u0301~1~0';
  }, {program: {version: 'actql/0.1', id: 'p', inputs: {
    'e\u0301/~': {kind: 'Source', connector: 'fixture', resource: 'absent'}}}}),
  programFixed('unregistered selector cannot borrow text location', false, report => {
    unregisteredSelector(report); report.reasons[0].location = {...location};
  }, {program: selectorProgram}),
  programFixed('unregistered selector cannot expose private metadata', false, report => {
    unregisteredSelector(report); report.reasons[0].facts.registration_revision = 'private';
  }, {program: selectorProgram}),
  programFixed('unregistered selector cannot borrow another revision', false, report => {
    unregisteredSelector(report); report.reasons[0].location.revision = otherRevision;
  }, {program: selectorProgram}),
  programFixed('unregistered selector cannot authorize a fix', false, report => {
    unregisteredSelector(report); report.reasons[0].fixes = [{code: 'close_block_comment',
      applicability: 'requires_review', risk: 'syntax_structure',
      target: {document_id: 'program', revision},
      edits: [{start_byte: 0, end_byte: 0, replacement: '*/'}]}];
  }, {program: selectorProgram}),
  programFixed('missing field uses original parent', true),
  programFixed('preparation failure retains original parent', true, () => {}, {phase: 'preparation_failed'}),
  programFixed('Program must be structured', false, report => {report.inputs[0].kind = 'text';}),
  programFixed('Program cannot borrow a source document', false, report => {
    report.inputs.push({document_id: 'source', kind: 'text', revision: otherRevision, byte_length: 6});
  }),
  programFixed('Program cannot borrow declaration custody', false, report => {
    report.inputs.push({document_id: 'parameter_declarations', kind: 'structured', revision: otherRevision, byte_length: 2});
  }),
  programFixed('pointer revision mismatch', false, report => {report.reasons[0].location.revision = otherRevision;}),
  programFixed('invalid pointer escape', false, report => {report.reasons[0].location.pointer = '/bad~2key';}),
  programFixed('structure cause cannot carry a private value', false, report => {report.reasons[0].facts.value = 'private';}),
  programFixed('Program cannot acquire a text fix', false, report => {report.reasons[0].fixes = [{
    code: 'close_block_comment', applicability: 'requires_review', risk: 'syntax_structure',
    target: {document_id: 'program', revision}, edits: [{start_byte: 32, end_byte: 32, replacement: '*/'}]}];}),
  programFixed('Program implementation location', true, report => {
    report.runnable = {verdict: 'no', reasons: [{code: 'implementation_limit'}]};
    report.verdict = 'undetermined'; report.reasons = [];
    report.coverage.limits = [{code: 'implementation_limit',
      location: {kind: 'structured', document_id: 'program', revision, pointer: ''}}];
  }),
  programFixed('Program budget location', true, report => {
    report.runnable = {verdict: 'no', reasons: [{code: 'analysis_budget_exhausted'}]};
    report.verdict = 'undetermined'; report.reasons = [];
    report.coverage.limits = [{code: 'analysis_budget_exhausted',
      location: {kind: 'structured', document_id: 'program', revision, pointer: ''}}];
  }),
  programFixed('old schema pin is rejected', false, (_report, checked) => {
    checked.reason_schema_cid = 'sha256:006f651784cb2f48f3b7cedc3881e7e902ab154d1d985dc219a0d2d975041739';
  }),
];
