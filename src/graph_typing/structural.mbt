///|
pub(all) enum StructuralOperation {
  Graft
  Union
  Subtract
} derive(Eq, Debug)

///|
pub(all) enum FieldStrategy {
  ExactEqual
  SetUnion
  SetDifference
  NumberSum
  NumberMean
  NumberMin
  NumberMax
} derive(Eq, Debug)

///|
pub struct PropertyStrategy {
  name : String
  strategy : FieldStrategy
}

///|
pub(all) enum StructuralObligation {
  AdmitGraphsUnderCommonContract
  CompareCompleteIdentityPayloads
  RejectUnspecifiedConflicts
  ApplyEveryAuthoredStrategy
  KeepCompleteOneSidedUnionRecords
  KeepOnlyLeftSubtractionRecords
  CloseSubtractionEndpoints
  ValidateCanonicalSetOperations
  ValidateFiniteNumericResults
  PreservePolicyDependencies
  ResolveStructuralResources
  ResolveSgaProfile
} derive(Eq, Debug)

///|
struct CheckedStructural {
  operation : StructuralOperation
  comparison : CheckedEquality
  output : @carrier.Carrier
  nodes : Array[PropertyStrategy]
  edges : Array[PropertyStrategy]
  usage : Usage
}

///|
fn strategy(c : @decode.Cursor) -> FieldStrategy raise Stop {
  let name = decoded(@decode.text(c))
  match name {
    "exact_equal" => ExactEqual
    "set_union" => SetUnion
    "set_difference" => SetDifference
    "number_sum" => NumberSum
    "number_mean" => NumberMean
    "number_min" => NumberMin
    "number_max" => NumberMax
    _ => fail(c, InvalidPropertyStrategy(name))
  }
}

///|
fn merged_properties(
  b : Budget,
  source : @decode.Cursor,
  selected : @decode.Cursor?,
  common : @carrier.Knowledge,
  left : @carrier.Knowledge,
  right : @carrier.Knowledge,
) -> (@carrier.Knowledge, Array[PropertyStrategy]) raise Stop {
  guard selected is Some(at) else { return (common, []) }
  let object = decoded(@decode.open_object(at))
  let names = decoded(@decode.object_field_names(at))
  spend(b, at, names.length() + @carrier.field_count(common))
  let replacements : Map[String, @contract.Contract] = Map([])
  let strategies : Array[PropertyStrategy] = []
  for name in names {
    let at = @decode.lookup(object, name).unwrap()
    let c = match @carrier.lookup(common, Unqualified(name)) {
      Present({ contract: Some(c), .. }) => c
      _ => fail(at, UnknownMergeProperty(name))
    }
    let s = strategy(at)
    let replacement = match s {
      ExactEqual => c
      NumberSum | NumberMean | NumberMin | NumberMax => {
        guard c.shape is @contract.Number else {
          fail(at, IncompatiblePropertyStrategy(name))
        }
        c
      }
      SetUnion | SetDifference => {
        guard c.shape is @contract.Array(item, ..) else {
          fail(at, IncompatiblePropertyStrategy(name))
        }
        if s == SetUnion {
          let a = match @carrier.lookup(left, Unqualified(name)) {
            Present(
              {
                contract: Some({ shape: @contract.Array(_, max_items=a), .. }),
                ..
              }
            ) => a
            _ => None
          }
          let z = match @carrier.lookup(right, Unqualified(name)) {
            Present(
              {
                contract: Some({ shape: @contract.Array(_, max_items=z), .. }),
                ..
              }
            ) => z
            _ => None
          }
          let bound = match (a, z) {
            (Some(a), Some(z)) =>
              if a <= 9007199254740991L - z {
                Some(a + z)
              } else {
                None
              }
            _ => None
          }
          @contract.array_contract(item, nullable=c.nullable, max_items=bound).unwrap()
        } else {
          c
        }
      }
    }
    replacements[name] = replacement
    strategies.push({ name, strategy: s, })
  }
  strategies.sort_by((a, z) => @canonical.compare_utf16(a.name, z.name))
  let fields : Array[(@row.FieldName, @contract.Contract?)] = []
  for i in 0..<@carrier.field_count(common) {
    let f = @carrier.field_at(common, i).unwrap()
    let name = @row.reference_name(f.name)
    charge(b, source, name)
    fields.push(
      (f.name, Some(replacements.get(name).unwrap_or(f.contract.unwrap()))),
    )
  }
  let rows = match
    @carrier.rows(
      fields,
      field_set=Closed,
      max_fields=fields.length(),
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(r) => r
    Err(_) => fail(source, BudgetExceeded)
  }
  (rows, strategies)
}

///|
pub fn check_structural(
  operation : StructuralOperation,
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedStructural, Issue] {
  check_structural_impl(operation, source, left, right, limits)
}

