///|
fn demand_facts_operand(nullable_type : Int, text : String) -> ParameterValue {
  let kind = if nullable_type == 0 {
    @contract.NumberType
  } else {
    @contract.StringType
  }
  Admitted(
    @admitted.admit(@contract.primitive(kind, nullable=true), payload(text), {
      max_nodes: 1,
      max_depth: 1,
      max_text_bytes: 100,
    }).unwrap().value,
  )
}

///|
/// Facts exactly as capture records them: one canonical measurement per value.
fn demand_facts_of(values : Array[ParameterValue]) -> ComparisonDemandFacts {
  let mut bytes = 0
  let mut nodes = 0
  let mut nulls = 0
  let mut bound = 0
  for value in values {
    let writer = @encode.measuring_writer(100000, 100000, 10) catch {
      _ => abort("fixture")
    }
    match value {
      Admitted(inner) =>
        @admitted.emit_wire_value(inner, writer) catch {
          _ => abort("fixture")
        }
      _ => abort("fixture")
    }
    let (value_bytes, value_nodes, _) = @encode.finish_measurement_usage(writer) catch {
      _ => abort("fixture")
    }
    bytes += value_bytes
    nodes += value_nodes
    bound = Int::max(bound, value_bytes)
    if value is Admitted(@admitted.Null) {
      nulls += 1
    }
  }
  {
    rows: values.length(),
    bytes,
    nodes,
    null_rows: nulls,
    value_bytes_bound: bound,
    depth: 0,
  }
}

