///|
priv struct PoolRecord {
  source_index : Int
  groups : Array[@value.CheckedValue]
  identities : Array[@value.CheckedValue]
  vector : @value.CheckedValue
}

///|
priv enum PoolSortMode {
  IdentityOrder
  GroupOrder
}

///|
priv enum PoolPhase {
  EncodeRelationIdentity
  BeginRecord
  InitializeGroups
  InitializeIdentities
  ReadField
  MatchGroup
  MatchIdentity
  ValidateGroups
  ValidateIdentities
  ValidateComponents
  CollectRecord
  InitializeScratch
  PreparePass
  PrepareMerge
  CompareGroup
  CompareIdentity
  CopyPass
  CheckDuplicate
  FindGroupEnd
  BeginComponent
  FoldComponent
  FinishComponent
  BuildOutput
  CommitOutput
  Finish
}

///|
priv struct PoolState {
  input : @records.ProducerRead?
  relation_input : @execution.ProducerRead?
  source : @storage.Storage?
  vectors : @carrier.Vectors
  output_vectors : @carrier.Vectors
  prepared : @lower.PreparedVector
  value_limits : @value.Limits
  mut output : @records.OutputBuilder?
  reduction : @numeric.PoolMethod
  dimensions : Int
  group_count : Int
  identity_count : Int
  source_identity_count : Int
  encode_member_identity : Bool
  member_identity_contract : @contract.Contract?
  component_name : String
  output_component_contract : @contract.Contract
  member_count_contract : @contract.Contract
  output_id : String?
  mut phase : PoolPhase
  mut record : Int
  mut field : Int
  mut group_probe : Int
  mut identity_probe : Int
  mut identity_builder : StringBuilder?
  mut identity_bytes : Int
  mut current_field : (@schema.FieldName, @value.CheckedValue)?
  mut source_vector : @value.CheckedValue?
  mut group_values : Array[@value.CheckedValue?]
  mut identity_values : Array[@value.CheckedValue?]
  mut collected_groups : Array[@value.CheckedValue]
  mut collected_identities : Array[@value.CheckedValue]
  mut component : Int
  mut records : Array[PoolRecord]
  mut scratch : Array[PoolRecord?]
  mut sort_mode : PoolSortMode
  mut width : Int
  mut run_start : Int
  mut left_index : Int
  mut middle : Int
  mut right_index : Int
  mut run_end : Int
  mut merge_index : Int
  mut compare_index : Int
  mut copy_index : Int
  mut duplicate_index : Int
  mut group_start : Int
  mut group_end : Int
  mut member_index : Int
  mut fold : @numeric.PoolFold?
  mut output_vector : @value.VectorBuilder?
  mut pooled_vector : @value.CheckedValue?
  mut output_field : Int
  mut output_fields : Array[(@schema.FieldName, @value.CheckedValue)]
  mut control_work_remaining : Int
}

