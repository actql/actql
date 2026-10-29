///|
/// Original retained compiler controls only, not schema/keys/ranking/core
/// bodies, an allowance, tariff or physical first-prelude. Read1H1R;
/// body1H10R5W; Reading1H1R1W; two overlapping phase alternatives2H6R2W;
/// four entry/advance/take Result/Option alternatives4H4R7W.
pub fn pipeline_evidence_read_control_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 9L, reference_slots: 22L, scalar_words: 15L, }
}

///|
/// Read/body/Reading/selected phase4H15R7W. Phase storage uses its maximum
/// original three-reference payload, including before those slots are filled.
pub fn pipeline_evidence_read_control_retained_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 4L, reference_slots: 15L, scalar_words: 7L, }
}

///|
/// The actual original map borrows every input name, complete schema and
/// producer. Each tuple is new; only Keyed/CandidateKeys add Relation variants.
/// Before that constructor, the same original input count bounds both branches.
pub(all) struct PipelineEvidenceStepConstruction {
  peak : @shape.CollectionConstructionExtent
  peak_utf16_units : Int64
  inspection_work : Int64
  replaced : @shape.CollectionConstructionExtent
  replaced_utf16_units : Int64
}

///|
pub(all) struct PipelineEvidenceStepHoldings {
  extent : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
  inspection_work : Int64
}

///|
pub fn pipeline_evidence_read_step_construction(
  original : PipelineEvidenceRead,
) -> PipelineEvidenceStepConstruction? {
  guard original.state is Reading(body) else { return None }
  if body.step is Carriers {
    return pipeline_carriers_construction(original).map(peak => {
      peak,
      peak_utf16_units: 0L,
      inspection_work: 0L,
      replaced: pipeline_core_zero_extent,
      replaced_utf16_units: 0L,
    })
  }
  if body.step is Core(_, _, _) {
    guard pipeline_core_read_entry_construction(
        body.source,
        body.inputs.length(),
      )
      is Some(core) &&
      @shape.collection_construction_extent({
        records: body.inputs.length().to_int64(),
        record_references: body.inputs.length().to_int64(),
        record_words: body.inputs.length().to_int64() + 6L,
        reference_arrays: 2L,
        reference_items: 2L * body.inputs.length().to_int64(),
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 0L,
        map_entries: 0L,
      })
      is Some(arguments) &&
      @shape.compose_collection_construction_extents([
        core,
        arguments,
        // Original selected core Limits1H6W and entry/phase alternatives.
        { record_headers: 4L, reference_slots: 3L, scalar_words: 4L, },
      ])
      is Some(peak) else {
      return None
    }
    return Some({
      peak,
      peak_utf16_units: 0L,
      inspection_work: 0L,
      replaced: pipeline_core_zero_extent,
      replaced_utf16_units: 0L,
    })
  }
  if body.step is CoreRunning(read) && read.state is Reading(core) {
    let quote = match core.phase {
      Inputs => core_input_step_construction(core)
      Parameters => core_parameter_step_construction(core)
      ImportedEvidence => core_imported_step_construction(core)
      DeltaContracts => core_delta_binding_step_construction(core)
      _ => None
    }
    guard quote is Some(q) else { return None }
    return Some({
      peak: q.peak,
      peak_utf16_units: q.peak_utf16_units,
      inspection_work: 0L,
      replaced: q.replaced,
      replaced_utf16_units: q.replaced_utf16_units,
    })
  }
  let keys = match body.step {
    Keys(_) => true
    Rankings(_, _) => false
    _ => return None
  }
  let n = body.inputs.length().to_int64()
  guard pipeline_evidence_array_construction(n) is Some(array) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
      n,
    )
    is Some(options) else {
    return None
  }
  let mut held = options
  let mut scratch : @shape.CollectionConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  let mut held_text = 0L
  let mut scratch_text = 0L
  let mut work = 0L
  for (_, input) in body.inputs {
    work += 1L
    if input is SourceViewInput(_, _, _, view) {
      let quote = if keys {
        @evidence.source_view_key_construction_inventory(view)
      } else {
        @evidence.source_view_ranking_construction_inventory(view)
      }
      guard quote is Some(q) &&
        @shape.add_collection_construction_extents(held, q.retained)
        is Some(next) else {
        return None
      }
      held = next
      held_text += q.retained_utf16_units
      scratch = pipeline_evidence_max_extent(scratch, q.scratch)
      scratch_text = Int64::max(scratch_text, q.scratch_utf16_units)
      work += q.inspection_work
    } else if keys && input is KeyedInput(_) {
      guard pipeline_evidence_array_construction(1L) is Some(singleton) &&
        @shape.compose_collection_construction_extents([
          held,
          singleton,
          { record_headers: 1L, reference_slots: 2L, scalar_words: 2L, },
        ])
        is Some(next) else {
        return None
      }
      held = next
    }
  }
  @shape.compose_collection_construction_extents([
    array,
    held,
    scratch,
    // Original selected Limits/usage/getter/Some/Result/phase/loop controls.
    { record_headers: 12L, reference_slots: 10L, scalar_words: 12L, },
  ]).map(peak => {
    peak,
    peak_utf16_units: held_text + scratch_text,
    inspection_work: work,
    replaced: pipeline_core_zero_extent,
    replaced_utf16_units: 0L,
  })
}

