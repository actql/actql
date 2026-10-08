// Independently fixed received-response cases. Only request identity is echoed
// by the transport harness; no expectation is derived from a Client or checker.
const revision = 'rev:' + '4'.repeat(64);
const otherRevision = 'rev:' + '5'.repeat(64);
const declarationRevision = 'rev:' + '6'.repeat(64);
const location = {kind: 'text', document_id: 'source', revision,
  start_byte: 6, end_byte: 6, precision: 'exact'};
const observation = {version: 'actql-check-outcome/0.1',
  reason_schema_cid: 'sha256:006f651784cb2f48f3b7cedc3881e7e902ab154d1d985dc219a0d2d975041739',
  outcome_schema_cid: 'sha256:801971ab7c91652f2e3a606cdae7567fe313ca2931df81d7ab4c24d3d130e0a9',
  outcome: 'completed', report: {context_ref: 'ctx:independent', scope: {kind: 'bound_input'},
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
  report.inputs[0].byte_length = 2;
  report.reasons = [{code: 'query_lexical_invalid', facts: {issue: 'unterminated_comment'},
    location: {...location, start_byte: 0, end_byte: 0},
    fixes: [{code: 'close_block_comment', applicability: 'requires_review', risk: 'syntax_structure',
      target: {document_id: 'source', revision},
      edits: [{start_byte: 2, end_byte: 2, replacement: '*/'}]}]}];
};
const missing = report => {
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
  report.verdict = 'undetermined'; report.reasons = [];
  report.coverage.limits = [{code: 'implementation_limit',
    facts: {issue: 'function_lowering_unresolved'}, location: {...location}}];
};
export const submissionCheckWireCorpus = [
  fixed('exact syntax EOF', true),
  fixed('accepted preparation failure retains checking', true, () => {}, {phase: 'preparation_failed'}),
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
