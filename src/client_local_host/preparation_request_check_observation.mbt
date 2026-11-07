///|
// The existing report writer has its own fixed 65536-byte/4096-node/16-depth
// encoding bound. Add its actual writer inventory and output String plus
// proportional findings, labels and current-publication Source/index views.
// All Program/Parameters/semantic-result originals stay on the SAME parent;
// none is parsed, copied, taken or semantically prepared again for disclosure.
fn[I] request_check_observation_bytes(
  child : ClientProgramCheckPreparation[I, Unit],
  source : @stages.Source,
  outcome : @checked.CheckOutcome,
  publication : String,
  input_label_bytes : Int64,
  original_parameters : String?,
) -> Int64? {
  let requests = match outcome {
    @checked.NeedsInputs(value) => @checked.input_request_count(value)
    _ => 0
  }
  let findings = @parameters.declaration_count(@stages.declarations(source)).to_int64() +
    2L * requests.to_int64() +
    4L
  // The same retained semantic envelope remains live through the report. Its
  // existing quote is not refunded or reused as this additional output budget.
  guard child.check_data is Some(_) else { return None }
  guard request_check_observation_inventory_bytes(
      publication, findings, input_label_bytes,
    )
    is Some(total) else {
    return None
  }
  if original_parameters is None {
    return Some(total)
  }
  guard child.arguments is Some(arguments) &&
    arguments.supplied is Some(supplied) &&
    request_check_original_pointer_bytes(original_parameters.unwrap(), supplied)
    is Some(pointer) else {
    return None
  }
  @execution.checked_preparation_add_product(total, pointer, 1L)
}