///|
fn pipeline_evidence_array_construction(
  n : Int64,
) -> @shape.CollectionConstructionExtent? {
  @shape.collection_construction_extent({
    records: 0L,
    record_references: 0L,
    record_words: 0L,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}

///|
fn pipeline_evidence_max_extent(
  a : @shape.CollectionConstructionExtent,
  b : @shape.CollectionConstructionExtent,
) -> @shape.CollectionConstructionExtent {
  {
    record_headers: Int64::max(a.record_headers, b.record_headers),
    reference_slots: Int64::max(a.reference_slots, b.reference_slots),
    scalar_words: Int64::max(a.scalar_words, b.scalar_words),
  }
}

///|
fn pipeline_carriers_construction(
  original : PipelineEvidenceRead,
) -> @shape.CollectionConstructionExtent? {
  guard original.state is Reading(body) && body.step is Carriers else {
    return None
  }
  let n = body.inputs.length().to_int64()
  guard @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(array) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 2L, reference_slots: 3L, scalar_words: 1L, },
      n,
    )
    is Some(entries) else {
    return None
  }
  // map/constructor closure2H2R; next phase1H1R1W; original input/owner/
  // knowledge access alternatives3H5R4W; returned phase/Result2H2R5W.
  @shape.compose_collection_construction_extents([
    array,
    entries,
    { record_headers: 8L, reference_slots: 10L, scalar_words: 10L, },
  ])
}

///|
/// Observe actual retained buffer capacity and the constructor's own wrapper
/// count. No second carrier/schema traversal, clone, key admission or text scan.
/// This is only the new carrier delta; fixed reader controls stay with parent.
pub fn pipeline_evidence_read_carriers_retained_extent(
  original : PipelineEvidenceRead,
) -> @shape.CollectionConstructionExtent? {
  guard original.state is Reading(body) && body.step is Keys(carriers) else {
    return None
  }
  guard @shape.reference_array_retained_extent(
      1L,
      carriers.capacity().to_int64(),
    )
    is Some(array) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 1L, reference_slots: 2L, scalar_words: 0L, },
      carriers.length().to_int64(),
    )
    is Some(tuples) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
      body.carrier_wrappers.to_int64(),
    )
    is Some(wrappers) else {
    return None
  }
  @shape.compose_collection_construction_extents([array, tuples, wrappers])
}

