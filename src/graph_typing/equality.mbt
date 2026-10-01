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
fn check_graph_pair(
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  limits : Limits,
  allowed? : Array[String] = ["with"],
  reference? : @decode.Cursor? = None,
  source_scanned? : Bool = false,
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
    if !source_scanned {
      scan(b, source)
    }
    let o = decoded(@decode.closed_object(source, allowed))
    let target = match reference {
      Some(at) => at
      None => decoded(@decode.required(o, "with"))
    }
    let with_name = decoded(@decode.text(target))
    if with_name.is_empty() ||
      @canonical.normalize_nfc_lf(with_name) != Ok(with_name) {
      fail(target, InvalidName(with_name))
    }
    let graphs : Array[@carrier.Graph] = []
    for (v, at) in [(left, source), (right, target)] {
      match v {
        @carrier.GraphValue(g) => {
          require_legacy_profile(g, at)
          graphs.push(g)
        }
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
      if @carrier.graph_label_count(g) is Some(count) {
        spend(b, source, count)
        for i in 0..<count {
          let label = @carrier.graph_label_at(g, i).unwrap()
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
    let label_contract = match
      (@carrier.graph_label_contract(a), @carrier.graph_label_contract(z)) {
      (Some(x), Some(y)) =>
        Some(
          @row.lookup(
            align_domains(b, source, singleton_schema(x), singleton_schema(y)),
            Unqualified("value"),
          ).unwrap(),
        )
      _ => None
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
        label_contract~,
      ) {
      Ok(@carrier.GraphValue(g)) => g
      _ => fail(source, BudgetExceeded)
    }
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
pub fn check_equality(
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedEquality, Issue] {
  let c = match check_graph_pair(source, left, right, limits) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  if c.usage.work >= limits.max_work ||
    limits.max_text_bytes - c.usage.text_bytes < 5 {
    return Err({
      kind: BudgetExceeded,
      path: @decode.cursor_path(source),
      span: @decode.cursor_span(source),
    })
  }
  Ok({
    ..c,
    usage: {
      ..c.usage,
      work: c.usage.work + 1,
      text_bytes: c.usage.text_bytes + 5,
    },
  })
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
  let out = []
  for i in 0..<equality_pending_count(_v) {
    out.push(equality_pending_at(_v, i).unwrap())
  }
  out
}

///|
/// O(1), without materializing the obligation array.
pub fn equality_pending_count(_v : CheckedEquality) -> Int {
  4
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn equality_pending_at(
  _v : CheckedEquality,
  index : Int,
) -> EqualityObligation? {
  match index {
    0 => Some(AdmitBothGraphs)
    1 => Some(CompareTypedCanonicalGraphs)
    2 => Some(ResolveComparisonResources)
    3 => Some(ResolveSgaProfile)
    _ => None
  }
}
