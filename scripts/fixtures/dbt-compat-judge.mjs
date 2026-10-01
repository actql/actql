// Verdicts for the dbt compatibility probe. Pure, so the probe's pass/fail
// rules are tested without dbt or an ActQL installation. Copied unchanged
// next to the acceptance in the external installation.

export const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);

// Rows compared with duplicates kept; order only where the case orders.
export function sameRows(actual, expected, order) {
  const multiset = rows => rows.map(canonical).sort();
  return order === 'unordered'
    ? canonical(multiset(actual)) === canonical(multiset(expected))
    : canonical(actual) === canonical(expected);
}

// Verdicts that fail the probe. Only a refusal at submission of a case that
// is observed (expect: "observe") is a finding rather than a failure; a Run
// that was admitted and then did not succeed is a fault of the run, never a
// statement about what ActQL supports.
export const FAILING_VERDICTS = Object.freeze(['baseline-failed',
  'wrong-result', 'run-failed']);

// item: {expect: "rows" | "observe", rows?, columns?, order?}
// outcome.stage: actql-submission-refused | actql-run-failed | named-result
export function judge(item, outcome, sourceColumns) {
  if (outcome.stage === 'actql-run-failed') return {verdict: 'run-failed'};
  if (outcome.stage === 'actql-submission-refused') {
    return item.expect === 'observe' ? {verdict: 'unsupported'}
      : {verdict: 'baseline-failed'};
  }
  if (outcome.stage !== 'named-result') {
    throw new TypeError(`Unknown probe stage ${outcome.stage}`);
  }
  const order = item.order ?? 'unordered';
  const problems = [];
  if (item.rows !== undefined && !sameRows(outcome.all, item.rows, order)) {
    problems.push('rows differ from the expected rows');
  }
  if (!sameRows(outcome.streamed, outcome.all, order)) {
    problems.push('streamed rows differ from all()');
  }
  if (outcome.streamState !== 'complete') {
    problems.push(`stream ended in state ${outcome.streamState}`);
  }
  const columns = item.columns ?? sourceColumns;
  if (item.rows !== undefined &&
      canonical(outcome.columns) !== canonical(columns)) {
    problems.push('result columns differ from the expected schema');
  }
  if (item.expect === 'rows' && item.rows === undefined) {
    problems.push('a rows case has no expected rows');
  }
  return problems.length === 0 ? {verdict: 'passed'}
    : {verdict: 'wrong-result', problems};
}

// The probe passes only when dbt compile stayed offline and unconnected,
// every case has a verdict that is not failing, and no fault stopped it.
export function probeStatus({outcomes, compileProblems = [], fault}) {
  const failures = outcomes.filter(item =>
    FAILING_VERDICTS.includes(item.verdict) || item.verdict === undefined);
  return {status: failures.length === 0 && compileProblems.length === 0 &&
    fault === undefined ? 'passed' : 'failed', failures};
}
