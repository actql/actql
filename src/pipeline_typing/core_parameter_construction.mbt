///|
/// Only the new original Parameter/selector/empty-vector domain. The earlier
/// input Map, schemas and declarations stay borrowed from their funded owner.
fn core_parameter_retained(
  body : PipelineCoreBody,
) -> @shape.CollectionConstructionExtent? {
  let mut held = pipeline_core_zero_extent
  if body.parameter_read is Some(read) {
    guard contract_preflight_retained(read) is Some(nested) else { return None }
    held = nested
  }
  if body.current is Some(_) {
    // Explicit from borrows the original Map Target. The default sole-input
    // branch creates its own Input(0) before the retained Some.
    guard @shape.add_collection_construction_extents(held, {
        record_headers: if body.from is None {
          2L
        } else {
          1L
        },
        reference_slots: 1L,
        scalar_words: if body.from is None {
          2L
        } else {
          1L
        },
      })
      is Some(next) else {
      return None
    }
    held = next
  }
  if body.steps is Some(steps) {
    guard body.ranked_steps is Some(ranked) &&
      body.keyed_steps is Some(keyed) &&
      @shape.reference_array_retained_extent(
        3L,
        steps.capacity().to_int64() +
        ranked.capacity().to_int64() +
        keyed.capacity().to_int64(),
      )
      is Some(arrays) &&
      @shape.compose_collection_construction_extents([
        held,
        arrays,
        { record_headers: 3L, reference_slots: 3L, scalar_words: 3L, },
      ])
      is Some(next) else {
      return None
    }
    held = next
  }
  Some(held)
}

///|
fn core_parameter_step_construction(
  body : PipelineCoreBody,
) -> CoreStepConstruction? {
  let mut issue_depth = @decode.admission_usage(body.source).depth
  if body.parameter_step is Select && body.from is Some(cursor) {
    // The public core may borrow a selector from another admitted tree. Its
    // own original path, not the steps Array's depth, backs its typed issue.
    issue_depth = Int::max(issue_depth, @decode.admission_usage(cursor).depth)
  }
  guard body.phase == Parameters &&
    core_parameter_retained(body) is Some(replaced) &&
    @decode.issue_path_construction_extent(issue_depth.to_int64())
    is Some(issue) &&
    @shape.add_collection_construction_extents(core_input_step_controls, issue)
    is Some(peak) else {
    return None
  }
  let mut peak = peak
  let mut text = 0L
  match body.parameter_step {
    Name =>
      if body.parameters is Some(parameters) &&
        body.parameter_index < @parameter.declaration_count(parameters) {
        guard contract_preflight_entry_construction() is Some(entry) &&
          @shape.add_collection_construction_extents(peak, entry) is Some(next) else {
          return None
        }
        peak = next
      }
    Contract => {
      guard contract_preflight_push_construction(body.parameter_read.unwrap())
        is Some(push) &&
        @shape.add_collection_construction_extents(peak, push) is Some(next) else {
        return None
      }
      peak = next
    }
    Select =>
      if body.from is Some(cursor) {
        // Read only the original borrowed String to obtain its UTF16 length.
        // Non-String retains the original InvalidBody path, not empty success.
        if @decode.text(cursor) is Ok(raw) {
          guard @canonical.nfc_lf_construction_extent(raw.length()) is Some(nfc) &&
            @shape.add_collection_construction_extents(peak, {
              record_headers: nfc.record_headers,
              reference_slots: nfc.reference_slots,
              scalar_words: nfc.scalar_words,
            })
            is Some(next) else {
            return None
          }
          peak = next
          text = nfc.owned_utf16_units
        }
      }
    Arrays => {
      guard @shape.collection_construction_extent({
          records: 3L,
          record_references: 3L,
          record_words: 3L,
          reference_arrays: 3L,
          reference_items: 0L,
          scalar_arrays: 0L,
          scalar_items: 0L,
          maps: 0L,
          map_entries: 0L,
        })
        is Some(arrays) &&
        @shape.add_collection_construction_extents(peak, arrays) is Some(next) else {
        return None
      }
      peak = next
    }
    _ => ()
  }
  Some({ peak, peak_utf16_units: text, replaced, replaced_utf16_units: 0L, })
}
