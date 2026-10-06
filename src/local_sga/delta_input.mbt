///|
priv enum DeltaInputPhase {
  ReadDeltaCell
  RecheckDeltaCell
  EmitDeltaCell
  StartDeltaParse
  ParseDeltaCell
  DecodeDeltaCell
  DeltaInputFinished
}

///|
/// Temporary input preparation for the existing Delta execution. The
/// right operand stays an exactly bound Relation read; no caller-supplied JSON
/// can replace it. Data conversion uses only the existing Value/source/decode
/// owners and does not confer reference or execution authority.
struct DeltaApplyInputPreparation {
  owner : @lower.BoundPrepared
  step : Int
  mut base : @lifecycle.ProducerView?
  mut rows : @execution.ProducerRead?
  column : Int
  contract : @contract.Contract
  limits : @delta.Limits
  mut output : @graph.OutputBuilder?
  mut base_preparation : @delta.ApplyBasePreparation?
  mut available : () -> Bool
  mut phase : DeltaInputPhase
  mut recheck : @value.RecheckCursor?
  mut writer : @encode.Writer?
  mut emitter : @value.WireEmitCursor?
  mut parser : @source.JsonParse?
  mut decoder : @decode.Admission?
  mut decoded : @decode.Cursor?
  mut claimed : Bool
}

///|
priv enum DeltaInputPoll {
  DeltaInputContinue(work~ : Int)
  DeltaInputComplete(@decode.Cursor, work~ : Int)
  DeltaInputFailed(DeltaApplyIssue, work~ : Int)
}

///|
fn delta_input_workspace_slots(limits : @delta.Limits) -> Int? {
  // Source/decode indexes, bounded recheck/wire continuations and transient
  // conversion records. Borrowed Relation retention is still an input-owner
  // obligation. This logical admission is not a proof of total physical memory.
  let nodes = Int::min(limits.max_output_nodes, limits.value_limits.max_nodes)
  let depth = Int::min(limits.max_output_depth, limits.value_limits.max_depth)
  guard nodes >= 0 && depth >= 0 && nodes <= 67108859 && depth <= 268435455 else {
    return None
  }
  let node_slots = nodes * 32
  let depth_slots = depth * 8
  guard node_slots <= 2147483519 - depth_slots else { return None }
  Some(node_slots + depth_slots + 128)
}

