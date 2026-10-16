///|
/// A bounded observation projection of the existing Run owner, not a Run,
/// permission, cancellation acknowledgement or physical-stop certificate.
struct RunStateObservation {
  value : @json.CanonicalValue
  key : String
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum RunStateObservationIssue {
  InvalidObservation
  ForeignRun
  InvalidRevision
  RevisionExhausted
  InvalidPriorObservation
  ObservationEncoding
} derive(Eq, Debug)

///|
fn valid_observation_revision(revision : Int64) -> Bool {
  revision >= 0L && revision <= 9007199254740991L
}

///|
fn emit_run_state_revision(
  writer : @encode.Writer,
  value : @json.CanonicalValue,
  revision : Int64,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  let mut inserted = false
  for (name, child) in @json.object_fields(value).unwrap() {
    if name == "revision" {
      continue
    }
    if !inserted && @canonical.compare_utf16("revision", name) < 0 {
      @encode.key(writer, "revision")
      @encode.decimal_number_value(writer, revision.to_string())
      inserted = true
    }
    @encode.key(writer, name)
    @json.emit_value(child, writer)
  }
  if !inserted {
    @encode.key(writer, "revision")
    @encode.decimal_number_value(writer, revision.to_string())
  }
  @encode.end_object(writer)
}

///|
fn emit_run_state_observation_key(
  writer : @encode.Writer,
  value : @json.CanonicalValue,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for (name, child) in @json.object_fields(value).unwrap() {
    // Read timestamps are observations of a fact, not new logical facts.
    // Control revision and every non-clock availability/cause field remain.
    if name == "revision" || name == "updated_at" {
      continue
    }
    @encode.key(writer, name)
    if name == "result_availability" {
      @encode.begin_object(writer)
      for (result, observation) in @json.object_fields(child).unwrap() {
        @encode.key(writer, result)
        @encode.begin_object(writer)
        for (field, item) in @json.object_fields(observation).unwrap() {
          if field != "observed_at" {
            @encode.key(writer, field)
            @json.emit_value(item, writer)
          }
        }
        @encode.end_object(writer)
      }
      @encode.end_object(writer)
    } else {
      @json.emit_value(child, writer)
    }
  }
  @encode.end_object(writer)
}

///|
/// Join an owner-produced state projection with the original journal's actual
/// current counter. Intermediate issuer projections need not contain that
/// journal field yet; no incomplete projection is admitted as public wire.
/// The existing generated current schema validates the complete candidate.
/// A present invalid revision is never repaired by overwriting it.
pub fn prepare_run_state_observation(
  wire : String,
  expected_run_id : String,
  current_revision : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunStateObservation, RunStateObservationIssue] {
  if !valid_observation_revision(current_revision) {
    return Err(InvalidRevision)
  }
  let value = match
    parse_contract_wire(wire, max_bytes, max_nodes, max_depth, data_keys=true) {
    Ok(value) => value
    Err(_) => return Err(InvalidObservation)
  }
  if @json.object_fields(value) is None {
    return Err(InvalidObservation)
  }
  if expected_run_id.is_empty() ||
    contract_string_from_value(value, "run_id") != Some(expected_run_id) {
    return Err(ForeignRun)
  }
  match @json.object_field(value, "revision") {
    None => ()
    Some(@json.Number(number)) =>
      match @scalar.read_safe_integer(number) {
        Some(revision) if valid_observation_revision(revision) => ()
        _ => return Err(InvalidRevision)
      }
    _ => return Err(InvalidRevision)
  }
  try {
    let complete = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_run_state_revision(complete, value, current_revision)
    let candidate = match
      parse_contract_wire(
        @encode.finish(complete),
        max_bytes,
        max_nodes,
        max_depth,
        data_keys=true,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidObservation)
    }
    if !validate_generated_protocol_shape(
        "run_state", candidate, true, max_bytes, max_nodes, max_depth,
      ) {
      return Err(InvalidObservation)
    }
    let key = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_run_state_observation_key(key, candidate)
    Ok({
      value: candidate,
      key: @encode.finish(key),
      max_bytes,
      max_nodes,
      max_depth,
    })
  } catch {
    _ => Err(ObservationEncoding)
  }
}

///|
/// Data-only equivalence key for the same original Run row. It grants nothing.
pub fn RunStateObservation::key(self : RunStateObservation) -> String {
  self.key
}

///|
/// The durable owner supplies the prior key/counter from that same row and
/// commits the returned revision with the new key before exposing the wire.
/// A missing key is legal only for a newly issued zero-counter row.
pub fn RunStateObservation::next_revision(
  self : RunStateObservation,
  prior_key : String?,
  current_revision : Int64,
) -> Result[Int64, RunStateObservationIssue] {
  if !valid_observation_revision(current_revision) {
    return Err(InvalidRevision)
  }
  match prior_key {
    None =>
      if current_revision == 0L {
        Ok(0L)
      } else {
        Err(InvalidPriorObservation)
      }
    Some(prior) =>
      if prior.is_empty() {
        Err(InvalidPriorObservation)
      } else if prior == self.key {
        Ok(current_revision)
      } else if current_revision == 9007199254740991L {
        Err(RevisionExhausted)
      } else {
        Ok(current_revision + 1L)
      }
  }
}

///|
/// Prepare bounded DATA; the durable owner exposes it only after confirming
/// its original row's revision commit. Serialization proves no execution right.
pub fn RunStateObservation::wire(
  self : RunStateObservation,
  revision : Int64,
) -> Result[String, RunStateObservationIssue] {
  if !valid_observation_revision(revision) {
    return Err(InvalidRevision)
  }
  try {
    let writer = @encode.writer(self.max_bytes, self.max_nodes, self.max_depth)
    emit_run_state_revision(writer, self.value, revision)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(ObservationEncoding)
  }
}
