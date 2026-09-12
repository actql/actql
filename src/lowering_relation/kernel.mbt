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
}

///|
pub(all) enum KernelIssue {
  MissingKernelNode
  InvalidKernelWiring
  KernelBudgetExceeded
  InvalidKernelLimits
  ExpressionFailure(ExpressionIssue)
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
/// Indexed immutable binding view, without copying the complete slot array.
pub fn ordered_binding_at(
  kernel : PreparedKernel,
  index : Int,
) -> (String, Expression)? {
  match kernel.body {
    OrderedBindings(bindings) => bindings.get(index)
    SnapshotMap(_) | Filter(_) | Select(_) => None
  }
}

///|
pub fn kernel_body(kernel : PreparedKernel) -> KernelBody {
  match kernel.body {
    SnapshotMap(bindings) => SnapshotMap(bindings.copy())
    OrderedBindings(bindings) => OrderedBindings(bindings.copy())
    Filter(expr) => Filter(expr)
    Select(fields) => Select(fields.copy())
  }
}

///|
/// O(1), allocation-free number of entries copied by kernel_body.
pub fn kernel_view_entries(kernel : PreparedKernel) -> Int {
  match kernel.body {
    SnapshotMap(bindings) | OrderedBindings(bindings) => bindings.length()
    Select(fields) => fields.length()
    Filter(_) => 0
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
    Derive(op) | Where(op) | Select(op) => op
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
    Projection => {
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
      Select(fields)
    }
    RowOperation | Reshape | Aggregation => return Err(MissingKernelNode)
  }
  let binding_count = match body {
    SnapshotMap(bindings) | OrderedBindings(bindings) => bindings.length()
    Filter(_) => 1
    Select(fields) => fields.length()
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