///|
fn advance_delta_input(
  input : DeltaApplyInputPreparation,
  quantum : Int,
) -> DeltaInputPoll {
  let mut used = 0
  while used < quantum {
    match input.phase {
      ReadDeltaCell => {
        used += 1
        guard input.rows is Some(rows) &&
          @execution.producer_read_cell(rows, 0, input.column)
          is Some(@execution.Captured(value)) &&
          @value.start_recheck_runtime_value(value, input.contract, {
            max_nodes: Int::min(
              input.limits.max_output_nodes,
              input.limits.value_limits.max_nodes,
            ),
            max_depth: Int::min(
              input.limits.max_output_depth,
              input.limits.value_limits.max_depth,
            ),
            max_text_bytes: Int::min(
              input.limits.max_output_text_bytes,
              input.limits.value_limits.max_text_bytes,
            ),
          })
          is Some(recheck) else {
          return DeltaInputFailed(DeltaApplyInvalidInput, work=used)
        }
        input.recheck = Some(recheck)
        input.phase = RecheckDeltaCell
      }
      RecheckDeltaCell => {
        used += 1
        guard input.recheck is Some(recheck) else {
          return DeltaInputFailed(InvalidDeltaApplyKernel, work=used)
        }
        match @value.advance_recheck_runtime_value(recheck) {
          @value.RecheckContinue => ()
          @value.RecheckFailed =>
            return DeltaInputFailed(DeltaApplyInvalidInput, work=used)
          @value.RecheckComplete(checked, _, _) => {
            input.recheck = None
            let writer = @encode.writer(
              input.limits.max_output_text_bytes,
              input.limits.max_output_nodes,
              input.limits.max_output_depth,
            ) catch {
              _ => return DeltaInputFailed(DeltaApplyInvalidInput, work=used)
            }
            input.writer = Some(writer)
            guard @value.json_payload(checked.value) is Some(payload) else {
              return DeltaInputFailed(DeltaApplyInvalidInput, work=used)
            }
            input.emitter = Some(@value.start_wire_emit(payload, writer))
            input.phase = EmitDeltaCell
          }
        }
      }
      EmitDeltaCell => {
        used += 1
        guard input.emitter is Some(emitter) else {
          return DeltaInputFailed(InvalidDeltaApplyKernel, work=used)
        }
        try {
          if @value.advance_wire_emit(emitter) {
            input.emitter = None
            input.phase = StartDeltaParse
          }
        } catch {
          _ => return DeltaInputFailed(DeltaApplyInvalidInput, work=used)
        }
      }
      StartDeltaParse => {
        used += 1
        guard input.writer is Some(writer) else {
          return DeltaInputFailed(InvalidDeltaApplyKernel, work=used)
        }
        let text = @encode.finish(writer) catch {
          _ => return DeltaInputFailed(DeltaApplyInvalidInput, work=used)
        }
        input.writer = None
        input.parser = match
          @source.start_json_parse(
            text,
            {
              max_input_bytes: input.limits.max_output_text_bytes,
              max_nodes: Int::min(
                input.limits.max_output_nodes,
                input.limits.value_limits.max_nodes,
              ),
              max_depth: Int::min(
                input.limits.max_output_depth,
                input.limits.value_limits.max_depth,
              ),
            },
            data_keys=true,
          ) {
          Ok(parser) => Some(parser)
          Err(_) => return DeltaInputFailed(DeltaApplyInvalidInput, work=used)
        }
        input.phase = ParseDeltaCell
      }
      ParseDeltaCell => {
        guard input.parser is Some(parser) else {
          return DeltaInputFailed(InvalidDeltaApplyKernel, work=used)
        }
        match @source.advance_json_parse(parser, quantum - used) {
          Ok(@source.JsonParseContinue(work~)) => used += work
          Ok(@source.JsonParseComplete(parsed, work~)) => {
            used += work
            input.parser = None
            input.decoder = match
              @decode.start_admission(parsed.node, {
                max_nodes: Int::min(
                  input.limits.max_output_nodes,
                  input.limits.value_limits.max_nodes,
                ),
                max_depth: Int::min(
                  input.limits.max_output_depth,
                  input.limits.value_limits.max_depth,
                ),
                max_string_bytes: input.limits.max_output_text_bytes,
                max_total_string_bytes: input.limits.max_output_text_bytes,
              }) {
              Ok(decoder) => Some(decoder)
              Err(_) =>
                return DeltaInputFailed(DeltaApplyInvalidInput, work=used)
            }
            input.phase = DecodeDeltaCell
          }
          Ok(@source.JsonParseFailed(_, work~)) =>
            return DeltaInputFailed(DeltaApplyInvalidInput, work=used + work)
          Err(_) => return DeltaInputFailed(InvalidDeltaApplyKernel, work=used)
        }
      }
      DecodeDeltaCell => {
        guard input.decoder is Some(decoder) else {
          return DeltaInputFailed(InvalidDeltaApplyKernel, work=used)
        }
        match @decode.advance_admission(decoder, quantum - used) {
          Ok(@decode.AdmissionContinue(work~)) => used += work
          Ok(@decode.AdmissionComplete(cursor, work~)) => {
            used += work
            input.decoder = None
            input.phase = DeltaInputFinished
            return DeltaInputComplete(cursor, work=used)
          }
          Ok(@decode.AdmissionFailed(_, work~)) =>
            return DeltaInputFailed(DeltaApplyInvalidInput, work=used + work)
          Err(_) => return DeltaInputFailed(InvalidDeltaApplyKernel, work=used)
        }
      }
      DeltaInputFinished =>
        return DeltaInputFailed(InvalidDeltaApplyKernel, work=used)
    }
  }
  DeltaInputContinue(work=used)
}

