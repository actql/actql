///|
/// Original constructor overlap, not a checked Program, Resource grant or
/// byte tariff. All counts come from the SAME current typed read state.
pub(all) struct LocalProgramReadStepConstruction {
  peak : @shape.CollectionConstructionExtent
  peak_utf16_units : Int64
} derive(Eq, Debug)

///|
fn topology_reference_array_peak(
  items : Int64,
) -> @shape.CollectionConstructionExtent? {
  @shape.collection_construction_extent({
    records: 0L,
    record_references: 0L,
    record_words: 0L,
    reference_arrays: 1L,
    reference_items: items,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}

///|
fn topology_map_peak(entries : Int64) -> @shape.CollectionConstructionExtent? {
  @shape.map_construction_extent(1L, entries).map(v => {
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
  })
}

///|
// Original publication import branch. Producer and Result bodies are borrowed;
// only producer/raw-entry/mapped-entry arrays, their original entry records,
// the producer index and one sequential name-list buffer are constructed.
fn topology_import_peak(
  producers : Int64,
  imports : Int64,
) -> @shape.CollectionConstructionExtent? {
  guard topology_reference_array_peak(producers) is Some(a) &&
    topology_reference_array_peak(imports) is Some(b) &&
    topology_reference_array_peak(imports) is Some(c) &&
    topology_reference_array_peak(3L) is Some(names) &&
    topology_map_peak(producers) is Some(known) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 2L, reference_slots: 6L, scalar_words: 0L, },
      imports,
    )
    is Some(entries) else {
    return None
  }
  // Limits1H3W; raw return/tuple2H2R3W; ResultImports1H2R3W;
  // child/wrapped Result/variant3H3R3W; usage pair1H2W; five map/selector
  // closures5H; lookup3H2R3W; four original stage/import/index Some4H4R4W;
  // active UTF8 scalar/Int results4H1R7W and error2H1R3W;
  // original import-issue alternatives2H3R2W. No text/byte buffer is encoded.
  let controls : @shape.CollectionConstructionExtent = {
    record_headers: 28L,
    reference_slots: 18L,
    scalar_words: 33L,
  }
  @shape.compose_collection_construction_extents([
    a, b, c, names, known, entries, controls,
  ])
}

///|
fn topology_input_peak(
  local_count : Int64,
  imports : Int64,
  remote_count : Int64,
  fields : Int,
) -> @shape.CollectionConstructionExtent? {
  guard @counts.checked_nonnegative_add_product(local_count, imports, 1L)
    is Some(total) &&
    @counts.checked_nonnegative_add_product(total, remote_count, 1L)
    is Some(total) &&
    topology_reference_array_peak(total) is Some(inputs) &&
    topology_map_peak(remote_count) is Some(names) &&
    @decode.open_object_construction_extent(fields) is Some(body) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 2L, reference_slots: 3L, scalar_words: 1L, },
      imports,
    )
    is Some(import_entries) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 1L, reference_slots: 2L, scalar_words: 0L, },
      remote_count,
    )
    is Some(remote_entries) else {
    return None
  }
  // Same required(inputs) indexed child4H4R4W +Ok1H1R1W and length Some1H2W;
  // active original local/import getters and tuple3H4R2W, remote partition/
  // declaration/key2H2R3W +key tuple1H1R1W; issue alternatives2H1R4W.
  // Local registrations are borrowed tuples; Result wrappers and remote tuples
  // above are the actual new entries. The names index unwinds before Pipeline.
  let controls : @shape.CollectionConstructionExtent = {
    record_headers: 14L,
    reference_slots: 13L,
    scalar_words: 17L,
  }
  @shape.compose_collection_construction_extents([
    inputs, names, body, import_entries, remote_entries, controls,
  ])
}

///|
/// Observe original constructor dimensions. Simple branches use constant-time
/// getters; key/ranking metadata walks are counted on the SAME parent. No UTF8
/// scan, import resolution, schema/key/type admission is repeated here.
pub fn local_program_read_step_construction(
  original : LocalProgramRead,
) -> LocalProgramReadStepConstruction? {
  guard original.state is Reading(body) &&
    !body.check_only &&
    body.environment is Some(_) else {
    return None
  }
  if body.stage is PipelineRead(_, _, _, _, _, _, _, read) {
    guard @pipeline.pipeline_evidence_read_step_construction(read) is Some(q) &&
      record_local_program_read_inspection(original, q.inspection_work) else {
      return None
    }
    return Some({ peak: q.peak, peak_utf16_units: q.peak_utf16_units, })
  }
  let peak = match body.stage {
    LocalInputs =>
      Some(local_program_read_reconciled_input_construction_extent())
    StageImports(stage, _, _, _) =>
      topology_import_peak(
        body.stages.length().to_int64(),
        @syntax.import_count(stage).to_int64(),
      )
    InputRegistration(stage, _, prepared, _, resolved, _, _) => {
      guard @decode.object_length(@syntax.stage_body(stage)) is Some(fields) else {
        return None
      }
      let remote = match body.sourceview_registrations {
        Some(registrations) => registrations[body.index].length()
        None => 0
      }
      topology_input_peak(
        @local.count(prepared).to_int64(),
        program_import_count(resolved).to_int64(),
        remote.to_int64(),
        fields,
      )
    }
    Pipeline(_, _, _, _, _, _, _, _) => {
      // Original steps/from Cursor calls, selected Declarations Some and
      // Limits/empty-delta arguments; no schema/type/keys body is constructed.
      guard @shape.collection_construction_extent({
          records: 0L,
          record_references: 0L,
          record_words: 0L,
          reference_arrays: 1L,
          reference_items: 0L,
          scalar_arrays: 0L,
          scalar_items: 0L,
          maps: 0L,
          map_entries: 0L,
        })
        is Some(delta) else {
        return None
      }
      @shape.compose_collection_construction_extents([
        @pipeline.pipeline_evidence_read_control_construction_extent(),
        @decode.indexed_child_construction_extent(),
        @decode.indexed_child_construction_extent(),
        delta,
        // Limits1H6W; selected declarations/from2H2R2W;
        // required Ok and original entry getters3H3R4W.
        { record_headers: 6L, reference_slots: 5L, scalar_words: 12L, },
      ])
    }
    _ => None
  }
  peak.map(peak => { peak, peak_utf16_units: 0L, })
}

