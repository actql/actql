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
    RowStep(kernel) => Ok({ kernel, roots, })
    InferBoundary(_)
    | ValuesStep(_)
    | TimeSeriesStep(_)
    | WindowStep(_)
    | JoinStep(_)
    | IntervalJoinStep(_)
    | AsOfJoinStep(_)
    | SequenceMatchStep(_)
    | CrossJoinStep(_)
    | AppendStep(_)
    | SetStep(_)
    | NestStep(_)
    | GraphMatchStep(_)
    | GraphDiagnosticStep(_)
    | GraphNormalizeStep(_)
    | GraphDeltaStep(_)
    | GraphTraverseStep(_)
    | PropertyGraphConstructionStep(_)
    | VectorStep(_)
    | EventStep(_)
    | CarrierProjectionStep(_) => Err(NotExpressionKernel)
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
        SnapshotMap(_) | OrderedBindings(_) => "REL.derive"
        Filter(_) => "REL.where"
        AssertAll(_) => "REL.assert_all"
        Groups(group) =>
          if group.window {
            "REL.window.project"
          } else {
            "REL.groupBy"
          }
        AnalyticRows(_) => "REL.analytic"
        Select(_)
        | AssertUnique(_)
        | JsonPick(_, _, _)
        | Limit(_, _, _)
        | TopK(_, _)
        | PartitionedTopK(_, _)
        | Pivot(_)
        | Unnest(_, _, _, _, _)
        | Unpivot(_, _, _, _)
        | DistinctRows
        | DedupeRows
        | StableSort(_)
        | Lag(_, _)
        | Watermark(_, _, _, _)
        | CountGroups(_) => raise @encode.InvalidStructure
      },
    )
    @encode.key(out, "params")
    if kernel.body is Groups(group) {
      emit_group_params(group, out)
    } else if kernel.body is AnalyticRows(analytic) {
      emit_analytic_params(analytic, out)
    } else {
      @encode.begin_object(out)
      match kernel.body {
        OrderedBindings(bindings) => {
          @encode.key(out, "bindings")
          @encode.begin_array(out)
          for (name, expression) in bindings {
            @encode.begin_object(out)
            @encode.key(out, "name")
            @encode.string_value(out, name)
            @encode.key(out, "expr")
            emit_expression_source(expression, out)
            @encode.end_object(out)
          }
          @encode.end_array(out)
        }
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
        AssertAll(expression) => {
          @encode.key(out, "expr")
          emit_expression_source(expression, out)
        }
        Select(_)
        | AssertUnique(_)
        | JsonPick(_, _, _)
        | Limit(_, _, _)
        | TopK(_, _)
        | PartitionedTopK(_, _)
        | Pivot(_)
        | Unnest(_, _, _, _, _)
        | Unpivot(_, _, _, _)
        | DistinctRows
        | DedupeRows
        | StableSort(_)
        | Lag(_, _)
        | Watermark(_, _, _, _)
        | CountGroups(_)
        | AnalyticRows(_)
        | Groups(_) => raise @encode.InvalidStructure
      }
      @encode.end_object(out)
    }
    @encode.end_object(out)
  } else {
    // Rebase only the local input reference, retaining checked owner and body.
    let rebased = { ..kernel, input_id: "input", }
    if rebased.body is Groups(_) {
      emit_kernel_prefix(rebased, out)
    }
    emit_kernel_node(rebased, out)
  }
  @encode.end_array(out)
  @encode.key(out, "version")
  @encode.string_value(out, "aoa-pipeline/0.1")
  @encode.end_object(out)
}
