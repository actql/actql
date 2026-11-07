///|
// One same-Request binding read beside a refused original lowerer. It is not
// a checked Program, replacement Source, permission or independent owner.
priv struct ClientRequestQueryRefusalBinding {
  declarations : @parameters.Declarations
  supplied : @decode.Cursor
  limits : @admitted.Limits
  reader : @parameters.BindingReadInput
  base : (Int64, Int64)
  mut retained : Int64
  mut scratch : Int64
  mut work : @resources.PreparationPhaseWorkContinuation64?
  mut returned : Bool
}

///|
// Fixed reader/holder/Result and the SAME continuation's construction controls
// are backed before their constructors. Variable bodies use existing recipes.
fn request_query_refusal_binding_control_bytes() -> Int64? {
  let work = @resources.preparation_phase_work_continuation64_construction_inventory()
  @execution.preparation_representation_cost(
    program_structure_units(
      24L + work.record_headers,
      48L + work.reference_slots,
      24L + work.scalar_words,
    ),
  )
}

///|
fn request_query_binding_collection_bytes(
  value : @shape.CollectionConstructionExtent,
  text? : Int64 = 0L,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  })
}

///|
fn request_query_binding_normalization_bytes(
  value : @canonical.NormalizationConstructionExtent?,
) -> Int64? {
  match value {
    None => Some(0L)
    Some(value) =>
      @execution.preparation_representation_cost({
        record_headers: value.record_headers,
        reference_slots: value.reference_slots,
        scalar_words: value.scalar_words,
        owned_utf16_units: value.owned_utf16_units,
        owned_wire_bytes: 0L,
      })
  }
}

///|
fn[I] request_query_binding_same_original(
  owner : ClientRequestPreparation[I],
  input : I,
  lowering : ClientRequestQueryLowering,
  binding : ClientRequestQueryRefusalBinding,
) -> Bool {
  owner.phase == Selecting &&
  owner.input is Some(original) &&
  physical_equal(original, input) &&
  owner.query_syntax is Some(query) &&
  query.lowering is Some(current) &&
  physical_equal(current, lowering) &&
  lowering.refusal_binding is Some(current_binding) &&
  physical_equal(current_binding, binding) &&
  owner.native_query_declarations is Some((_, declarations)) &&
  physical_equal(declarations, binding.declarations) &&
  owner.native_parameters is Some(supplied) &&
  @decode.tree_index(binding.supplied, supplied) ==
  @decode.tree_index(binding.supplied, binding.supplied) &&
  lowering.binding_limits == Some(binding.limits)
}

///|
fn pause_request_query_refusal_binding(
  lowering : ClientRequestQueryLowering,
) -> Unit {
  if lowering.refusal_binding is Some(binding) &&
    binding.work is Some(work) &&
    !binding.returned {
    if @resources.return_preparation_phase_work_continuation64(work) is Ok(_) {
      binding.returned = true
    }
  }
}

///|
fn[I] finish_request_query_refusal_binding_work(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.query_syntax is Some(query) &&
    query.lowering is Some(lowering) &&
    lowering.refusal_binding is Some(binding) &&
    binding.work is Some(work) {
    match @resources.finish_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => binding.work = None
    }
  }
  Ok(())
}

