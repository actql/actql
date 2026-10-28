///|
/// SAME input-domain quantities. Borrowed schemas/evidence/Strings are never
/// recursively quoted, copied or admitted here. The old Map and nested stack
/// stay with the original parent until post-constructor reconciliation.

///|
// Carrier read1H8R12W; five optional borrowed roots5H5R5W and its original
// parent Some1H1R1W. Co-count their closed alternatives, not child bodies.
let carrier_preflight_controls : @shape.CollectionConstructionExtent = {
  record_headers: 7L,
  reference_slots: 14L,
  scalar_words: 18L,
}

///|
// Actual selected advance/state/Result5H5R5W; original typed child/getter
// alternatives6H8R6W; UTF8-window/narrowed returns6H2R12W; Source/tree/key
// selectors8H10R10W; Issue/Stop/Err3H4R3W. Issue path backing is separate.
// Sequential UTF8 calls do not retain another text buffer.
let core_input_step_controls : @shape.CollectionConstructionExtent = {
  record_headers: 28L,
  reference_slots: 29L,
  scalar_words: 36L,
}

///|
fn core_input_retained(
  body : PipelineCoreBody,
) -> @shape.CollectionConstructionExtent? {
  guard @shape.map_retained_extent(
      1L,
      body.names.capacity().to_int64(),
      body.names.length().to_int64(),
    )
    is Some(names) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 1L, reference_slots: 0L, scalar_words: 1L, },
      body.names.length().to_int64(),
    )
    is Some(targets) &&
    @shape.add_collection_construction_extents(names, targets) is Some(held) else {
    return None
  }
  if body.carrier_read is Some(read) {
    guard @shape.add_collection_construction_extents(
        held, carrier_preflight_controls,
      )
      is Some(held) else {
      return None
    }
    if read.contract is Some(contract) {
      guard contract_preflight_retained(contract) is Some(nested) else {
        return None
      }
      return @shape.add_collection_construction_extents(held, nested)
    }
    return Some(held)
  }
  Some(held)
}

///|
fn carrier_preflight_new_contract(read : CarrierPreflightRead) -> Bool {
  match read.step {
    Start => read.original is @carrier.GraphValue(_)
    RowsField =>
      read.field_index < read.fields &&
      @carrier.field_at(read.rows.unwrap(), read.field_index).unwrap().contract
      is Some(_)
    GraphKey => read.key_index < read.keys
    _ => false
  }
}

///|
fn carrier_preflight_reference(
  read : CarrierPreflightRead,
) -> @schema.FieldName? {
  match read.step {
    RowsField =>
      if read.field_index < read.fields {
        Some(
          @carrier.field_at(read.rows.unwrap(), read.field_index).unwrap().name,
        )
      } else {
        None
      }
    VectorIdentity => {
      guard read.original is @carrier.VectorValue(vectors) else { return None }
      if read.field_index < read.fields {
        Some(
          @carrier.vector_identity_at(vectors, read.field_index).unwrap().name,
        )
      } else {
        None
      }
    }
    VectorComponents => {
      guard read.original is @carrier.VectorValue(vectors) else { return None }
      Some(@carrier.vector_components(vectors).name)
    }
    _ => None
  }
}

