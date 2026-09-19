///|
/// Evidence for one exact immutable Events or Vectors generation. It does not
/// assert a logical content identity or cross-process authority.
struct Evidence {
  carrier : @carrier.Kind
  records : Int
  identities : Int
  measured_value_bytes : Int
  retained_value_bytes : Int
  construction_work : Int
  workspace_slots : Int
}

///|
struct OutputBuilder {
  records : @storage.Builder
  retention : @lifecycle.RetentionPort[
    @storage.Storage,
    Evidence,
    @storage.Storage,
  ]
  mut open : Bool
}

///|
struct Completed {
  core : @lifecycle.Completed[Evidence, @storage.Storage]
}

///|
struct CompletionReference {
  core : @lifecycle.CompletionReference
}

///|
struct ProducerRead {
  core : @lifecycle.ProducerRead[Evidence, @storage.Storage]
}

///|
pub(all) enum Issue {
  Lifecycle(@lifecycle.Issue)
  Storage(@storage.Issue)
  Producer(@lifecycle.ProducerReadIssue)
  InvalidStorageBytes
  Closed
} derive(Eq, Debug)

///|
fn storage_measure(value : @storage.Storage) -> @lifecycle.Measure? {
  let count = @storage.record_count(value)
  match @storage.carrier(value) {
    @carrier.EventValue(_) => Some(@lifecycle.EventsMeasure(records=count))
    @carrier.VectorValue(vectors) =>
      Some(
        @lifecycle.VectorsMeasure(
          records=count,
          dimensions=@carrier.vector_dimensions(vectors).to_int(),
        ),
      )
    _ => None
  }
}

