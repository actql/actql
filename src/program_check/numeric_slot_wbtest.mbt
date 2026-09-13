///|
test "formal numeric groups bind persistent slots without future observations" {
  let profile = numeric_profile_fixture()
  let identities : Array[String] = []
  for window in [false, true] {
    let ordinal = if window { 1 } else { 0 }
    let domain = if window { "window" } else { "group" }
    for function in ["sum", "avg"] {
      for filter in ["", ",\"filter\":\"FALSE\""] {
        let checked : Array[CheckedProgram] = []
        let _ = local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          second_stage=true,
          through_check=true,
          numeric_profile=Some(profile),
          tea=window,
          checked_results=checked,
          producer_expression="1",
          second_steps="[" +
            (if window {
              "{\"row_window\":{\"time\":\"id\",\"kind\":\"sliding\",\"size\":10,\"step\":3}},"
            } else {
              ""
            }) +
            "{\"" +
            (if window { "window_group" } else { "group" }) +
            "\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"" +
            function +
            "\",\"field\":\"value\"" +
            filter +
            "}}},\"as\":\"selected\"}]",
          second_result_from="selected",
          extra_step_budget=2,
        )
        let program = checked[0]
        assert_eq(unit_group_numeric_slot_count(program, 0), Some(0))
        assert_eq(unit_group_numeric_slot_count(program, 1), Some(1))
        assert_true(unit_group_numeric_slot_at(program, 1, 1) is None)
        let slot = unit_group_numeric_slot_at(program, 1, 0).unwrap()
        let location = group_numeric_slot_operation(slot)
        let demand = group_numeric_slot_demand(slot)
        assert_eq(location.unit_definition_cid, program.units[1].definition_cid)
        assert_eq(location.source_ordinal, ordinal)
        assert_true(
          physical_equal(location.pipeline, program.units[1].pipeline),
        )
        assert_true(physical_equal(demand.profile, profile))
        assert_eq(demand.step.operation is @pipeline.WindowGroup(_), window)
        if window {
          let keys = @relation.group_keys(demand.group)
          assert_eq(keys.length(), 3)
          assert_eq(keys[0].field, Unqualified("window_start"))
          assert_eq(keys[1].field, Unqualified("window_end"))
        }
        let rule_cid = if window {
          "sha256:868fc8f92638572086e4063a815ba235ebe8bc1f207c935c5a99cc82ddabe8ee"
        } else {
          "sha256:3bbd17b81b40403cea2b43db3324a9c2b2185bc8c86a994d58f009e317b1a73d"
        }
        let mut rules = 0
        for i in 0..<unit_contract_count(program, 1).unwrap() {
          if unit_contract_at(program, 1, i).unwrap().0 == rule_cid {
            rules += 1
          }
        }
        assert_eq(rules, 1)
        // Independent spelling of the normative preimage, not the product emitter.
        let expected = "{\"aggregate_name\":\"value\",\"reduction_profile_cid\":\"" +
          @numeric.cid(profile) +
          "\",\"source_ordinal\":" +
          ordinal.to_string() +
          ",\"unit_definition_cid\":\"" +
          program.units[1].definition_cid +
          "\",\"version\":\"actql-" +
          domain +
          "-numeric-slot/0.1\"}"
        assert_eq(
          group_numeric_slot_cid(slot),
          "sha256:" + @sha.text_hex(expected).unwrap(),
        )
        let budget = IdentityBudget::{
          work: 100000,
          bytes: 100000,
          nodes: 10000,
          depth: 20,
        }
        let bytes = publication_metadata(
          w => emit_group_numeric_slot(slot, w) catch { e => raise Encoding(e) },
          budget,
        )
        assert_eq(@utf8.decode(bytes), expected)
        identities.push(group_numeric_slot_cid(slot))
        let closure = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut captures = 0
        for i in 0..<@context.operation_closure_count(closure) {
          guard @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(GroupExecution(check))) &&
            check.rule is CaptureNumericObservation(retained) else {
            continue
          }
          captures += 1
          assert_true(physical_equal(retained, demand))
        }
        assert_eq(captures, 1)
        let initial = IdentityBudget::{
          work: 100000,
          bytes: 100000,
          nodes: 10000,
          depth: 20,
        }
        let measured = IdentityBudget::{ ..initial, }
        let _ = prepare_program_numeric_slot_identities(
          program.units,
          requirements(program),
          measured,
        )
        let exact = IdentityBudget::{
          work: initial.work - measured.work,
          bytes: initial.bytes - measured.bytes,
          nodes: initial.nodes - measured.nodes,
          depth: 20,
        }
        let _ = prepare_program_numeric_slot_identities(
          program.units,
          requirements(program),
          exact,
        )
        assert_eq(exact.work, 0)
        assert_eq(exact.bytes, 0)
        assert_eq(exact.nodes, 0)
        for dimension in 0..<3 {
          let limited = IdentityBudget::{
            work: initial.work -
            measured.work -
            (if dimension == 0 { 1 } else { 0 }),
            bytes: initial.bytes -
            measured.bytes -
            (if dimension == 1 { 1 } else { 0 }),
            nodes: initial.nodes -
            measured.nodes -
            (if dimension == 2 { 1 } else { 0 }),
            depth: 20,
          }
          let before = (limited.work, limited.bytes, limited.nodes)
          try
            prepare_program_numeric_slot_identities(
              program.units,
              requirements(program),
              limited,
            )
          catch {
            BudgetExceeded | Encoding(_) => ()
            e => raise e
          } noraise {
            _ => fail("short identity budget accepted")
          }
          assert_eq((limited.work, limited.bytes, limited.nodes), before)
        }
      }
    }
  }
  for i in 0..<identities.length() {
    for j in 0..<i {
      assert_true(identities[i] != identities[j])
    }
  }
}
