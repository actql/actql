///|
/// SAME selected name/source preflight with its current remaining binding
/// Budget. The recipe is shared with original declaration preflight; selected
/// defaults still spend this budget without another default Value admission.
pub fn binding_preflight_construction_inventory(
  original : BindingReadInput,
) -> DeclarationPreflightConstructionInventory? {
  guard original.state is ReadingBinding(body) &&
    body.phase == BindingPreflight &&
    body.construction is Some(completed) &&
    completed.entries[body.index] is Some(current) &&
    current.geometry is Some(geometry) else {
    return None
  }
  guard parameter_preflight_construction_inventory(
      geometry,
      current.depth,
      body.budget.nodes,
      body.budget.depth,
      body.budget.text,
    )
    is Some(preflight) &&
    @shape.add_collection_construction_extents(
      preflight.refusal,
      binding_issue_origin_construction_extent(),
    )
    is Some(refusal) else {
    return None
  }
  Some({ ..preflight, refusal, })
}

///|
/// Constructed output of the original binding Value step. Default CheckedValue
/// stays borrowed from its declaration; only a supplied value selects the SAME
/// Value/constraints constructor owners. Neither quantity admits a value.
pub(all) struct BindingValueConstructionInventory {
  returned : @shape.CollectionConstructionExtent
  constraints : @shape.CollectionConstructionExtent
  value : @value.ParameterValuePhaseConstructionInventory?
} derive(Eq, Debug)

///|
pub fn binding_value_construction_inventory(
  original : BindingReadInput,
) -> BindingValueConstructionInventory? {
  guard original.state is ReadingBinding(body) &&
    body.phase == BindingValue &&
    body.construction is Some(completed) &&
    completed.entries[body.index] is Some(current) &&
    current.geometry is Some(geometry) else {
    return None
  }
  // BoundParameter3R1W plus3 incremental growing-entry slots. Header owns
  // the SAME Array wrapper/backing; it is not expanded once per entry.
  let entry : @shape.CollectionConstructionExtent = {
    record_headers: 1L,
    reference_slots: 6L,
    scalar_words: 1L,
  }
  let returned = if body.index + 1 == original.declarations.entries.length() {
    guard @shape.add_collection_construction_extents(
        entry,
        binding_completion_construction_extent(),
      )
      is Some(value) else {
      return None
    }
    value
  } else {
    entry
  }
  if !current.provided {
    return Some({
      returned,
      constraints: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
      },
      value: None,
    })
  }
  guard @value.parameter_syntax_value_phase_construction_inventory(
      current.declaration.syntax,
      geometry,
      current.depth.to_int64(),
      original.limits.max_depth,
    )
    is Some(value) &&
    @shape.add_collection_construction_extents(
      value.temporary,
      binding_issue_construction_extent(),
    )
    is Some(temporary) &&
    @shape.add_collection_construction_extents(returned, value.returned)
    is Some(returned) &&
    @decode.cursor_path_construction_extent(
      current.depth.to_int64() +
      Int64::min(
        geometry.nodes.to_int64(),
        original.limits.max_depth.to_int64() + 1L,
      ) +
      1L,
    )
    is Some(path) &&
    parameter_constraints_construction_extent(current.geometry, path)
    is Some(constraints) &&
    @shape.add_collection_construction_extents(
      constraints,
      binding_issue_origin_construction_extent(),
    )
    is Some(constraints) else {
    return None
  }
  Some({ returned, constraints, value: Some({ ..value, temporary, }), })
}