///|
fn demand_facts_budget(
  max_value_bytes : Int,
  work : Int,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> NativeValueBudget {
  {
    guards: { max_value_bytes, max_output_rows: 100, },
    work,
    bytes,
    nodes,
    depth,
  }
}

///|
fn demand_facts_state() -> ComparisonDemand {
  { rows: 0, field_bytes: 0L, rhs_bytes: None, null_rows: 0, }
}

///|
fn demand_issue_key(issue : NativeDemandIssue) -> String {
  match issue {
    Operand(row, rhs, detail) =>
      "operand:\{row}:\{rhs}:" + demand_detail_key(detail)
    Predicate(detail) => "predicate:" + demand_detail_key(detail)
    InvalidState => "invalid-state"
    InvalidLimits => "invalid-limits"
    InvalidLayout => "invalid-layout"
    InvalidResultCount => "invalid-result-count"
    InputRepresentationRequired => "representation-required"
  }
}

///|
fn demand_detail_key(detail : NativeValueIssue) -> String {
  match detail {
    MeasurementWork => "work"
    ValueBytes => "value-bytes"
    OutputRows => "output-rows"
    Measurement(InvalidStructure) => "measurement:structure"
    Measurement(InvalidUnicode) => "measurement:unicode"
    Measurement(InvalidNumber) => "measurement:number"
    Measurement(OutputLimit) => "measurement:output-limit"
    Measurement(ClosedWriter) => "measurement:closed"
  }
}

///|
test "column facts reproduce the ordered comparison demand fold exactly or decline untouched" {
  let columns : Array[(Int, Array[String])] = [
    (0, []),
    (0, ["1", "22", "333"]),
    (0, ["null", "7", "null"]),
    (0, ["null", "null"]),
    (1, ["\"a\"", "null", "\"a much longer operand\""]),
    (1, ["\"éé\"", "\"x\""]),
  ]
  let right_sides : Array[(Int, String)] = [
    (0, "5"),
    (0, "null"),
    (1, "\"bb\""),
    (1, "\"a right side longer than the operand ceiling\""),
  ]
  let mut applied = 0
  let mut declined = 0
  for column in columns {
    let (kind, texts) = column
    let values = texts.map(text => demand_facts_operand(kind, text))
    let facts = demand_facts_of(values)
    for right in right_sides {
      let rhs = demand_facts_operand(right.0, right.1)
      let rhs_usage = demand_facts_of([rhs])
      let exact_work = facts.rows + 1
      let exact_bytes = facts.bytes + rhs_usage.bytes
      let exact_nodes = facts.nodes + rhs_usage.nodes
      let ceiling = Int::max(facts.value_bytes_bound, rhs_usage.bytes)
      for
        limits in [
          (ceiling, exact_work, exact_bytes, exact_nodes, 1),
          (ceiling, exact_work - 1, exact_bytes, exact_nodes, 1),
          (ceiling, exact_work, exact_bytes - 1, exact_nodes, 1),
          (ceiling, exact_work, exact_bytes, exact_nodes - 1, 1),
          (ceiling - 1, exact_work, exact_bytes, exact_nodes, 1),
          (facts.value_bytes_bound, 1000, 1000, 1000, 1),
          (ceiling, 1000, 1000, 1000, 0),
          (ceiling, 1000, 1000, 1000, 1),
        ] {
        let (max_value_bytes, work, bytes, nodes, depth) = limits
        // Ordered fold, as the one-column scan performs it.
        let scanned_state = demand_facts_state()
        let scanned_budget = demand_facts_budget(
          max_value_bytes, work, bytes, nodes, depth,
        )
        let mut scanned_issue = None
        for value in values {
          if accumulate_comparison_demand(
              scanned_state, scanned_budget, value, rhs,
            )
            is Err(issue) {
            scanned_issue = Some(issue)
            break
          }
        }
        // Facts rule on the same starting state and budget.
        let state = demand_facts_state()
        let budget = demand_facts_budget(
          max_value_bytes, work, bytes, nodes, depth,
        )
        let used = apply_comparison_demand_facts(state, budget, facts, rhs)
        assert_eq(used, scanned_issue is None)
        if used {
          applied += 1
          assert_eq(
            (state.rows, state.field_bytes, state.rhs_bytes, state.null_rows),
            (
              scanned_state.rows,
              scanned_state.field_bytes,
              scanned_state.rhs_bytes,
              scanned_state.null_rows,
            ),
          )
          assert_eq(
            (budget.work, budget.bytes, budget.nodes),
            (scanned_budget.work, scanned_budget.bytes, scanned_budget.nodes),
          )
          // The finished usage (predicate bytes, physical charges) is identical.
          let physical : @execution.FixedInputGuardMeasureLimits = {
            max_work: work,
            max_bytes: bytes,
            max_nodes: nodes,
            max_depth: depth,
          }
          let true_rows = (facts.rows - state.null_rows) / 2
          let a = finish_comparison_demand(state, true_rows, budget, physical)
          let b = finish_comparison_demand(
            scanned_state, true_rows, scanned_budget, physical,
          )
          match (a, b) {
            (Ok(x), Ok(y)) =>
              assert_eq(
                (
                  x.rows,
                  x.field_bytes,
                  x.rhs_bytes,
                  x.true_rows,
                  x.false_rows,
                  x.null_rows,
                  x.predicate_bytes,
                  x.physical_work,
                  x.physical_bytes,
                  x.physical_nodes,
                ),
                (
                  y.rows,
                  y.field_bytes,
                  y.rhs_bytes,
                  y.true_rows,
                  y.false_rows,
                  y.null_rows,
                  y.predicate_bytes,
                  y.physical_work,
                  y.physical_bytes,
                  y.physical_nodes,
                ),
              )
            (Err(x), Err(y)) =>
              assert_eq(demand_issue_key(x), demand_issue_key(y))
            _ => fail("finish outcomes differ")
          }
        } else {
          declined += 1
          // Declining leaves nothing charged; the ordered scan then reports
          // its own first failure (row, side and kind) unchanged.
          assert_eq(
            (state.rows, state.field_bytes, state.rhs_bytes, state.null_rows),
            (0, 0L, None, 0),
          )
          assert_eq(
            (budget.work, budget.bytes, budget.nodes),
            (work, bytes, nodes),
          )
          assert_true(scanned_issue is Some(_))
        }
      }
    }
  }
  assert_true(applied > 0 && declined > 0)
}

///|
test "column facts cannot be applied to a started or inconsistent demand" {
  let rhs = demand_facts_operand(0, "5")
  let values = ["1", "null"].map(text => demand_facts_operand(0, text))
  let facts = demand_facts_of(values)
  let state = demand_facts_state()
  let budget = demand_facts_budget(10, 100, 100, 100, 1)
  accumulate_comparison_demand(state, budget, values[0], rhs).unwrap()
  assert_false(apply_comparison_demand_facts(state, budget, facts, rhs))
  assert_eq(state.rows, 1)
  let fresh = demand_facts_state()
  let fresh_budget = demand_facts_budget(10, 100, 100, 100, 1)
  assert_false(
    apply_comparison_demand_facts(
      fresh,
      fresh_budget,
      { ..facts, null_rows: facts.rows + 1, },
      rhs,
    ),
  )
  assert_false(
    apply_comparison_demand_facts(
      fresh,
      fresh_budget,
      { ..facts, bytes: -1, },
      rhs,
    ),
  )
  assert_eq((fresh.rows, fresh_budget.work), (0, 100))
}
