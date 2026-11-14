///|
// This is one data expansion: detached snapshot -> Source tree + owned index.
// The original snapshot quote cannot cover the additional simultaneous trees.
// Reuse the Source/index envelopes once; there is one actual grow callback,
// no serializer, policy-sized padding, new tariff or per-wrapper Resource call.
fn request_native_tree_units(
  units : Int64,
  values : Int64,
  limits : @syntax.Limits,
  max_key_units? : Int? = None,
) -> @execution.PreparationRepresentationUnits? {
  guard request_native_input_geometry(
      units,
      values,
      limits.source.max_input_bytes,
      limits.source.max_depth,
    )
    is Some((_, nodes, depth)) else {
    return None
  }
  // SDK quantities are independently rounded high-water bounds. Their
  // difference is not a bound on key text; the original total units are.
  let key_units = units
  let key_bound = match max_key_units {
    Some(original) => original
    None => {
      if key_units > 2147483647L {
        return None
      }
      key_units.to_int()
    }
  }
  guard @source.captured_json_construction_extent(
      nodes,
      depth,
      normalize_keys=true,
      key_units~,
      max_key_units=key_bound,
    )
    is Some(source) &&
    @decode.admission_construction_inventory(nodes, nodes, nodes, nodes, depth)
    is Some(index) else {
    return None
  }
  @execution.compose_preparation_representation([
    {
      record_headers: source.record_headers,
      reference_slots: source.reference_slots,
      scalar_words: source.scalar_words,
      owned_utf16_units: source.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    decode_construction_preparation_units(index.indexed),
    decode_construction_preparation_units(index.keys),
    decode_construction_preparation_units(index.ancestry),
    decode_construction_preparation_units(index.controls),
  ])
}

///|
fn request_native_input_units(
  units : Int64,
  values : Int64,
  limits : @syntax.Limits,
  max_key_units? : Int? = None,
) -> @execution.PreparationRepresentationUnits? {
  guard request_native_tree_units(units, values, limits, max_key_units~)
    is Some(tree) else {
    return None
  }
  @execution.compose_preparation_representation([
    program_json_driver_controls, tree,
  ])
}

///|
/// Enter the EXISTING Source/index/Program controller on the same Request and
/// snapshot debit. No editable counts, parsed tree or caller admission Bool
/// is accepted. The normal Node manager must supply its SAME captured input.
pub fn[I, T] prepare_request_native_program_input(
  owner : ClientRequestPreparation[I],
  input : I,
  captured : T,
  reader : @source.JsonDataReader[T],
  limits : @syntax.Limits,
  supplied? : T? = None,
) -> Result[
  ClientProgramJsonPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  guard owner.phase == Open &&
    !owner.native_parameters_ready &&
    request_intent_input_ready(owner) &&
    owner.program_json is None else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let tree = match
    request_native_input_units(
      owner.snapshot_units,
      owner.snapshot_values,
      limits,
      max_key_units=if owner.submitted_intent is Some(_) &&
        owner.snapshot_key_units.val >= 0 {
        Some(owner.snapshot_key_units.val)
      } else {
        None
      },
    ) {
    None => return Err(Policy)
    Some(value) => value
  }
  let units = if supplied is Some(_) {
    let (source, tree_limits) = @local_preparation.local_parameter_input_limits()
    guard request_native_tree_units(
        owner.snapshot_units,
        owner.snapshot_values,
        { source, tree: tree_limits, max_stages: 0, },
      )
      is Some(parameters) &&
      @execution.compose_preparation_representation([tree, parameters])
      is Some(combined) else {
      return Err(Policy)
    }
    combined
  } else {
    tree
  }
  guard @execution.preparation_representation_cost(units) is Some(bytes) else {
    return Err(Policy)
  }
  let (r0, e0) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  // Existing retained-index reconciliation also executes the fixed quote
  // controller after the constructor returns. Fund that same scratch BEFORE
  // entry; small inputs cannot borrow accidental tree/Map peak slack.
  guard @execution.checked_preparation_add_product(r0, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(
      bytes, program_json_quote_control_bytes, 1L,
    )
    is Some(execution_bytes) &&
    @execution.checked_preparation_add_product(e0, execution_bytes, 1L)
    is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      return Err(Capacity(issue))
    }
    Ok(_) => ()
  }
  // Existing Local intake admits supplied values before the Program document.
  // Preserve that typed refusal order and the exact original cursor.
  owner.native_parameters = match supplied {
    None => None
    Some(value) =>
      match @local_preparation.admit_captured_local_parameters(value, reader) {
        Err(issue) => {
          owner.phase = ProgramJsonFailed
          return Err(Parameters(issue))
        }
        Ok(value) => Some(value)
      }
  }
  let indexed = match
    @syntax.admit_captured_program_input(captured, reader, limits) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      return Err(ProgramJson(Syntax(issue)))
    }
    Ok(value) => value
  }
  // The native Source/index constructor has returned. Its transient Source
  // tree, key Maps and ancestry are gone; the original immutable index stays.
  // Reuse the existing retained-index projection and admission's cached DATA,
  // never walk/parse the input again. Without separate Parameter geometry the
  // supplied-Parameter branch conservatively keeps its original whole quote.
  let retained = if owner.native_parameters is None {
    let root = @syntax.program_input_cursor(indexed)
    let actual = @decode.admission_usage(root)
    let observed = @decode.admission_preparation_data(root)
    match
      program_index_retained_units(
        indexed,
        observed.fields,
        observed.fields + observed.texts,
        actual.nodes,
        actual.nodes,
      ) {
      Some(value) => value
      None => {
        owner.phase = ProgramJsonFailed
        return Err(Policy)
      }
    }
  } else {
    units
  }
  let child = request_program_index_preparation(
    owner, input, indexed, retained, limits, r0, e0,
  )
  owner.native_parameters_ready = true
  owner.program_json = Some(child)
  child.phase = Indexed
  match reconcile_program_json_preparation_index(child) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      return Err(ProgramJson(issue))
    }
    Ok(_) => ()
  }
  owner.phase = ProgramJson
  Ok(child)
}

