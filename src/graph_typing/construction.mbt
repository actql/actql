///|
pub(all) enum ConstructionObligation {
  AdmitGraphInputRows
  CloseBothEndpointsAgainstDeclaredNodes
  DeriveDistinctEndpointNodes
  JournalEndpointCompletion
  JournalLabelCompletion
  CollapseEqualIdentityPayloads
  RejectConflictingIdentityPayloads
  ResolveGraphConstructionResources
  ResolveSgaProfile
} derive(Eq, Debug)

///|
struct CheckedConstruction {
  source : @decode.Cursor
  nodes_name : String?
  edges_name : String?
  output : @carrier.Carrier
  pending : Array[ConstructionObligation]
  usage : Usage
}

///|
fn construction_reference(at : @decode.Cursor) -> @row.FieldName raise Stop {
  let name = decoded(@decode.text(at))
  if name.is_empty() || @canonical.normalize_nfc_lf(name) != Ok(name) {
    fail(at, InvalidName(name))
  }
  if name.has_prefix("left.") || name.has_prefix("right.") {
    let parts = name.split(".").to_array()
    if parts.length() != 2 || parts[1].is_empty() {
      fail(at, InvalidName(name))
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
    Unqualified(name)
  }
}

///|
fn construction_field(
  rows : @carrier.Knowledge,
  at : @decode.Cursor,
) -> @carrier.Field raise Stop {
  let reference = construction_reference(at)
  match @carrier.lookup(rows, reference) {
    Present(f) => f
    _ => fail(at, UnknownConstructionField(@row.reference_name(reference)))
  }
}

///|
fn construction_identity(
  rows : @carrier.Knowledge,
  at : @decode.Cursor,
) -> @carrier.Field raise Stop {
  let f = construction_field(rows, at)
  guard f.contract is Some(c) && !c.nullable && @contract.key_comparable(c, c) else {
    fail(at, InvalidConstructionIdentity)
  }
  f
}

///|
fn construction_rows(
  c : @carrier.Carrier,
  at : @decode.Cursor,
) -> @carrier.Knowledge raise Stop {
  match c {
    @carrier.Relation(r) => r
    _ => fail(at, WrongCarrier(@carrier.kind(c)))
  }
}

///|
fn construction_name(at : @decode.Cursor) -> String raise Stop {
  let s = decoded(@decode.text(at))
  if s.is_empty() || @canonical.normalize_nfc_lf(s) != Ok(s) {
    fail(at, InvalidName(s))
  }
  s
}

///|
fn construction_properties(
  b : Budget,
  at : @decode.Cursor,
  rows : @carrier.Knowledge,
  fields : @decode.Cursor?,
  implicit_all : Bool,
  roles : Array[@row.FieldName],
) -> @carrier.Knowledge raise Stop {
  let chosen : Array[(@carrier.Field, @decode.Cursor)] = []
  let seen : Map[String, Bool] = Map([])
  if fields is Some(list) {
    let items = decoded(@decode.elements(list))
    spend(b, list, items.length())
    for item in items {
      let f = construction_field(rows, item)
      let name = @row.reference_name(f.name)
      if seen.contains(name) {
        fail(item, DuplicateConstructionField(name))
      }
      seen[name] = true
      if !roles.contains(f.name) {
        chosen.push((f, item))
      }
    }
  } else if implicit_all {
    spend(b, at, @carrier.field_count(rows))
    for i in 0..<@carrier.field_count(rows) {
      let f = @carrier.field_at(rows, i).unwrap()
      if !roles.contains(f.name) {
        chosen.push((f, at))
      }
    }
  }
  let entries : Array[(@row.FieldName, @contract.Contract?)] = []
  for (f, location) in chosen {
    let name = @row.reference_name(f.name)
    charge(b, location, name)
    // Graph property names are flat authored names; a scoped input needs an
    // explicit upstream alias rather than losing its provenance here.
    guard f.name is @row.Unqualified(_) else {
      fail(location, InvalidName(name))
    }
    entries.push((f.name, f.contract))
  }
  match
    @carrier.rows(
      entries,
      field_set=if implicit_all { @carrier.field_set(rows) } else { Closed },
      max_fields=entries.length(),
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(r) => r
    Err(_) => fail(at, BudgetExceeded)
  }
}

///|
/// Callers resolve the named inputs; concise form uses only the edge/current input.
pub fn check_construction(
  source : @decode.Cursor,
  nodes : @carrier.Carrier?,
  edges : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedConstruction, Issue] {
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
    let root = decoded(
      @decode.closed_object(source, [
        "nodes", "edges", "source", "target", "label",
      ]),
    )
    let explicit = @decode.lookup(root, "nodes") is Some(_) ||
      @decode.lookup(root, "edges") is Some(_)
    let (node_at, edge_at, edge_obj, nodes_name, edges_name) = if explicit {
      for key in ["source", "target", "label"] {
        if @decode.lookup(root, key) is Some(at) {
          fail(at, InvalidBody)
        }
      }
      let n = decoded(@decode.required(root, "nodes"))
      let e = decoded(@decode.required(root, "edges"))
      let no = decoded(@decode.closed_object(n, ["from", "id", "fields"]))
      let eo = decoded(
        @decode.closed_object(e, ["from", "source", "target", "label", "fields"]),
      )
      (
        Some((n, no)),
        e,
        eo,
        Some(construction_name(decoded(@decode.required(no, "from")))),
        Some(construction_name(decoded(@decode.required(eo, "from")))),
      )
    } else {
      (None, source, root, None, None)
    }
    if explicit != (nodes is Some(_)) {
      fail(source, InvalidBody)
    }
    let rows = construction_rows(edges, edge_at)
    let src_at = decoded(@decode.required(edge_obj, "source"))
    let dst_at = decoded(@decode.required(edge_obj, "target"))
    let src = construction_identity(rows, src_at)
    let dst = construction_identity(rows, dst_at)
    let mut id = @row.lookup(
      align_domains(
        b,
        edge_at,
        singleton_schema(src.contract.unwrap()),
        singleton_schema(dst.contract.unwrap()),
      ),
      Unqualified("value"),
    ).unwrap()
    let mut label_completion = false
    let label = if @decode.lookup(edge_obj, "label") is Some(at) {
      Some(construction_field(rows, at))
    } else if !explicit {
      let mut found : @carrier.Field? = None
      for name in ["edge_type", "rel"] {
        if found is None &&
          @carrier.lookup(rows, Unqualified(name)) is Present(f) {
          found = Some(f)
          label_completion = true
        }
      }
      found
    } else {
      None
    }
    let label_contract = match label {
      Some(f) => {
        guard f.contract is Some(c) && c.shape is @contract.Text(_) else {
          fail(
            @decode.lookup(edge_obj, "label").unwrap_or(edge_at),
            InvalidConstructionLabel,
          )
        }
        Some(c)
      }
      None => None
    }
    let roles = [src.name, dst.name]
    if label is Some(f) {
      roles.push(f.name)
    }
    let edge_props = construction_properties(
      b,
      edge_at,
      rows,
      @decode.lookup(edge_obj, "fields"),
      !explicit,
      roles,
    )
    let (node_name, node_props) = match node_at {
      Some((at, o)) => {
        let rows = construction_rows(nodes.unwrap(), at)
        let identity = construction_identity(
          rows,
          decoded(@decode.required(o, "id")),
        )
        id = @row.lookup(
          align_domains(
            b,
            at,
            singleton_schema(identity.contract.unwrap()),
            singleton_schema(id),
          ),
          Unqualified("value"),
        ).unwrap()
        (
          identity.name,
          construction_properties(
            b,
            at,
            rows,
            @decode.lookup(o, "fields"),
            false,
            [identity.name],
          ),
        )
      }
      None =>
        (
          @row.Unqualified("node_id"),
          @carrier.rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap(),
        )
    }
    let alias_names = @carrier.graph_row_names(
      node_name,
      src.name,
      dst.name,
      label.map(f => f.name),
      max_name_bytes=b.text,
    )
    let names = match alias_names {
      Ok(n) => n
      Err(_) => fail(source, BudgetExceeded)
    }
    for
      name in [
        Some(node_name),
        Some(src.name),
        Some(dst.name),
        label.map(f => f.name),
      ] {
      if name is Some(name) {
        spend(b, source, 1)
        charge(b, source, @row.reference_name(name))
      }
    }
    let output = match
      @carrier.graph(
        id,
        node_props,
        edge_props,
        labels=None,
        max_labels=0,
        max_label_bytes=0,
        row_names=Some(names),
        label_contract~,
      ) {
      Ok(g) => g
      Err(_) => fail(source, InvalidConstructionIdentity)
    }
    let pending = [
      AdmitGraphInputRows,
      CollapseEqualIdentityPayloads,
      RejectConflictingIdentityPayloads,
      ResolveGraphConstructionResources,
      ResolveSgaProfile,
      JournalEndpointCompletion,
    ]
    pending.push(
      if explicit {
        CloseBothEndpointsAgainstDeclaredNodes
      } else {
        DeriveDistinctEndpointNodes
      },
    )
    if label_completion {
      pending.push(JournalLabelCompletion)
    }
    Ok({
      source,
      nodes_name,
      edges_name,
      output,
      pending,
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
pub fn construction_output(c : CheckedConstruction) -> @carrier.Carrier {
  c.output
}

///|
pub fn construction_usage(c : CheckedConstruction) -> Usage {
  c.usage
}

///|
pub fn construction_pending(
  c : CheckedConstruction,
) -> Array[ConstructionObligation] {
  c.pending.copy()
}

///|
pub fn construction_nodes_name(c : CheckedConstruction) -> String? {
  c.nodes_name
}

///|
pub fn construction_edges_name(c : CheckedConstruction) -> String? {
  c.edges_name
}

///|
pub fn construction_source(c : CheckedConstruction) -> @decode.Cursor {
  c.source
}