///|
fn check_structural_impl(
  operation : StructuralOperation,
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  limits : Limits,
  reference? : @decode.Cursor? = None,
  source_scanned? : Bool = false,
) -> Result[CheckedStructural, Issue] {
  try {
    let comparison = match
      check_graph_pair(
        source,
        left,
        right,
        limits,
        allowed=if operation == Graft { ["with"] } else { ["with", "merge"] },
        reference~,
        source_scanned~,
      ) {
      Ok(c) => c
      Err(e) => raise Stop(e)
    }
    let used = comparison.usage
    let b : Budget = {
      limits,
      work: limits.max_work - used.work,
      nodes: limits.max_nodes - used.nodes,
      text: limits.max_text_bytes - used.text_bytes,
    }
    let root = decoded(@decode.open_object(source))
    let merge = match @decode.lookup(root, "merge") {
      Some(c) =>
        Some(
          decoded(
            @decode.closed_object(c, ["node_properties", "edge_properties"]),
          ),
        )
      None => None
    }
    let node_map = match merge {
      Some(o) => @decode.lookup(o, "node_properties")
      None => None
    }
    let edge_map = match merge {
      Some(o) => @decode.lookup(o, "edge_properties")
      None => None
    }
    let common = comparison.common
    let (nodes, node_strategies) = merged_properties(
      b,
      source,
      node_map,
      @carrier.graph_node_properties(common),
      @carrier.graph_node_properties(comparison.left),
      @carrier.graph_node_properties(comparison.right),
    )
    let (edges, edge_strategies) = merged_properties(
      b,
      source,
      edge_map,
      @carrier.graph_edge_properties(common),
      @carrier.graph_edge_properties(comparison.left),
      @carrier.graph_edge_properties(comparison.right),
    )
    let output = if node_strategies.is_empty() && edge_strategies.is_empty() {
      @carrier.graph_carrier(common)
    } else {
      let labels = match @carrier.graph_label_count(common) {
        None => None
        Some(n) => {
          spend(b, source, n)
          let labels = []
          for i in 0..<n {
            let label = @carrier.graph_label_at(common, i).unwrap()
            charge(b, source, label)
            labels.push(label)
          }
          Some(labels)
        }
      }
      match
        @carrier.graph(
          @carrier.graph_identity(common),
          nodes,
          edges,
          labels~,
          max_labels=labels.map(x => x.length()).unwrap_or(0),
          max_label_bytes=limits.max_text_bytes,
          row_names=@carrier.graph_names(comparison.left),
          label_contract=@carrier.graph_label_contract(common),
        ) {
        Ok(g) => g
        Err(_) => fail(source, BudgetExceeded)
      }
    }
    Ok({
      operation,
      comparison,
      output,
      nodes: node_strategies,
      edges: edge_strategies,
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
pub fn structural_output(c : CheckedStructural) -> @carrier.Carrier {
  c.output
}

///|
pub fn structural_usage(c : CheckedStructural) -> Usage {
  c.usage
}

///|
pub fn structural_operation(c : CheckedStructural) -> StructuralOperation {
  c.operation
}

///|
pub fn structural_source(c : CheckedStructural) -> @decode.Cursor {
  c.comparison.source
}

///|
pub fn structural_with_name(c : CheckedStructural) -> String {
  c.comparison.with_name
}

///|
pub fn structural_strategies(
  c : CheckedStructural,
  side : @row.Side,
) -> Array[PropertyStrategy] {
  if side == Left {
    c.nodes.copy()
  } else {
    c.edges.copy()
  }
}

///|
pub fn structural_pending(c : CheckedStructural) -> Array[StructuralObligation] {
  let obligations = [
    AdmitGraphsUnderCommonContract,
    CompareCompleteIdentityPayloads,
    RejectUnspecifiedConflicts,
    PreservePolicyDependencies,
    ResolveStructuralResources,
    ResolveSgaProfile,
  ]
  if c.operation == Subtract {
    obligations.push(KeepOnlyLeftSubtractionRecords)
    obligations.push(CloseSubtractionEndpoints)
  } else {
    obligations.push(KeepCompleteOneSidedUnionRecords)
  }
  if !c.nodes.is_empty() || !c.edges.is_empty() {
    obligations.push(ApplyEveryAuthoredStrategy)
  }
  for strategies in [c.nodes, c.edges] {
    for s in strategies {
      match s.strategy {
        SetUnion | SetDifference =>
          if !obligations.contains(ValidateCanonicalSetOperations) {
            obligations.push(ValidateCanonicalSetOperations)
          }
        NumberSum | NumberMean | NumberMin | NumberMax =>
          if !obligations.contains(ValidateFiniteNumericResults) {
            obligations.push(ValidateFiniteNumericResults)
          }
        _ => ()
      }
    }
  }
  obligations
}