///|
// Original phase holder DATA shared by native Program and parsed documents.
// Both entering callers fund their actual parse/index backing before entry.
fn[I] request_program_index_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  indexed : @syntax.ParsedProgramInput,
  units : @execution.PreparationRepresentationUnits,
  limits : @syntax.Limits,
  r0 : Int64,
  e0 : Int64,
) -> ClientProgramJsonPreparation[I, Unit] {
  {
    capacity: owner.capacity,
    input: Some(input),
    source: None,
    indexed: Some(indexed),
    ready: None,
    retained_index: Some(units),
    structure: None,
    structure_quote: None,
    program: None,
    structural_issue: None,
    work: None,
    limits,
    base_retained: r0,
    base_execution: e0,
    busy: false,
    phase: RetainedIndex,
  }
}

///|
// Same observed native envelope for Program and submitted-intent expansion.
// These are constructor bounds, not a policy/semantic grant or a second scan.
fn request_native_input_geometry(
  units : Int64,
  values : Int64,
  max_bytes : Int,
  max_depth : Int,
) -> (Int, Int, Int)? {
  if units < 1L || values < 1L || values > units || values > 2147483646L {
    return None
  }
  // Each visited native value/key/Text unit was observed by the SAME SDK
  // traversal. A native binary64 spelling is at most 25 ASCII bytes; escaped
  // Text/key units are at most six. 32 covers either per-visited-value case.
  // Key enumeration retains all original keys before a node-limit refusal,
  // so nodes remain bounded by the observed snapshot, not a tighter policy.
  let maximum = Int::max(1, max_bytes).to_int64()
  let text_units = units - values
  let text_bytes = if text_units > maximum / 6L {
    maximum
  } else {
    6L * text_units
  }
  let value_bytes = if values > maximum / 32L { maximum } else { 32L * values }
  let bytes = Int64::min(maximum, text_bytes + value_bytes).to_int()
  let nodes = values.to_int()
  let depth = Int::max(1, Int::min(max_depth, nodes))
  Some((bytes, nodes, depth))
}
