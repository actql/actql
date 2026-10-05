///|
priv enum AppendPhase {
  Fields
  Required
  Identities
  BeginKey
  KeyValue
  FinishKey
  ReadPriorIdentity
  CompareKey
  BeginRecord
  BeginField
  FieldName
  FieldValue
  EndField
  FinishRecord
  Commit
  Complete
  Failed
}

///|
/// A provisional record stays under the original builder's custody. Advancing
/// grants neither completion nor publication authority.
struct AppendCursor {
  builder : Builder
  width : Int
  mut workspace : Int
  actual : Map[String, @value.CheckedValue]
  mut fields : Array[(@schema.FieldName, @value.CheckedValue)]
  identities : Array[@value.CheckedValue]
  mut supplied : Array[(@schema.FieldName, @value.CheckedValue)]
  mut phase : AppendPhase
  mut index : Int
  mut writer : @encode.Writer?
  mut wire : @value.WireEmitCursor?
  mut name : @encode.StringEmitCursor?
  mut work_limited : Bool
  mut key : String
  mut candidate : Record?
  mut prior_identities : Array[@value.CheckedValue]?
  mut prior_field : Int
  mut comparison : IdentityComparison?
  mut comparison_slots : Int
  mut key_bytes : Int
  mut key_work : Int
  mut record_bytes : Int
  mut record_work : Int
  mut cleaned : Bool
}

///|
/// Fixed cursor/phase custody (eight), field snapshot and lookup entries,
/// identity values, and three depth-bounded stacks (writer, value continuation,
/// child continuation). Logical construction work is accounted separately.
pub fn append_workspace_slots(
  fields : Int,
  identities : Int,
  depth : Int,
) -> Int? {
  if fields < 0 || identities < 0 || depth < 0 || fields > (2147483647 - 8) / 2 {
    return None
  }
  let first = 8 + fields * 2
  if identities > 2147483647 - first {
    return None
  }
  let second = first + identities
  if depth > (2147483647 - second) / 3 {
    return None
  }
  Some(second + depth * 3)
}

///|
pub fn start_append(
  builder : Builder,
  fields : Array[(@schema.FieldName, @value.CheckedValue)],
) -> Result[AppendCursor, Issue] {
  if !builder.open || !builder.owns_private || builder.pending_append is Some(_) {
    return Err(Closed)
  }
  if fields.length() > builder.limits.max_fields_per_record {
    builder.open = false
    return Err(FieldLimit)
  }
  guard append_workspace_slots(
      fields.length(),
      builder.identities.length(),
      builder.limits.max_value_depth,
    )
    is Some(workspace) &&
    workspace <= builder.limits.max_workspace_slots - builder.workspace_slots else {
    builder.open = false
    return Err(WorkspaceLimit)
  }
  let cursor : AppendCursor = {
    builder,
    width: fields.length(),
    workspace,
    actual: Map([]),
    fields: [],
    identities: [],
    supplied: fields,
    phase: Fields,
    index: 0,
    writer: None,
    wire: None,
    name: None,
    work_limited: false,
    key: "",
    candidate: None,
    prior_identities: None,
    prior_field: 0,
    comparison: None,
    comparison_slots: 0,
    key_bytes: 0,
    key_work: 0,
    record_bytes: 0,
    record_work: 0,
    cleaned: false,
  }
  builder.pending_append = Some(cursor)
  Ok(cursor)
}

///|
fn fail_append(cursor : AppendCursor, issue : Issue) -> Result[Bool, Issue] {
  cursor.phase = Failed
  cursor.builder.open = false
  // Do not release provisional custody before the caller observes stop.
  Err(issue)
}

///|
fn append_writer(
  cursor : AppendCursor,
  key : Bool,
) -> @encode.Writer raise @encode.EncodeFailure {
  let builder = cursor.builder
  let pending_work = cursor.width + 1 + cursor.key_work
  let remaining_work = builder.limits.max_work - builder.work
  if pending_work >= remaining_work {
    cursor.work_limited = true
    raise @encode.OutputLimit
  }
  let nodes = Int::min(
    builder.limits.max_value_nodes,
    remaining_work - pending_work,
  )
  cursor.work_limited = nodes < builder.limits.max_value_nodes
  let bytes = Int::min(
    builder.limits.max_value_bytes,
    builder.limits.max_total_value_bytes -
    builder.value_bytes -
    cursor.key_bytes,
  )
  if key {
    @encode.hashing_writer(bytes, nodes, builder.limits.max_value_depth)
  } else {
    // Only identity text is needed for uniqueness. The record's discarded wire
    // text must not be assembled into a giant String at the final poll.
    @encode.measuring_writer(bytes, nodes, builder.limits.max_value_depth)
  }
}

