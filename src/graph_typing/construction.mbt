///|
pub(all) enum ConstructionObligation {
  AdmitGraphInputRows
  RejectDuplicateDefinitionKeys
  ExcludeNullKeysAndMissingEndpoints
  ResolveGraphConstructionResources
  ResolvePropertyGraphProfile
} derive(Eq, Debug)

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
