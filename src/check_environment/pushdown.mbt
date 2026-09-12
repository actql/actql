///|
pub(all) struct PushdownLimits {
  max_work : Int
  max_contracts : Int
  max_operations : Int
} derive(Eq, Debug)

///|
pub(all) enum PushdownIssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  UnsupportedBody
  CarrierMismatch
  OperationMismatch
} derive(Eq, Debug)

///|
pub(all) struct PushdownIssue {
  kind : PushdownIssueKind
  source : @decode.Cursor?
}

///|
struct PushdownContract {
  envelope : ContractEnvelope
  carrier : String?
  operations : Array[String]
}

///|
pub struct SourcePushdown {
  reference : CatalogReference
  contract : PushdownContract
}

///|
struct PushdownContracts {
  shapes : SourceViewShapes
  entries : Array[PushdownContract]
  by_cid : Map[String, PushdownContract]
  views : Map[Int, SourcePushdown]
  work : Int
  operations : Int
}

///|
priv suberror PushdownStop {
  PushdownStop(PushdownIssue)
}

///|
priv struct PushdownBudget {
  limits : PushdownLimits
  mut work : Int
  mut operations : Int
}

///|
fn[T] pushdown_fail(
  kind : PushdownIssueKind,
  source : @decode.Cursor,
) -> T raise PushdownStop {
  raise PushdownStop({ kind, source: Some(source), })
}

///|
fn pushdown_spend(
  b : PushdownBudget,
  n : Int,
  c : @decode.Cursor,
) -> Unit raise PushdownStop {
  if n > b.limits.max_work - b.work {
    pushdown_fail(BudgetExceeded, c)
  }
  b.work += n
}

///|
fn pushdown_text(
  c : @decode.Cursor,
  b : PushdownBudget,
) -> String raise PushdownStop {
  let s = match @decode.text(c) {
    Ok(s) => s
    Err(_) => pushdown_fail(InvalidBody, c)
  }
  pushdown_spend(b, s.length(), c)
  s
}

///|
fn pushdown_operations(
  c : @decode.Cursor,
  b : PushdownBudget,
) -> Array[String] raise PushdownStop {
  guard @decode.array_length(c) is Some(n) else {
    pushdown_fail(InvalidBody, c)
  }
  if n > b.limits.max_operations - b.operations {
    pushdown_fail(BudgetExceeded, c)
  }
  pushdown_spend(b, n, c)
  b.operations += n
  if n > pushdown_operation_limit() {
    pushdown_fail(InvalidBody, c)
  }
  let result = []
  for i in 0..<n {
    let item = @decode.element_at(c, i).unwrap()
    let op = pushdown_text(item, b)
    if !pushdown_operation_name(op) || result.contains(op) {
      pushdown_fail(InvalidBody, item)
    }
    result.push(op)
  }
  result
}

///|
fn pushdown_body(
  envelope : ContractEnvelope,
  b : PushdownBudget,
) -> PushdownContract raise PushdownStop {
  let root = envelope.body
  let n = @decode.object_length(root)
  if n == Some(0) {
    return { envelope, carrier: None, operations: [], }
  }
  if n != Some(3) {
    pushdown_fail(InvalidBody, root)
  }
  for i in 0..<3 {
    pushdown_spend(b, @decode.field_at(root, i).unwrap().0.length(), root)
  }
  let obj = match
    @decode.closed_object(root, ["version", "carrier", "operations"]) {
    Ok(obj) => obj
    Err(_) => pushdown_fail(InvalidBody, root)
  }
  let version = @decode.lookup(obj, "version").unwrap()
  if pushdown_text(version, b) != "actql-source-view-pushdown/0.1" {
    pushdown_fail(UnsupportedBody, version)
  }
  let carrier = @decode.lookup(obj, "carrier").unwrap()
  let name = pushdown_text(carrier, b)
  match name {
    "relation" | "graph" | "events" | "vectors" => ()
    _ => pushdown_fail(InvalidBody, carrier)
  }
  let ops = @decode.lookup(obj, "operations").unwrap()
  let operations = pushdown_operations(ops, b)
  if name != "relation" && operations.length() != 0 {
    pushdown_fail(InvalidBody, ops)
  }
  { envelope, carrier: Some(name), operations, }
}

