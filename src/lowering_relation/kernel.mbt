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
pub enum KernelBody {
  SnapshotMap(Array[(String, Expression)])
  OrderedBindings(Array[(String, Expression)])
  Filter(Expression)
  Select(Array[@relation.ProjectionField])
  Limit(Int64, Int64, @pipeline.LogicalOrder)
  DistinctRows
  DedupeRows
  StableSort(@pipeline.SortOrder?)
}

///|
pub(all) enum KernelIssue {
  MissingKernelNode
  InvalidKernelWiring
  KernelBudgetExceeded
  InvalidKernelLimits
  ExpressionFailure(ExpressionIssue)
  InvalidTakeCount
  PendingTakeOrder
  PendingSortOrder
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
/// Allocation-free batch selection view; the order remains owned by preparation.
pub fn kernel_take(kernel : PreparedKernel) -> (Int64, Int64)? {
  match kernel.body {
    Limit(count, offset, _) => Some((count, offset))
    SnapshotMap(_)
    | OrderedBindings(_)
    | Filter(_)
    | Select(_)
    | DistinctRows
    | DedupeRows
    | StableSort(_) => None
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
    | Select(_)
    | Limit(_, _, _)
    | DistinctRows
    | DedupeRows
    | StableSort(_) => None
  }
}

///|
pub fn kernel_body(kernel : PreparedKernel) -> KernelBody {
  match kernel.body {
    SnapshotMap(bindings) => SnapshotMap(bindings.copy())
    OrderedBindings(bindings) => OrderedBindings(bindings.copy())
    Filter(expr) => Filter(expr)
    Select(fields) => Select(fields.copy())
    Limit(count, offset, order) => Limit(count, offset, order)
    DistinctRows => DistinctRows
    DedupeRows => DedupeRows
    StableSort(order) => StableSort(order)
  }
}

///|
/// O(1), allocation-free number of entries copied by kernel_body.
pub fn kernel_view_entries(kernel : PreparedKernel) -> Int {
  match kernel.body {
    SnapshotMap(bindings) | OrderedBindings(bindings) => bindings.length()
    Select(fields) => fields.length()
    Filter(_) | Limit(_, _, _) | DistinctRows | DedupeRows | StableSort(_) => 0
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
    | Distinct(op)
    | Dedupe(op)
    | Sort(op) => op
    Values(_) => return Err(MissingKernelNode)
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
    Projection | Reshape | Aggregation => return Err(MissingKernelNode)
  }
  let binding_count = match body {
    SnapshotMap(bindings) | OrderedBindings(bindings) => bindings.length()
    Filter(_) => 1
    Select(fields) => fields.length()
    Limit(_, _, _) =>
      take_completion(owner.prepared.owner, step_index)
      .map(@evidence.key_field_count)
      .unwrap_or(0)
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