///|
// Each constructor grows the SAME reservation atomically, retaining the
// original scratch high-water mark and all returned values. Returning work
// suspends this one phase across current callbacks; it never refunds work.
fn[I] grow_request_query_refusal_binding(
  owner : ClientRequestPreparation[I],
  input : I,
  lowering : ClientRequestQueryLowering,
  binding : ClientRequestQueryRefusalBinding,
  retained : Int64,
  scratch : Int64,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard request_query_binding_same_original(owner, input, lowering, binding) else {
    return Err(ForeignOriginal)
  }
  guard @execution.checked_preparation_add_product(
      binding.retained,
      retained,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(binding.base.0, retained, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(binding.base.1, retained, 1L)
    is Some(e) &&
    @execution.checked_preparation_add_product(
      e,
      Int64::max(binding.scratch, scratch),
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  if binding.work is Some(work) && !binding.returned {
    match @resources.return_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => binding.returned = true
    }
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard request_query_binding_same_original(owner, input, lowering, binding) else {
    return Err(ForeignOriginal)
  }
  if binding.work is Some(work) && binding.returned {
    match @resources.resume_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => binding.returned = false
    }
  }
  binding.retained = retained
  binding.scratch = Int64::max(binding.scratch, scratch)
  Ok(())
}

///|
fn[I] finish_request_query_refusal_binding(
  owner : ClientRequestPreparation[I],
  input : I,
  lowering : ClientRequestQueryLowering,
) -> Result[@parameters.Issue?, ClientRequestPreparationIssue] {
  guard owner.phase == QueryLoweringFailed &&
    owner.native_query_declarations is Some((declaration_root, declarations)) &&
    owner.native_parameters is Some(supplied) &&
    lowering.binding_limits is Some(limits) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  // Both admitted inputs already retain their original geometry. This bound
  // covers the one fact walk, header and semantic constructor visits, without
  // substituting a Host ceiling for observed input demand.
  let count = @parameters.declaration_count(declarations).to_int64()
  let nodes = Int::max(
    @decode.admission_usage(declaration_root).nodes,
    @decode.admission_usage(supplied).nodes,
  ).to_int64()
  guard @execution.checked_preparation_add_product(8L, nodes, 8L)
    is Some(per_entry) &&
    @execution.checked_preparation_add_product(1L, count, per_entry)
    is Some(maximum) else {
    return Err(Policy)
  }
  let base = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  let reader = match
    @parameters.prepare_binding_read(declarations, Some(supplied), limits) {
    Err(issue) => return Err(ParameterDeclarations(issue))
    Ok(value) => value
  }
  let binding : ClientRequestQueryRefusalBinding = {
    declarations,
    supplied,
    limits,
    reader,
    base,
    retained: 0L,
    scratch: 0L,
    work: None,
    returned: false,
  }
  lowering.refusal_binding = Some(binding)
  let work = match
    @resources.begin_preparation_phase_work_continuation64(
      owner.capacity,
      input,
      @resources.ParameterBindingBodyInventory,
      maximum,
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(value) => value
  }
  binding.work = Some(work)
  guard request_query_binding_same_original(owner, input, lowering, binding) else {
    return Err(ForeignOriginal)
  }
  guard @parameters.binding_header_construction_extent(reader, 0)
    is Some(header) &&
    request_query_binding_collection_bytes(header) is Some(bytes) else {
    return Err(Policy)
  }
  match
    grow_request_query_refusal_binding(
      owner, input, lowering, binding, bytes, 0L,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @resources.spend_preparation_phase_work_continuation64(work, 1L) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  @parameters.advance_binding_read(reader)
  if @parameters.binding_read_phase(reader) != @parameters.BindingComplete {
    guard @parameters.binding_read_construction_inventory(reader)
      is Some(inventory) &&
      request_query_binding_collection_bytes(inventory.retained)
      is Some(retained) &&
      request_query_binding_collection_bytes(inventory.temporary)
      is Some(scratch) else {
      return Err(Policy)
    }
    match
      grow_request_query_refusal_binding(
        owner, input, lowering, binding, retained, scratch,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    guard @parameters.observe_binding_read_construction(reader) is Some(used) else {
      return Err(Policy)
    }
    match @resources.spend_preparation_phase_work_continuation64(work, used) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => ()
    }
  }
  while @parameters.binding_read_phase(reader) != @parameters.BindingComplete {
    let phase = @parameters.binding_read_phase(reader)
    let (retained, scratch) = match phase {
      BindingSelection => {
        guard @parameters.binding_selection_construction_extent(reader)
          is Some(value) &&
          request_query_binding_collection_bytes(value) is Some(retained) else {
          return Err(Policy)
        }
        (retained, 0L)
      }
      BindingPreflight => {
        guard @parameters.binding_preflight_construction_inventory(reader)
          is Some(value) &&
          request_query_binding_collection_bytes(value.traversal) is Some(a) &&
          request_query_binding_collection_bytes(value.refusal) is Some(b) &&
          request_query_binding_normalization_bytes(value.key_normalization)
          is Some(c) &&
          @execution.checked_preparation_add_product(a, b, 1L) is Some(ab) &&
          @execution.checked_preparation_add_product(ab, c, 1L) is Some(total) else {
          return Err(Policy)
        }
        (0L, total)
      }
      BindingValue => {
        guard @parameters.binding_value_construction_inventory(reader)
          is Some(value) &&
          request_query_binding_collection_bytes(
            value.returned,
            text=value.value.map(v => v.returned_utf16_units).unwrap_or(0L),
          )
          is Some(retained) &&
          request_query_binding_collection_bytes(value.constraints)
          is Some(constraints) else {
          return Err(Policy)
        }
        let scratch = match value.value {
          None => constraints
          Some(value) => {
            guard request_query_binding_collection_bytes(
                value.temporary,
                text=value.temporary_utf16_units,
              )
              is Some(temporary) &&
              request_query_binding_normalization_bytes(value.normalization)
              is Some(normalization) &&
              @execution.checked_preparation_add_product(
                constraints, temporary, 1L,
              )
              is Some(ab) &&
              @execution.checked_preparation_add_product(ab, normalization, 1L)
              is Some(total) else {
              return Err(Policy)
            }
            total
          }
        }
        (retained, scratch)
      }
      _ => return Err(WrongPhase)
    }
    match
      grow_request_query_refusal_binding(
        owner, input, lowering, binding, retained, scratch,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let used = match @parameters.binding_read_current_construction(reader) {
      Some(value) =>
        if phase == BindingSelection {
          1L
        } else {
          1L + value.geometry.map(g => g.nodes.to_int64()).unwrap_or(0L)
        }
      None => return Err(WrongPhase)
    }
    match @resources.spend_preparation_phase_work_continuation64(work, used) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => ()
    }
    @parameters.advance_binding_read(reader)
  }
  match @resources.finish_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  binding.work = None
  guard @parameters.reuse_binding_read(
      reader,
      declarations,
      Some(supplied),
      limits,
    )
    is Some(result) else {
    return Err(ForeignOriginal)
  }
  match result {
    Err(issue) => Ok(Some(issue))
    Ok(_) => Ok(None)
  }
}
