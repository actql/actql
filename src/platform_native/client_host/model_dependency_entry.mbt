///|
/// Private references fixed by the original receiving and producing Scopes.
/// This record carries no credentials, captured rows, or dispatch authority.
priv struct NativeModelEntryDependencyPort {
  input : Int
  stage : Int
  step : Int
  artifact : String
  manifest : String
  producer_scope : String
}

///|
priv struct NativeModelEntryDependencyProducer {
  scope : String
  slots : Array[NativeCompletedModelDependencySlot]
}

///|
priv struct NativeModelEntryDependency {
  scope : String
  ports : Array[NativeModelEntryDependencyPort]
  producers : Array[NativeModelEntryDependencyProducer]
}

///|
// The dependent Work retains this proof only after the original persistence
// operation returns successfully. It owns neither the Entry bytes nor a
// second settlement, and cannot renew dispatch.
priv struct NativeDependentModelEnteredOriginal {
  entry : @model.ModelCallEntry
  scope : @publication.BoundModelInvocationScope
  attempt_cid : String
  entry_digest : String
  extent : Int64
}

///|
// Confirm the original keyed Entry before retaining or resolving its locator.
// A later-generation cell is refused even when it contains identical bytes.
fn NativeClientRunJournal::read_dependent_model_entry_locked(
  self : Self,
  attempt_cid : String,
  digest : String,
  maximum : Int64,
  reads : NativeClientJournalReadAccess,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  guard self.transaction_active &&
    physical_equal(self.database, reads.database) &&
    saved_effect_capture_cid_valid(attempt_cid) &&
    saved_effect_capture_cid_valid(digest) &&
    maximum > 0L else {
    return Err(CustodyLost)
  }
  read_native_saved_model_row(
    reads, "client_model_call_originals", attempt_cid, maximum,
  ).bind(body => {
    fund_native_saved_model_selection(reads).bind(_ => {
      if "sha256:" + @sha.hex(body) != digest {
        return Err(CustodyLost)
      }
      Ok(body)
    })
  })
}

///|
let native_plain_model_entry_version = "actql-native-model-call-original/0.1"

///|
let native_dependent_model_entry_version = "actql-native-dependent-model-call-original/0.1"

///|
// Additional closed syntax, canonical ASCII CIDs, and longest Int spelling
// only. The existing Entry quote still owns its three escaped evidence wires.
fn native_model_entry_dependency_geometry(
  dependency : NativeModelEntryDependency?,
) -> (Int64, Int, Int)? {
  guard dependency is Some(value) else { return Some((0L, 16, 2)) }
  if value.ports.is_empty() || value.producers.is_empty() {
    return None
  }
  let ports = value.ports.length().to_int64()
  let producers = value.producers.length().to_int64()
  let mut slots = 0L
  for producer in value.producers {
    if producer.slots.is_empty() {
      return None
    }
    slots += producer.slots.length().to_int64()
  }
  let fixed = ",\"dependency\":{\"ports\":[],\"producers\":[],\"scope_cid\":\"\"}"
    .length()
    .to_int64() +
    71L +
    (native_dependent_model_entry_version.length() -
    native_plain_model_entry_version.length()).to_int64()
  let port = "{\"artifact_cid\":\"\",\"input\":2147483647,\"manifest_cid\":\"\",\"producer_scope_cid\":\"\",\"stage\":2147483647,\"step\":2147483647},"
    .length()
    .to_int64() +
    213L
  let producer = "{\"scope_cid\":\"\",\"slots\":[]},".length().to_int64() + 71L
  let slot = "{\"attempt_cid\":\"\",\"bundle_cid\":\"\",\"raw_cid\":\"\",\"slot\":2147483647},"
    .length()
    .to_int64() +
    213L
  guard @execution.checked_preparation_add_product(fixed, port, ports)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, producer, producers)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, slot, slots)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(24L, 16L, ports) is Some(nodes) &&
    @execution.checked_preparation_add_product(nodes, 8L, producers)
    is Some(nodes) &&
    @execution.checked_preparation_add_product(nodes, 12L, slots) is Some(nodes) &&
    nodes < 2147483519L else {
    return None
  }
  Some((bytes, nodes.to_int(), 7))
}

