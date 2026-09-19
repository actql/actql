///|
/// Non-wire prepared operation. This preserves normative AoA payloads and
/// checked ownership, but does not establish registry/capacity admission.
struct PreparedKernel {
  owner : BoundPrepared
  step_index : Int
  input_id : String
  checked : @relation.CheckedOperation
  body : KernelBody
}

///|
/// A bound watermark threshold. Prefix mode retains the exact checked input
/// order whose occurrence sequence defines the running maximum.
pub enum PreparedWatermarkThreshold {
  FixedWatermark(Double)
  PrefixWatermark(Int64, @pipeline.LogicalOrder)
}

///|
pub enum KernelBody {
  SnapshotMap(Array[(String, Expression)])
  OrderedBindings(Array[(String, Expression)])
  Filter(Expression)
  AssertAll(Expression)
  AssertUnique(Array[@schema.FieldName])
  JsonPick(@schema.FieldName, Array[String], String)
  Select(Array[@relation.ProjectionField])
  Limit(Int64, Int64, @pipeline.LogicalOrder)
  TopK(Int64, @pipeline.LogicalOrder)
  PartitionedTopK(Int64, @pipeline.LogicalOrder)
  Pivot(PreparedPivot)
  Unnest(@schema.FieldName, String, String?, Bool, Int64?)
  Unpivot(Array[@schema.FieldName], Array[@schema.FieldName], String, String)
  DistinctRows
  DedupeRows
  StableSort(@pipeline.SortOrder?)
  Lag(Int64, @pipeline.SortCompletion)
  Watermark(
    @schema.FieldName,
    Bool,
    @relation.LatePolicy,
    PreparedWatermarkThreshold
  )
  AnalyticRows(PreparedAnalytic)
  CountGroups(PreparedCountGroup)
  Groups(PreparedGroup)
}

///|
pub(all) enum KernelIssue {
  MissingKernelNode
  InvalidKernelWiring
  KernelBudgetExceeded
  InvalidKernelLimits
  ExpressionFailure(ExpressionIssue)
  InvalidTakeCount
  InvalidTopKCount
  PendingTakeOrder
  PendingTopKOrder
  PendingSortOrder
  PendingLagOrder
  InvalidLagOffset
  PendingWatermarkOrder
  InvalidWatermarkThreshold
  PivotFailure(PivotIssue)
  CountGroupFailure(CountGroupIssue)
  GroupFailure(GroupIssue)
  AnalyticFailure(AnalyticIssue)
}

///|
pub fn kernel_owner(kernel : PreparedKernel) -> BoundPrepared {
  kernel.owner
}

///|
pub fn kernel_step(kernel : PreparedKernel) -> Int {
  kernel.step_index
}

///|
pub fn kernel_input(kernel : PreparedKernel) -> String {
  kernel.input_id
}

///|
pub fn kernel_checked(kernel : PreparedKernel) -> @relation.CheckedOperation {
  kernel.checked
}

///|
/// Allocation-free dispatch inspection; unrelated kernels do not copy bindings.
pub fn kernel_count_group(kernel : PreparedKernel) -> PreparedCountGroup? {
  match kernel.body {
    CountGroups(group) => Some(group)
    _ => None
  }
}

///|
/// Allocation-free complete group view bound to this checked kernel.
pub fn kernel_group(kernel : PreparedKernel) -> PreparedGroup? {
  match kernel.body {
    Groups(group) => Some(group)
    _ => None
  }
}

///|
/// Allocation-free pivot dispatch view bound to this exact checked owner.
pub fn kernel_pivot(kernel : PreparedKernel) -> PreparedPivot? {
  match kernel.body {
    Pivot(value) => Some(value)
    _ => None
  }
}

///|
/// Allocation-free complete analytic view bound to this checked kernel.
pub fn kernel_analytic(kernel : PreparedKernel) -> PreparedAnalytic? {
  match kernel.body {
    AnalyticRows(value) => Some(value)
    _ => None
  }
}

