// Project declared public input/control bytes into focused source/checker
// tests. No product compiler, evaluator or returned schema supplies an oracle.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {carrierContinuationSuccesses as successes,carrierContinuationRefusals as refusals}
  from './fixtures/carrier-continuation-source-input.mjs';
const path='src/query_program/carrier_continuation_public_fixture_test.mbt';
const context=`///|
fn carrier_continuation_public_context() -> Context {
  {
    ..pair_context(),
    inputs: [{
      relation: [{ value: "records", quoted: false, }],
      name: "records",
      source: GeneratedValues(from_unpivot_public_cursor(
        "{\\\"values\\\":{\\\"schema\\\":{\\\"id\\\":{\\\"type\\\":\\\"number\\\",\\\"nullable\\\":false},\\\"amount\\\":{\\\"type\\\":\\\"number\\\",\\\"nullable\\\":true}},\\\"rows\\\":[{\\\"id\\\":2,\\\"amount\\\":20},{\\\"id\\\":1,\\\"amount\\\":null},{\\\"id\\\":3,\\\"amount\\\":30}]},\\\"as\\\":\\\"records\\\"}"
      )),
      visible_fields: ["id", "amount"],
      graph_bindings: [],
    }],
  }
}

///|
fn carrier_continuation_fixture_program(text : String, format : @frontend.Format) -> @program.Program {
  let lowered = @frontend.lower(text, format, Some(carrier_continuation_public_context())).unwrap()
  match lowered.program {
    Some(program) => program
    None => @program.parse(lowered.document, construction_limits().program, format=lowered.format).unwrap()
  }
}

///|
fn carrier_continuation_fixture_schema(program : @program.Program) -> Array[@schema.Field] raise {
  let checked = match @check.check_parsed(program, graph_event_environment(), None, graph_rows_check_limits()) {
    Checked(checked) => checked
    Rejected(diagnostic) => { graph_rows_rejected(diagnostic); fail("rejected declared control") }
    NeedsInputs(_) => fail("focused control uses closed Values, not a provider")
  }
  let results = @stage_results.stage_at(@check.checked_stage_results(checked), 0).unwrap()
  let result = @relation_results.lookup(results, "rows").unwrap()
  @schema.fields(@relation_results.output_schema(result))
}
`;
const format=item=>({sql:'Sql','aql-text':'Text',json:'Json'})[item.format];
const successBody=successes.map(item=>`    (${JSON.stringify(item.name)}, ${JSON.stringify(item.text)}, @frontend.${format(item)})`).join(',\n');
const graphRefusals=refusals.filter(item=>/demanded-events|unused-events|root-events|marked-relation|shadowed-events/u.test(item.name));
const refusalBody=graphRefusals.map(item=>`    (${JSON.stringify(item.name)}, ${JSON.stringify(item.text)}, @frontend.${format(item)})`).join(',\n');
const edgeBody=refusals.filter(item=>item.name.includes('relation-tail-graph-call')).map(item=>`    (${JSON.stringify(item.text)}, @frontend.${format(item)})`).join(',\n');
const body=`// Generated from independently declared public fixtures; do not edit.
${context}
///|
test "F01 F02 declared public inputs reach the normal SQL AQL-text and machine checker" {
  let expected = carrier_continuation_fixture_schema(carrier_continuation_fixture_program(${JSON.stringify(successes[0].text)}, @frontend.Json))
  for (name, text, format) in [
${successBody}
  ] {
    let program = carrier_continuation_fixture_program(text, format)
    let actual = carrier_continuation_fixture_schema(program)
    assert_eq(actual.map(field => @schema.reference_name(field.name)), ["node_key", "occurred_ms"], msg=name)
    for i in 0..<actual.length() {
      assert_eq(actual[i].presence, expected[i].presence, msg=name)
      assert_true(@contract.type_equal(actual[i].contract, expected[i].contract, 10000), msg=name)
    }
    let wire = semantic(program)
    if name.contains("events") {
      for operation in ["node_rows", "to_events", "events"] {
        assert_eq(wire.split("\\\"" + operation + "\\\":").length() - 1, 1, msg=name)
      }
    }
    if name.contains("source-events") {
      assert_eq(wire.split("\\\"values\\\":{").length(), 2, msg=name)
      assert_true(wire.contains("\\\"filter\\\":{\\\"eq\\\":[{\\\"field\\\":\\\"id\\\"},{\\\"literal\\\":1}]}"), msg=name)
    }
  }
}

///|
test "F01 declared explicit Graph refusals keep the authored operand cause" {
  for (name, text, format) in [
${refusalBody}
  ] {
    match @frontend.lower(text, format, Some(carrier_continuation_public_context())) {
      Err(QueryLowering(GraphExpected(Some(origin)))) => {
        assert_eq(@origin.kind(origin), @origin.Authored, msg=name)
        assert_true(@origin.span(origin).end_byte > @origin.span(origin).start_byte, msg=name)
      }
      _ => fail("Expected authored GraphExpected: " + name)
    }
  }
}

///|
test "F02 declared Graph-only tail refuses the actual Relation" {
  for (text, format) in [
${edgeBody}
  ] {
    assert_true(@frontend.lower(text, format, Some(carrier_continuation_public_context())) is Err(QueryLowering(InvalidQuery)))
  }
}
`;
assert.deepEqual(process.argv.slice(2),process.argv.includes('--write')?['--write']:[]);
const formatted=spawnSync('moonfmt',['-'],{input:body,encoding:'utf8',timeout:5000});
assert.equal(formatted.error,undefined);
assert.equal(formatted.status,0,formatted.stderr);
if(process.argv.includes('--write')) writeFileSync(path,formatted.stdout);
else assert.equal(readFileSync(path,'utf8'),formatted.stdout,'Stale carrier public source fixture');
console.log(JSON.stringify({sourceCases:successes.length,graphRefusals:graphRefusals.length,relationTailRefusals:2,writes:process.argv.includes('--write')}));