///|
/// Actual newly constructed key/ranking delta. Borrowed Produced/Candidate/
/// Ranking input bodies are not traversed. Only Source outputs are new full
/// witnesses; singleton_key owns a new container around its borrowed witness.
pub fn pipeline_evidence_read_step_holdings(
  original : PipelineEvidenceRead,
  previous : PipelineEvidenceReadPhase,
) -> PipelineEvidenceStepHoldings? {
  guard original.state is Reading(body) else { return None }
  if body.step is CoreRunning(read) {
    guard read.state is Reading(core) else { return None }
    if previous == CoreInputs {
      guard (core.phase == Inputs || core.phase == Parameters) &&
        core_input_retained(core) is Some(extent) else {
        return None
      }
      return Some({ extent, owned_utf16_units: 0L, inspection_work: 0L, })
    }
    if previous == CoreParameters {
      guard (core.phase == Parameters || core.phase == ImportedEvidence) &&
        core_parameter_retained(core) is Some(extent) else {
        return None
      }
      return Some({ extent, owned_utf16_units: 0L, inspection_work: 0L, })
    }
    if previous == CoreImportedEvidence {
      guard (core.phase == ImportedEvidence || core.phase == DeltaContracts) &&
        core_imported_retained(core) is Some(extent) else {
        return None
      }
      return Some({ extent, owned_utf16_units: 0L, inspection_work: 0L, })
    }
    if previous == CoreDeltaContracts {
      guard core.phase == DeltaContracts || core.phase == Steps else {
        return None
      }
      return core_delta_binding_holdings(core)
    }
    guard previous == Core else { return None }
    guard core.phase == Inputs &&
      pipeline_core_read_entry_holdings(read) is Some(held) &&
      @shape.reference_array_retained_extent(
        2L,
        core.produced_inputs.capacity().to_int64() +
        core.input_contracts.capacity().to_int64(),
      )
      is Some(arguments) &&
      @shape.scale_collection_construction_extent(
        { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
        body.core_produced_wrappers.to_int64(),
      )
      is Some(options) &&
      @shape.compose_collection_construction_extents([
        held,
        arguments,
        options,
        { record_headers: 1L, reference_slots: 0L, scalar_words: 6L, },
      ])
      is Some(extent) else {
      return None
    }
    return Some({ extent, owned_utf16_units: 0L, inspection_work: 0L, })
  }
  let (keys, values, rankings) = match body.step {
    Rankings(_, values) =>
      if previous == Keys {
        (true, Some(values), None)
      } else {
        return None
      }
    Core(_, _, values) =>
      if previous == Rankings {
        (false, None, Some(values))
      } else {
        return None
      }
    _ => return None
  }
  let capacity = if keys {
    values.unwrap().capacity()
  } else {
    rankings.unwrap().capacity()
  }
  guard @shape.reference_array_retained_extent(1L, capacity.to_int64())
    is Some(array) else {
    return None
  }
  let mut held = array
  let mut text = 0L
  let mut work = 0L
  for index, (_, input) in body.inputs {
    work += 1L
    let mut option = false
    if keys {
      let value = values.unwrap()[index]
      match input {
        SourceViewInput(_, _, _, _) =>
          if value is Some(value) {
            guard @evidence.source_key_set_retained_construction(value)
              is Some(q) &&
              @shape.add_collection_construction_extents(held, q.extent)
              is Some(next) else {
              return None
            }
            held = next
            work += q.observation_work
            option = true
          }
        KeyedInput(_) => {
          guard value is Some(value) &&
            @evidence.key_set_container_retained_extent(value)
            is Some(container) &&
            @shape.add_collection_construction_extents(held, container)
            is Some(next) else {
            return None
          }
          held = next
          work += 1L
          option = true
        }
        CandidateKeysInput(_) | RelationEvidenceInput(_) => option = true
        _ => ()
      }
    } else {
      let value = rankings.unwrap()[index]
      match input {
        SourceViewInput(_, _, _, _) =>
          if value is Some(value) {
            guard @evidence.source_ranking_retained_construction(value)
              is Some(q) &&
              @shape.add_collection_construction_extents(held, q.extent)
              is Some(next) else {
              return None
            }
            held = next
            text += q.owned_utf16_units
            work += q.observation_work
            option = true
          }
        RankingInput(_) | RelationEvidenceInput(_) => option = true
        _ => ()
      }
    }
    if option {
      guard @shape.add_collection_construction_extents(held, {
          record_headers: 1L,
          reference_slots: 1L,
          scalar_words: 1L,
        })
        is Some(next) else {
        return None
      }
      held = next
    }
  }
  Some({ extent: held, owned_utf16_units: text, inspection_work: work, })
}
