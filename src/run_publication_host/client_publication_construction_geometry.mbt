///|
/// Per-original wire geometry, in the same Unit/Result/scope order as the
/// publication fact issuer. These are construction DATA, not admitted facts,
/// a capacity reservation, or authority to skip any saved-body validation.
pub(all) struct ClientPublicationPlanFactGeometry {
  limits : Array[(Int, Int, Int)]
  bindings : Array[(Int, Int, Int)]
  entries : Array[(Int, Int, Int)]
} derive(Eq, Debug)

///|
/// Bodies are held once per identity. Emitter totals include every original
/// occurrence, including bodies later deduplicated; these are logical wire/
/// node work dimensions, not CPU time or the complete constructor work quote.
pub(all) struct ClientPublicationWitnessGeometry {
  bodies : Array[(Int, Int, Int)]
  occurrences : Int64
  emitted_bytes : Int64
  emitted_nodes : Int64
} derive(Eq, Debug)

///|
fn measure_client_publication_binding(
  value : PreparedClientProgram,
  unit : Int,
  index : Int,
  scope : ClientPublicationLimitScope,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), ClientPublicationBindingIssue] {
  let (definition, name, measure, subject, maximum, resolved) = match
    client_publication_binding_arguments(value, unit, index, scope) {
    Ok(fields) => fields
    Err(issue) => return Err(issue)
  }
  try {
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_publication_binding(
      writer,
      definition,
      name,
      measure,
      subject,
      maximum,
      resolved,
      Some(()),
      (_, writer) => @encode.emit_measurement(writer, (73, 1, 0)),
    )
    Ok(@encode.finish_measurement_usage(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
// This literal remains the same source for the concatenated original body and
// its measuring writer. The latter never creates or hashes a placeholder CID.
fn client_publication_limit_fact_kind() -> String {
  "resolved_limit"
}

///|
/// Measure the checked Result publication bundle before its wire/tree copies
/// are allocated. Limit claims use their existing owner measurement. Binding
/// geometry uses the actual argument projection and serializer; a future
/// SHA256 identity contributes its fixed encoded extent, never a fake token.
pub fn measure_prepared_client_publication_plan_facts(
  value : PreparedClientProgram,
  max_facts : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientPublicationPlanFactGeometry, ClientPublicationPlanFactIssue] {
  if max_facts <= 0 || max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(Limits(InvalidLimit))
  }
  let program = @strategy.graph_program(value.graph)
  let limits : Array[(Int, Int, Int)] = []
  let bindings : Array[(Int, Int, Int)] = []
  let entries : Array[(Int, Int, Int)] = []
  for unit in 0..<@checked.unit_count(program) {
    guard @checked.unit_publication_count(program, unit) is Some(count) else {
      return Err(Limits(CheckedLimit(MissingPublication)))
    }
    for index in 0..<count {
      guard @checked.unit_publication_at(program, unit, index)
        is Some(publication) else {
        return Err(Limits(CheckedLimit(MissingPublication)))
      }
      for scope in [Rows, Bytes] {
        if limits.length() >= max_facts {
          return Err(Limits(BudgetExceeded))
        }
        let claim = match scope {
          Rows => @checked.publication_rows(publication)
          Bytes => @checked.publication_bytes(publication)
        }
        let limit = @capacity.measure_limit(
          claim, max_wire_bytes, max_nodes, max_depth,
        ) catch {
          _ => return Err(Limits(CheckedLimit(Encoding)))
        }
        let binding = match
          measure_client_publication_binding(
            value, unit, index, scope, max_wire_bytes, max_nodes, max_depth,
          ) {
          Ok(measurement) => measurement
          Err(issue) => return Err(Bindings(CheckedBinding(issue)))
        }
        let entry = try {
          let writer = @encode.measuring_writer(
            max_wire_bytes, max_nodes, max_depth,
          )
          @encode.begin_object(writer)
          @encode.key(writer, "kind")
          @encode.string_value(writer, client_publication_limit_fact_kind())
          @encode.key(writer, "value")
          @encode.emit_measurement(writer, limit)
          @encode.end_object(writer)
          @encode.finish_measurement_usage(writer)
        } catch {
          _ => return Err(Limits(BudgetExceeded))
        }
        limits.push(limit)
        bindings.push(binding)
        entries.push(entry)
      }
    }
  }
  Ok({ limits, bindings, entries, })
}

///|
/// Measure the same deduplicated original witness inventory as the issuer.
/// The occurrence count retains repeated emitter work even when only one
/// identity/body is held. No new wire, hash, parser or arithmetic proof is
/// produced; the real issuer still checks equal-CID complete-body equality.
pub fn measure_prepared_client_publication_witnesses(
  value : PreparedClientProgram,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientPublicationWitnessGeometry, ClientPublicationWitnessIssue] {
  let occurrences = Ref(0L)
  let emitted_bytes = Ref(0L)
  let emitted_nodes = Ref(0L)
  collect_client_publication_witnesses(
    value,
    max_witnesses,
    max_wire_bytes,
    max_nodes,
    max_depth,
    witness => {
      guard @execution.checked_preparation_add_product(occurrences.val, 1L, 1L)
        is Some(next) else {
        return Err(BudgetExceeded)
      }
      occurrences.val = next
      try {
        let writer = @encode.measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
        @capacity.emit(witness, writer)
        let measurement = @encode.finish_measurement_usage(writer)
        guard @execution.checked_preparation_add_product(
            emitted_bytes.val,
            measurement.0.to_int64(),
            1L,
          )
          is Some(bytes) &&
          @execution.checked_preparation_add_product(
            emitted_nodes.val,
            measurement.1.to_int64(),
            1L,
          )
          is Some(nodes) else {
          return Err(BudgetExceeded)
        }
        emitted_bytes.val = bytes
        emitted_nodes.val = nodes
        Ok(measurement)
      } catch {
        _ => Err(Encoding)
      }
    },
    (left, right) => left == right,
  ).map(original => {
    bodies: original.0,
    occurrences: occurrences.val,
    emitted_bytes: emitted_bytes.val,
    emitted_nodes: emitted_nodes.val,
  })
}
