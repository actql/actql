///|
/// Owned source/graph projections for one expression kernel. Not a sealed
/// fragment: request schemas/parameters, ceilings, witnesses and admission
/// must still be attached. The original upstream remains available to compose.
struct FragmentPipeline {
  kernel : PreparedKernel
  roots : RootIndex
}

///|
pub fn prepare_fragment_pipeline(
  sequence : PreparedSequence,
  step : Int,
  limits : RootLimits,
) -> Result[FragmentPipeline, RootIssue] {
  let roots = match prepare_kernel_roots(sequence, step, limits) {
    Ok(roots) => roots
    Err(issue) => return Err(issue)
  }
  match sequence.steps[step] {
    RowStep(kernel) =>
      if kernel.body is OrderedBindings(_) {
        Err(NeedsOrderedEncoding)
      } else {
        Ok({ kernel, roots, })
      }
    ValuesStep(_) => Err(NotExpressionKernel)
  }
}

///|
pub fn fragment_pipeline_roots(fragment : FragmentPipeline) -> RootIndex {
  fragment.roots
}

///|
pub fn fragment_pipeline_input(fragment : FragmentPipeline) -> String {
  fragment.kernel.input_id
}

///|
pub fn fragment_pipeline_output_schema(
  fragment : FragmentPipeline,
) -> @schema.Schema {
  @relation.output_schema(fragment.kernel.checked)
}

///|
pub fn emit_fragment_source_pipeline(
  fragment : FragmentPipeline,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_fragment_pipeline(fragment, true, out)
}

///|
pub fn emit_fragment_machine_pipeline(
  fragment : FragmentPipeline,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_fragment_pipeline(fragment, false, out)
}

///|
fn emit_fragment_pipeline(
  fragment : FragmentPipeline,
  source : Bool,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let kernel = fragment.kernel
  let node = kernel.owner.prepared.nodes[kernel.step_index]
  @encode.begin_object(out)
  @encode.key(out, "output")
  @encode.string_value(out, node.id)
  @encode.key(out, "sources")
  @encode.begin_object(out)
  @encode.key(out, "input")
  @encode.begin_object(out)
  @encode.key(out, "sort")
  @encode.string_value(out, "relation")
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.key(out, "steps")
  @encode.begin_array(out)
  if source {
    @encode.begin_object(out)
    @encode.key(out, "id")
    @encode.string_value(out, node.id)
    @encode.key(out, "in")
    @encode.begin_array(out)
    @encode.string_value(out, "input")
    @encode.end_array(out)
    @encode.key(out, "op")
    @encode.string_value(
      out,
      match kernel.body {
        SnapshotMap(_) => "REL.derive"
        Filter(_) => "REL.where"
        Select(_) => raise @encode.InvalidStructure
        OrderedBindings(_) => raise @encode.InvalidStructure
      },
    )
    @encode.key(out, "params")
    @encode.begin_object(out)
    match kernel.body {
      OrderedBindings(_) => raise @encode.InvalidStructure
      SnapshotMap(bindings) => {
        @encode.key(out, "exprs")
        @encode.begin_object(out)
        for (name, expression) in bindings {
          @encode.key(out, name)
          emit_expression_source(expression, out)
        }
        @encode.end_object(out)
      }
      Filter(expression) => {
        @encode.key(out, "expr")
        emit_expression_source(expression, out)
      }
      Select(_) => raise @encode.InvalidStructure
    }
    @encode.end_object(out)
    @encode.end_object(out)
  } else {
    // Rebase only the local input reference, retaining checked owner and body.
    emit_kernel_node({ ..kernel, input_id: "input", }, out)
  }
  @encode.end_array(out)
  @encode.key(out, "version")
  @encode.string_value(out, "aoa-pipeline/0.1")
  @encode.end_object(out)
}