///|
/// Allocation-free batch selection view; the order remains owned by preparation.
pub fn kernel_take(kernel : PreparedKernel) -> (Int64, Int64)? {
  match kernel.body {
    Limit(count, offset, _) => Some((count, offset))
    SnapshotMap(_)
    | OrderedBindings(_)
    | Filter(_)
    | AssertAll(_)
    | AssertUnique(_)
    | JsonPick(_, _, _)
    | Select(_)
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
    | AnalyticRows(_)
    | CountGroups(_)
    | Groups(_) => None
  }
}

///|
/// Indexed immutable binding view, without copying the complete slot array.
pub fn ordered_binding_at(
  kernel : PreparedKernel,
  index : Int,
) -> (String, Expression)? {
  match kernel.body {
    OrderedBindings(bindings) => bindings.get(index)
    SnapshotMap(_)
    | Filter(_)
    | AssertAll(_)
    | AssertUnique(_)
    | JsonPick(_, _, _)
    | Select(_)
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
    | AnalyticRows(_)
    | CountGroups(_)
    | Groups(_) => None
  }
}

///|
pub fn kernel_body(kernel : PreparedKernel) -> KernelBody {
  match kernel.body {
    SnapshotMap(bindings) => SnapshotMap(bindings.copy())
    OrderedBindings(bindings) => OrderedBindings(bindings.copy())
    Filter(expr) => Filter(expr)
    AssertAll(expr) => AssertAll(expr)
    AssertUnique(keys) => AssertUnique(keys.copy())
    JsonPick(column, path, output) => JsonPick(column, path.copy(), output)
    Select(fields) => Select(fields.copy())
    Limit(count, offset, order) => Limit(count, offset, order)
    TopK(count, order) => TopK(count, order)
    PartitionedTopK(count, order) => PartitionedTopK(count, order)
    Pivot(value) => Pivot(value)
    Unnest(column, element, index, outer, max_items) =>
      Unnest(column, element, index, outer, max_items)
    Unpivot(columns, keep, name_column, value_column) =>
      Unpivot(columns.copy(), keep.copy(), name_column, value_column)
    DistinctRows => DistinctRows
    DedupeRows => DedupeRows
    StableSort(order) => StableSort(order)
    Lag(offset, order) => Lag(offset, order)
    Watermark(time, timestamp, policy, threshold) =>
      Watermark(time, timestamp, policy, threshold)
    AnalyticRows(value) => AnalyticRows(value)
    CountGroups(group) => CountGroups(group)
    Groups(group) => Groups(group)
  }
}

///|
/// O(1), allocation-free number of entries copied by kernel_body.
pub fn kernel_view_entries(kernel : PreparedKernel) -> Int {
  match kernel.body {
    SnapshotMap(bindings) | OrderedBindings(bindings) => bindings.length()
    Select(fields) => fields.length()
    AssertUnique(keys) => keys.length()
    JsonPick(_, path, _) => path.length() + 2
    Filter(_)
    | AssertAll(_)
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
    | AnalyticRows(_)
    | CountGroups(_)
    | Groups(_) => 0
  }
}

///|
pub fn prepare_kernel(
  owner : BoundPrepared,
  step_index : Int,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  limits : ExpressionLimits,
) -> Result[PreparedKernel, KernelIssue] {
  prepare_kernel_measured(
    owner,
    step_index,
    max_bindings~,
    max_name_bytes~,
    limits,
  ).map(result => result.0)
}