///|
pub fn prepare_output(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[OutputBuilder, Issue] {
  if storage_bytes < 0L {
    return Err(InvalidStorageBytes)
  }
  let binding = match @lifecycle.prepare_binding(owner, target) {
    Ok(value) => value
    Err(issue) => return Err(Lifecycle(issue))
  }
  let kind = @lifecycle.binding_kind(binding)
  if kind != @carrier.EventsKind && kind != @carrier.VectorsKind {
    return Err(Lifecycle(@lifecycle.WrongCarrier))
  }
  let records = match
    @storage.prepare(@lifecycle.binding_carrier(binding), limits) {
    Ok(value) => value
    Err(issue) => return Err(Storage(issue))
  }
  let retention = @lifecycle.prepare_retention_port(binding, (
    material : @storage.Storage,
  ) => {
    guard storage_measure(material) is Some(measure) else { return None }
    let receipt = match @lifecycle.complete_receipt(binding, measure) {
      Ok(value) => value
      Err(_) => return None
    }
    let evidence : Evidence = {
      carrier: @carrier.kind(@storage.carrier(material)),
      records: @storage.record_count(material),
      identities: @storage.identity_count(material),
      measured_value_bytes: @storage.measured_input_value_bytes(material),
      retained_value_bytes: @storage.retained_value_bytes(material),
      construction_work: @storage.construction_work(material),
      workspace_slots: @storage.retained_workspace_slots(material),
    }
    Some((receipt, evidence, material, storage_bytes, available))
  })
  Ok({ records, retention, open: true, })
}

///|
pub fn append_record(
  output : OutputBuilder,
  fields : Array[(@schema.FieldName, @value.CheckedValue)],
) -> Result[Unit, Issue] {
  if !output.open {
    return Err(Closed)
  }
  @storage.append(output.records, fields).map_err(issue => {
    output.open = false
    @lifecycle.cancel_retention_port(output.retention) |> ignore
    Storage(issue)
  })
}

///|
/// Structural slots already retained by the unpublished output generation.
pub fn output_workspace_slots(output : OutputBuilder) -> Int {
  @storage.builder_workspace_slots(output.records)
}

///|
pub fn cancel_output(output : OutputBuilder) -> Bool {
  if !output.open {
    return false
  }
  output.open = false
  let storage = @storage.cancel(output.records)
  let retention = @lifecycle.cancel_retention_port(output.retention)
  storage || retention
}

///|
pub fn finish_output(output : OutputBuilder) -> Result[Completed, Issue] {
  if !output.open {
    return Err(Closed)
  }
  output.open = false
  let records = match @storage.finish(output.records) {
    Ok(value) => value
    Err(issue) => {
      @lifecycle.cancel_retention_port(output.retention) |> ignore
      return Err(Storage(issue))
    }
  }
  let retained = match @lifecycle.retain(output.retention, records) {
    Ok(value) => value
    Err(issue) => return Err(Lifecycle(issue))
  }
  match @lifecycle.complete(retained) {
    Ok(value) => Ok({ core: value, })
    Err(issue) => Err(Lifecycle(issue))
  }
}

///|
pub fn completed_available(value : Completed) -> Bool {
  @lifecycle.completed_available(value.core)
}

///|
pub fn completed_measure(value : Completed) -> @lifecycle.Measure {
  @lifecycle.completed_measure(value.core)
}

///|
pub fn completed_storage(value : Completed) -> @storage.Storage? {
  if completed_available(value) {
    @lifecycle.completed_payload(value.core)
  } else {
    None
  }
}

///|
pub fn completed_storage_bytes(value : Completed) -> Int64? {
  @lifecycle.completed_storage_bytes(value.core)
}

///|
pub fn completed_evidence(value : Completed) -> Evidence? {
  if completed_available(value) {
    @lifecycle.completed_evidence(value.core)
  } else {
    None
  }
}

///|
pub fn evidence_carrier(value : Evidence) -> @carrier.Kind {
  value.carrier
}

///|
pub fn evidence_records(value : Evidence) -> Int {
  value.records
}

///|
pub fn evidence_identity_count(value : Evidence) -> Int {
  value.identities
}

///|
pub fn evidence_measured_value_bytes(value : Evidence) -> Int {
  value.measured_value_bytes
}

///|
pub fn evidence_retained_value_bytes(value : Evidence) -> Int {
  value.retained_value_bytes
}

///|
pub fn evidence_construction_work(value : Evidence) -> Int {
  value.construction_work
}

///|
pub fn evidence_workspace_slots(value : Evidence) -> Int {
  value.workspace_slots
}

///|
pub fn completed_reference(value : Completed) -> CompletionReference {
  { core: @lifecycle.completion_reference(value.core), }
}

///|
pub fn completed_reference_available(value : CompletionReference) -> Bool {
  @lifecycle.completion_reference_available(value.core)
}

///|
pub fn prepare_producer_read(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : Completed,
) -> Result[ProducerRead, Issue] {
  match
    @lifecycle.prepare_producer_read(
      receiver,
      input_index,
      expected_producer,
      output.core,
    ) {
    Ok(value) => Ok({ core: value, })
    Err(issue) => Err(Producer(issue))
  }
}

///|
pub fn producer_read_available(value : ProducerRead) -> Bool {
  @lifecycle.producer_read_available(value.core)
}

///|
pub fn producer_read_receiver(value : ProducerRead) -> @lower.BoundPrepared {
  @lifecycle.producer_read_receiver(value.core)
}

///|
pub fn producer_read_input_index(value : ProducerRead) -> Int {
  @lifecycle.producer_read_input_index(value.core)
}

///|
pub fn producer_read_same(left : ProducerRead, right : ProducerRead) -> Bool {
  @lifecycle.producer_read_same(left.core, right.core)
}

///|
pub fn producer_read_storage(value : ProducerRead) -> @storage.Storage? {
  @lifecycle.producer_read_payload(value.core)
}

///|
pub fn producer_read_matches_reference(
  value : ProducerRead,
  reference : CompletionReference,
) -> Bool {
  @lifecycle.producer_read_matches_reference(value.core, reference.core)
}
