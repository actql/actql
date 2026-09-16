///|
/// Finite demand rule for the compiler's eager scalar comparison or count.
/// Summaries come only from the exact bound managed input. They do not attest
/// native evaluation, selected rows, order, retention or current use authority.
struct ManagedQueryDemand[T] {
  query : ManagedFixedQuery[T]
  state : ComparisonDemand?
  budget : NativeValueBudget
  physical : @execution.FixedInputGuardMeasureLimits
  mut consumed : Bool
}

///|
pub fn[T] prepare_managed_query_demand(
  query : ManagedFixedQuery[T],
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[ManagedQueryDemand[T], NativeDemandIssue] {
  if max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if !managed_fixed_query_matches(query, query.input) {
    return Err(InvalidState)
  }
  let rows = @execution.managed_producer_read_row_count(query.input)
  let budget : NativeValueBudget = {
    guards: { max_value_bytes, max_output_rows: rows, },
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  let state = match query.query {
    CountGroup(_) => None
    InnerJoin(_) => return Err(InvalidLayout)
    FilterSelect(native) => {
      let column = match
        fixed_comparison_column(
          @execution.managed_producer_read_schema(query.input),
          native,
          budget,
        ) {
        Ok(column) => column
        Err(issue) => return Err(issue)
      }
      guard @execution.managed_producer_read_column_measurement(
          query.input,
          column,
        )
        is Some(facts) else {
        return Err(InvalidState)
      }
      // Failure summaries do not identify the required first operand failure.
      // A caller can use ordinary ordered measurement, not invent a location.
      if rows > 0 &&
        (
          facts.max_value_bytes > max_value_bytes ||
          facts.admitted_depth > physical.max_depth
        ) {
        return Err(InputRepresentationRequired)
      }
      let rhs = match native.parameter.value {
        Admitted(value) => Admitted(value)
        Null => Null
        _ => return Err(InvalidLayout)
      }
      let rhs_bytes = if rows == 0 {
        None
      } else {
        Some(
          match measure_demand_scalar(budget, rhs) {
            Ok(bytes) => bytes
            Err(issue) => return Err(Operand(0, true, issue))
          },
        )
      }
      Some(ComparisonDemand::{
        rows,
        field_bytes: facts.bytes.to_int64(),
        rhs_bytes,
        null_rows: if rhs is Null || rhs is Admitted(@admitted.Null) {
          rows
        } else {
          facts.null_rows
        },
      })
    }
  }
  if !managed_fixed_query_matches(query, query.input) {
    return Err(InvalidState)
  }
  Ok({ query, state, budget, physical, consumed: false, })
}

///|
/// Exactly one provisional receipt consumes this demand. Native WHERE must have
/// produced exactly the true rows; the installed execution verifier establishes
/// that correspondence, not a count or metadata assertion by itself.
pub fn[T] finish_managed_query_demand(
  demand : ManagedQueryDemand[T],
  query : ManagedFixedQuery[T],
  receipt : @execution.ManagedOutputValueReceipt,
) -> Result[FixedComputeDemandUsage, NativeDemandIssue] {
  if demand.consumed ||
    !physical_equal(demand.query, query) ||
    !managed_fixed_query_matches(query, query.input) ||
    !@execution.managed_output_value_receipt_matches(
      receipt,
      fixed_query_owner(query.query),
      fixed_query_target(query.query),
    ) {
    return Err(InvalidState)
  }
  demand.consumed = true
  let output_rows = @execution.managed_output_value_row_count(receipt)
  match demand.state {
    None =>
      Ok(
        DirectCount(
          input_rows=@execution.managed_producer_read_row_count(query.input),
          output_rows~,
        ),
      )
    Some(state) =>
      finish_comparison_demand(
        state,
        output_rows,
        demand.budget,
        demand.physical,
      ).map(usage => Comparison(usage))
  }
}
