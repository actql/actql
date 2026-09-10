///|
pub(all) enum EqualityObligation {
  AdmitBothGraphs
  CompareTypedCanonicalGraphs
  ResolveComparisonResources
  ResolveSgaProfile
} derive(Eq, Debug)

///|
struct CheckedEquality {
  source : @decode.Cursor
  with_name : String
  left : @carrier.Graph
  right : @carrier.Graph
  common : @carrier.Graph
  usage : Usage
}

///|
fn align_domains(
  b : Budget,
  source : @decode.Cursor,
  left : @row.Schema,
  right : @row.Schema,
) -> @row.Schema raise Stop {
  let aligned = match
    @alignment.align_schemas(source, left, right, {
      max_work: b.work,
      max_nodes: b.nodes,
      max_depth: b.limits.max_depth,
      max_text_bytes: b.text,
    }) {
    Ok(v) => v
    Err(e) =>
      if e.kind == @alignment.BudgetExceeded {
        fail(source, BudgetExceeded)
      } else {
        fail(source, ContractMismatch(e.kind))
      }
  }
  let used = @alignment.alignment_usage(aligned)
  b.work -= used.work
  b.nodes -= used.nodes
  b.text -= used.text_bytes
  @alignment.aligned_schema(aligned)
}

///|
pub fn check_equality(
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedEquality, Issue] {
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
    let o = decoded(@decode.closed_object(source, ["with"]))
    let target = decoded(@decode.required(o, "with"))
    let with_name = decoded(@decode.text(target))
    if with_name.is_empty() ||
      @canonical.normalize_nfc_lf(with_name) != Ok(with_name) {
      fail(target, InvalidName(with_name))
    }
    let graphs : Array[@carrier.Graph] = []
    for (v, at) in [(left, source), (right, target)] {
      match v {
        @carrier.GraphValue(g) => graphs.push(g)
        @carrier.Opaque(GraphKind) => fail(at, IncompleteGraph)
        _ => fail(at, WrongCarrier(@carrier.kind(v)))
      }
    }
    let a = graphs[0]
    let z = graphs[1]
    // Use the same bounded recursive domain join as the Relation checker.
    // Compatible extents/nullability are not forced to be byte-identical.
    let properties : Array[@carrier.Knowledge] = []
    for
      (x, y) in [
        (@carrier.graph_node_properties(a), @carrier.graph_node_properties(z)),
        (@carrier.graph_edge_properties(a), @carrier.graph_edge_properties(z)),
      ] {
      let x = match @carrier.complete_schema(x) {
        Some(s) => s
        None => fail(source, IncompleteGraph)
      }
      let y = match @carrier.complete_schema(y) {
        Some(s) => s
        None => fail(target, IncompleteGraph)
      }
      properties.push(@carrier.typed_rows(align_domains(b, source, x, y)))
    }
    let x = @row.from_fields(
      [(Unqualified("id"), @carrier.graph_identity(a))],
      max_fields=1,
      max_name_bytes=2,
    ).unwrap()
    let y = @row.from_fields(
      [(Unqualified("id"), @carrier.graph_identity(z))],
      max_fields=1,
      max_name_bytes=2,
    ).unwrap()
    let identities = align_domains(b, source, x, y)
    // Label-domain differences are values to compare, not a reason to return
    // false statically or to reject otherwise compatible graph contracts.
    let labels : Array[String] = []
    let seen : Map[String, Bool] = Map([])
    let mut all_known = true
    for g in graphs {
      if @carrier.graph_labels(g) is Some(domain) {
        spend(b, source, domain.length())
        for label in domain {
          charge(b, source, label)
          if !seen.contains(label) {
            seen[label] = true
            labels.push(label)
          }
        }
      } else {
        all_known = false
      }
    }
    let common = match
      @carrier.graph(
        @row.lookup(identities, Unqualified("id")).unwrap(),
        properties[0],
        properties[1],
        labels=if all_known { Some(labels) } else { None },
        max_labels=labels.length(),
        max_label_bytes=limits.max_text_bytes,
        row_names=@carrier.graph_names(a),
      ) {
      Ok(@carrier.GraphValue(g)) => g
      _ => fail(source, BudgetExceeded)
    }
    spend(b, source, 1)
    charge(b, source, "equal")
    Ok({
      source,
      with_name,
      left: a,
      right: z,
      common,
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
pub fn equality_output(_v : CheckedEquality) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("equal"),
          Some(@contract.primitive(BooleanType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=5,
    ).unwrap(),
  )
}

///|
pub fn equality_usage(v : CheckedEquality) -> Usage {
  v.usage
}

///|
pub fn equality_with_name(v : CheckedEquality) -> String {
  v.with_name
}

///|
pub fn equality_source(v : CheckedEquality) -> @decode.Cursor {
  v.source
}

///|
pub fn equality_input(v : CheckedEquality, side : @row.Side) -> @carrier.Graph {
  if side == Left {
    v.left
  } else {
    v.right
  }
}

///|
pub fn equality_pending(_v : CheckedEquality) -> Array[EqualityObligation] {
  [
    AdmitBothGraphs,
    CompareTypedCanonicalGraphs,
    ResolveComparisonResources,
    ResolveSgaProfile,
  ]
}