///|
struct PoolExecution {
  session : @bounded.Session[PoolState, @records.Completed, PoolIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum PoolPoll {
  PoolContinue(progress~ : Int64, work~ : Int64)
  PoolComplete(@records.Completed, progress~ : Int64, work~ : Int64)
  PoolFailed(PoolIssue, progress~ : Int64, work~ : Int64)
  PoolStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum PoolIssue {
  InvalidPoolKernel
  InvalidPoolLimits
  PoolInputUnavailable
  InvalidPoolRecord(Int)
  InvalidPoolVector(Int)
  InvalidPoolGroup(Int)
  InvalidPoolIdentity(Int)
  DuplicatePoolIdentity(Int, Int)
  PoolWorkspaceLimit
  PoolWorkLimit
  PoolNumeric(@numeric.Issue)
  PoolKeyOrder(@value.KeyOrderIssue)
  PoolOutput(@records.Issue)
  PoolExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn pool_checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn pool_checked_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn pool_workspace(
  records : Int,
  dimensions : Int,
  groups : Int,
  identities : Int,
  output_fields : Int,
) -> Int? {
  guard pool_checked_add(groups, identities) is Some(keys) &&
    pool_checked_add(keys, 2) is Some(record_width) &&
    pool_checked_multiply(records, record_width) is Some(ordered) &&
    pool_checked_multiply(ordered, 2) is Some(sort_slots) &&
    pool_checked_add(output_fields, dimensions) is Some(output_slots) &&
    pool_checked_add(sort_slots, output_slots) is Some(first) &&
    pool_checked_add(first, keys) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn pool_input_available(state : PoolState) -> Bool {
  match (state.input, state.relation_input) {
    (Some(input), None) => @records.producer_read_available(input)
    (None, Some(input)) => @execution.producer_read_available(input)
    _ => false
  }
}

///|
fn pool_record_count(state : PoolState) -> Int? {
  match (state.source, state.relation_input) {
    (Some(source), None) => Some(@storage.record_count(source))
    (None, Some(input)) => Some(@execution.producer_read_row_count(input))
    _ => None
  }
}

///|
fn pool_record_field_count(state : PoolState, record : Int) -> Int? {
  match (state.source, state.relation_input) {
    (Some(source), None) => @storage.record_field_count(source, record)
    (None, Some(input)) =>
      if record >= 0 && record < @execution.producer_read_row_count(input) {
        Some(@schema.field_count(@execution.producer_read_schema(input)))
      } else {
        None
      }
    _ => None
  }
}

///|
fn pool_record_field_at(
  state : PoolState,
  record : Int,
  field : Int,
) -> (@schema.FieldName, @value.CheckedValue)? {
  match (state.source, state.relation_input) {
    (Some(source), None) => @storage.record_field_at(source, record, field)
    (None, Some(input)) => {
      guard @schema.field_at(@execution.producer_read_schema(input), field)
        is Some(expected) &&
        @execution.producer_read_checked_cell(
          input,
          record,
          field,
          state.value_limits,
        )
        is Some(checked) else {
        return None
      }
      Some((expected.name, checked))
    }
    _ => None
  }
}

///|
fn begin_pool_record(state : PoolState) -> Result[Unit, PoolIssue] {
  guard pool_record_field_count(state, state.record) is Some(_) else {
    return Err(InvalidPoolRecord(state.record))
  }
  state.field = 0
  state.group_probe = 0
  state.identity_probe = 0
  state.identity_builder = None
  state.identity_bytes = 0
  state.current_field = None
  state.source_vector = None
  state.group_values = []
  state.identity_values = []
  state.collected_groups = []
  state.collected_identities = []
  state.identity_builder = None
  state.component = 0
  state.phase = InitializeGroups
  Ok(())
}

///|
fn load_pool_field(state : PoolState) -> Result[Unit, PoolIssue] {
  guard pool_record_field_at(state, state.record, state.field)
    is Some((name, checked)) else {
    return Err(InvalidPoolRecord(state.record))
  }
  if @schema.reference_name(name) == state.component_name {
    if state.source_vector is Some(_) {
      return Err(InvalidPoolVector(state.record))
    }
    state.source_vector = Some(checked)
  }
  state.current_field = Some((name, checked))
  state.group_probe = 0
  state.phase = MatchGroup
  Ok(())
}

///|
fn match_pool_group(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.current_field is Some((name, checked)) &&
    @lower.vector_pool_group_at(state.prepared, state.group_probe)
    is Some(group) else {
    return Err(InvalidPoolRecord(state.record))
  }
  if @schema.reference_name(name) == group {
    if state.group_values[state.group_probe] is Some(_) {
      return Err(InvalidPoolGroup(state.record))
    }
    state.group_values[state.group_probe] = Some(checked)
  }
  state.group_probe += 1
  if state.group_probe >= state.group_count {
    state.identity_probe = 0
    state.phase = MatchIdentity
  }
  Ok(())
}

///|
fn match_pool_identity(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.current_field is Some((name, checked)) else {
    return Err(InvalidPoolRecord(state.record))
  }
  let expected = if state.relation_input is Some(_) {
    @lower.vector_pool_identity_at(state.prepared, state.identity_probe)
  } else {
    @carrier.vector_identity_at(state.vectors, state.identity_probe).map(identity => {
      @schema.reference_name(identity.name)
    })
  }
  guard expected is Some(expected) else {
    return Err(InvalidPoolRecord(state.record))
  }
  if @schema.reference_name(name) == expected {
    if state.identity_values[state.identity_probe] is Some(_) {
      return Err(InvalidPoolIdentity(state.record))
    }
    state.identity_values[state.identity_probe] = Some(checked)
  }
  state.identity_probe += 1
  if state.identity_probe >= state.source_identity_count {
    state.current_field = None
    state.field += 1
    state.phase = ReadField
  }
  Ok(())
}

///|
fn finish_pool_fields(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.source_vector is Some(checked) &&
    checked.value is @value.Vector(values) &&
    @value.element_count(values) == state.dimensions else {
    return Err(InvalidPoolVector(state.record))
  }
  state.group_probe = 0
  state.phase = ValidateGroups
  Ok(())
}

///|
fn validate_pool_group(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.group_values[state.group_probe] is Some(value) else {
    return Err(InvalidPoolGroup(state.record))
  }
  match @value.compare_key_values(value, value) {
    Ok(_) => ()
    Err(issue) => return Err(PoolKeyOrder(issue))
  }
  state.collected_groups.push(value)
  state.group_probe += 1
  if state.group_probe >= state.group_count {
    state.identity_probe = 0
    state.phase = ValidateIdentities
  }
  Ok(())
}

///|
fn validate_pool_identity(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.identity_values[state.identity_probe] is Some(value) else {
    return Err(InvalidPoolIdentity(state.record))
  }
  match @value.compare_key_values(value, value) {
    Ok(_) => ()
    Err(issue) => return Err(PoolKeyOrder(issue))
  }
  if !state.encode_member_identity {
    state.collected_identities.push(value)
  }
  state.identity_probe += 1
  if state.identity_probe >= state.source_identity_count {
    if state.encode_member_identity {
      state.identity_probe = 0
      state.identity_builder = Some(StringBuilder())
      state.identity_bytes = 0
      state.phase = EncodeRelationIdentity
    } else {
      state.component = 0
      state.phase = ValidateComponents
    }
  }
  Ok(())
}

///|
fn encode_pool_identity_component(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.identity_builder is Some(output) else {
    return Err(InvalidPoolKernel)
  }
  if state.identity_probe >= state.source_identity_count {
    guard state.member_identity_contract is Some(contract) &&
      @value.checked_text_value(output.to_string(), contract) is Some(value) else {
      return Err(InvalidPoolIdentity(state.record))
    }
    state.identity_builder = None
    state.collected_identities.push(value)
    state.component = 0
    state.phase = ValidateComponents
    return Ok(())
  }
  let value = state.identity_values[state.identity_probe].unwrap()
  guard @value.canonical_scalar_text(value, state.value_limits.max_text_bytes)
    is Some(text) &&
    @scalar.unicode_scalar_count(text) is Some(codepoints) &&
    @scalar.admit_utf8_length(text, state.value_limits.max_text_bytes)
    is Ok(text_bytes) else {
    return Err(InvalidPoolIdentity(state.record))
  }
  let prefix = codepoints.to_string() + ":"
  let suffix = "|"
  guard @scalar.admit_utf8_length(prefix, state.value_limits.max_text_bytes)
    is Ok(prefix_bytes) &&
    prefix_bytes <= state.value_limits.max_text_bytes - state.identity_bytes &&
    text_bytes <=
    state.value_limits.max_text_bytes - state.identity_bytes - prefix_bytes &&
    suffix.length() <=
    state.value_limits.max_text_bytes -
    state.identity_bytes -
    prefix_bytes -
    text_bytes else {
    return Err(InvalidPoolIdentity(state.record))
  }
  output.write_string(prefix)
  output.write_string(text)
  output.write_string(suffix)
  state.identity_bytes += prefix_bytes + text_bytes + suffix.length()
  state.identity_probe += 1
  Ok(())
}

///|
fn validate_pool_component(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.source_vector is Some(checked) &&
    checked.value is @value.Vector(values) &&
    @value.element_at(values, state.component) is Some(component) else {
    return Err(InvalidPoolVector(state.record))
  }
  match @numeric.quantize(component) {
    Ok(_) => {
      state.component += 1
      Ok(())
    }
    Err(issue) => Err(PoolNumeric(issue))
  }
}

///|
fn collect_pool_record(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.source_vector is Some(vector) else {
    return Err(InvalidPoolVector(state.record))
  }
  state.records.push({
    source_index: state.record,
    groups: state.collected_groups,
    identities: state.collected_identities,
    vector,
  })
  state.group_values = []
  state.identity_values = []
  state.collected_groups = []
  state.collected_identities = []
  state.source_vector = None
  state.record += 1
  state.phase = BeginRecord
  Ok(())
}

///|
fn pool_capped_run_end(start : Int, width : Int, count : Int) -> Int {
  if width >= count - start {
    count
  } else {
    start + width
  }
}

///|
fn prepare_pool_merge(state : PoolState) -> Unit {
  state.middle = pool_capped_run_end(
    state.run_start,
    state.width,
    state.records.length(),
  )
  state.run_end = pool_capped_run_end(
    state.middle,
    state.width,
    state.records.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.compare_index = 0
  state.phase = match state.sort_mode {
    GroupOrder => CompareGroup
    IdentityOrder => CompareIdentity
  }
}

///|
fn emit_pool_merge(state : PoolState, take_left : Bool) -> Unit {
  let selected = if take_left {
    let value = state.records[state.left_index]
    state.left_index += 1
    value
  } else {
    let value = state.records[state.right_index]
    state.right_index += 1
    value
  }
  state.scratch[state.merge_index] = Some(selected)
  state.merge_index += 1
  state.compare_index = 0
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareMerge
  } else {
    state.phase = match state.sort_mode {
      GroupOrder => CompareGroup
      IdentityOrder => CompareIdentity
    }
  }
}

///|
fn compare_pool_values(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
) -> Result[Int, PoolIssue] {
  @value.compare_key_values(left, right).map_err(issue => PoolKeyOrder(issue))
}

///|
fn compare_pool_group(state : PoolState) -> Result[Unit, PoolIssue] {
  if state.left_index >= state.middle {
    emit_pool_merge(state, false)
    return Ok(())
  }
  if state.right_index >= state.run_end {
    emit_pool_merge(state, true)
    return Ok(())
  }
  if state.compare_index >= state.group_count {
    state.compare_index = 0
    state.phase = CompareIdentity
    return Ok(())
  }
  let comparison = match
    compare_pool_values(
      state.records[state.left_index].groups[state.compare_index],
      state.records[state.right_index].groups[state.compare_index],
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if comparison < 0 {
    emit_pool_merge(state, true)
  } else if comparison > 0 {
    emit_pool_merge(state, false)
  } else {
    state.compare_index += 1
  }
  Ok(())
}

///|
fn compare_pool_identity(state : PoolState) -> Result[Unit, PoolIssue] {
  if state.left_index >= state.middle {
    emit_pool_merge(state, false)
    return Ok(())
  }
  if state.right_index >= state.run_end {
    emit_pool_merge(state, true)
    return Ok(())
  }
  if state.compare_index >= state.identity_count {
    emit_pool_merge(state, true)
    return Ok(())
  }
  let comparison = match
    compare_pool_values(
      state.records[state.left_index].identities[state.compare_index],
      state.records[state.right_index].identities[state.compare_index],
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if comparison < 0 {
    emit_pool_merge(state, true)
  } else if comparison > 0 {
    emit_pool_merge(state, false)
  } else {
    state.compare_index += 1
  }
  Ok(())
}

///|
fn finish_pool_sort_pass(state : PoolState) -> Unit {
  state.copy_index = 0
  state.phase = CopyPass
}

///|
fn copy_pool_sort_item(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.scratch[state.copy_index] is Some(value) else {
    return Err(InvalidPoolKernel)
  }
  state.records[state.copy_index] = value
  state.scratch[state.copy_index] = None
  state.copy_index += 1
  if state.copy_index >= state.records.length() {
    if state.width >= state.records.length() - state.width {
      match state.sort_mode {
        IdentityOrder => {
          state.duplicate_index = 1
          state.compare_index = 0
          state.phase = CheckDuplicate
        }
        GroupOrder => {
          state.group_start = 0
          state.group_end = 1
          state.compare_index = 0
          state.phase = FindGroupEnd
        }
      }
    } else {
      state.width *= 2
      state.run_start = 0
      state.phase = PrepareMerge
    }
  }
  Ok(())
}

///|
fn check_pool_duplicate(state : PoolState) -> Result[Unit, PoolIssue] {
  if state.duplicate_index >= state.records.length() {
    state.sort_mode = GroupOrder
    state.width = 1
    state.run_start = 0
    state.phase = PreparePass
    return Ok(())
  }
  if state.compare_index >= state.identity_count {
    return Err(
      DuplicatePoolIdentity(
        state.records[state.duplicate_index - 1].source_index,
        state.records[state.duplicate_index].source_index,
      ),
    )
  }
  let comparison = match
    compare_pool_values(
      state.records[state.duplicate_index - 1].identities[state.compare_index],
      state.records[state.duplicate_index].identities[state.compare_index],
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if comparison == 0 {
    state.compare_index += 1
  } else {
    state.duplicate_index += 1
    state.compare_index = 0
  }
  Ok(())
}

///|
fn find_pool_group_end(state : PoolState) -> Result[Unit, PoolIssue] {
  if state.group_start >= state.records.length() {
    state.phase = Finish
    return Ok(())
  }
  if state.group_end >= state.records.length() {
    state.component = 0
    state.phase = BeginComponent
    return Ok(())
  }
  if state.compare_index >= state.group_count {
    state.group_end += 1
    state.compare_index = 0
    return Ok(())
  }
  let comparison = match
    compare_pool_values(
      state.records[state.group_start].groups[state.compare_index],
      state.records[state.group_end].groups[state.compare_index],
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if comparison == 0 {
    state.compare_index += 1
  } else {
    state.component = 0
    state.phase = BeginComponent
  }
  Ok(())
}

///|
fn pool_vector_component(record : PoolRecord, index : Int) -> Double? {
  guard record.vector.value is @value.Vector(values) else { return None }
  @value.element_at(values, index)
}

///|
fn begin_pool_component(state : PoolState) -> Result[Unit, PoolIssue] {
  if state.output_vector is None {
    guard @value.prepare_vector_value(state.dimensions) is Some(builder) else {
      return Err(
        InvalidPoolVector(state.records[state.group_start].source_index),
      )
    }
    state.output_vector = Some(builder)
  }
  state.fold = Some(@numeric.prepare_pool(state.reduction))
  state.member_index = state.group_start
  state.phase = FoldComponent
  Ok(())
}

///|
fn fold_pool_component(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.fold is Some(fold) &&
    pool_vector_component(state.records[state.member_index], state.component)
    is Some(component) else {
    return Err(
      InvalidPoolVector(state.records[state.member_index].source_index),
    )
  }
  match @numeric.pool_step(fold, component) {
    Ok(_) => {
      state.member_index += 1
      Ok(())
    }
    Err(issue) => Err(PoolNumeric(issue))
  }
}

///|
fn finish_pool_component(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.fold is Some(fold) && state.output_vector is Some(builder) else {
    return Err(InvalidPoolKernel)
  }
  let component = match @numeric.finish_pool(fold) {
    Ok(value) => value
    Err(issue) => return Err(PoolNumeric(issue))
  }
  guard @value.append_vector_component(builder, component) else {
    return Err(InvalidPoolVector(state.records[state.group_start].source_index))
  }
  state.fold = None
  state.component += 1
  state.phase = BeginComponent
  Ok(())
}

///|
fn group_value_by_name(
  state : PoolState,
  name : String,
) -> @value.CheckedValue? {
  for index in 0..<state.group_count {
    if @lower.vector_pool_group_at(state.prepared, index) == Some(name) {
      return Some(state.records[state.group_start].groups[index])
    }
  }
  if state.group_count == 1 && state.output_id == Some(name) {
    return Some(state.records[state.group_start].groups[0])
  }
  None
}

///|
fn build_pool_output_field(state : PoolState) -> Result[Unit, PoolIssue] {
  guard @carrier.field_at(
      @carrier.vector_records(state.output_vectors),
      state.output_field,
    )
    is Some(field) else {
    return Err(InvalidPoolKernel)
  }
  let name = @schema.reference_name(field.name)
  let value = if name == state.component_name {
    guard state.pooled_vector is Some(vector) else {
      return Err(InvalidPoolKernel)
    }
    vector
  } else if name == "member_count" {
    guard @value.checked_number_value(
        (state.group_end - state.group_start).to_double(),
        state.member_count_contract,
      )
      is Some(count) else {
      return Err(InvalidPoolKernel)
    }
    count
  } else {
    guard group_value_by_name(state, name) is Some(group) else {
      return Err(InvalidPoolKernel)
    }
    group
  }
  state.output_fields.push((field.name, value))
  state.output_field += 1
  Ok(())
}

///|
fn commit_pool_output(state : PoolState) -> Result[Unit, PoolIssue] {
  guard state.output is Some(output) else { return Err(InvalidPoolKernel) }
  match @records.append_record(output, state.output_fields) {
    Ok(_) => {
      state.output_fields = []
      state.pooled_vector = None
      state.group_start = state.group_end
      state.group_end = state.group_start + 1
      state.compare_index = 0
      state.phase = FindGroupEnd
      Ok(())
    }
    Err(issue) => Err(PoolOutput(issue))
  }
}

///|
fn pool_step(
  state : PoolState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, PoolIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !pool_input_available(state) {
      return @bounded.Failed(PoolInputUnavailable, progress, used)
    }
    if !(state.phase is Finish) && used >= state.control_work_remaining {
      return @bounded.Failed(PoolWorkLimit, progress, used)
    }
    match state.phase {
      BeginRecord =>
        if state.record < pool_record_count(state).unwrap_or(-1) {
          match begin_pool_record(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = InitializeScratch
        }
      InitializeGroups =>
        if state.group_values.length() < state.group_count {
          state.group_values.push(None)
          used += 1
        } else {
          state.phase = InitializeIdentities
        }
      InitializeIdentities =>
        if state.identity_values.length() < state.source_identity_count {
          state.identity_values.push(None)
          used += 1
        } else {
          state.phase = ReadField
        }
      ReadField => {
        let count = pool_record_field_count(state, state.record).unwrap_or(-1)
        if state.field < count {
          match load_pool_field(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          match finish_pool_fields(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        }
      }
      MatchGroup => {
        used += 1
        match match_pool_group(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      MatchIdentity => {
        used += 1
        match match_pool_identity(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ValidateGroups => {
        used += 1
        match validate_pool_group(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ValidateIdentities => {
        used += 1
        match validate_pool_identity(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      EncodeRelationIdentity => {
        used += 1
        match encode_pool_identity_component(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ValidateComponents =>
        if state.component < state.dimensions {
          used += 1
          match validate_pool_component(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = CollectRecord
        }
      CollectRecord => {
        used += 1
        match collect_pool_record(state) {
          Ok(_) => progress += 1
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      InitializeScratch =>
        if state.scratch.length() < state.records.length() {
          state.scratch.push(None)
          used += 1
        } else if state.records.length() <= 1 {
          state.sort_mode = GroupOrder
          state.group_start = 0
          state.group_end = 1
          state.compare_index = 0
          state.phase = FindGroupEnd
        } else {
          state.sort_mode = IdentityOrder
          state.width = 1
          state.run_start = 0
          state.phase = PreparePass
        }
      PreparePass => {
        state.run_start = 0
        state.phase = PrepareMerge
      }
      PrepareMerge =>
        if state.run_start >= state.records.length() {
          finish_pool_sort_pass(state)
        } else {
          prepare_pool_merge(state)
        }
      CompareGroup => {
        used += 1
        match compare_pool_group(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CompareIdentity => {
        used += 1
        match compare_pool_identity(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyPass => {
        used += 1
        match copy_pool_sort_item(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CheckDuplicate => {
        used += 1
        match check_pool_duplicate(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      FindGroupEnd => {
        used += 1
        match find_pool_group_end(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      BeginComponent =>
        if state.component < state.dimensions {
          used += 1
          match begin_pool_component(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          guard state.output_vector is Some(builder) &&
            @value.finish_checked_vector_value(
              builder,
              state.output_component_contract,
            )
            is Some(vector) else {
            return @bounded.Failed(InvalidPoolKernel, progress, used)
          }
          state.output_vector = None
          state.pooled_vector = Some(vector)
          state.output_field = 0
          state.output_fields = []
          state.phase = BuildOutput
        }
      FoldComponent =>
        if state.member_index < state.group_end {
          used += 1
          match fold_pool_component(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishComponent
        }
      FinishComponent => {
        used += 1
        match finish_pool_component(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      BuildOutput =>
        if state.output_field <
          @carrier.field_count(@carrier.vector_records(state.output_vectors)) {
          used += 1
          match build_pool_output_field(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = CommitOutput
        }
      CommitOutput => {
        used += 1
        match commit_pool_output(state) {
          Ok(_) => progress += 1
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      Finish => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidPoolKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(PoolOutput(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_pool_state(state : PoolState) -> Bool {
  if state.output_vector is Some(builder) {
    @value.cancel_vector_value(builder) |> ignore
    state.output_vector = None
  }
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.group_values = []
  state.identity_values = []
  state.collected_groups = []
  state.collected_identities = []
  state.identity_builder = None
  state.records = []
  state.scratch = []
  state.output_fields = []
  state.source_vector = None
  state.pooled_vector = None
  state.fold = None
  true
}

///|
fn start_pool_with_control_work_limit(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit : Int,
) -> Result[PoolExecution, PoolIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.VectorStep(prepared)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "VEC.pool" &&
    @records.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidPoolKernel)
  }
  guard @records.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.VectorValue(vectors) &&
    @lower.vector_output_carrier(prepared)
    is @carrier.VectorValue(output_vectors) &&
    @lower.vector_pool_group_count(prepared) is Some(group_count) &&
    @lower.vector_pool_method(prepared) is Some(pool_method) else {
    return Err(PoolInputUnavailable)
  }
  let raw_dimensions = @carrier.vector_dimensions(vectors)
  guard raw_dimensions >= 1.0 && raw_dimensions <= 2147483647.0 else {
    return Err(InvalidPoolLimits)
  }
  let dimensions = raw_dimensions.to_int()
  let identity_count = @carrier.vector_identity_count(vectors)
  let output_rows = @carrier.vector_records(output_vectors)
  let output_fields = @carrier.field_count(output_rows)
  let component = @carrier.vector_components(output_vectors)
  guard dimensions.to_double() == raw_dimensions &&
    group_count > 0 &&
    identity_count > 0 &&
    component.contract is Some(component_contract) &&
    @carrier.lookup(output_rows, @schema.Unqualified("member_count"))
    is @carrier.Present({ contract: Some(member_count_contract), .. }) &&
    pool_workspace(
      @storage.record_count(source),
      dimensions,
      group_count,
      identity_count,
      output_fields,
    )
    is Some(workspace) &&
    workspace <= limits.max_workspace_slots else {
    return Err(PoolWorkspaceLimit)
  }
  if control_work_limit < 0 {
    return Err(InvalidPoolLimits)
  }
  if control_work_limit == 0 {
    return Err(PoolWorkLimit)
  }
  let reduction = match pool_method {
    @lower.PoolMean => @numeric.Mean
    @lower.PoolSum => @numeric.Sum
    @lower.PoolMax => @numeric.Max
  }
  let output = match
    @records.prepare_output(
      owner,
      @pipeline.Step(step),
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PoolOutput(issue))
  }
  let state : PoolState = {
    input: Some(input),
    relation_input: None,
    source: Some(source),
    vectors,
    output_vectors,
    prepared,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    output: Some(output),
    reduction,
    dimensions,
    group_count,
    identity_count,
    source_identity_count: identity_count,
    encode_member_identity: false,
    member_identity_contract: None,
    component_name: @schema.reference_name(
      @carrier.vector_components(vectors).name,
    ),
    output_component_contract: component_contract,
    member_count_contract,
    output_id: @lower.vector_pool_output_id(prepared),
    phase: BeginRecord,
    record: 0,
    field: 0,
    group_probe: 0,
    identity_probe: 0,
    identity_builder: None,
    identity_bytes: 0,
    current_field: None,
    source_vector: None,
    group_values: [],
    identity_values: [],
    collected_groups: [],
    collected_identities: [],
    component: 0,
    records: [],
    scratch: [],
    sort_mode: IdentityOrder,
    width: 1,
    run_start: 0,
    left_index: 0,
    middle: 0,
    right_index: 0,
    run_end: 0,
    merge_index: 0,
    compare_index: 0,
    copy_index: 0,
    duplicate_index: 1,
    group_start: 0,
    group_end: 1,
    member_index: 0,
    fold: None,
    output_vector: None,
    pooled_vector: None,
    output_field: 0,
    output_fields: [],
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control, state, pool_step, cleanup_pool_state, @records.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes,
    max_noninterruptible_value_bytes: limits.max_value_bytes,
  })
}

///|
pub fn start_pool(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[PoolExecution, PoolIssue] {
  start_pool_with_control_work_limit(
    control,
    sequence,
    step,
    input,
    limits,
    storage_bytes,
    available,
    limits.max_work,
  )
}

///|
/// Execute the registered Relation-to-Vectors expansion as one bounded local
/// occurrence. The intermediate member view remains private: it is not a
/// completion, publication, or substitute input binding.
pub fn start_relation_pool(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @execution.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[PoolExecution, PoolIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.VectorStep(prepared)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "VEC.pool" &&
    @execution.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidPoolKernel)
  }
  guard @lower.vector_pool_member_vectors(prepared) is Some(vectors) &&
    @lower.vector_output_carrier(prepared)
    is @carrier.VectorValue(output_vectors) &&
    @lower.vector_pool_group_count(prepared) is Some(group_count) &&
    @lower.vector_pool_identity_count(prepared) is Some(source_identity_count) &&
    @lower.vector_pool_encodes_member_identity(prepared)
    is Some(encode_member_identity) &&
    @lower.vector_pool_method(prepared) is Some(pool_method) &&
    @lower.vector_pool_vector_role(prepared) is Some(component_name) else {
    return Err(PoolInputUnavailable)
  }
  let raw_dimensions = @carrier.vector_dimensions(vectors)
  guard raw_dimensions >= 1.0 && raw_dimensions <= 2147483647.0 else {
    return Err(InvalidPoolLimits)
  }
  let dimensions = raw_dimensions.to_int()
  let identity_count = if encode_member_identity {
    1
  } else {
    source_identity_count
  }
  guard pool_checked_add(
      source_identity_count,
      if encode_member_identity {
        1
      } else {
        0
      },
    )
    is Some(workspace_identities) else {
    return Err(PoolWorkspaceLimit)
  }
  let output_rows = @carrier.vector_records(output_vectors)
  let output_fields = @carrier.field_count(output_rows)
  let component = @carrier.vector_components(output_vectors)
  guard dimensions.to_double() == raw_dimensions &&
    group_count > 0 &&
    source_identity_count > 0 &&
    identity_count > 0 &&
    component.contract is Some(component_contract) &&
    @carrier.lookup(output_rows, @schema.Unqualified("member_count"))
    is @carrier.Present({ contract: Some(member_count_contract), .. }) &&
    pool_workspace(
      @execution.producer_read_row_count(input),
      dimensions,
      group_count,
      workspace_identities,
      output_fields,
    )
    is Some(workspace) &&
    workspace <= limits.max_workspace_slots else {
    return Err(PoolWorkspaceLimit)
  }
  if limits.max_work < 0 {
    return Err(InvalidPoolLimits)
  }
  if limits.max_work == 0 {
    return Err(PoolWorkLimit)
  }
  let reduction = match pool_method {
    @lower.PoolMean => @numeric.Mean
    @lower.PoolSum => @numeric.Sum
    @lower.PoolMax => @numeric.Max
  }
  let output = match
    @records.prepare_output(
      owner,
      @pipeline.Step(step),
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PoolOutput(issue))
  }
  let member_identity_contract = if encode_member_identity {
    @contract.string_contract(nullable=false)
  } else {
    None
  }
  guard !encode_member_identity || member_identity_contract is Some(_) else {
    @records.cancel_output(output) |> ignore
    return Err(InvalidPoolKernel)
  }
  let state : PoolState = {
    input: None,
    relation_input: Some(input),
    source: None,
    vectors,
    output_vectors,
    prepared,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    output: Some(output),
    reduction,
    dimensions,
    group_count,
    identity_count,
    source_identity_count,
    encode_member_identity,
    member_identity_contract,
    component_name,
    output_component_contract: component_contract,
    member_count_contract,
    output_id: @lower.vector_pool_output_id(prepared),
    phase: BeginRecord,
    record: 0,
    field: 0,
    group_probe: 0,
    identity_probe: 0,
    identity_builder: None,
    identity_bytes: 0,
    current_field: None,
    source_vector: None,
    group_values: [],
    identity_values: [],
    collected_groups: [],
    collected_identities: [],
    component: 0,
    records: [],
    scratch: [],
    sort_mode: IdentityOrder,
    width: 1,
    run_start: 0,
    left_index: 0,
    middle: 0,
    right_index: 0,
    run_end: 0,
    merge_index: 0,
    compare_index: 0,
    copy_index: 0,
    duplicate_index: 1,
    group_start: 0,
    group_end: 1,
    member_index: 0,
    fold: None,
    output_vector: None,
    pooled_vector: None,
    output_field: 0,
    output_fields: [],
    control_work_remaining: limits.max_work,
  }
  let (session, token) = @bounded.start(
    control, state, pool_step, cleanup_pool_state, @records.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes,
    max_noninterruptible_value_bytes: limits.max_value_bytes,
  })
}

///|
pub fn pool_max_noninterruptible_value_nodes(value : PoolExecution) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn pool_max_noninterruptible_value_bytes(value : PoolExecution) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_pool(
  value : PoolExecution,
  quantum : Int,
) -> Result[PoolPoll, PoolIssue] {
  guard value.token is Some(token) else {
    return Err(PoolExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(PoolExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(PoolContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(PoolComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(PoolFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(PoolStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn pool_stopped(value : PoolExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn pool_cleanup_pending(value : PoolExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_pool(value : PoolExecution) -> Result[Bool, PoolIssue] {
  @bounded.cleanup(value.session).map_err(issue => PoolExecutionIssue(issue))
}
