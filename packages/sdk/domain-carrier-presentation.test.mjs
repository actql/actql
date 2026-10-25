import test from 'node:test';
import assert from 'node:assert/strict';
import {explainCheckReason, getCheckPresentationInfo, renderCheckOutcome} from './check-presentation.mjs';
import {getCheckReasonCatalogEntry} from './check-reason-catalog.generated.js';
import {validCheckOutcome, checkReasonSchemaCid, checkOutcomeSchemaCid} from '../client-wire/index.mjs';

const outcome = reason => ({version:'actql-check-outcome/0.1', outcome:'completed',
  reason_schema_cid:checkReasonSchemaCid, outcome_schema_cid:checkOutcomeSchemaCid,
  report:{context_ref:'ctx:synthetic',scope:{kind:'bound_input'},verdict:'invalid',
    runnable:{verdict:'no',reasons:[{code:reason.code}]},
    inputs:[{document_id:'source',revision:'rev:'+'a'.repeat(64),kind:'text',byte_length:8}],
    coverage:{limits:[],unresolved:[]},reasons:[reason],requirements:[]}});
const cases = [
  [{code:'expression_domain_mismatch',facts:{domain:'key_comparable_operands'}},'incompatible types','互換性'],
  [{code:'expression_domain_mismatch',facts:{domain:'matching_numeric_domains'}},'numeric domain','数値領域'],
  [{code:'carrier_mismatch',facts:{expected_carrier:'vectors',actual_carrier:'relation'}},'Vectors input','Vectors入力'],
  [{code:'carrier_mismatch',facts:{expected_carrier:'relation',actual_carrier:'vectors'}},'Relation input','Relation入力'],
];

test('closed operand and carrier facts give immutable specific English and Japanese advice', () => {
  for (const [reason, english, japanese] of cases) {
    assert.equal(validCheckOutcome(outcome(reason)),true);
    const snapshot=structuredClone(reason), explanation=explainCheckReason(reason);
    assert.equal(explanation.kind,'known'); assert.ok(explanation.summary.includes(english));
    assert.equal(Object.isFrozen(explanation),true); assert.deepEqual(reason,snapshot);
    assert.ok(explainCheckReason(reason,{locale:'ja'}).summary.includes(japanese));
    assert.equal(Object.isFrozen(getCheckReasonCatalogEntry(reason.code).presentation.variants),true);
    const rendered=renderCheckOutcome(outcome(reason),{format:'text'},()=>undefined,()=>undefined);
    assert.ok(rendered.includes(english)); assert.ok(rendered.includes('completed/invalid'));
  }
  assert.equal(getCheckPresentationInfo({locale:'ja'}).translationRevision,'2026-10-25.ja.11');
});

test('missing or unknown domain predicates remain unexplained and fail wire admission', () => {
  for(const reason of [
    {code:'expression_domain_mismatch'},
    {code:'expression_domain_mismatch',facts:{domain:'future_domain'}},
    {code:'carrier_mismatch'},
    {code:'carrier_mismatch',facts:{expected_carrier:'future_carrier',actual_carrier:'relation'}},
  ]) {
    assert.equal(explainCheckReason(reason).kind,'unknown');
    assert.equal(validCheckOutcome(outcome(reason)),false);
  }
  assert.equal(explainCheckReason({code:'future_reason'}).kind,'unknown');
});

test('closed facts refuse arbitrary parser text and do not reflect it in explanations', () => {
  const secret='SYNTHETIC_PRIVATE_TOKEN';
  for (const [reason] of cases) {
    const withPrivate={...reason,facts:{...reason.facts,private_message:secret}};
    assert.equal(validCheckOutcome(outcome(withPrivate)),false);
    assert.equal(JSON.stringify(explainCheckReason(withPrivate)).includes(secret),false);
    assert.equal(renderCheckOutcome(outcome(withPrivate),{},()=>undefined,()=>undefined),undefined);
  }
});

test('carrier mismatch excludes equal carriers and unsupported carrier names', () => {
  for(const carrier of ['relation','vectors']) {
    assert.equal(validCheckOutcome(outcome({code:'carrier_mismatch',facts:{expected_carrier:carrier,actual_carrier:carrier}})),false);
  }
  assert.equal(validCheckOutcome(outcome({code:'carrier_mismatch',facts:{expected_carrier:'vectors',actual_carrier:'future_carrier'}})),false);
});