///|
/// Original successful post-constructor holdings only. Actual current buffer/
/// bucket capacities are observed, never inferred from policy maxima. Prior
/// holdings stay with the same read and are not counted again in this delta.
fn local_program_read_step_retained_extent_owned(
  original : LocalProgramRead,
  previous : LocalProgramReadPhase,
) -> @shape.CollectionConstructionExtent? {
  guard original.state is Reading(body) else { return None }
  match (previous, body.stage) {
    (LocalInputs, StageImports(_, _, _, _)) =>
      Some(local_program_read_reconciled_input_retained_extent())
    (Imports, InputRegistration(_, _, _, _, Publication(v), _, _)) => {
      guard @shape.reference_array_retained_extent(
          1L,
          v.entries.capacity().to_int64(),
        )
        is Some(array) &&
        @shape.scale_collection_construction_extent(
          { record_headers: 1L, reference_slots: 3L, scalar_words: 0L, },
          v.entries.length().to_int64(),
        )
        is Some(entries) else {
        return None
      }
      @shape.compose_collection_construction_extents([
        array,
        entries,
        { record_headers: 2L, reference_slots: 3L, scalar_words: 4L, },
      ])
    }
    (InputRegistration, Pipeline(_, prepared, _, resolved, _, _, object, inputs)
    ) => {
      guard @shape.reference_array_retained_extent(
          1L,
          inputs.capacity().to_int64(),
        )
        is Some(array) &&
        @decode.object_view_retained_extent(object) is Some(object) &&
        @shape.scale_collection_construction_extent(
          { record_headers: 2L, reference_slots: 3L, scalar_words: 1L, },
          program_import_count(resolved).to_int64(),
        )
        is Some(imports) else {
        return None
      }
      let _ = prepared
      let remote_count = match body.sourceview_registrations {
        Some(registrations) => registrations[body.index].length()
        None => 0
      }
      guard @shape.scale_collection_construction_extent(
          { record_headers: 1L, reference_slots: 2L, scalar_words: 0L, },
          remote_count.to_int64(),
        )
        is Some(remote) else {
        return None
      }
      @shape.compose_collection_construction_extents([
        array, object, imports, remote,
      ])
    }
    (Pipeline, PipelineRead(_, _, _, _, _, _, _, read)) => {
      guard @pipeline.pipeline_evidence_read_phase(read) == @pipeline.Carriers &&
        @shape.reference_array_retained_extent(1L, 0L) is Some(delta) else {
        return None
      }
      @shape.compose_collection_construction_extents([
        @pipeline.pipeline_evidence_read_control_retained_extent(),
        delta,
        // Limits1H6W; declarations/from Some2H2R2W and the two
        // original steps/from Cursor wrappers2H4R2W. Tree backing borrowed.
        { record_headers: 5L, reference_slots: 6L, scalar_words: 10L, },
      ])
    }
    (PipelineCarriers, PipelineRead(_, _, _, _, _, _, _, read)) =>
      @pipeline.pipeline_evidence_read_carriers_retained_extent(read)
    _ => None
  }
}

///|
pub(all) struct LocalProgramReadStepHoldings {
  extent : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
}

///|
/// Same actual successful holdings and metadata work. Only returned original
/// buffers are observed; this does not re-admit names, keys or score contracts.
pub fn local_program_read_step_retained_extent(
  original : LocalProgramRead,
  previous : LocalProgramReadPhase,
) -> LocalProgramReadStepHoldings? {
  if previous == PipelineKeys ||
    previous == PipelineRankings ||
    previous == PipelineCore {
    guard original.state is Reading(body) &&
      body.stage is PipelineRead(_, _, _, _, _, _, _, read) &&
      @pipeline.pipeline_evidence_read_step_holdings(read) is Some(q) &&
      record_local_program_read_inspection(original, q.inspection_work) else {
      return None
    }
    return Some({ extent: q.extent, owned_utf16_units: q.owned_utf16_units, })
  }
  local_program_read_step_retained_extent_owned(original, previous).map(extent => {
    extent,
    owned_utf16_units: 0L,
  })
}
