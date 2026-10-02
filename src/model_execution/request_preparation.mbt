///|
// Formal call identity uses an exact completed-input scope. The legacy private
// component path keeps its prior spelling and cannot produce public evidence.
priv struct PreparedModelRequest {
  request : ModelRequest
  call : @publication.RunEvidenceValue?
  key_cid : String
  wire_bytes : Int64
}

///|
priv enum RequestPreparationPhase {
  ReadKey
  KeyWire(@admitted.WireEmitCursor)
  SlotWire(@admitted.WireEmitCursor)
  FinishKeyIdentity
  ReadInput
  InputWire(@admitted.WireEmitCursor)
}

///|
priv struct ModelRequestPreparation {
  slot : Int
  keys : Array[@admitted.CheckedValue]
  inputs : Array[(String, @admitted.CheckedValue)]
  key_writer : @encode.Writer
  slot_writer : @encode.Writer
  input_writer : @encode.Writer
  mut value_writer : @encode.Writer?
  mut key_index : Int
  mut input_index : Int
  mut key_cid : String?
  mut slot_cid : String?
  mut call : @publication.RunEvidenceValue?
  mut phase : RequestPreparationPhase
}

///|
fn start_model_request_preparation(
  state : ModelState,
) -> Result[ModelRequestPreparation, ModelExecutionIssue] {
  let bytes = Int64::min(state.limits.max_request_bytes, 2147483647L).to_int()
  try {
    // These are the existing private identity bounds, not a new language
    // restriction. Each key value is emitted incrementally into both sinks.
    let key_writer = if state.call_scope is Some(_) {
      @encode.writer(4096, 256, 8)
    } else {
      @encode.hashing_writer(4096, 256, 8)
    }
    let slot_writer = @encode.hashing_writer(4096, 256, 8)
    // Every JSON node and nesting level costs a byte, so the wire ceiling
    // also bounds this measuring sink without borrowing output-value limits.
    let input_writer = @encode.measuring_writer(bytes, bytes, bytes)
    if state.call_scope is Some(_) {
      @encode.begin_object(key_writer)
      @encode.key(key_writer, "components")
    }
    @encode.begin_array(key_writer)
    @encode.begin_object(slot_writer)
    @encode.key(slot_writer, "fixed_request_cid")
    @encode.string_value(slot_writer, state.fixed_request_cid)
    @encode.key(slot_writer, "key")
    @encode.begin_array(slot_writer)
    @encode.begin_object(input_writer)
    Ok({
      slot: state.requests.length(),
      keys: [],
      inputs: [],
      key_writer,
      slot_writer,
      input_writer,
      value_writer: None,
      key_index: 0,
      input_index: 0,
      key_cid: None,
      slot_cid: None,
      call: None,
      phase: ReadKey,
    })
  } catch {
    _ => Err(RequestLimit)
  }
}