///|
fn core_input_step_construction(
  body : PipelineCoreBody,
) -> CoreStepConstruction? {
  guard body.phase == Inputs &&
    core_input_retained(body) is Some(replaced) &&
    @decode.issue_path_construction_extent(
      @decode.admission_usage(body.source).depth.to_int64(),
    )
    is Some(issue) &&
    @shape.add_collection_construction_extents(core_input_step_controls, issue)
    is Some(peak) else {
    return None
  }
  let mut peak = peak
  let mut text = 0L
  if body.input_index < body.inputs.length() {
    match body.input_step {
      Name => {
        guard @canonical.nfc_lf_construction_extent(
            body.inputs[body.input_index].0.length(),
          )
          is Some(nfc) &&
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
      CarrierStart => {
        guard @shape.add_collection_construction_extents(
            peak, carrier_preflight_controls,
          )
          is Some(next) else {
          return None
        }
        peak = next
      }
      Carrier => {
        guard carrier_preflight_step_construction(body.carrier_read.unwrap())
          is Some(child) &&
          @shape.add_collection_construction_extents(peak, child.peak)
          is Some(next) else {
          return None
        }
        peak = next
        text = child.peak_utf16_units
      }
      KeyAlias =>
        if body.alias_index < body.alias_count {
          let key = @evidence.key_witness_at(
            body.keyed_inputs[body.input_index].unwrap(),
            body.key_index,
          ).unwrap()
          let field = @evidence.key_alias_at(
            key,
            body.field_index,
            body.alias_index,
          ).unwrap()
          let spelling = @schema.reference_name_construction_extent(field.name)
          guard @shape.add_collection_construction_extents(
              peak,
              spelling.scratch,
            )
            is Some(next) else {
            return None
          }
          peak = next
          text = spelling.scratch_utf16_units
        }
      Register => {
        // The same linked Map owns old/new bucket overlap. Its old retained
        // storage is already backed; subtract that SAME owner's old units.
        guard @shape.map_construction_extent(
            1L,
            body.names.length().to_int64() + 1L,
          )
          is Some(grow) &&
          @shape.map_retained_extent(
            1L,
            body.names.capacity().to_int64(),
            body.names.length().to_int64(),
          )
          is Some(old) &&
          grow.record_headers >= old.record_headers &&
          grow.reference_slots >= old.reference_slots &&
          grow.scalar_words >= old.scalar_words else {
          return None
        }
        let additional : @shape.CollectionConstructionExtent = {
          record_headers: grow.record_headers - old.record_headers + 1L,
          reference_slots: grow.reference_slots - old.reference_slots,
          scalar_words: grow.scalar_words - old.scalar_words + 1L,
        }
        guard @shape.add_collection_construction_extents(peak, additional)
          is Some(next) else {
          return None
        }
        peak = next
      }
      _ => ()
    }
  }
  Some({ peak, peak_utf16_units: text, replaced, replaced_utf16_units: 0L, })
}

///|
/// SAME next Carrier/Contract constructor, shared by input and imported delta.
fn carrier_preflight_step_construction(
  read : CarrierPreflightRead,
) -> CoreStepConstruction? {
  let mut peak = pipeline_core_zero_extent
  let mut text = 0L
  if carrier_preflight_new_contract(read) {
    guard contract_preflight_entry_construction() is Some(entry) &&
      @shape.add_collection_construction_extents(peak, entry) is Some(next) else {
      return None
    }
    peak = next
  }
  if carrier_preflight_reference(read) is Some(reference) {
    let spelling = @schema.reference_name_construction_extent(reference)
    guard @shape.add_collection_construction_extents(peak, spelling.scratch)
      is Some(next) else {
      return None
    }
    peak = next
    text = spelling.scratch_utf16_units
  }
  // Event identity and time charges are sequential, but quote both exact
  // original spellings; neither is schema/type validation or retained.
  if read.step is EventColumns && read.original is @carrier.EventValue(events) {
    let a = @schema.reference_name_construction_extent(events.identity.name)
    let b = @schema.reference_name_construction_extent(events.time.name)
    guard @shape.compose_collection_construction_extents([
        peak,
        a.scratch,
        b.scratch,
      ])
      is Some(next) else {
      return None
    }
    peak = next
    text = a.scratch_utf16_units + b.scratch_utf16_units
  }
  if read.step is Contract &&
    read.contract is Some(contract) &&
    (contract.step is PushArray || contract.step is PushField) {
    guard contract_preflight_push_construction(contract) is Some(push) &&
      @shape.add_collection_construction_extents(peak, push) is Some(next) else {
      return None
    }
    peak = next
  }
  Some({
    peak,
    peak_utf16_units: text,
    replaced: pipeline_core_zero_extent,
    replaced_utf16_units: 0L,
  })
}