///|
/// One field, identity, wire frame or text chunk per poll. Exact canonical
/// byte/node work remains the original append discipline, independent of polls.
pub fn advance_append(cursor : AppendCursor) -> Result[Bool, Issue] {
  if cursor.cleaned || cursor.phase is Complete || cursor.phase is Failed {
    return Err(Closed)
  }
  let builder = cursor.builder
  if !builder.open || !builder.owns_private || builder.pending_append is None {
    return fail_append(cursor, Closed)
  }
  try {
    match cursor.phase {
      Fields => {
        if cursor.supplied.length() != cursor.width {
          return fail_append(cursor, InvalidRecord)
        }
        if cursor.index < cursor.width {
          let (name, value) = cursor.supplied[cursor.index]
          let spelling = @schema.reference_name(name)
          if cursor.actual.contains(spelling) {
            return fail_append(cursor, InvalidRecord)
          }
          match @carrier.lookup(builder.records, name) {
            @carrier.Present(expected) => {
              guard expected.contract is Some(contract) &&
                contract_equal(builder, contract, value.contract) else {
                return fail_append(cursor, InvalidRecord)
              }
            }
            @carrier.Absent => return fail_append(cursor, InvalidRecord)
            @carrier.Unknown => ()
          }
          cursor.actual[spelling] = value
          cursor.fields.push((name, value))
          cursor.index += 1
        } else {
          cursor.supplied = []
          cursor.index = 0
          cursor.phase = Required
        }
      }
      Required =>
        if @carrier.field_at(builder.records, cursor.index) is Some(expected) {
          if !cursor.actual.contains(@schema.reference_name(expected.name)) {
            return fail_append(cursor, InvalidRecord)
          }
          cursor.index += 1
        } else {
          if @carrier.field_set(builder.records) == @carrier.Closed &&
            cursor.width != @carrier.field_count(builder.records) {
            return fail_append(cursor, InvalidRecord)
          }
          cursor.index = 0
          cursor.phase = Identities
        }
      Identities =>
        if builder.identities.get(cursor.index) is Some(name) {
          guard cursor.actual.get(name) is Some(value) else {
            return fail_append(cursor, InvalidIdentity)
          }
          cursor.identities.push(value)
          cursor.index += 1
        } else {
          cursor.index = 0
          cursor.phase = if cursor.identities.is_empty() {
            BeginRecord
          } else {
            BeginKey
          }
        }
      BeginKey => {
        let writer = append_writer(cursor, true)
        cursor.writer = Some(writer)
        @encode.begin_array(writer)
        cursor.phase = KeyValue
      }
      KeyValue => {
        let writer = cursor.writer.unwrap()
        if cursor.wire is None {
          cursor.wire = Some(
            @value.start_wire_emit(
              cursor.identities[cursor.index].value,
              writer,
            ),
          )
        }
        if @value.advance_wire_emit(cursor.wire.unwrap()) {
          cursor.wire = None
          cursor.index += 1
          if cursor.index == cursor.identities.length() {
            cursor.phase = FinishKey
          }
        }
      }
      FinishKey => {
        let writer = cursor.writer.unwrap()
        @encode.end_array(writer)
        let (key, bytes, nodes, _) = @encode.finish_hash_metrics(writer)
        cursor.writer = None
        cursor.key = key
        cursor.key_bytes = bytes
        cursor.key_work = nodes
        if builder.keys.get(key) is Some(candidate) {
          // The original cursor covers one emitter's three stacks. Reserve
          // the second emitter, prior identity references and fixed comparison
          // custody before allocation. No retained wire fragments are needed.
          guard append_workspace_slots(
              0,
              cursor.identities.length(),
              builder.limits.max_value_depth,
            )
            is Some(extra) &&
            extra <=
            builder.limits.max_workspace_slots -
            builder.workspace_slots -
            cursor.workspace else {
            return fail_append(cursor, WorkspaceLimit)
          }
          cursor.workspace += extra
          cursor.comparison_slots = extra
          cursor.prior_identities = Some([])
          cursor.candidate = Some(candidate)
          cursor.index = 0
          cursor.phase = ReadPriorIdentity
        } else {
          cursor.index = 0
          cursor.phase = BeginRecord
        }
      }
      ReadPriorIdentity =>
        if cursor.index == builder.identities.length() {
          cursor.comparison = Some({
            left: identity_stream(builder, cursor.identities),
            right: identity_stream(builder, cursor.prior_identities.unwrap()),
          })
          cursor.phase = CompareKey
        } else {
          let record = cursor.candidate.unwrap()
          guard record.fields.get(cursor.prior_field) is Some((field, value)) else {
            return fail_append(cursor, InvalidIdentity)
          }
          cursor.prior_field += 1
          if @schema.reference_name(field) == builder.identities[cursor.index] {
            cursor.prior_identities.unwrap().push(value)
            cursor.prior_field = 0
            cursor.index += 1
          }
        }
      CompareKey =>
        if advance_identity_comparison(cursor.comparison.unwrap())
          is Some(equal) {
          cancel_identity_comparison(cursor.comparison.unwrap())
          cursor.comparison = None
          if equal {
            return fail_append(cursor, DuplicateIdentity)
          }
          cursor.prior_identities.unwrap().clear()
          cursor.candidate = cursor.candidate.unwrap().prior_identity
          cursor.index = 0
          cursor.prior_field = 0
          if cursor.candidate is None {
            cursor.workspace -= cursor.comparison_slots
            cursor.comparison_slots = 0
            cursor.prior_identities = None
            cursor.phase = BeginRecord
          } else {
            cursor.phase = ReadPriorIdentity
          }
        }
      BeginRecord => {
        let writer = append_writer(cursor, false)
        cursor.writer = Some(writer)
        @encode.begin_array(writer)
        cursor.phase = if cursor.width == 0 { FinishRecord } else { BeginField }
      }
      BeginField => {
        let writer = cursor.writer.unwrap()
        @encode.begin_array(writer)
        cursor.name = Some(
          @encode.start_string_value(
            writer,
            @schema.reference_name(cursor.fields[cursor.index].0),
          ),
        )
        cursor.phase = FieldName
      }
      FieldName =>
        if @encode.advance_string_value(cursor.name.unwrap()) {
          cursor.name = None
          cursor.wire = Some(
            @value.start_wire_emit(
              cursor.fields[cursor.index].1.value,
              cursor.writer.unwrap(),
            ),
          )
          cursor.phase = FieldValue
        }
      FieldValue =>
        if @value.advance_wire_emit(cursor.wire.unwrap()) {
          cursor.wire = None
          cursor.phase = EndField
        }
      EndField => {
        @encode.end_array(cursor.writer.unwrap())
        cursor.index += 1
        cursor.phase = if cursor.index == cursor.width {
          FinishRecord
        } else {
          BeginField
        }
      }
      FinishRecord => {
        let writer = cursor.writer.unwrap()
        @encode.end_array(writer)
        let (bytes, nodes, _) = @encode.finish_measurement_usage(writer)
        cursor.writer = None
        cursor.record_bytes = bytes
        cursor.record_work = nodes
        // The retained copy is already part of the reserved field snapshot.
        // Keep cursor custody until the record has actually been committed.
        if cursor.width + 2 >
          builder.limits.max_workspace_slots -
          builder.workspace_slots -
          cursor.workspace {
          return fail_append(cursor, WorkspaceLimit)
        }
        if reserve(
            builder,
            cursor.key_bytes + bytes,
            cursor.key_bytes + bytes,
            cursor.width + 1 + cursor.key_work + nodes,
            cursor.width + 2 + cursor.workspace,
          )
          is Some(issue) {
          return fail_append(cursor, issue)
        }
        cursor.phase = Commit
      }
      Commit => {
        let record : Record = {
          fields: cursor.fields,
          prior_identity: if cursor.identities.is_empty() {
            None
          } else {
            builder.keys.get(cursor.key)
          },
        }
        builder.values.push(record)
        if !cursor.identities.is_empty() {
          builder.keys[cursor.key] = record
        }
        builder.input_records += 1
        builder.value_bytes += cursor.key_bytes + cursor.record_bytes
        builder.retained_value_bytes += cursor.key_bytes + cursor.record_bytes
        builder.work += cursor.width + 1 + cursor.key_work + cursor.record_work
        builder.workspace_slots += cursor.width + 2
        cursor.phase = Complete
        cleanup_append(cursor) |> ignore
        return Ok(true)
      }
      Complete | Failed => return Err(Closed)
    }
    Ok(false)
  } catch {
    _ =>
      fail_append(
        cursor,
        if cursor.work_limited {
          WorkLimit
        } else {
          ValueLimit
        },
      )
  }
}

///|
/// Stop must be confirmed by the execution owner before cancellation cleanup.
/// A cancelled or failed provisional record closes writing, not prior custody.
pub fn cleanup_append(cursor : AppendCursor) -> Bool {
  if cursor.cleaned {
    return false
  }
  if cursor.wire is Some(wire) {
    @value.cancel_wire_emit(wire)
    cursor.wire = None
  }
  if cursor.name is Some(name) {
    @encode.cancel_string_value(name)
    cursor.name = None
  }
  if cursor.writer is Some(writer) {
    @encode.cancel_writer(writer)
    cursor.writer = None
  }
  if cursor.comparison is Some(comparison) {
    cancel_identity_comparison(comparison)
    cursor.comparison = None
  }
  if !(cursor.phase is Complete) {
    cursor.builder.open = false
    cursor.fields.clear()
  }
  cursor.fields = []
  cursor.actual.clear()
  cursor.identities.clear()
  if cursor.prior_identities is Some(values) {
    values.clear()
    cursor.prior_identities = None
  }
  cursor.candidate = None
  cursor.supplied = []
  cursor.key = ""
  cursor.cleaned = true
  cursor.builder.pending_append = None
  true
}
