///|
/// The same imported Maps remain the mutable domain. Qualified key spellings
/// become owned Map storage; no earlier schema or Graph-contract body copies.
fn core_delta_binding_holdings(
  body : PipelineCoreBody,
) -> PipelineEvidenceStepHoldings? {
  guard core_imported_retained(body) is Some(held) else { return None }
  let mut held = held
  let mut text = body.delta_bound_name_units
  if body.delta_binding is Some(_) {
    held = @shape.add_collection_construction_extents(held, {
      record_headers: 1L,
      reference_slots: 1L,
      scalar_words: 1L,
    }).unwrap()
  }
  if body.delta_binding_key is Some(_) {
    guard core_delta_binding_original(body) is Some((_, field, _)) else {
      return None
    }
    let spelling = @schema.reference_name_construction_extent(field)
    held = @shape.add_collection_construction_extents(held, spelling.scratch).unwrap()
    text = @capacity.checked_nonnegative_add_product(
      text,
      spelling.scratch_utf16_units,
      1L,
    ).unwrap()
    held = @shape.add_collection_construction_extents(held, {
      record_headers: 1L,
      reference_slots: 1L,
      scalar_words: 1L,
    }).unwrap()
  }
  if body.delta_binding_old is Some(_) {
    held = @shape.add_collection_construction_extents(held, {
      // Same actual-storage snapshot record and its original parent Some.
      record_headers: 2L,
      reference_slots: 1L,
      scalar_words: 4L,
    }).unwrap()
  }
  held = @shape.add_collection_construction_extents(held, {
    record_headers: body.delta_bound_name_headers,
    reference_slots: 0L,
    scalar_words: 0L,
  }).unwrap()
  Some({ extent: held, owned_utf16_units: text, inspection_work: 0L, })
}

///|
fn core_delta_binding_step_construction(
  body : PipelineCoreBody,
) -> CoreStepConstruction? {
  guard body.phase == DeltaContracts &&
    core_delta_binding_holdings(body) is Some(old) &&
    @decode.issue_path_construction_extent(
      @decode.admission_usage(body.source).depth.to_int64(),
    )
    is Some(path) &&
    @shape.add_collection_construction_extents(core_input_step_controls, path)
    is Some(peak) else {
    return None
  }
  let mut peak = peak
  let mut text = 0L
  if body.delta_binding_step != Count &&
    core_delta_binding_original(body) is None {
    return None
  }
  match body.delta_binding_step {
    Count =>
      peak = @shape.add_collection_construction_extents(peak, {
        record_headers: 1L,
        reference_slots: 1L,
        scalar_words: 1L,
      }).unwrap()
    Name => {
      let (name, _, _) = body.delta_binding.unwrap()
      guard @canonical.nfc_lf_construction_extent(name.length()) is Some(nfc) else {
        return None
      }
      peak = @shape.add_collection_construction_extents(peak, {
        record_headers: nfc.record_headers,
        reference_slots: nfc.reference_slots,
        scalar_words: nfc.scalar_words,
      }).unwrap()
      text = nfc.owned_utf16_units
    }
    Target => ()
    Field => {
      let (_, field, _) = body.delta_binding.unwrap()
      let spelling = @schema.reference_name_construction_extent(field)
      let utf8 = @scalar.utf8_length_admission_construction_units()
      peak = @shape.compose_collection_construction_extents([
        peak,
        @carrier.lookup_construction_extent(),
        spelling.scratch,
        carrier_preflight_controls,
        {
          record_headers: utf8.0,
          reference_slots: utf8.1,
          scalar_words: utf8.2,
        },
        // Map retained-observation8H1R16W, key/old snapshot Some2H2R2W,
        // original Graph Carrier wrapper1H1R1W.
        { record_headers: 11L, reference_slots: 4L, scalar_words: 19L, },
      ]).unwrap()
      text = spelling.scratch_utf16_units
    }
    Carrier => {
      guard carrier_preflight_step_construction(body.carrier_read.unwrap())
        is Some(child) else {
        return None
      }
      peak = @shape.add_collection_construction_extents(peak, child.peak).unwrap()
      text = child.peak_utf16_units
    }
    Register => {
      let fields = body.delta_inputs.unwrap()[body.delta_binding_target].fields
      let old_map = body.delta_binding_old.unwrap()
      guard @shape.map_construction_extent(1L, fields.length().to_int64() + 1L)
        is Some(grow) &&
        grow.record_headers >= old_map.record_headers &&
        grow.reference_slots >= old_map.reference_slots &&
        grow.scalar_words >= old_map.scalar_words else {
        return None
      }
      peak = @shape.compose_collection_construction_extents([
        peak,
        {
          record_headers: grow.record_headers - old_map.record_headers,
          reference_slots: grow.reference_slots - old_map.reference_slots,
          scalar_words: grow.scalar_words - old_map.scalar_words,
        },
        // Actual after-Map quote8/1/16, extent delta descriptor1/0/3,
        // sum5/1/10, spelling geometry4/4/7 and two checked counters2/0/4;
        // the next original binding Some1/1/1 is captured in this same return.
        { record_headers: 21L, reference_slots: 7L, scalar_words: 41L, },
      ]).unwrap()
    }
  }
  Some({
    peak,
    peak_utf16_units: text,
    replaced: old.extent,
    replaced_utf16_units: old.owned_utf16_units,
  })
}