///|
fn emit_native_model_entry_dependency(
  writer : @encode.Writer,
  value : NativeModelEntryDependency,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "ports")
  @encode.begin_array(writer)
  for port in value.ports {
    @encode.begin_object(writer)
    @encode.key(writer, "artifact_cid")
    @encode.string_value(writer, port.artifact)
    @encode.key(writer, "input")
    @encode.number_value(writer, port.input.to_double())
    @encode.key(writer, "manifest_cid")
    @encode.string_value(writer, port.manifest)
    @encode.key(writer, "producer_scope_cid")
    @encode.string_value(writer, port.producer_scope)
    @encode.key(writer, "stage")
    @encode.number_value(writer, port.stage.to_double())
    @encode.key(writer, "step")
    @encode.number_value(writer, port.step.to_double())
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "producers")
  @encode.begin_array(writer)
  for producer in value.producers {
    @encode.begin_object(writer)
    @encode.key(writer, "scope_cid")
    @encode.string_value(writer, producer.scope)
    @encode.key(writer, "slots")
    @encode.begin_array(writer)
    for (slot, attempt, raw, bundle) in producer.slots {
      @encode.begin_object(writer)
      @encode.key(writer, "attempt_cid")
      @encode.string_value(writer, attempt)
      @encode.key(writer, "bundle_cid")
      @encode.string_value(writer, bundle)
      @encode.key(writer, "raw_cid")
      @encode.string_value(writer, raw)
      @encode.key(writer, "slot")
      @encode.number_value(writer, slot.to_double())
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "scope_cid")
  @encode.string_value(writer, value.scope)
  @encode.end_object(writer)
}

///|
fn native_dependent_entry_index(
  fields : @decode.ObjectView,
  key : String,
) -> Int? {
  guard @decode.lookup(fields, key) is Some(value) &&
    @decode.int32(value) is Ok(index) &&
    index >= 0 else {
    return None
  }
  Some(index)
}

///|
fn decode_native_dependent_entry_port(
  cursor : @decode.Cursor,
) -> NativeModelEntryDependencyPort? {
  guard @decode.closed_object(cursor, [
      "artifact_cid", "input", "manifest_cid", "producer_scope_cid", "stage", "step",
    ])
    is Ok(fields) &&
    native_dependent_entry_index(fields, "input") is Some(input) &&
    native_dependent_entry_index(fields, "stage") is Some(stage) &&
    native_dependent_entry_index(fields, "step") is Some(step) &&
    native_model_output_policy_cid(fields, "artifact_cid") is Some(artifact) &&
    native_model_output_policy_cid(fields, "manifest_cid") is Some(manifest) &&
    native_model_output_policy_cid(fields, "producer_scope_cid")
    is Some(producer_scope) else {
    return None
  }
  Some({ input, stage, step, artifact, manifest, producer_scope, })
}

///|
fn decode_native_dependent_entry_producer(
  cursor : @decode.Cursor,
) -> NativeModelEntryDependencyProducer? {
  guard @decode.closed_object(cursor, ["scope_cid", "slots"]) is Ok(fields) &&
    native_model_output_policy_cid(fields, "scope_cid") is Some(scope) &&
    @decode.lookup(fields, "slots") is Some(values) &&
    @decode.array_length(values) is Some(count) &&
    count > 0 else {
    return None
  }
  let slots = Array(capacity=count)
  let mut previous = -1
  for index in 0..<count {
    guard @decode.element_at(values, index) is Some(value) &&
      @decode.closed_object(value, [
        "attempt_cid", "bundle_cid", "raw_cid", "slot",
      ])
      is Ok(fields) &&
      native_model_output_policy_cid(fields, "attempt_cid") is Some(attempt) &&
      native_model_output_policy_cid(fields, "bundle_cid") is Some(bundle) &&
      native_model_output_policy_cid(fields, "raw_cid") is Some(raw) &&
      native_dependent_entry_index(fields, "slot") is Some(slot) &&
      slot > previous else {
      return None
    }
    slots.push((slot, attempt, raw, bundle))
    previous = slot
  }
  Some({ scope, slots, })
}

