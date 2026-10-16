///|
fn keyed_effect_operation(kind : @query.KeyedEffectKind) -> String {
  match kind {
    Update => "update"
    Upsert => "upsert"
    Delete => "delete"
  }
}

///|
fn keyed_effect_candidates(
  publication : UpdateTargetPublication,
  kind : @query.KeyedEffectKind,
  max_work : Int,
) -> Result[(Array[@environment.MappingContractShape], Int), UpdateTargetIssue] {
  if max_work < 0 {
    return Err(WorkLimit)
  }
  let candidates : Array[@environment.MappingContractShape] = []
  let mut remaining = max_work
  for index in 0..<@environment.mapping_shape_count(publication.mappings) {
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let mapping = @environment.mapping_shape_at(publication.mappings, index).unwrap()
    let (supported, work) = match
      @environment.mapping_supports_operation(
        mapping,
        keyed_effect_operation(kind),
        if kind == Upsert {
          "key"
        } else {
          "id"
        },
        remaining,
      ) {
      Ok(value) => value
      Err(@environment.MappingPermissionIssue::WorkLimit) =>
        return Err(WorkLimit)
      Err(_) => return Err(InvalidPublication)
    }
    remaining -= work
    if supported {
      candidates.push(mapping)
    }
  }
  Ok((candidates, remaining))
}

///|
/// Select the exact declared keyed operation using the same original Mapping
/// inventory. UPDATE retains its historical path and charged work unchanged.
pub fn resolve_keyed_effect_target_binding(
  publication : UpdateTargetPublication,
  kind : @query.KeyedEffectKind,
  name : Array[@query.NamePart],
  explicit_mapping : @query.NamePart?,
  max_work : Int,
) -> Result[ResolvedUpdateTarget, UpdateTargetIssue] {
  if kind == Update {
    return resolve_update_target_binding(
      publication, name, explicit_mapping, max_work,
    )
  }
  let (candidates, remaining) = match
    keyed_effect_candidates(publication, kind, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  resolve_effect_target_candidates(
    publication, candidates, name, explicit_mapping, remaining,
  )
}

///|
/// Concrete original-pair lookup for the existing captured Effect owner.
/// The header supplies the operation; this selection does not grant execution.
pub fn resolve_concrete_keyed_effect_target_binding(
  publication : UpdateTargetPublication,
  kind : @query.KeyedEffectKind,
  target : String,
  mapping_reference : String,
  max_work : Int,
) -> Result[ResolvedUpdateTarget, UpdateTargetIssue] {
  if kind == Update {
    return resolve_concrete_update_target_binding(
      publication, target, mapping_reference, max_work,
    )
  }
  let (candidates, remaining) = match
    keyed_effect_candidates(publication, kind, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  resolve_concrete_effect_target_candidates(
    publication, candidates, target, mapping_reference, remaining,
  )
}
