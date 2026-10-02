///|
pub(all) enum ConstructionObligation {
  AdmitGraphInputRows
  CloseBothEndpointsAgainstDeclaredNodes
  DeriveDistinctEndpointNodes
  JournalEndpointCompletion
  JournalLabelCompletion
  CollapseEqualIdentityPayloads
  RejectConflictingIdentityPayloads
  RejectDuplicateDefinitionKeys
  ExcludeNullKeysAndMissingEndpoints
  ResolveGraphConstructionResources
  ResolveSgaProfile
  ResolvePropertyGraphProfile
} derive(Eq, Debug)

///|
// A retired checked type is retained temporarily for downstream source
// migration, but its former admission factory can no longer construct it.
#warnings("-struct_never_constructed")
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
fn construction_name(at : @decode.Cursor) -> String raise Stop {
  let s = decoded(@decode.text(at))
  if s.is_empty() || @canonical.normalize_nfc_lf(s) != Ok(s) {
    fail(at, InvalidName(s))
  }
  s
}

///|
/// The endpoint-tuple constructor is retired. It cannot infer independent edge
/// keys or definition identity; use the admitted Property Graph constructor.
pub fn check_construction(
  source : @decode.Cursor,
  _nodes : @carrier.Carrier?,
  _edges : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedConstruction, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    fail(source, UnsupportedGraphOperation)
  } catch {
    Stop(issue) => Err(issue)
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
/// O(1), without materializing the obligation array.
pub fn construction_pending_count(c : CheckedConstruction) -> Int {
  c.pending.length()
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn construction_pending_at(
  c : CheckedConstruction,
  index : Int,
) -> ConstructionObligation? {
  c.pending.get(index)
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