///|
// Called only after the parent charges one transition and checks stop/work.
// ReserveSlots precedes this phase for every row, and no request can dispatch
// until all rows finish. A failed later row therefore makes zero calls.
fn advance_model_request_preparation(
  state : ModelState,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  let owner = @relation.prepared_infer_rows_owner(state.rows)
  guard state.request is Some(request) else {
    if state.requests.length() ==
      @relation.prepared_infer_rows_count(state.rows) {
      state.phase = if state.physical_preflight is Some(_) {
        PreparePhysicalRequests
      } else {
        DispatchSlot
      }
      return @bounded.Continue(1, 1)
    }
    match start_model_request_preparation(state) {
      Ok(value) => state.request = Some(value)
      Err(issue) => return @bounded.Failed(issue, 1, 1)
    }
    return @bounded.Continue(1, 1)
  }
  match request.phase {
    ReadKey => {
      if request.key_index < @infer.key_count(owner) {
        guard @relation.prepared_infer_rows_key(
            state.rows,
            request.slot,
            request.key_index,
          )
          is Some(value) else {
          return @bounded.Failed(OutputIdentity, 1, 1)
        }
        request.keys.push(value)
        if state.call_scope is Some(_) {
          guard @infer.key_at(owner, request.key_index) is Some(binding) else {
            return @bounded.Failed(OutputIdentity, 1, 1)
          }
          try {
            let contract_writer = @encode.hashing_writer(4096, 256, 8)
            @contract.emit_checked(value.contract, contract_writer)
            let contract_cid = "sha256:" + @encode.finish_hash(contract_writer)
            @encode.begin_object(request.key_writer)
            @encode.key(request.key_writer, "field")
            @encode.string_value(
              request.key_writer,
              @schema.reference_name(binding.field),
            )
            @encode.key(request.key_writer, "value_contract_cid")
            @encode.string_value(request.key_writer, contract_cid)
            let writer = @encode.hashing_writer(4096, 256, 8)
            request.value_writer = Some(writer)
            match value.value {
              @admitted.Reference(reference) => {
                @encode.string_value(
                  writer,
                  @admitted.reference_identity_cid(reference),
                )
                request.phase = FinishKeyIdentity
              }
              _ =>
                request.phase = KeyWire(
                  @admitted.start_wire_emit(value.value, writer),
                )
            }
          } catch {
            _ => return @bounded.Failed(OutputIdentity, 1, 1)
          }
        } else {
          request.phase = KeyWire(
            @admitted.start_wire_emit(value.value, request.key_writer),
          )
        }
        return @bounded.Continue(1, 1)
      }
      try {
        @encode.end_array(request.key_writer)
        if state.call_scope is Some(scope) {
          @encode.key(request.key_writer, "version")
          @encode.string_value(request.key_writer, "actql-model-input-key/0.1")
          @encode.end_object(request.key_writer)
          let key = match
            @publication.seal_run_evidence_value(
              "model_input_key",
              @encode.finish(request.key_writer),
              8192,
              512,
              10,
            ) {
            Ok(value) => value
            Err(_) => return @bounded.Failed(OutputIdentity, 1, 1)
          }
          let slot = match
            @publication_host.issue_client_infer_call_slot(
              scope, key, 8192, 512, 10,
            ) {
            Ok(value) => value
            Err(_) => return @bounded.Failed(OutputIdentity, 1, 1)
          }
          request.key_cid = Some(@publication.run_evidence_value_identity(key))
          request.slot_cid = Some(
            @publication.run_evidence_value_identity(slot),
          )
          request.call = Some(slot)
        } else {
          request.key_cid = Some(
            "sha256:" + @encode.finish_hash(request.key_writer),
          )
          @encode.end_array(request.slot_writer)
          @encode.key(request.slot_writer, "slot")
          @encode.number_value(request.slot_writer, request.slot.to_double())
          @encode.end_object(request.slot_writer)
          request.slot_cid = Some(
            "sha256:" + @encode.finish_hash(request.slot_writer),
          )
        }
      } catch {
        _ => return @bounded.Failed(OutputIdentity, 1, 1)
      }
      request.phase = ReadInput
      @bounded.Continue(1, 1)
    }
    KeyWire(cursor) => {
      let finished = @admitted.advance_wire_emit(cursor) catch {
        _ => return @bounded.Failed(OutputIdentity, 1, 1)
      }
      if finished {
        if state.call_scope is Some(_) {
          request.phase = FinishKeyIdentity
        } else {
          request.phase = SlotWire(
            @admitted.start_wire_emit(
              request.keys[request.key_index].value,
              request.slot_writer,
            ),
          )
        }
      }
      @bounded.Continue(1, 1)
    }
    FinishKeyIdentity => {
      try {
        guard request.value_writer is Some(writer) else {
          return @bounded.Failed(OutputIdentity, 1, 1)
        }
        @encode.key(request.key_writer, "value_cid")
        @encode.string_value(
          request.key_writer,
          "sha256:" + @encode.finish_hash(writer),
        )
        @encode.end_object(request.key_writer)
      } catch {
        _ => return @bounded.Failed(OutputIdentity, 1, 1)
      }
      request.value_writer = None
      request.key_index += 1
      request.phase = ReadKey
      @bounded.Continue(1, 1)
    }
    SlotWire(cursor) => {
      let finished = @admitted.advance_wire_emit(cursor) catch {
        _ => return @bounded.Failed(OutputIdentity, 1, 1)
      }
      if finished {
        request.key_index += 1
        request.phase = ReadKey
      }
      @bounded.Continue(1, 1)
    }
    ReadInput => {
      if request.input_index < @infer.input_binding_count(owner) {
        guard @infer.input_binding_at(owner, request.input_index)
          is Some(binding) &&
          @relation.prepared_infer_rows_value(
            state.rows,
            request.slot,
            request.input_index,
          )
          is Some(value) else {
          return @bounded.Failed(OutputIdentity, 1, 1)
        }
        let role = @infer.input_binding_role(binding)
        @encode.key(request.input_writer, role) catch {
          _ => return @bounded.Failed(RequestLimit, 1, 1)
        }
        request.inputs.push((role, value))
        request.phase = InputWire(
          @admitted.start_wire_emit(value.value, request.input_writer),
        )
        return @bounded.Continue(1, 1)
      }
      let bytes = try {
        @encode.end_object(request.input_writer)
        @encode.finish_measurement(request.input_writer)
      } catch {
        _ => return @bounded.Failed(RequestLimit, 1, 1)
      }
      guard request.key_cid is Some(key_cid) &&
        request.slot_cid is Some(slot_cid) else {
        return @bounded.Failed(OutputIdentity, 1, 1)
      }
      state.requests.push({
        request: {
          task: state.task,
          slot: request.slot,
          slot_cid,
          fixed_request_cid: state.fixed_request_cid,
          key: request.keys,
          inputs: request.inputs,
        },
        call: request.call,
        key_cid,
        wire_bytes: bytes.to_int64(),
      })
      state.request = None
      if state.requests.length() ==
        @relation.prepared_infer_rows_count(state.rows) {
        state.phase = if state.physical_preflight is Some(_) {
          PreparePhysicalRequests
        } else {
          DispatchSlot
        }
      }
      @bounded.Continue(1, 1)
    }
    InputWire(cursor) => {
      let finished = @admitted.advance_wire_emit(cursor) catch {
        _ => return @bounded.Failed(RequestLimit, 1, 1)
      }
      if finished {
        request.input_index += 1
        request.phase = ReadInput
      }
      @bounded.Continue(1, 1)
    }
  }
}

///|
fn cancel_model_request_preparation(request : ModelRequestPreparation) -> Unit {
  match request.phase {
    KeyWire(cursor) | SlotWire(cursor) | InputWire(cursor) =>
      @admitted.cancel_wire_emit(cursor)
    ReadKey | ReadInput | FinishKeyIdentity => ()
  }
  request.keys.clear()
  request.inputs.clear()
}
