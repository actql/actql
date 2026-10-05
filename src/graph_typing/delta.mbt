///|
pub(all) enum DeltaOperation {
  Difference
  Application(@row.FieldName)
} derive(Eq, Debug)

///|
/// The Graph contract is an expectation for semantic data admission, not a
/// capability or evidence that a supplied row has already passed admission.
struct CheckedDelta {
  source : @decode.Cursor
  operation : DeltaOperation
  graph_contract : @graph_contract.CheckedContract
  output : @carrier.Carrier
  usage : Usage
}

///|
pub(all) enum DeltaObligation {
  AdmitDeltaGraphs
  ResolveDeltaResources
  EnforceDeltaRelationRows
  AdmitExactlyOneDeltaRow
  AdmitDeltaActions
  VerifyDeltaBaseBeforeTarget
} derive(Eq, Debug)

///|
fn delta_budget(source : @decode.Cursor, limits : Limits) -> Budget raise Stop {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    fail(source, InvalidLimits)
  }
  let budget : Budget = {
    limits,
    work: limits.max_work,
    nodes: limits.max_nodes,
    text: limits.max_text_bytes,
  }
  scan(budget, source)
  budget
}

///|
fn delta_graph_contract(
  budget : Budget,
  source : @decode.Cursor,
  input : @carrier.Carrier,
) -> @graph_contract.CheckedContract raise Stop {
  guard input is @carrier.GraphValue(_) else {
    fail(
      source,
      if @carrier.kind(input) == GraphKind {
        IncompleteGraph
      } else {
        WrongCarrier(@carrier.kind(input))
      },
    )
  }
  let contract = match
    @graph_contract.admit(input, {
      max_bytes: budget.text,
      max_nodes: Int::min(budget.work, budget.nodes),
      max_depth: budget.limits.max_depth,
    }) {
    Ok(contract) => contract
    Err(_) => fail(source, BudgetExceeded)
  }
  let nodes = @graph_contract.nodes(contract)
  spend(budget, source, nodes)
  budget.nodes -= nodes
  budget.text -= @graph_contract.bytes(contract)
  contract
}

///|
fn delta_budget_usage(budget : Budget) -> Usage {
  {
    work: budget.limits.max_work - budget.work,
    nodes: budget.limits.max_nodes - budget.nodes,
    text_bytes: budget.limits.max_text_bytes - budget.text,
  }
}

///|
pub fn check_graph_diff(
  source : @decode.Cursor,
  base : @carrier.Carrier,
  target : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedDelta, Issue] {
  try {
    let budget = delta_budget(source, limits)
    let body = decoded(@decode.closed_object(source, ["with"]))
    let at = decoded(@decode.required(body, "with"))
    let name = decoded(@decode.text(at))
    if name.is_empty() || @canonical.normalize_nfc_lf(name) != Ok(name) {
      fail(at, InvalidName(name))
    }
    let graph_contract = delta_graph_contract(budget, source, base)
    let target_contract = delta_graph_contract(budget, at, target)
    // Both snapshots use one saved definition body. Contract equality is not
    // an assertion about current graph contents or any data's admissibility.
    if @graph_contract.cid(graph_contract) !=
      @graph_contract.cid(target_contract) {
      fail(at, DeltaContractMismatch)
    }
    let output = diagnostic_rows(
      source,
      [
        (
          @row.Unqualified("delta"),
          Some(@contract.primitive(JsonType, nullable=false)),
        ),
      ],
      budget,
    )
    Ok({
      source,
      operation: Difference,
      graph_contract,
      output,
      usage: delta_budget_usage(budget),
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn check_apply_graph_delta(
  source : @decode.Cursor,
  base : @carrier.Carrier,
  relation : @carrier.Carrier,
  expected_contract : @graph_contract.CheckedContract?,
  limits : Limits,
) -> Result[CheckedDelta, Issue] {
  try {
    let budget = delta_budget(source, limits)
    let body = decoded(@decode.closed_object(source, ["with", "field"]))
    let with_at = decoded(@decode.required(body, "with"))
    let name = decoded(@decode.text(with_at))
    if name.is_empty() || @canonical.normalize_nfc_lf(name) != Ok(name) {
      fail(with_at, InvalidName(name))
    }
    let graph_contract = delta_graph_contract(budget, source, base)
    if expected_contract is Some(expected) &&
      @graph_contract.cid(expected) != @graph_contract.cid(graph_contract) {
      fail(with_at, DeltaContractMismatch)
    }
    let field_at = decoded(@decode.required(body, "field"))
    let name = decoded(@decode.text(field_at))
    guard @carrier.relation_rows(relation) is Some(rows) else {
      fail(with_at, WrongCarrier(@carrier.kind(relation)))
    }
    let count = @carrier.field_count(rows)
    spend(budget, field_at, count)
    let mut selected : @carrier.Field? = None
    for index in 0..<count {
      let field = @carrier.field_at(rows, index).unwrap()
      charge(budget, field_at, @row.reference_name(field.name))
      if @row.reference_name(field.name) == name {
        selected = Some(field)
      }
    }
    let field = match selected {
      Some(field) => field
      None => fail(field_at, UnknownDeltaField(name))
    }
    let ty = match field.contract {
      Some(ty) => ty
      None => fail(field_at, UntypedDeltaField(name))
    }
    // Conditional, nullable or non-JSON values cannot enter the semantic Delta
    // admission boundary. JSON here is ordinary typed data, never authority.
    if field.presence != @row.Required ||
      ty.nullable ||
      !(ty.shape is @contract.Json) {
      fail(field_at, InvalidDeltaType)
    }
    Ok({
      source,
      operation: Application(field.name),
      graph_contract,
      output: base,
      usage: delta_budget_usage(budget),
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn delta_source(value : CheckedDelta) -> @decode.Cursor {
  value.source
}

///|
pub fn delta_operation(value : CheckedDelta) -> DeltaOperation {
  value.operation
}

///|
pub fn delta_graph(value : CheckedDelta) -> @graph_contract.CheckedContract {
  value.graph_contract
}

///|
pub fn delta_output(value : CheckedDelta) -> @carrier.Carrier {
  value.output
}

///|
pub fn delta_usage(value : CheckedDelta) -> Usage {
  value.usage
}

///|
pub fn delta_pending_count(value : CheckedDelta) -> Int {
  if value.operation is Difference {
    3
  } else {
    5
  }
}

///|
pub fn delta_pending_at(value : CheckedDelta, index : Int) -> DeltaObligation? {
  match (value.operation, index) {
    (_, 0) => Some(AdmitDeltaGraphs)
    (_, 1) => Some(ResolveDeltaResources)
    (Difference, 2) => Some(EnforceDeltaRelationRows)
    (Application(_), 2) => Some(AdmitExactlyOneDeltaRow)
    (Application(_), 3) => Some(AdmitDeltaActions)
    (Application(_), 4) => Some(VerifyDeltaBaseBeforeTarget)
    _ => None
  }
}
