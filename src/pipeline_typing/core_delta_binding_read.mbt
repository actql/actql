///|
/// SAME captured immutable binding, not a reconstructed name/CID or authority.
fn core_delta_binding_original(
  body : PipelineCoreBody,
) -> (String, @schema.FieldName, @graph_contract.CheckedContract)? {
  let selected = body.delta_binding
  guard selected is Some(binding) &&
    body.delta_contracts.length() == body.delta_binding_count &&
    body.delta_binding_index < body.delta_binding_count &&
    physical_equal(body.delta_contracts[body.delta_binding_index], binding) else {
    return None
  }
  selected
}

///|
fn advance_pipeline_core_delta_bindings(
  body : PipelineCoreBody,
) -> Unit raise Stop {
  let source = body.source
  let b = body.b
  if body.delta_binding_step != Count &&
    core_delta_binding_original(body) is None {
    fail(source, InvalidDeltaContractBinding)
  }
  match body.delta_binding_step {
    Count => {
      let count = body.delta_contracts.length()
      spend(b, source, count)
      body.delta_binding_count = count
      body.delta_binding_index = 0
      if count == 0 {
        body.phase = Steps
      } else {
        // Capture before any data-dependent quote; the header is already in
        // this Count constructor's fixed inventory. No empty selection phase.
        body.delta_binding = Some(body.delta_contracts[0])
        body.delta_binding_step = Name
      }
    }
    Name => {
      let (input_name, _, _) = body.delta_binding.unwrap()
      name(b, source, input_name)
      body.delta_binding_step = Target
    }
    Target => {
      let (input_name, _, _) = body.delta_binding.unwrap()
      body.delta_binding_target = match body.names.get(input_name) {
        Some(Input(index)) => index
        _ => fail(source, InvalidDeltaContractBinding)
      }
      body.delta_binding_step = Field
    }
    Field => {
      let (_, field, contract) = body.delta_binding.unwrap()
      let rows = match body.inputs[body.delta_binding_target].1 {
        @carrier.Relation(rows) => rows
        _ => fail(source, InvalidDeltaContractBinding)
      }
      guard @carrier.lookup(rows, field)
        is Present({ name: original, contract: Some(_), .. }) else {
        fail(source, InvalidDeltaContractBinding)
      }
      // Use the name of the SAME admitted field. Unqualified spelling borrows
      // its original String; qualification owns only its one new spelling.
      let key = @schema.reference_name(original)
      charge(b, source, key)
      let fields = body.delta_inputs.unwrap()[body.delta_binding_target].fields
      if fields.contains(key) {
        fail(source, InvalidDeltaContractBinding)
      }
      body.delta_binding_key = Some(key)
      body.delta_binding_old = Some(
        @shape.map_retained_extent(
          1L,
          fields.capacity().to_int64(),
          fields.length().to_int64(),
        ).unwrap(),
      )
      body.carrier_read = Some(
        begin_carrier_preflight_read(
          b,
          source,
          @carrier.graph_carrier(@graph_contract.graph(contract)),
        ),
      )
      body.delta_binding_step = Carrier
    }
    Carrier => {
      let read = body.carrier_read.unwrap()
      advance_carrier_preflight_read(read)
      match read.state {
        Pending => ()
        Complete => {
          clear_carrier_preflight_read(read)
          body.carrier_read = None
          body.delta_binding_step = Register
        }
        Rejected(issue) => raise Stop(issue)
        Cleared =>
          abort("original Delta binding Carrier retired before its Core")
      }
    }
    Register => {
      let (_, field, contract) = body.delta_binding.unwrap()
      let fields = body.delta_inputs.unwrap()[body.delta_binding_target].fields
      fields[body.delta_binding_key.unwrap()] = contract
      let old = body.delta_binding_old.unwrap()
      let actual = @shape.map_retained_extent(
        1L,
        fields.capacity().to_int64(),
        fields.length().to_int64(),
      ).unwrap()
      guard actual.record_headers >= old.record_headers &&
        actual.reference_slots >= old.reference_slots &&
        actual.scalar_words >= old.scalar_words else {
        abort("original Delta Map storage shrank during insertion")
      }
      body.delta_completed_storage = @shape.add_collection_construction_extents(
        body.delta_completed_storage,
        {
          record_headers: actual.record_headers - old.record_headers,
          reference_slots: actual.reference_slots - old.reference_slots,
          scalar_words: actual.scalar_words - old.scalar_words,
        },
      ).unwrap()
      let spelling = @schema.reference_name_construction_extent(field)
      if spelling.scratch_utf16_units > 0L {
        body.delta_bound_name_headers = @capacity.checked_nonnegative_add_product(
          body.delta_bound_name_headers,
          1L,
          1L,
        ).unwrap()
        body.delta_bound_name_units = @capacity.checked_nonnegative_add_product(
          body.delta_bound_name_units,
          spelling.scratch_utf16_units,
          1L,
        ).unwrap()
      }
      body.delta_binding = None
      body.delta_binding_key = None
      body.delta_binding_old = None
      body.delta_binding_index += 1
      if body.delta_binding_index == body.delta_binding_count {
        body.phase = Steps
      } else {
        body.delta_binding = Some(
          body.delta_contracts[body.delta_binding_index],
        )
        body.delta_binding_step = Name
      }
    }
  }
}
