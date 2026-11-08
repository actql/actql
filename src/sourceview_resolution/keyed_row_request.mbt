///|
pub(all) enum KeyedRowRequestIssue {
  InvalidLimits
  WorkLimit
  PairLimit
  CorrelationArity
  InvalidCorrelation(Int)
  UnboundHostBinding
  Closed
} derive(Eq, Debug)

///|
/// One typed request instance under the original admitted SourceView. This is
/// not an acquisition grant, response-completeness proof or capture receipt.
struct KeyedRowRequest {
  owner : ParameterizedKeyedRequest
  fields : Array[(String, @value.CheckedValue)]
  work : Int
  nodes : Int
  text : Int
}

///|
/// A compilation/execution continuation, not a new acquisition owner. The
/// caller retains its input borrow and reserves this bounded workspace in the
/// existing ledger. Correlated runtime values are checked by the shared value
/// cursor; an envelope is never parsed into a newly issued reference here.
struct KeyedRowRequestCursor {
  owner : ParameterizedKeyedRequest
  keys : Array[@value.Value]
  fields : Array[(String, @value.CheckedValue)]
  limits : RequestLimits
  mut work : Int
  mut nodes : Int
  mut text : Int
  mut index : Int
  mut active : @value.RecheckCursor?
  mut finished : Bool
}

///|
pub enum KeyedRowRequestPoll {
  KeyedRowRequestContinue
  KeyedRowRequestComplete(KeyedRowRequest)
  KeyedRowRequestFailed(KeyedRowRequestIssue)
}

///|
pub fn start_keyed_row_request(
  request : ParameterizedKeyedRequest,
  keys : Array[@value.Value],
  limits : RequestLimits,
) -> Result[KeyedRowRequestCursor, KeyedRowRequestIssue] {
  if limits.max_work < 0 ||
    limits.max_pairs < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let roles = keyed_request_correlation(request.request)
  let count = @environment.source_correlation_pair_count(roles)
  if keys.length() != count {
    return Err(CorrelationArity)
  }
  if count > limits.max_pairs ||
    request.fields.length() > limits.max_pairs - count {
    return Err(PairLimit)
  }
  if request.host_bindings != 0 {
    return Err(UnboundHostBinding)
  }
  let mut remaining = limits.max_work
  if remaining < 1 || count > remaining - 1 {
    return Err(WorkLimit)
  }
  remaining -= count + 1
  // Reserve the detached key array and each retained authored-field/name before
  // copying. The request checker already forbids authored correlation fields.
  for field in request.fields {
    if remaining < 1 || field.field.slot.field_name.length() > remaining - 1 {
      return Err(WorkLimit)
    }
    remaining -= field.field.slot.field_name.length() + 1
  }
  let fields = []
  for field in request.fields {
    let value = match field.value {
      CheckedLiteral(value) => value
      BoundParameter(parameter) => parameter.value
      UnboundHostBinding(_) => return Err(UnboundHostBinding)
    }
    fields.push((field.field.slot.field_name, value))
  }
  Ok({
    owner: request,
    keys: keys.copy(),
    fields,
    limits,
    work: limits.max_work - remaining,
    nodes: 0,
    text: 0,
    index: 0,
    active: None,
    finished: false,
  })
}

///|
pub fn cancel_keyed_row_request(cursor : KeyedRowRequestCursor) -> Unit {
  if !cursor.finished {
    if cursor.active is Some(active) {
      @value.cancel_recheck_runtime_value(active)
    }
    cursor.active = None
    cursor.keys.clear()
    cursor.fields.clear()
    cursor.finished = true
  }
}

///|
fn keyed_row_request_fail(
  cursor : KeyedRowRequestCursor,
  issue : KeyedRowRequestIssue,
) -> KeyedRowRequestPoll {
  cancel_keyed_row_request(cursor)
  KeyedRowRequestFailed(issue)
}