///|
fn cleanup_delta_input(input : DeltaApplyInputPreparation) -> Unit {
  if input.recheck is Some(recheck) {
    @value.cancel_recheck_runtime_value(recheck)
  }
  if input.emitter is Some(emitter) {
    @value.cancel_wire_emit(emitter)
  }
  if input.parser is Some(parser) {
    @source.cancel_json_parse(parser)
  }
  if input.decoder is Some(decoder) {
    @decode.cancel_admission(decoder)
  }
  if input.base_preparation is Some(base) {
    @delta.cleanup_apply_base(base)
  }
  if input.output is Some(output) {
    @graph.cancel_output(output) |> ignore
  }
  input.base_preparation = None
  input.output = None
  input.recheck = None
  input.emitter = None
  input.writer = None
  input.parser = None
  input.decoder = None
  input.decoded = None
  input.base = None
  input.rows = None
  input.available = () => false
  input.phase = DeltaInputFinished
}

///|
pub enum DeltaApplyInputPoll {
  DeltaApplyInputContinue(work~ : Int)
  DeltaApplyInputReady(work~ : Int)
  DeltaApplyInputFailed(DeltaApplyIssue, work~ : Int)
}

///|
fn delta_input_available(input : DeltaApplyInputPreparation) -> Bool {
  guard input.base is Some(base) && input.rows is Some(rows) else {
    return false
  }
  delta_input_reads_available(
    input.owner,
    input.step,
    base,
    rows,
    input.available,
  )
}

///|
fn delta_input_reads_available(
  owner : @lower.BoundPrepared,
  step : Int,
  base : @lifecycle.ProducerView,
  rows : @execution.ProducerRead,
  available : () -> Bool,
) -> Bool {
  available() &&
  @lifecycle.producer_read_reference_matches_operation_input(
    @lifecycle.producer_view_read_reference(base),
    owner,
    step,
    0,
  ) &&
  @execution.producer_read_matches_operation_input(rows, owner, step, 1)
}

///|
/// Preparation for the exact two checked operands, not a Plan selector or a
/// resource receipt. Callers must charge each reported preparation work unit in
/// their existing control budget and retain this custody until cleanup. The
/// ready state exposes no cursor that could be substituted by an unbound value.
pub fn prepare_delta_apply_input(
  sequence : @lower.PreparedSequence,
  step : Int,
  base : @lifecycle.ProducerView,
  rows : @execution.ProducerRead,
  limits : @delta.Limits,
  storage_limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[DeltaApplyInputPreparation, DeltaApplyIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphDeltaStep(delta)) &&
    @graph_type.delta_operation(@lower.graph_delta_checked(delta))
    is @graph_type.Application(name) &&
    @lower.graph_delta_output_carrier(delta) is @carrier.GraphValue(graph) &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(base),
      owner,
      step,
      0,
    ) &&
    @execution.producer_read_matches_operation_input(rows, owner, step, 1) &&
    @execution.producer_read_has_cell_access(rows) &&
    @execution.producer_read_row_count(rows) == 1 else {
    return Err(DeltaApplyInvalidInput)
  }
  if storage_bytes < 0L ||
    limits.max_output_text_bytes < 0 ||
    limits.value_limits.max_text_bytes < 0 ||
    !available() {
    return Err(DeltaApplyInvalidInput)
  }
  guard delta_input_workspace_slots(limits) is Some(required) &&
    required <= limits.max_workspace_slots else {
    return Err(DeltaApplyWorkspaceLimit)
  }
  let schema = @execution.producer_read_schema(rows)
  let mut found = None
  for column in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, column).unwrap()
    if field.name == name {
      found = Some((column, field))
      break
    }
  }
  guard found is Some((column, field)) &&
    field.presence == @schema.Required &&
    !@contract.contract_nullable(field.contract) &&
    (@contract.type_equal(
      field.contract,
      @contract.primitive(JsonType, nullable=false),
      storage_limits.max_contract_work,
    ) catch {
      _ => false
    }) else {
    return Err(DeltaApplyInvalidInput)
  }
  // Configuration/snapshot setup is cold preparation, not a resumed poll with
  // a fictitious work report. Reserve simultaneous Relation conversion state
  // in the same installed workspace before starting the snapshot preparation.
  let output = match
    @graph.prepare_output(
      owner,
      @pipeline.Step(step),
      @storage.DeclaredNodes,
      storage_limits,
      storage_bytes,
      available,
    ) {
    Ok(output) => output
    Err(issue) => return Err(DeltaApplyOutput(issue))
  }
  let base_preparation = match
    @delta.prepare_apply_base_view(
      base,
      graph,
      limits,
      storage_limits,
      output_builder=@graph.output_storage_builder(output),
      reserved_workspace_slots=required,
    ) {
    Ok(value) => value
    Err(issue) => {
      @graph.cancel_output(output) |> ignore
      return Err(DeltaApplyKernel(issue))
    }
  }
  Ok({
    owner,
    step,
    base: Some(base),
    rows: Some(rows),
    column,
    contract: field.contract,
    limits,
    output: Some(output),
    base_preparation: Some(base_preparation),
    available,
    phase: ReadDeltaCell,
    recheck: None,
    writer: None,
    emitter: None,
    parser: None,
    decoder: None,
    decoded: None,
    claimed: false,
  })
}

