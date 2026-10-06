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
struct RecordAppend {
  output : OutputBuilder
  cursor : @storage.AppendCursor
  mut settled : Bool
}

///|
/// Preserve the enclosing kernel's live scratch in the shared append reservation.
/// Standalone callers without such scratch must explicitly select zero.
pub fn start_record_append(
  output : OutputBuilder,
  fields : Array[(@schema.FieldName, @value.CheckedValue)],
  external_workspace_slots~ : Int,
) -> Result[RecordAppend, Issue] {
  if !output.open {
    return Err(Closed)
  }
  match
    @storage.start_append(output.records, fields, external_workspace_slots~) {
    Ok(cursor) => Ok({ output, cursor, settled: false, })
    Err(issue) => {
      if issue != @storage.Closed {
        output.open = false
        @lifecycle.cancel_retention_port(output.retention) |> ignore
      }
      Err(Storage(issue))
    }
  }
}

///|
pub fn advance_record_append(value : RecordAppend) -> Result[Bool, Issue] {
  if !value.output.open || value.settled {
    return Err(Closed)
  }
  match @storage.advance_append(value.cursor) {
    Ok(done) => {
      value.settled = done
      Ok(done)
    }
    Err(issue) => {
      value.output.open = false
      @lifecycle.cancel_retention_port(value.output.retention) |> ignore
      Err(Storage(issue))
    }
  }
}

///|
pub fn cleanup_record_append(value : RecordAppend) -> Bool {
  @storage.cleanup_append(value.cursor)
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
    @carrier.Relation(rows) =>
      Some(
        @lifecycle.RelationMeasure(
          rows=count,
          columns=@carrier.field_count(rows),
        ),
      )
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
  prepare_output_with_identities(
    owner,
    target,
    [],
    limits,
    storage_bytes,
    available,
  )
}

///|
pub fn prepare_output_with_identities(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  additional_identities : Array[@schema.FieldName],
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
  if kind != @carrier.RelationKind &&
    kind != @carrier.EventsKind &&
    kind != @carrier.VectorsKind {
    return Err(Lifecycle(@lifecycle.WrongCarrier))
  }
  let records = match
    @storage.prepare_with_additional_identities(
      @lifecycle.binding_carrier(binding),
      additional_identities,
      limits,
    ) {
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
  if @storage.builder_append_pending(output.records) {
    return Err(Storage(@storage.Closed))
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
  if @storage.builder_append_pending(output.records) {
    return Err(Storage(@storage.Closed))
  }
  output.open = false
  let records = match @storage.finish(output.records) {
    Ok(value) => value
    Err(issue) => {
      @storage.cancel(output.records) |> ignore
      @lifecycle.cancel_retention_port(output.retention) |> ignore
      return Err(Storage(issue))
    }
  }
  let retained = match @lifecycle.retain(output.retention, records) {
    Ok(value) => value
    Err(issue) => {
      @storage.discard(records)
      return Err(Lifecycle(issue))
    }
  }
  match @lifecycle.complete(retained) {
    Ok(value) => Ok({ core: value, })
    Err(issue) => {
      @storage.discard(records)
      Err(Lifecycle(issue))
    }
  }
}

///|
pub fn completed_available(value : Completed) -> Bool {
  @lifecycle.completed_available(value.core)
}

///|
/// Reclaim a completed generation rejected before downstream handoff.
pub fn discard_completed(value : Completed) -> Bool {
  @lifecycle.reclaim_completed(value.core, storage => {
    @storage.discard(storage)
    true
  })
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
pub fn completed_carrier_reference(
  value : Completed,
) -> @lifecycle.CompletionReference {
  @lifecycle.completion_reference(value.core)
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
/// Bind a completed record generation to one exact downstream step edge in
/// the same checked sequence.
pub fn prepare_step_read(
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
  output : Completed,
) -> Result[ProducerRead, Issue] {
  match
    @lifecycle.prepare_step_producer_read(
      receiver,
      consumer_step,
      input_index,
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
pub fn producer_read_matches_step(
  value : ProducerRead,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
) -> Bool {
  @lifecycle.producer_read_reference_matches_step(
    @lifecycle.producer_read_reference(value.core),
    receiver,
    consumer_step,
    input_index,
  )
}

///|
pub fn producer_read_matches_operation_input(
  value : ProducerRead,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  edge_index : Int,
) -> Bool {
  @lifecycle.producer_read_reference_matches_operation_input(
    @lifecycle.producer_read_reference(value.core),
    receiver,
    consumer_step,
    edge_index,
  )
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

///|
pub fn producer_read_carrier_reference(
  value : ProducerRead,
) -> @lifecycle.ProducerReadReference {
  @lifecycle.producer_read_reference(value.core)
}

///|
/// Expose an exact Events or Vectors read without exporting record Storage.
pub fn producer_read_view(
  value : ProducerRead,
) -> Result[@lifecycle.ProducerView, Issue] {
  guard producer_read_storage(value) is Some(storage) else {
    return Err(Producer(@lifecycle.ProducerUnavailable))
  }
  @lifecycle.prepare_record_producer_view(
    producer_read_carrier_reference(value),
    @storage.record_count(storage),
    record => @storage.record_field_count(storage, record),
    (record, field) => @storage.record_field_at(storage, record, field),
  ).map_err(issue => {
    Lifecycle(
      match issue {
        @lifecycle.WrongCarrier => @lifecycle.WrongCarrier
        @lifecycle.InvalidExtent => @lifecycle.InvalidMeasure
        @lifecycle.Unavailable => @lifecycle.Unavailable
        @lifecycle.InvalidRecord | @lifecycle.InvalidField =>
          @lifecycle.Unverified
      },
    )
  })
}

///|
/// Erase only the storage representation while retaining exact record custody.
pub fn completed_material(
  value : Completed,
) -> Result[@lifecycle.Material, Issue] {
  @lifecycle.prepare_material(
    completed_carrier_reference(value),
    (receiver, input_index, expected_producer) => {
      match
        prepare_producer_read(receiver, input_index, expected_producer, value) {
        Ok(read) =>
          match producer_read_view(read) {
            Ok(view) => Some(view)
            Err(_) => None
          }
        Err(_) => None
      }
    },
    (receiver, consumer_step, input_index, expected_producer) => {
      if !physical_equal(receiver, expected_producer) {
        None
      } else {
        match prepare_step_read(receiver, consumer_step, input_index, value) {
          Ok(read) =>
            match producer_read_view(read) {
              Ok(view) => Some(view)
              Err(_) => None
            }
          Err(_) => None
        }
      }
    },
    fn() { discard_completed(value) },
  ).map_err(issue => Lifecycle(issue))
}