///|
fn prepare_kernel_measured(
  owner : BoundPrepared,
  step_index : Int,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  limits : ExpressionLimits,
) -> Result[(PreparedKernel, ExpressionLimits, Int, Int), KernelIssue] {
  if max_bindings < 0 ||
    max_name_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_work < 0 ||
    limits.max_depth < 0 ||
    limits.max_literal_nodes < 0 ||
    limits.max_literal_text_bytes < 0 {
    return Err(InvalidKernelLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) else {
    return Err(MissingKernelNode)
  }
  let checked = match node.payload {
    Derive(op)
    | Where(op)
    | Select(op)
    | Limit(op)
    | TopK(op)
    | TopKBy(op)
    | Pivot(op)
    | Unnest(op)
    | Unpivot(op)
    | Distinct(op)
    | Dedupe(op)
    | Sort(op)
    | CountGroup(op)
    | WindowGroup(op)
    | Lag(op)
    | Watermark(op)
    | Analytic(op)
    | AssertRows(op) => op
    JsonPick(op) => op
    Values(_)
    | TimeSeriesValue(_)
    | RowWindow(_)
    | InnerJoin(_)
    | CrossJoinRows(_)
    | AppendRows(_)
    | SetRows(_)
    | NestRows(_)
    | BasicGraph(_)
    | StructuralGraph(_)
    | GraphUnion(_)
    | GraphMeanValue(_)
    | GraphMatchRows(_)
    | GraphReachRows(_)
    | GraphSubgraphValue(_)
    | GraphTraverseRows(_)
    | GraphShortestRows(_)
    | GraphEqualityRows(_)
    | GraphDiffRows(_)
    | GraphApplyValue(_)
    | VectorValue(_)
    | NearestValue(_)
    | PoolValue(_)
    | EventValue(_)
    | CarrierProjection(_) => return Err(MissingKernelNode)
  }
  if node.inputs.length() != 1 {
    return Err(InvalidKernelWiring)
  }
  let mut remaining = limits
  let mut names_remaining = max_name_bytes
  let body = match @relation.form(checked) {
    DeriveArray | DeriveMap | Predicate => {
      let count = @relation.binding_count(checked)
      if count > max_bindings {
        return Err(KernelBudgetExceeded)
      }
      let bindings : Array[(String, Expression)] = []
      let mut predicate : Expression? = None
      for i = 0; i < count; i = i + 1 {
        let binding = @relation.binding_at(checked, i).unwrap()
        if binding.name is Some(name) {
          if name.length() > names_remaining {
            return Err(KernelBudgetExceeded)
          }
          let size = @utf8.encode(name).length()
          if size > names_remaining {
            return Err(KernelBudgetExceeded)
          }
          names_remaining -= size
        }
        let (expr, usage) = match
          lower_expression_measured(owner, step_index, i, remaining) {
          Ok(pair) => pair
          Err(e) => return Err(ExpressionFailure(e))
        }
        remaining = {
          ..remaining,
          max_nodes: remaining.max_nodes - usage.nodes,
          max_work: remaining.max_work - usage.work,
          max_literal_nodes: remaining.max_literal_nodes - usage.literal_nodes,
          max_literal_text_bytes: remaining.max_literal_text_bytes -
          usage.literal_bytes,
        }
        match binding.name {
          Some(name) => bindings.push((name, expr))
          None => predicate = Some(expr)
        }
      }
      if @relation.form(checked) != @relation.Predicate {
        if bindings.length() != count {
          return Err(InvalidKernelWiring)
        }
        if @relation.form(checked) == @relation.DeriveArray {
          OrderedBindings(bindings)
        } else {
          SnapshotMap(bindings)
        }
      } else {
        guard count == 1 && predicate is Some(expr) else {
          return Err(InvalidKernelWiring)
        }
        Filter(expr)
      }
    }
    Projection | RowOperation if @relation.form(checked) == @relation.Projection ||
      node.projection_id is Some(_) => {
      // Projection has no indexed accessor yet. The checked schema bounds
      // its cardinality before asking for the defensive-copy projection view.
      if @schema.field_count(@relation.output_schema(checked)) > max_bindings {
        return Err(KernelBudgetExceeded)
      }
      let fields = @relation.projection(checked)
      for field in fields {
        for
          name in [
            @schema.reference_name(field.input),
            @schema.reference_name(field.output),
          ] {
          if name.length() > names_remaining {
            return Err(KernelBudgetExceeded)
          }
          let size = @utf8.encode(name).length()
          if size > names_remaining {
            return Err(KernelBudgetExceeded)
          }
          names_remaining -= size
        }
      }
      if @relation.form(checked) == @relation.Projection {
        Select(fields)
      } else {
        DistinctRows
      }
    }
    RowOperation if @relation.operation(checked) == @relation.AssertRows =>
      match @relation.row_operation(checked) {
        Some(@relation.AssertWhere) => {
          if max_bindings < 1 {
            return Err(KernelBudgetExceeded)
          }
          let (expr, usage) = match
            lower_expression_measured(owner, step_index, 0, remaining) {
            Ok(pair) => pair
            Err(e) => return Err(ExpressionFailure(e))
          }
          remaining = {
            ..remaining,
            max_nodes: remaining.max_nodes - usage.nodes,
            max_work: remaining.max_work - usage.work,
            max_literal_nodes: remaining.max_literal_nodes - usage.literal_nodes,
            max_literal_text_bytes: remaining.max_literal_text_bytes -
            usage.literal_bytes,
          }
          AssertAll(expr)
        }
        Some(@relation.AssertUnique(keys)) => {
          if keys.length() > max_bindings || keys.length() > remaining.max_work {
            return Err(KernelBudgetExceeded)
          }
          let fields : Array[@schema.FieldName] = []
          for key in keys {
            let name = @schema.reference_name(key.field)
            if name.length() > names_remaining {
              return Err(KernelBudgetExceeded)
            }
            let size = @utf8.encode(name).length()
            if size > names_remaining {
              return Err(KernelBudgetExceeded)
            }
            names_remaining -= size
            fields.push(key.field)
          }
          remaining = {
            ..remaining,
            max_work: remaining.max_work - fields.length(),
          }
          AssertUnique(fields)
        }
        _ => return Err(InvalidKernelWiring)
      }
    RowOperation if @relation.operation(checked) == @relation.Sort => {
      let authored = @relation.sort_term_count(checked)
      let resolution = if authored == 0 {
        None
      } else {
        guard @pipeline.sort_order(owner.prepared.owner, step_index)
          is Some(order) else {
          return Err(PendingSortOrder)
        }
        Some(order)
      }
      let completion = resolution.bind(order => {
        match @pipeline.sort_order_strategy(order) {
          CandidateKey(key) => Some(key)
          ExistingTotal(_) => None
        }
      })
      let appended = completion
        .map(@pipeline.sort_completion_count)
        .unwrap_or(0)
      if authored > max_bindings ||
        appended > max_bindings - authored ||
        authored > remaining.max_work ||
        appended > remaining.max_work - authored {
        return Err(KernelBudgetExceeded)
      }
      remaining = {
        ..remaining,
        max_work: remaining.max_work - authored - appended,
      }
      for i = 0; i < authored + appended; i = i + 1 {
        let field = if i < authored {
          @relation.sort_term_at(checked, i).unwrap().field
        } else {
          @pipeline.sort_completion_field(completion.unwrap(), i - authored).unwrap()
        }
        let name = @schema.reference_name(field)
        if name.length() > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        let bytes = @utf8.encode(name).length()
        if bytes > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= bytes
      }
      StableSort(resolution)
    }
    RowOperation if @relation.operation(checked) == @relation.TopK ||
      @relation.operation(checked) == @relation.TopKBy => {
      guard @pipeline.logical_order(owner.prepared.owner, Step(step_index))
        is Some(order) &&
        @pipeline.order_sort_completion(order) is Some(completion) else {
        return Err(PendingTopKOrder)
      }
      let partitions = @relation.top_k_partition_count(checked)
      let authored = @relation.ranking_term_count(checked)
      let appended = @pipeline.sort_completion_count(completion)
      if partitions > max_bindings ||
        authored > max_bindings - partitions ||
        appended > max_bindings - partitions - authored ||
        partitions > remaining.max_work ||
        authored > remaining.max_work - partitions ||
        appended > remaining.max_work - partitions - authored {
        return Err(KernelBudgetExceeded)
      }
      remaining = {
        ..remaining,
        max_work: remaining.max_work - partitions - authored - appended,
      }
      for i = 0; i < partitions + authored + appended; i = i + 1 {
        let field = if i < partitions {
          @relation.top_k_partition_at(checked, i).unwrap().field
        } else if i < partitions + authored {
          @relation.ranking_term_at(checked, i - partitions).unwrap().field
        } else {
          @pipeline.sort_completion_field(completion, i - partitions - authored).unwrap()
        }
        let name = @schema.reference_name(field)
        let bytes = @utf8.encode(name).length()
        if bytes > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= bytes
      }
      guard @relation.top_k_count(checked) is Some(value) else {
        return Err(InvalidKernelWiring)
      }
      let count = match value {
        Literal(n) => n
        Parameter(name) => {
          let size = @utf8.encode(name).length()
          if size > names_remaining {
            return Err(KernelBudgetExceeded)
          }
          names_remaining -= size
          guard owner.by_name.get(name) is Some(bound) &&
            bound.value is @value.Number(n) &&
            @scalar.read_safe_integer(n) is Some(n) else {
            return Err(InvalidTopKCount)
          }
          n
        }
      }
      if count < 1L || count > 9007199254740991L {
        return Err(InvalidTopKCount)
      }
      if @relation.operation(checked) == @relation.TopK {
        TopK(count, order)
      } else {
        PartitionedTopK(count, order)
      }
    }
    Reshape if @relation.operation(checked) == @relation.Unnest => {
      guard @relation.reshape(checked)
        is Some(@relation.Unnest(column~, element~, index~, outer~, max_items~)) else {
        return Err(InvalidKernelWiring)
      }
      let bindings = 2 + (if index is Some(_) { 1 } else { 0 })
      if bindings > max_bindings || bindings > remaining.max_work {
        return Err(KernelBudgetExceeded)
      }
      remaining = { ..remaining, max_work: remaining.max_work - bindings, }
      for name in [@schema.reference_name(column), element] {
        let bytes = @utf8.encode(name).length()
        if bytes > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= bytes
      }
      if index is Some(name) {
        let bytes = @utf8.encode(name).length()
        if bytes > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= bytes
      }
      Unnest(column, element, index, outer, max_items)
    }
    Reshape if @relation.operation(checked) == @relation.Unpivot => {
      let columns = @relation.unpivot_columns_count(checked)
      let keep = @relation.unpivot_keep_count(checked)
      guard @relation.unpivot_outputs(checked)
        is Some((name_column, value_column)) else {
        return Err(InvalidKernelWiring)
      }
      let bindings = columns + keep + 2
      if columns <= 0 ||
        columns > max_bindings ||
        keep > max_bindings - columns ||
        2 > max_bindings - columns - keep ||
        bindings > remaining.max_work {
        return Err(KernelBudgetExceeded)
      }
      let lowered_columns : Array[@schema.FieldName] = []
      let lowered_keep : Array[@schema.FieldName] = []
      for i = 0; i < columns + keep + 2; i = i + 1 {
        let name = if i < columns {
          let field = @relation.unpivot_column_at(checked, i).unwrap().field
          lowered_columns.push(field)
          @schema.reference_name(field)
        } else if i < columns + keep {
          let field = @relation.unpivot_keep_at(checked, i - columns).unwrap().field
          lowered_keep.push(field)
          @schema.reference_name(field)
        } else if i == columns + keep {
          name_column
        } else {
          value_column
        }
        let bytes = @utf8.encode(name).length()
        if bytes > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= bytes
      }
      remaining = { ..remaining, max_work: remaining.max_work - bindings, }
      Unpivot(lowered_columns, lowered_keep, name_column, value_column)
    }
    RowOperation if @relation.operation(checked) == @relation.DedupeRows => {
      let keys = @relation.dedupe_key_count(checked)
      let terms = @relation.dedupe_order_count(checked)
      if keys > max_bindings ||
        terms > max_bindings - keys ||
        keys > remaining.max_work ||
        terms > remaining.max_work - keys {
        return Err(KernelBudgetExceeded)
      }
      remaining = { ..remaining, max_work: remaining.max_work - keys - terms, }
      for i = 0; i < keys + terms; i = i + 1 {
        let field = if i < keys {
          @relation.dedupe_key_at(checked, i).unwrap().field
        } else {
          @relation.dedupe_order_at(checked, i - keys).unwrap().field
        }
        let name = @schema.reference_name(field)
        if name.length() > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        let bytes = @utf8.encode(name).length()
        if bytes > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= bytes
      }
      DedupeRows
    }
    RowOperation if @relation.operation(checked) == @relation.Distinct =>
      DistinctRows
    RowOperation if @relation.operation(checked) == @relation.WatermarkRows => {
      guard @relation.row_operation(checked)
        is Some(@relation.Watermark(time~, timestamp~, threshold~, policy~)) else {
        return Err(InvalidKernelWiring)
      }
      if max_bindings < 2 || remaining.max_work < 2 {
        return Err(KernelBudgetExceeded)
      }
      let time_name = @schema.reference_name(time.field)
      let time_bytes = @utf8.encode(time_name).length()
      if time_bytes > names_remaining {
        return Err(KernelBudgetExceeded)
      }
      names_remaining -= time_bytes
      let bind_name = fn(
        name : String,
      ) -> Result[@value.CheckedValue, KernelIssue] {
        let bytes = @utf8.encode(name).length()
        if bytes > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= bytes
        match owner.by_name.get(name) {
          Some(value) => Ok(value)
          None => Err(InvalidWatermarkThreshold)
        }
      }
      let prepared_threshold = match threshold {
        @relation.FixedThreshold(value) => FixedWatermark(value)
        @relation.ThresholdParameter(name) => {
          guard bind_name(name) is Ok(bound) &&
            bound.value is @value.Number(value) &&
            !value.is_nan() &&
            !value.is_inf() &&
            !(value == 0.0 && 1.0 / value < 0.0) else {
            return Err(InvalidWatermarkThreshold)
          }
          FixedWatermark(value)
        }
        @relation.PrefixSkew(value, duration~) => {
          guard @pipeline.resolve_existing_input_order(
              owner.prepared.owner,
              step_index,
            )
            is Some(resolution) &&
            @pipeline.input_order_requirement(resolution)
            is @relation.WatermarkPrefixOrder else {
            return Err(PendingWatermarkOrder)
          }
          guard node.input_targets.get(0) is Some(target) &&
            target == @pipeline.input_order_target(resolution) else {
            return Err(InvalidKernelWiring)
          }
          let skew = match value {
            Literal(value) => value
            Parameter(name) => {
              guard bind_name(name) is Ok(bound) else {
                return Err(InvalidWatermarkThreshold)
              }
              if duration {
                guard bound.value is @value.Text(text) &&
                  @scalar.read_duration_ms(text) is Some(value) else {
                  return Err(InvalidWatermarkThreshold)
                }
                value
              } else {
                guard bound.value is @value.Number(number) &&
                  @scalar.read_safe_integer(number) is Some(value) else {
                  return Err(InvalidWatermarkThreshold)
                }
                value
              }
            }
          }
          if skew < 1L || skew > 9007199254740991L {
            return Err(InvalidWatermarkThreshold)
          }
          PrefixWatermark(skew, @pipeline.input_order_evidence(resolution))
        }
      }
      remaining = { ..remaining, max_work: remaining.max_work - 2, }
      Watermark(time.field, timestamp, policy, prepared_threshold)
    }
    RowOperation if @relation.operation(checked) == @relation.Lag => {
      guard @pipeline.lag_order_completion(owner.prepared.owner, step_index)
        is Some(completion) else {
        return Err(PendingLagOrder)
      }
      guard @relation.lag_navigation(checked)
        is Some((field, output, offset_value)) else {
        return Err(InvalidKernelWiring)
      }
      let partitions = @relation.lag_partition_count(checked)
      let authored = @relation.lag_term_count(checked)
      let appended = @pipeline.sort_completion_count(completion)
      let entries = partitions + authored + appended + 2
      if partitions > max_bindings ||
        authored > max_bindings - partitions ||
        appended > max_bindings - partitions - authored ||
        2 > max_bindings - partitions - authored - appended ||
        entries > remaining.max_work {
        return Err(KernelBudgetExceeded)
      }
      for i = 0; i < entries - 1; i = i + 1 {
        let name = if i < partitions {
          @schema.reference_name(
            @relation.lag_partition_at(checked, i).unwrap().field,
          )
        } else if i < partitions + authored {
          @schema.reference_name(
            @relation.lag_term_at(checked, i - partitions).unwrap().field,
          )
        } else if i < partitions + authored + appended {
          @schema.reference_name(
            @pipeline.sort_completion_field(
              completion,
              i - partitions - authored,
            ).unwrap(),
          )
        } else {
          @schema.reference_name(field.field)
        }
        let bytes = @utf8.encode(name).length()
        if bytes > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= bytes
      }
      let output_bytes = @utf8.encode(output).length()
      if output_bytes > names_remaining {
        return Err(KernelBudgetExceeded)
      }
      names_remaining -= output_bytes
      let offset = match offset_value {
        Literal(value) => value
        Parameter(name) => {
          let bytes = @utf8.encode(name).length()
          if bytes > names_remaining {
            return Err(KernelBudgetExceeded)
          }
          names_remaining -= bytes
          guard owner.by_name.get(name) is Some(bound) &&
            bound.value is @value.Number(number) &&
            @scalar.read_safe_integer(number) is Some(value) else {
            return Err(InvalidLagOffset)
          }
          value
        }
      }
      if offset < 1L || offset > 9007199254740991L {
        return Err(InvalidLagOffset)
      }
      remaining = { ..remaining, max_work: remaining.max_work - entries, }
      Lag(offset, completion)
    }
    Aggregation if @relation.operation(checked) == @relation.Analytic => {
      let (analytic, after) = match
        prepare_analytic(
          owner, step_index, max_bindings, names_remaining, remaining,
        ) {
        Ok(value) => value
        Err(issue) => return Err(AnalyticFailure(issue))
      }
      names_remaining -= analytic_name_bytes(analytic)
      remaining = after
      AnalyticRows(analytic)
    }
    RowOperation => {
      guard @relation.row_operation(checked)
        is Some(@relation.Take(count~, offset~)) else {
        return Err(MissingKernelNode)
      }
      guard @pipeline.take_order(owner.prepared.owner, step_index)
        is Some(order) else {
        return Err(PendingTakeOrder)
      }
      if take_completion(owner.prepared.owner, step_index) is Some(key) {
        let count = @evidence.key_field_count(key)
        if count > max_bindings || count > remaining.max_work {
          return Err(KernelBudgetExceeded)
        }
        remaining = { ..remaining, max_work: remaining.max_work - count, }
        for i = 0; i < count; i = i + 1 {
          let name = @schema.reference_name(
            @evidence.key_field_at(key, i).unwrap().name,
          )
          if name.length() > names_remaining {
            return Err(KernelBudgetExceeded)
          }
          let bytes = @utf8.encode(name).length()
          if bytes > names_remaining {
            return Err(KernelBudgetExceeded)
          }
          names_remaining -= bytes
        }
      }
      let bind_count = fn(
        value : @relation.CountValue,
        minimum : Int64,
      ) -> Result[Int64, KernelIssue] {
        let n = match value {
          Literal(n) => n
          Parameter(name) => {
            if name.length() > names_remaining {
              return Err(KernelBudgetExceeded)
            }
            let size = @utf8.encode(name).length()
            if size > names_remaining {
              return Err(KernelBudgetExceeded)
            }
            names_remaining -= size
            guard owner.by_name.get(name) is Some(bound) &&
              bound.value is @value.Number(n) else {
              return Err(InvalidTakeCount)
            }
            guard @scalar.read_safe_integer(n) is Some(n) else {
              return Err(InvalidTakeCount)
            }
            n
          }
        }
        if n < minimum || n > 9007199254740991L {
          Err(InvalidTakeCount)
        } else {
          Ok(n)
        }
      }
      let count = match bind_count(count, 1L) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let offset = match bind_count(offset, 0L) {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      Limit(count, offset, order)
    }
    Aggregation if @relation.operation(checked) == @relation.Pivot => {
      let (pivot, name_bytes, entries) = match
        prepare_pivot(
          owner,
          checked,
          Int::min(max_bindings, remaining.max_work),
          names_remaining,
        ) {
        Ok(value) => value
        Err(issue) => return Err(PivotFailure(issue))
      }
      names_remaining -= name_bytes
      remaining = { ..remaining, max_work: remaining.max_work - entries, }
      Pivot(pivot)
    }
    Aggregation => {
      let count_group = if node.payload is WindowGroup(_) {
        None
      } else {
        match
          prepare_count_group(
            checked,
            Int::min(max_bindings, remaining.max_work),
            names_remaining,
          ) {
          Ok(group) => Some(group)
          Err(UnsupportedAggregate(_)) => None
          Err(e) => return Err(CountGroupFailure(e))
        }
      }
      match count_group {
        Some(group) => {
          names_remaining -= group.name_bytes
          remaining = {
            ..remaining,
            max_work: remaining.max_work -
            group.keys.length() -
            group.counts.length(),
          }
          CountGroups(group)
        }
        None => {
          let (group, after_expressions) = match
            prepare_group(
              owner,
              step_index,
              Int::min(max_bindings, remaining.max_work),
              names_remaining,
              remaining,
            ) {
            Ok(value) => value
            Err(issue) => return Err(GroupFailure(issue))
          }
          let entries = group_entry_count(group)
          if entries > after_expressions.max_work {
            return Err(KernelBudgetExceeded)
          }
          names_remaining -= group_name_bytes(group)
          remaining = {
            ..after_expressions,
            max_work: after_expressions.max_work - entries,
          }
          Groups(group)
        }
      }
    }
    Reshape if @relation.operation(checked) == @relation.JsonPick => {
      guard @relation.json_pick_source(checked) is Some((column, output)) else {
        return Err(InvalidKernelWiring)
      }
      let count = @relation.json_pick_path_count(checked)
      if count <= 0 ||
        count > max_bindings - 2 ||
        count > remaining.max_work - 2 {
        return Err(KernelBudgetExceeded)
      }
      let path : Array[String] = []
      for name in [@schema.reference_name(column), output] {
        let size = @utf8.encode(name).length()
        if size > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= size
      }
      for i = 0; i < count; i = i + 1 {
        guard @relation.json_pick_path_at(checked, i) is Some(name) else {
          return Err(InvalidKernelWiring)
        }
        let size = @utf8.encode(name).length()
        if size > names_remaining {
          return Err(KernelBudgetExceeded)
        }
        names_remaining -= size
        path.push(name)
      }
      remaining = { ..remaining, max_work: remaining.max_work - count - 2, }
      JsonPick(column, path, output)
    }
    Projection | Reshape => return Err(MissingKernelNode)
  }
  let binding_count = match body {
    CountGroups(group) => group.keys.length() + group.counts.length()
    Groups(group) => group_entry_count(group)
    AnalyticRows(value) => analytic_entry_count(value)
    Pivot(value) => pivot_index_count(value) + pivot_axis_count(value) + 2
    SnapshotMap(bindings) | OrderedBindings(bindings) => bindings.length()
    Filter(_) | AssertAll(_) => 1
    AssertUnique(keys) => keys.length()
    JsonPick(_, path, _) => path.length() + 2
    Select(fields) => fields.length()
    Limit(_, _, _) =>
      take_completion(owner.prepared.owner, step_index)
      .map(@evidence.key_field_count)
      .unwrap_or(0)
    TopK(_, order) | PartitionedTopK(_, order) =>
      @relation.top_k_partition_count(checked) +
      @relation.ranking_term_count(checked) +
      @pipeline.order_sort_completion(order)
      .map(@pipeline.sort_completion_count)
      .unwrap_or(0)
    Unnest(_, _, index, _, _) => 2 + (if index is Some(_) { 1 } else { 0 })
    Unpivot(columns, keep, _, _) => columns.length() + keep.length() + 2
    StableSort(resolution) =>
      @relation.sort_term_count(checked) +
      resolution
      .map(order => {
        match @pipeline.sort_order_strategy(order) {
          CandidateKey(key) => @pipeline.sort_completion_count(key)
          ExistingTotal(_) => 0
        }
      })
      .unwrap_or(0)
    Lag(_, completion) =>
      @relation.lag_partition_count(checked) +
      @relation.lag_term_count(checked) +
      @pipeline.sort_completion_count(completion) +
      2
    Watermark(_, _, _, _) => 2
    DedupeRows =>
      @relation.dedupe_key_count(checked) +
      @relation.dedupe_order_count(checked)
    DistinctRows =>
      if node.projection_id is Some(_) {
        @schema.field_count(@relation.output_schema(checked))
      } else {
        0
      }
  }
  Ok(
    (
      { owner, step_index, input_id: node.inputs[0], checked, body, },
      remaining,
      max_name_bytes - names_remaining,
      binding_count,
    ),
  )
}
