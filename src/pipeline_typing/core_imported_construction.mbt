///|
fn core_imported_retained(
  body : PipelineCoreBody,
) -> @shape.CollectionConstructionExtent? {
  let mut held = pipeline_core_zero_extent
  if body.literal_inputs is Some(values) {
    guard core_imported_array_retained(values.capacity()) is Some(extent) else {
      return None
    }
    held = @shape.add_collection_construction_extents(held, extent).unwrap()
  }
  if body.literal_steps is Some(values) {
    guard core_imported_array_retained(values.capacity()) is Some(extent) else {
      return None
    }
    held = @shape.add_collection_construction_extents(held, extent).unwrap()
  }
  if body.delta_inputs is Some(values) {
    guard core_imported_array_retained(values.capacity()) is Some(extent) else {
      return None
    }
    held = @shape.add_collection_construction_extents(held, extent).unwrap()
    held = @shape.add_collection_construction_extents(
      held,
      body.delta_completed_storage,
    ).unwrap()
    if !values.is_empty() {
      // One retained snapshot of actual completed Map storage, not their bodies again.
      held = @shape.add_collection_construction_extents(held, {
        record_headers: 1L,
        reference_slots: 0L,
        scalar_words: 3L,
      }).unwrap()
    }
  }
  if body.delta_steps is Some(values) {
    guard core_imported_array_retained(values.capacity()) is Some(extent) else {
      return None
    }
    held = @shape.add_collection_construction_extents(held, extent).unwrap()
  }
  if body.literal_read is Some(read) {
    guard @evidence.literal_domains_read_retained_extent(read) is Some(extent) else {
      return None
    }
    held = @shape.compose_collection_construction_extents([
      held,
      extent,
      // Actual selected TransferLimits1H2W and this parent's read Some1H1R1W.
      { record_headers: 2L, reference_slots: 1L, scalar_words: 3L, },
    ]).unwrap()
  }
  if body.delta_pending is Some(pending) {
    guard @shape.map_retained_extent(
        1L,
        pending.fields.capacity().to_int64(),
        pending.fields.length().to_int64(),
      )
      is Some(map) else {
      return None
    }
    held = @shape.compose_collection_construction_extents([
      held,
      map,
      // The original empty_delta record and this same pending Some.
      { record_headers: 2L, reference_slots: 2L, scalar_words: 1L, },
    ]).unwrap()
  }
  if body.delta_iterator is Some(_) {
    held = @shape.compose_collection_construction_extents([
      held,
      @shape.reference_map_iterator_retained_extent(),
      { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
    ]).unwrap()
  }
  if body.delta_field is Some(_) {
    // SAME original iterator pair/Some, not another key/Contract body.
    held = @shape.add_collection_construction_extents(held, {
      record_headers: 2L,
      reference_slots: 3L,
      scalar_words: 1L,
    }).unwrap()
  }
  if body.carrier_read is Some(read) {
    held = @shape.compose_collection_construction_extents([
      held,
      carrier_preflight_controls,
      // This Graph Carrier wrapper is new; its graph remains the original contract's.
      { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
    ]).unwrap()
    if read.contract is Some(contract) {
      guard contract_preflight_retained(contract) is Some(extent) else {
        return None
      }
      held = @shape.add_collection_construction_extents(held, extent).unwrap()
    }
  }
  Some(held)
}

///|
fn core_imported_array_retained(
  capacity : Int,
) -> @shape.CollectionConstructionExtent? {
  guard @shape.reference_array_retained_extent(1L, capacity.to_int64())
    is Some(array) else {
    return None
  }
  @shape.add_collection_construction_extents(array, {
    record_headers: 1L,
    reference_slots: 1L,
    scalar_words: 1L,
  })
}

///|
fn core_imported_array_construction(
  count : Int,
) -> @shape.CollectionConstructionExtent? {
  @shape.collection_construction_extent({
    records: 1L,
    record_references: 1L,
    record_words: 1L,
    reference_arrays: 1L,
    reference_items: count.to_int64(),
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}

///|
fn core_imported_step_construction(
  body : PipelineCoreBody,
) -> CoreStepConstruction? {
  guard body.phase == ImportedEvidence &&
    core_imported_retained(body) is Some(replaced) &&
    @decode.issue_path_construction_extent(
      @decode.admission_usage(body.source).depth.to_int64(),
    )
    is Some(path) &&
    @shape.add_collection_construction_extents(core_input_step_controls, path)
    is Some(base) else {
    return None
  }
  let mut peak = base
  let mut text = 0L
  match body.imported_step {
    LiteralInputs => {
      guard core_imported_array_construction(body.produced_inputs.length())
        is Some(array) else {
        return None
      }
      peak = @shape.add_collection_construction_extents(peak, array).unwrap()
    }
    LiteralDomain =>
      if body.imported_index < body.produced_inputs.length() &&
        body.literal_inputs.unwrap()[body.imported_index] is Some(_) {
        guard @evidence.literal_domains_read_entry_construction(
            @decode.admission_usage(body.source).depth.to_int64(),
          )
          is Some(entry) else {
          return None
        }
        peak = @shape.compose_collection_construction_extents([
          peak,
          entry,
          { record_headers: 2L, reference_slots: 1L, scalar_words: 3L, },
        ]).unwrap()
      }
    LiteralRead => {
      guard @evidence.literal_domains_read_step_construction(
          body.literal_read.unwrap(),
        )
        is Some(step) else {
        return None
      }
      peak = @shape.add_collection_construction_extents(peak, step).unwrap()
    }
    LiteralSteps | DeltaStart | DeltaSteps => {
      guard core_imported_array_construction(0) is Some(array) else {
        return None
      }
      peak = @shape.add_collection_construction_extents(peak, array).unwrap()
    }
    DeltaInput =>
      if body.imported_index < body.produced_inputs.length() {
        guard @shape.map_construction_extent(1L, 0L) is Some(map) else {
          return None
        }
        peak = @shape.compose_collection_construction_extents([
          peak,
          {
            record_headers: map.record_headers,
            reference_slots: map.reference_slots,
            scalar_words: map.scalar_words,
          },
          { record_headers: 2L, reference_slots: 2L, scalar_words: 1L, },
        ]).unwrap()
        if body.produced_inputs[body.imported_index] is Some(_) {
          peak = @shape.compose_collection_construction_extents([
            peak,
            @shape.reference_map_iterator_construction_extent(),
            { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
          ]).unwrap()
        }
      }
    DeltaField => {
      let utf8 = @scalar.utf8_length_admission_construction_units()
      peak = @shape.compose_collection_construction_extents([
        peak,
        @shape.reference_map_iterator_next_construction_extent(),
        carrier_preflight_controls,
        {
          record_headers: utf8.0,
          reference_slots: utf8.1,
          scalar_words: utf8.2,
        },
        { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
      ]).unwrap()
    }
    DeltaCarrier => {
      guard carrier_preflight_step_construction(body.carrier_read.unwrap())
        is Some(step) else {
        return None
      }
      peak = @shape.add_collection_construction_extents(peak, step.peak).unwrap()
      text = step.peak_utf16_units
    }
    DeltaRegister => {
      let fields = body.delta_pending.unwrap().fields
      guard @shape.map_construction_extent(1L, fields.length().to_int64() + 1L)
        is Some(grow) &&
        @shape.map_retained_extent(
          1L,
          fields.capacity().to_int64(),
          fields.length().to_int64(),
        )
        is Some(old) &&
        grow.record_headers >= old.record_headers &&
        grow.reference_slots >= old.reference_slots &&
        grow.scalar_words >= old.scalar_words else {
        return None
      }
      peak = @shape.add_collection_construction_extents(peak, {
        record_headers: grow.record_headers - old.record_headers,
        reference_slots: grow.reference_slots - old.reference_slots,
        scalar_words: grow.scalar_words - old.scalar_words,
      }).unwrap()
    }
    DeltaAppend => {
      let values = body.delta_inputs.unwrap()
      guard @shape.reference_array_push_construction_extent(
          values.length(),
          values.capacity(),
        )
        is Some(backing) else {
        return None
      }
      // Actual map-retained quote8H1R16W, wrapper descriptor1H1R, and
      // two shared extent sums10H2R20W. Prior sum stays with replaced
      // until this constructor returns; this is not another Map traversal.
      peak = @shape.compose_collection_construction_extents([
        peak,
        backing,
        { record_headers: 19L, reference_slots: 4L, scalar_words: 36L, },
      ]).unwrap()
    }
  }
  Some({ peak, peak_utf16_units: text, replaced, })
}