///|
fn decode_native_dependent_entry_inventory(
  cursor : @decode.Cursor,
  attempt : String,
) -> NativeModelEntryDependency? {
  guard @decode.closed_object(cursor, ["ports", "producers", "scope_cid"])
    is Ok(fields) &&
    native_model_output_policy_cid(fields, "scope_cid") is Some(scope) &&
    @decode.lookup(fields, "ports") is Some(port_values) &&
    @decode.lookup(fields, "producers") is Some(producer_values) &&
    @decode.array_length(port_values) is Some(port_count) &&
    port_count > 0 &&
    @decode.array_length(producer_values) is Some(producer_count) &&
    producer_count > 0 &&
    producer_count <= port_count else {
    return None
  }
  let ports = Array(capacity=port_count)
  let scopes : Map[String, Bool] = Map([])
  let mut previous = (-1, -1, -1)
  for index in 0..<port_count {
    guard @decode.element_at(port_values, index).bind(
        decode_native_dependent_entry_port,
      )
      is Some(port) &&
      port.producer_scope != scope else {
      return None
    }
    let coordinate = (port.input, port.stage, port.step)
    if coordinate <= previous {
      return None
    }
    previous = coordinate
    scopes[port.producer_scope] = false
    ports.push(port)
  }
  if scopes.length() != producer_count {
    return None
  }
  let producers = Array(capacity=producer_count)
  let attempts : Map[String, Bool] = Map([])
  attempts[attempt] = true
  for index in 0..<producer_count {
    guard @decode.element_at(producer_values, index).bind(
        decode_native_dependent_entry_producer,
      )
      is Some(producer) &&
      scopes.get(producer.scope) == Some(false) else {
      return None
    }
    for (_, original, _, _) in producer.slots {
      if attempts.contains(original) {
        return None
      }
      attempts[original] = true
    }
    scopes[producer.scope] = true
    producers.push(producer)
  }
  Some({ scope, ports, producers, })
}

///|
fn admit_native_saved_dependent_inventory(
  reads : NativeClientJournalReadAccess,
  raw_dependency : @decode.Cursor,
  attempt_cid : String,
  nodes : Int,
) -> Result[NativeModelEntryDependency, NativeClientRunJournalIssue] {
  // Fund the vectors and lookup tables while the original parsed tree is live.
  guard @execution.preparation_representation_cost({
      record_headers: nodes.to_int64(),
      reference_slots: 6L * nodes.to_int64(),
      scalar_words: 4L * nodes.to_int64(),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(duplicates) else {
    return Err(CapacityExceeded)
  }
  match
    fund_native_saved_model_construction(
      reads, duplicates, duplicates, duplicates,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard decode_native_dependent_entry_inventory(raw_dependency, attempt_cid)
    is Some(dependency) else {
    return Err(CustodyLost)
  }
  Ok(dependency)
}

///|
// The input comes from the selected original keyed row. Every variable
// group in the canonical writer contains at least one 71-byte CID.
fn admit_native_saved_dependent_model_entry(
  reads : NativeClientJournalReadAccess,
  run : NativeClientRunRecord,
  body : Bytes,
  attempt_cid : String,
) -> Result[NativeModelEntryDependency, NativeClientRunJournalIssue] {
  let nodes = 24 + 16 * (body.length() / 71)
  let fields = match
    parse_native_saved_model_object(
      reads,
      body,
      [
        "attempt", "authority", "call", "dependency", "request_scope_cid", "run_definition_cid",
        "slot", "version",
      ],
      nodes,
      7,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard epoch_text(fields, "version") ==
    Some(native_dependent_model_entry_version) &&
    epoch_text(fields, "request_scope_cid") ==
    Some(@host.client_request_scope_cid(run.request)) &&
    epoch_text(fields, "run_definition_cid") ==
    Some(@publication.publication_contract_identity(run.definition)) &&
    native_dependent_entry_index(fields, "slot") is Some(slot) &&
    @decode.lookup(fields, "dependency") is Some(raw_dependency) else {
    return Err(CustodyLost)
  }
  let dependency = match
    admit_native_saved_dependent_inventory(
      reads, raw_dependency, attempt_cid, nodes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let call = match
    read_native_saved_model_entry_leaf(reads, fields, "call", "model_call_slot") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let attempt = match
    read_native_saved_model_entry_leaf(
      reads, fields, "attempt", "model_call_attempt",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let authority = match
    read_native_saved_model_entry_leaf(
      reads, fields, "authority", "model_dispatch_authority",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @publication.run_evidence_value_identity(attempt) == attempt_cid &&
    @publication.check_retained_model_call_entry_scope(
      run.definition,
      dependency.scope,
      call,
      attempt,
      authority,
    )
    is Ok(_) else {
    return Err(CustodyLost)
  }
  guard native_model_entry_dependency_geometry(Some(dependency))
    is Some((_, nodes, depth)) &&
    journal_row_construction_working(body.length(), nodes, depth)
    is Some((retained, execution, block)) else {
    return Err(CapacityExceeded)
  }
  fund_native_saved_model_construction(reads, retained, execution, block).bind(_ => {
    match
      native_model_entry_body(
        run.request,
        run.definition,
        slot,
        call,
        attempt,
        authority,
        body.length(),
        dependency=Some(dependency),
      ) {
      Ok(expected) if expected == body => Ok(dependency)
      _ => Err(CustodyLost)
    }
  })
}
