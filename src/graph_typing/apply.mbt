///|
pub(all) enum ApplyObligation {
  RequireExactlyOneDeltaRow
  ValidateDeltaVersionAndClosedShape
  MatchPinnedGraphContract
  AdmitBaseUnderPinnedContract
  MatchExactBaseIdentity
  ValidateOrderedUniqueActions
  ValidateExactBeforeRecords
  ValidateAddRemoveUpdateExistence
  ApplyNodeAndEdgeChangesTogether
  ValidateResultEndpointsAndContract
  MatchExactTargetIdentity
  PreserveGraphPolicyDependencies
  ResolveApplyResources
  ResolveSgaProfile
} derive(Eq, Debug)

///|
struct CheckedApply {
  output : @carrier.Carrier
  source : @decode.Cursor
  with_name : String
  field : String
  expected : @graph_contract.CheckedContract
  delta : @contract.Contract
  usage : Usage
}

///|
fn singleton_schema(c : @contract.Contract) -> @row.Schema {
  @row.from_fields([(Unqualified("value"), c)], max_fields=1, max_name_bytes=5).unwrap()
}

///|
/// The expected contract is resolved independently of the Delta payload.
/// Checking retains runtime admission obligations; it does not apply any data.
pub fn check_apply(
  source : @decode.Cursor,
  base : @carrier.Carrier,
  delta_rows : @carrier.Carrier,
  expected : @graph_contract.CheckedContract,
  limits : Limits,
) -> Result[CheckedApply, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let o = decoded(@decode.closed_object(source, ["with", "field"]))
    let target = decoded(@decode.required(o, "with"))
    let with_name = decoded(@decode.text(target))
    if with_name.is_empty() ||
      @canonical.normalize_nfc_lf(with_name) != Ok(with_name) {
      fail(target, InvalidName(with_name))
    }
    let field_at = decoded(@decode.required(o, "field"))
    let field = decoded(@decode.text(field_at))
    if field.is_empty() || @canonical.normalize_nfc_lf(field) != Ok(field) {
      fail(field_at, InvalidName(field))
    }
    let graph = match base {
      @carrier.GraphValue(g) => g
      @carrier.Opaque(GraphKind) => fail(source, IncompleteGraph)
      _ => fail(source, WrongCarrier(@carrier.kind(base)))
    }
    let rows = match delta_rows {
      @carrier.Relation(r) => r
      _ => fail(target, WrongCarrier(@carrier.kind(delta_rows)))
    }
    let reference : @row.FieldName = if field.has_prefix("left.") ||
      field.has_prefix("right.") {
      let parts = field.split(".").to_array()
      if parts.length() != 2 || parts[1].is_empty() {
        fail(field_at, InvalidName(field))
      }
      Qualified(
        if parts[0] == "left" {
          Left
        } else {
          Right
        },
        parts[1].to_owned(),
      )
    } else {
      Unqualified(field)
    }
    let actual = match @carrier.lookup(rows, reference) {
      Present({ contract: Some(c), .. }) => c
      Present(_) => fail(field_at, UntypedDeltaField(field))
      _ => fail(field_at, UnknownDeltaField(field))
    }
    let expected_graph = @graph_contract.graph(expected)
    // Compatibility is not admission: broader extents/nullability still need
    // data validation under the exact pinned contract, never a newly joined one.
    for
      (a, z) in [
        (
          @carrier.graph_node_properties(graph),
          @carrier.graph_node_properties(expected_graph),
        ),
        (
          @carrier.graph_edge_properties(graph),
          @carrier.graph_edge_properties(expected_graph),
        ),
      ] {
      let a = match @carrier.complete_schema(a) {
        Some(s) => s
        None => fail(source, IncompleteGraph)
      }
      let z = @carrier.complete_schema(z).unwrap()
      ignore(align_domains(b, source, a, z))
    }
    ignore(
      align_domains(
        b,
        source,
        singleton_schema(@carrier.graph_identity(graph)),
        singleton_schema(@carrier.graph_identity(expected_graph)),
      ),
    )
    // Retained evidence does not allow unbounded traversal of a supplied contract.
    let pinned = match
      @graph_contract.admit_graph(expected_graph, {
        max_bytes: b.text,
        max_nodes: if b.nodes < b.work {
          b.nodes
        } else {
          b.work
        },
        max_depth: limits.max_depth,
      }) {
      Ok(c) => c
      Err(_) => fail(source, BudgetExceeded)
    }
    b.nodes -= @graph_contract.nodes(pinned)
    spend(b, source, @graph_contract.nodes(pinned))
    b.text -= @graph_contract.bytes(pinned)
    let delta = delta_shape(b, field_at, expected_graph)
    match actual.shape {
      @contract.Json => () // JSON still requires complete semantic admission.
      @contract.Object(_) =>
        ignore(
          align_domains(
            b,
            field_at,
            singleton_schema(actual),
            singleton_schema(delta),
          ),
        )
      _ => fail(field_at, InvalidDeltaType)
    }
    Ok({
      output: @carrier.with_graph_names(
        expected_graph,
        @carrier.graph_names(graph),
      ),
      source,
      with_name,
      field,
      expected,
      delta,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn apply_output(v : CheckedApply) -> @carrier.Carrier {
  v.output
}

///|
pub fn apply_graph_contract(
  v : CheckedApply,
) -> @graph_contract.CheckedContract {
  v.expected
}

///|
pub fn apply_delta_contract(v : CheckedApply) -> @contract.Contract {
  v.delta
}

///|
pub fn apply_with_name(v : CheckedApply) -> String {
  v.with_name
}

///|
pub fn apply_field(v : CheckedApply) -> String {
  v.field
}

///|
pub fn apply_source(v : CheckedApply) -> @decode.Cursor {
  v.source
}

///|
pub fn apply_usage(v : CheckedApply) -> Usage {
  v.usage
}

///|
pub fn apply_pending(_v : CheckedApply) -> Array[ApplyObligation] {
  let out = []
  for i in 0..<apply_pending_count(_v) {
    out.push(apply_pending_at(_v, i).unwrap())
  }
  out
}

///|
/// O(1), without materializing the obligation array.
pub fn apply_pending_count(_v : CheckedApply) -> Int {
  14
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn apply_pending_at(_v : CheckedApply, index : Int) -> ApplyObligation? {
  match index {
    0 => Some(RequireExactlyOneDeltaRow)
    1 => Some(ValidateDeltaVersionAndClosedShape)
    2 => Some(MatchPinnedGraphContract)
    3 => Some(AdmitBaseUnderPinnedContract)
    4 => Some(MatchExactBaseIdentity)
    5 => Some(ValidateOrderedUniqueActions)
    6 => Some(ValidateExactBeforeRecords)
    7 => Some(ValidateAddRemoveUpdateExistence)
    8 => Some(ApplyNodeAndEdgeChangesTogether)
    9 => Some(ValidateResultEndpointsAndContract)
    10 => Some(MatchExactTargetIdentity)
    11 => Some(PreserveGraphPolicyDependencies)
    12 => Some(ResolveApplyResources)
    13 => Some(ResolveSgaProfile)
    _ => None
  }
}