///|
/// Checks supplied bodies and every SourceView occurrence. This admits declared
/// capabilities, not provider equivalence, data access or execution authority.
pub fn check_pushdown_contracts(
  shapes : SourceViewShapes,
  limits : PushdownLimits,
) -> Result[PushdownContracts, PushdownIssue] {
  if limits.max_work < 0 ||
    limits.max_contracts < 0 ||
    limits.max_operations < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let references = shapes.values.policies.references
  let b = { limits, work: 0, operations: 0, }
  let entries = []
  let by_cid : Map[String, PushdownContract] = Map([])
  let views : Map[Int, SourcePushdown] = Map([])
  try {
    for envelope in references.contents.registry.entries {
      pushdown_spend(b, 1, envelope.body)
      if envelope.kind != "pushdown" {
        continue
      }
      if entries.length() >= limits.max_contracts {
        pushdown_fail(BudgetExceeded, envelope.body)
      }
      let contract = pushdown_body(envelope, b)
      entries.push(contract)
      by_cid[envelope.cid] = contract
    }
    for reference in references.references {
      pushdown_spend(b, 1, reference.source)
      if reference.contract.kind != "pushdown" {
        continue
      }
      let root = member_body(reference.item)
      pushdown_spend(b, @decode.object_length(root).unwrap(), root)
      let obj = @decode.open_object(root).unwrap()
      let output = @decode.open_object(@decode.lookup(obj, "output").unwrap()).unwrap()
      let carrier = pushdown_text(@decode.lookup(output, "carrier").unwrap(), b)
      let source = @decode.lookup(obj, "pushdown").unwrap()
      let declared = @decode.lookup(
        @decode.open_object(source).unwrap(),
        "operations",
      ).unwrap()
      let operations = pushdown_operations(declared, b)
      let contract = by_cid[reference.contract.cid]
      if contract.carrier is Some(expected) && expected != carrier {
        pushdown_fail(CarrierMismatch, source)
      }
      if operations.length() != contract.operations.length() ||
        !operations.all(op => contract.operations.contains(op)) {
        pushdown_fail(OperationMismatch, declared)
      }
      views[member_index(reference.item)] = { reference, contract, }
    }
    Ok({
      shapes,
      entries,
      by_cid,
      views,
      work: b.work,
      operations: b.operations,
    })
  } catch {
    PushdownStop(issue) => Err(issue)
  }
}

///|
pub fn pushdown_shapes(v : PushdownContracts) -> SourceViewShapes {
  v.shapes
}

///|
pub fn pushdown_usage(v : PushdownContracts) -> (Int, Int, Int) {
  (v.work, v.entries.length(), v.operations)
}

///|
pub fn pushdown_contract_at(
  v : PushdownContracts,
  i : Int,
) -> PushdownContract? {
  v.entries.get(i)
}

///|
pub fn pushdown_envelope(v : PushdownContract) -> ContractEnvelope {
  v.envelope
}

///|
pub fn pushdown_carrier(v : PushdownContract) -> String? {
  v.carrier
}

///|
pub fn pushdown_operation_count(v : PushdownContract) -> Int {
  v.operations.length()
}

///|
pub fn pushdown_operation_at(v : PushdownContract, i : Int) -> String? {
  v.operations.get(i)
}

///|
pub fn source_pushdown(v : PushdownContracts, item : Member) -> SourcePushdown? {
  if member_section(item) != SourceViews ||
    !physical_equal(
      member_environment(item),
      v.shapes.values.policies.references.contents.registry.environment,
    ) {
    return None
  }
  v.views.get(member_index(item))
}