///|
// One complete UTF8 input and scalar-key reader peak; the existing path's
// retained names and RFC6901 output coexist. All dimensions come from this
// input and its admitted depth, not the whole policy allowance. Scalars and
// path tokens are explained sequentially, never read as another Parameters map.
fn request_check_original_pointer_bytes(
  body : String,
  supplied : @decode.Cursor,
) -> Int64? {
  let (limits, _) = @local_preparation.local_parameter_input_limits()
  let units = body.length()
  guard units > 0 && units <= limits.max_input_bytes else { return None }
  // Report byte labels are DATA, never construction measurements. Derive the
  // UTF8 upper bound from this actual retained String without another scan.
  let wire_bytes = 4L * units.to_int64()
  let scalar_bytes = Int::min(4 * units, limits.max_input_bytes)
  guard @source.json_construction_extent(
      scalar_bytes,
      1,
      1,
      normalize_keys=false,
    )
    is Some(scalar) &&
    @execution.preparation_representation_cost({
      record_headers: scalar.record_headers,
      reference_slots: scalar.reference_slots,
      scalar_words: scalar.scalar_words,
      owned_utf16_units: scalar.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(read) &&
    @source.json_tree_retained_construction_extent(1, 0, 0, 0, units.to_int64())
    is Some(retained) &&
    @canonical.nfc_lf_construction_extent(units) is Some(normalization) &&
    @execution.preparation_representation_cost({
      record_headers: retained.record_headers + normalization.record_headers,
      reference_slots: retained.reference_slots + normalization.reference_slots,
      scalar_words: retained.scalar_words + normalization.scalar_words,
      owned_utf16_units: retained.owned_utf16_units +
      normalization.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(matching) &&
    @execution.execution_capacity_inventory_bytes([
      { unit: @execution.QuotedBytes, count: wire_bytes, copies: 1, },
      {
        unit: @execution.QuotedBytes,
        count: scalar_bytes.to_int64(),
        copies: 1,
      },
      { unit: @execution.DecodedTextBytes, count: units.to_int64(), copies: 4, },
      {
        unit: @execution.ValueNodeSlots,
        count: @decode.admission_usage(supplied).depth.to_int64() + 2L,
        copies: 4,
      },
    ])
    is Some(path) else {
    return None
  }
  // The scalar parser returns before its original key correspondence check.
  // Retain that scalar beside normalization, then take the two actual peaks.
  @execution.checked_preparation_add_product(
    Int64::max(read, matching),
    path,
    1L,
  )
}

///|
fn request_check_observation_reference(
  value : String,
  prefix : String,
  digits? : Int = 64,
) -> Bool {
  value.length() == prefix.length() + digits &&
  value.has_prefix(prefix) &&
  value[prefix.length():]
  .to_owned()
  .iter()
  .all(character => {
    let n = character.to_int()
    (n >= 48 && n <= 57) || (n >= 97 && n <= 102)
  })
}

///|
/// An optional public observation of the SAME still-live nominal refusal.
/// The Host binds report document revisions/byte lengths to its original SDK
/// snapshot and supplies current audience metadata after authorization awaits.
/// These DATA are never capacity, Source authority or an acceptance witness.
/// A retired/unavailable original returns None; it is not rechecked/recreated.
pub fn[I] project_request_check_outcome(
  owner : ClientRequestPreparation[I],
  input : I,
  terminal : ClientRequestTerminalIssue,
  visible_publication : String,
  context_ref : String,
  input_kind : String,
  input_revision : String,
  input_bytes : Int,
  declarations_revision : String?,
  declarations_bytes : Int,
  parameters_revision : String?,
  parameters_bytes : Int,
  correlation_ref : String,
  selector_namespace : @local_preparation.ClientCheckSourceSelectorNamespace?,
  source_namespace? : @local_preparation.ClientCheckSourceNamespace? = None,
  original_parameters? : String? = None,
) -> Result[String?, ClientRequestPreparationIssue] {
  if terminal is QuerySyntax(_) || terminal is QueryLowering(_) {
    return project_request_query_check_outcome(
      owner, input, terminal, visible_publication, context_ref, input_kind, input_revision,
      input_bytes, declarations_revision, declarations_bytes, parameters_revision,
      parameters_bytes, correlation_ref, source_namespace, original_parameters,
    )
  }
  let original = match terminal {
    CheckOutcome(value) => value
    _ => return Ok(None)
  }
  if owner.phase != ProgramCheck {
    return if owner.phase == Selecting { Err(WrongPhase) } else { Ok(None) }
  }
  guard owner.input is Some(held) && physical_equal(held, input) else {
    return Err(ForeignOriginal)
  }
  guard owner.program_check is Some(child) else { return Ok(None) }
  if child.phase == Transferred ||
    child.phase == Retired ||
    child.check_outcome is None ||
    child.arguments is None {
    return Ok(None)
  }
  if child.busy || child.work is Some(_) || child.policy_subject_work is Some(_) {
    return Err(WrongPhase)
  }
  guard child.phase == SemanticCheckRejected &&
    child.arguments is Some(arguments) &&
    arguments.source_preparation is Some(source) &&
    child.check_outcome is Some(outcome) &&
    physical_equal(outcome, original) &&
    owner.held_program is Some(program) &&
    physical_equal(program, arguments.program) else {
    return Err(ForeignOriginal)
  }
  if !["program", "text"].contains(input_kind) ||
    !request_check_observation_reference(context_ref, "ctx:") ||
    !request_check_observation_reference(input_revision, "rev:") ||
    input_bytes < 0 ||
    declarations_bytes < 0 ||
    parameters_bytes < 0 ||
    !request_check_observation_reference(correlation_ref, "corr:", digits=32) ||
    declarations_revision
    .map(value => !request_check_observation_reference(value, "rev:"))
    .unwrap_or(false) ||
    parameters_revision
    .map(value => !request_check_observation_reference(value, "rev:"))
    .unwrap_or(false) {
    return Err(Policy)
  }
  if (owner.query_syntax is Some(_) && input_kind != "text") ||
    (owner.native_query_declarations is Some(_)) !=
    (declarations_revision is Some(_)) ||
    (declarations_revision is None && declarations_bytes != 0) ||
    (arguments.supplied is Some(_)) != (parameters_revision is Some(_)) ||
    (parameters_revision is None && parameters_bytes != 0) ||
    (
      original_parameters is Some(body) &&
      (arguments.supplied is None || body.length() > parameters_bytes)
    ) {
    return Err(ForeignOriginal)
  }
  let registration = child.source_registration
  let registry = child.check_registry
  let inputs = match registration {
    Some(value) =>
      @context.source_registration_collected_inputs(
        @checked.parsed_source_registration_read(value),
      )
    None =>
      match registry {
        Some(original) =>
          @checked.parsed_check_collected_source_inputs(original)
        None => None
      }
  }
  // Cached admission usage bounds the authored label bytes without walking or
  // copying the Program again. Collection is borrowed, never repeated here.
  let input_label_bytes = match inputs {
    Some(value) =>
      @decode.admission_usage(@syntax.program_body(program)).total_string_bytes.to_int64() +
      16L * @sourceview_input.count(value).to_int64()
    None => 0L
  }
  guard request_check_observation_bytes(
      child, source, outcome, visible_publication, input_label_bytes, original_parameters,
    )
    is Some(bytes) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  child.busy = true
  preparation_module_call(
    () => {
      let (r, e) = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
        @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
        return Err(Policy)
      }
      match
        @resources.reserve_working_preparation_phase(
          owner.capacity,
          input,
          r,
          e,
        ) {
        Err(issue) => return Err(Capacity(issue))
        Ok(_) => ()
      }
      // The imported current callback cannot replace or retire these originals
      // while constructing output. Do not restore a changed/cleared alias.
      guard owner.phase == Selecting &&
        owner.input is Some(current_input) &&
        physical_equal(current_input, input) &&
        owner.program_check is Some(current) &&
        physical_equal(current, child) &&
        child.busy &&
        child.phase == SemanticCheckRejected &&
        child.arguments is Some(current_arguments) &&
        physical_equal(current_arguments, arguments) &&
        child.check_outcome is Some(current_outcome) &&
        physical_equal(current_outcome, original) else {
        return Err(ForeignOriginal)
      }
      guard (match (registration, child.source_registration) {
        (None, None) => true
        (Some(original), Some(current)) => physical_equal(original, current)
        _ => false
      }) else {
        return Err(ForeignOriginal)
      }
      guard (match (registry, child.check_registry) {
        (None, None) => true
        (Some(original), Some(current)) => physical_equal(original, current)
        _ => false
      }) else {
        return Err(ForeignOriginal)
      }
      let current_inputs = match child.source_registration {
        Some(value) =>
          @context.source_registration_collected_inputs(
            @checked.parsed_source_registration_read(value),
          )
        None =>
          match child.check_registry {
            Some(original) =>
              @checked.parsed_check_collected_source_inputs(original)
            None => None
          }
      }
      guard (match (inputs, current_inputs) {
        (None, None) => true
        (Some(original), Some(current)) => physical_equal(original, current)
        _ => false
      }) else {
        return Err(ForeignOriginal)
      }
      Ok(
        Some(
          @local_preparation.client_program_project_original_check_outcome(
            program,
            source,
            arguments.supplied,
            inputs,
            outcome,
            arguments.environment,
            visible_publication,
            context_ref,
            input_kind,
            input_revision,
            input_bytes,
            declarations_revision,
            declarations_bytes,
            parameters_revision,
            parameters_bytes,
            correlation_ref,
            selector_namespace,
            original_parameters~,
          ),
        ),
      )
    },
    () => {
      child.busy = false
      if owner.phase == Selecting {
        owner.phase = ProgramCheck
      }
    },
  )
}

///|
// The same writer and proportional findings tariff for both original phases.
fn request_check_observation_inventory_bytes(
  publication : String,
  findings : Int64,
  input_label_bytes : Int64,
) -> Int64? {
  let (parse, _) = @source_publication.source_publication_input_limits()
  let units = publication.length().to_int64()
  if units > parse.max_input_bytes.to_int64() {
    return None
  }
  let nodes = Int64::min(units + 1L, parse.max_nodes.to_int64())
  guard @encode.text_writer_construction_inventory(65536, 4096, 16)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + 65536L,
      owned_wire_bytes: 0L,
    })
    is Some(output) &&
    @execution.execution_capacity_inventory_bytes([
      // Source/index plus the borrowed alias/cursor inspection vectors.
      { unit: @execution.ValueNodeSlots, count: nodes, copies: 4, },
      { unit: @execution.DecodedTextBytes, count: units, copies: 2, },
      // Original collected Source labels coexist with one expected URI and
      // its sequential concatenation intermediates, not one copy per alias.
      {
        unit: @execution.DecodedTextBytes,
        count: input_label_bytes,
        copies: 4,
      },
      // Findings and the writer's sequential reason/requirement vectors.
      { unit: @execution.ValueNodeSlots, count: findings, copies: 4, },
      // Existing report labels are bounded to256 before pointer emission.
      { unit: @execution.DecodedTextBytes, count: 256L * findings, copies: 4, },
      // UTF-8 publication encoding coexists with its reader. Small borrowed
      // context/revision strings and call frames use trusted Host overhead.
      { unit: @execution.QuotedBytes, count: 4L * units, copies: 1, },
    ])
    is Some(data) else {
    return None
  }
  @execution.checked_preparation_add_product(output, data, 1L)
}