///|
/// Each advance consumes logical work before entering the shared resumable
/// recheck. Missing/NULL are not substituted; only the admitted role contract
/// decides whether a supplied value is valid.
pub fn advance_keyed_row_request(
  cursor : KeyedRowRequestCursor,
) -> KeyedRowRequestPoll {
  if cursor.finished {
    return KeyedRowRequestFailed(Closed)
  }
  if cursor.work == cursor.limits.max_work {
    return keyed_row_request_fail(cursor, WorkLimit)
  }
  cursor.work += 1
  if cursor.index == cursor.keys.length() {
    cursor.finished = true
    cursor.keys.clear()
    return KeyedRowRequestComplete({
      owner: cursor.owner,
      fields: cursor.fields,
      work: cursor.work,
      nodes: cursor.nodes,
      text: cursor.text,
    })
  }
  if cursor.active is None {
    let role = @environment.source_correlation_pair_at(
        keyed_request_correlation(cursor.owner.request),
        cursor.index,
      ).unwrap().request
    if role.name.length() > cursor.limits.max_work - cursor.work {
      return keyed_row_request_fail(cursor, WorkLimit)
    }
    cursor.work += role.name.length()
    cursor.active = @value.start_recheck_runtime_value(
      cursor.keys[cursor.index],
      role.contract,
      {
        max_nodes: cursor.limits.values.max_nodes - cursor.nodes,
        max_depth: cursor.limits.values.max_depth,
        max_text_bytes: cursor.limits.values.max_text_bytes - cursor.text,
      },
    )
    if cursor.active is None {
      return keyed_row_request_fail(cursor, InvalidCorrelation(cursor.index))
    }
    return KeyedRowRequestContinue
  }
  match @value.advance_recheck_runtime_value(cursor.active.unwrap()) {
    RecheckContinue => KeyedRowRequestContinue
    RecheckFailed =>
      keyed_row_request_fail(cursor, InvalidCorrelation(cursor.index))
    RecheckComplete(value, nodes, text) => {
      let role = @environment.source_correlation_pair_at(
          keyed_request_correlation(cursor.owner.request),
          cursor.index,
        ).unwrap().request
      cursor.fields.push((role.name, value))
      cursor.nodes += nodes
      cursor.text += text
      cursor.active = None
      cursor.index += 1
      KeyedRowRequestContinue
    }
  }
}

///|
pub fn keyed_row_request_owner(
  value : KeyedRowRequest,
) -> ParameterizedKeyedRequest {
  value.owner
}

///|
/// Borrow one already checked field from this exact request, without decoding
/// its wire into newly issued values or copying its retained field array.
pub fn keyed_row_request_field(
  request : KeyedRowRequest,
  name : String,
) -> @value.CheckedValue? {
  for (field, value) in request.fields {
    if field == name {
      return Some(value)
    }
  }
  None
}

///|
pub fn keyed_row_request_usage(value : KeyedRowRequest) -> (Int, Int, Int) {
  (value.work, value.nodes, value.text)
}

///|
/// Cumulative logical work remains observable on failure and cancellation. The
/// acquisition caller debits differences in its existing owner; rereading this
/// counter is not another debit and request failure never refunds prior work.
pub fn keyed_row_request_work(cursor : KeyedRowRequestCursor) -> Int {
  cursor.work
}

///|
/// The physical caller reserves wire bytes/nodes before calling, and performs
/// its current read authorization before dispatch. This function only emits
/// the retained typed values; it does not grant I/O or renew reference leases.
pub fn keyed_row_request_wire(
  value : KeyedRowRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RequestWireIssue] {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    issue => return Err(Encoding(issue))
  }
  try {
    @encode.begin_object(writer)
    for (name, field) in value.fields {
      @encode.key(writer, name)
      @value.emit_checked_wire_value(field, writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => {
      @encode.cancel_writer(writer)
      Err(Encoding(issue))
    }
  }
}

///|
/// The completed Request's own retained carriers, not its borrowed values.
/// Static CheckedValues stay on the original Parameter/template owner; runtime
/// payloads stay on the original left producer. Only correlation recheck
/// wrappers are new. Moving this Request beyond a temporary constructor must
/// retain this actual variable inventory on that caller's existing holding.
pub fn keyed_row_request_retained_inventory(
  value : KeyedRowRequest,
) -> @shape.CollectionConstructionExtent? {
  let fields = value.fields.length().to_int64()
  let correlated = @environment.source_correlation_pair_count(
    keyed_request_correlation(value.owner.request),
  ).to_int64()
  @shape.collection_construction_extent({
    records: 1L + fields + correlated,
    record_references: 2L + 2L * fields + 2L * correlated,
    record_words: 3L,
    reference_arrays: 1L,
    reference_items: fields,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}