///|
pub fn advance_delta_apply_input(
  input : DeltaApplyInputPreparation,
  quantum : Int,
) -> Result[DeltaApplyInputPoll, DeltaApplyIssue] {
  if quantum < 1 || input.phase is DeltaInputFinished {
    return Err(InvalidDeltaApplyKernel)
  }
  if !delta_input_available(input) {
    input.phase = DeltaInputFinished
    return Ok(DeltaApplyInputFailed(DeltaApplyInputUnavailable, work=0))
  }
  match advance_delta_input(input, quantum) {
    DeltaInputContinue(work~) => Ok(DeltaApplyInputContinue(work~))
    DeltaInputFailed(issue, work~) => {
      input.phase = DeltaInputFinished
      Ok(DeltaApplyInputFailed(issue, work~))
    }
    DeltaInputComplete(cursor, work~) => {
      input.decoded = Some(cursor)
      Ok(DeltaApplyInputReady(work~))
    }
  }
}

///|
/// Attach the ready Relation data to the already prepared Graph configuration.
/// No Graph definition/snapshot preparation is repeated here. Normal provider
/// selection/resource resolution remains a separate boundary. Successful start
/// transfers the one output; failure never reclaims either borrowed input.
fn claim_delta_apply_input(
  input : DeltaApplyInputPreparation,
) -> Result[
  (@delta.ApplyPreparation, @graph.OutputBuilder, () -> Bool),
  DeltaApplyIssue,
] {
  guard input.phase is DeltaInputFinished &&
    !input.claimed &&
    input.decoded is Some(cursor) &&
    input.base is Some(base) &&
    input.rows is Some(rows) &&
    input.output is Some(output) &&
    input.base_preparation is Some(base_preparation) &&
    delta_input_available(input) else {
    return Err(DeltaApplyInvalidInput)
  }
  let preparation = match
    @delta.start_apply_from_prepared_base(base_preparation, cursor) {
    Ok(preparation) => preparation
    Err(issue) => return Err(DeltaApplyKernel(issue))
  }
  let owner = input.owner
  let step = input.step
  let available = input.available
  let current = fn() {
    delta_input_reads_available(owner, step, base, rows, available)
  }
  input.claimed = true
  input.output = None
  cleanup_delta_input(input)
  Ok((preparation, output, current))
}

///|
/// Start after separately budgeted input admission. Callers using one control
/// budget for conversion and application should use start_delta_apply_inputs.
pub fn start_delta_apply_from_admitted_input(
  control : @bounded.Control,
  input : DeltaApplyInputPreparation,
  control_work_limit? : Int? = None,
) -> Result[DeltaApplyExecution, DeltaApplyIssue] {
  if control_work_limit is Some(limit) && limit < 0 {
    return Err(DeltaApplyControlWorkLimit)
  }
  let (preparation, output, current) = match claim_delta_apply_input(input) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    start_prepared_delta_apply(
      control,
      preparation,
      output,
      current,
      control_work_limit~,
    ) {
    Ok(execution) => Ok(execution)
    Err(issue) => {
      @delta.cleanup_apply(preparation) |> ignore
      @graph.cancel_output(output) |> ignore
      cleanup_delta_input(input)
      Err(issue)
    }
  }
}

///|
pub fn cleanup_delta_apply_input(input : DeltaApplyInputPreparation) -> Unit {
  cleanup_delta_input(input)
}
