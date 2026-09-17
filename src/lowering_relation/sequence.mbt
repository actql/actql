///|
/// Opaque, wholly prepared operation sequence. NOT an admitted executable
/// fragment: registry/params, input proofs and runtime obligations remain.
struct PreparedSequence {
  owner : BoundPrepared
  steps : Array[PreparedStep]
}

///|
pub enum PreparedStep {
  ValuesStep(PreparedValues)
  RowStep(PreparedKernel)
  JoinStep(PreparedJoinKernel)
  AppendStep(PreparedAppendKernel)
}

///|
pub(all) struct SequenceLimits {
  max_steps : Int
  max_rows : Int
  max_cells : Int
  max_bindings : Int
  max_name_bytes : Int
  expressions : ExpressionLimits
}

///|
pub(all) enum SequenceIssue {
  InvalidSequenceLimits
  SequenceLimit
  ValuesFailure(Int, ValuesIssue)
  KernelFailure(Int, KernelIssue)
  JoinFailure(Int, InnerJoinIssue)
  AppendFailure(Int, AppendIssue)
}

///|
pub fn sequence_owner(value : PreparedSequence) -> BoundPrepared {
  value.owner
}

///|
pub fn sequence_count(value : PreparedSequence) -> Int {
  value.steps.length()
}

///|
pub fn sequence_step(value : PreparedSequence, index : Int) -> PreparedStep? {
  value.steps.get(index)
}

///|
pub fn prepare_sequence(
  owner : BoundPrepared,
  limits : SequenceLimits,
) -> Result[PreparedSequence, SequenceIssue] {
  let e = limits.expressions
  if limits.max_steps < 0 ||
    limits.max_rows < 0 ||
    limits.max_cells < 0 ||
    limits.max_bindings < 0 ||
    limits.max_name_bytes < 0 ||
    e.max_nodes < 0 ||
    e.max_work < 0 ||
    e.max_depth < 0 ||
    e.max_literal_nodes < 0 ||
    e.max_literal_text_bytes < 0 {
    return Err(InvalidSequenceLimits)
  }
  if owner.prepared.nodes.length() > limits.max_steps {
    return Err(SequenceLimit)
  }
  let steps : Array[PreparedStep] = []
  let mut rows = limits.max_rows
  let mut cells = limits.max_cells
  let mut bindings = limits.max_bindings
  let mut names = limits.max_name_bytes
  let mut expressions = limits.expressions
  for i = 0; i < owner.prepared.nodes.length(); i = i + 1 {
    let step = match owner.prepared.nodes[i].payload {
      InnerJoin(_) => {
        let kernel = match prepare_join_kernel(owner, i, bindings, names) {
          Ok(v) => v
          Err(e) => return Err(JoinFailure(i, e))
        }
        bindings -= kernel.profile.keys.length() +
          kernel.profile.projection.length()
        names -= kernel.profile.name_bytes
        if @join.output_guard(kernel.profile.checked) is Some(Parameter(name)) {
          names -= @utf8.encode(name).length()
        }
        JoinStep(kernel)
      }
      AppendRows(_) => {
        let kernel = match prepare_append_kernel(owner, i, bindings, names) {
          Ok(value) => value
          Err(issue) => return Err(AppendFailure(i, issue))
        }
        bindings -= append_kernel_field_count(kernel)
        names -= append_kernel_name_bytes(kernel)
        AppendStep(kernel)
      }
      Values(values) => {
        let prepared = match
          prepare_values_node(owner, i, max_rows=rows, max_cells=cells) {
          Ok(v) => v
          Err(e) => return Err(ValuesFailure(i, e))
        }
        let count = @values.row_count(values)
        // prepare_values_node proved this product <= the remaining Int bound.
        cells -= count * @schema.field_count(@values.output_schema(values))
        rows -= count
        ValuesStep(prepared)
      }
      Derive(_)
      | Where(_)
      | Select(_)
      | Limit(_)
      | Distinct(_)
      | Dedupe(_)
      | Sort(_)
      | CountGroup(_)
      | AssertRows(_)
      | JsonPick(_) => {
        let (kernel, remaining, used_names, used_bindings) = match
          prepare_kernel_measured(
            owner,
            i,
            max_bindings=bindings,
            max_name_bytes=names,
            expressions,
          ) {
          Ok(v) => v
          Err(e) => return Err(KernelFailure(i, e))
        }
        expressions = remaining
        bindings -= used_bindings
        names -= used_names
        RowStep(kernel)
      }
    }
    steps.push(step)
  }
  Ok({ owner, steps, })
}

///|
/// Emits the steps array only, not a made-up fragment/Plan envelope. Writer
/// finish is the publication boundary; unsupported sequences yield no value.
pub fn emit_sequence_steps(
  value : PreparedSequence,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(out)
  for step in value.steps {
    match step {
      ValuesStep(v) => emit_values_node(v, out)
      JoinStep(v) => emit_join_kernel(v, out)
      AppendStep(v) => emit_append_kernel(v, out)
      RowStep(v) => {
        emit_kernel_prefix(v, out)
        emit_kernel_node(v, out)
      }
    }
  }
  @encode.end_array(out)
}
