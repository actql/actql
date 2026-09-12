///|
/// Exact selected extension; not an assertion of backend execution support.
struct RegisteredOrderedContract {
  relation : RegisteredRelationContracts
  cid : String
}

///|
pub(all) enum OrderedContractIssue {
  InvalidOrderedContractLimits
  OrderedContractBodyLimit
  OrderedContractMismatch
}

///|
pub fn admit_ordered_contract(
  relation : RegisteredRelationContracts,
  body : @identity.CanonicalValue,
  limits : RegistryLimits,
) -> Result[RegisteredOrderedContract, OrderedContractIssue] {
  if limits.max_body_bytes < 0 ||
    limits.max_body_nodes < 0 ||
    limits.max_body_depth < 0 {
    return Err(InvalidOrderedContractLimits)
  }
  let cid = @identity.cid_value(
    body,
    limits.max_body_bytes,
    limits.max_body_nodes,
    limits.max_body_depth,
  ) catch {
    _ => return Err(OrderedContractBodyLimit)
  }
  if cid != selected_ordered_contract_cid {
    return Err(OrderedContractMismatch)
  }
  Ok({ relation, cid, })
}

///|
/// References retain the only kernel from which bindings may be emitted.
/// A caller cannot attach this table to a different set of expressions.
struct OrderedParams {
  contract : RegisteredOrderedContract
  references : @lower.OrderedReferences
}

///|
pub fn prepare_ordered_params(
  contract : RegisteredOrderedContract,
  references : @lower.OrderedReferences,
) -> OrderedParams {
  { contract, references, }
}

///|
pub fn ordered_params_kernel(params : OrderedParams) -> @lower.PreparedKernel {
  @lower.ordered_reference_kernel(params.references)
}

///|
pub fn ordered_params_registry(
  params : OrderedParams,
) -> RegisteredRelationContracts {
  params.contract.relation
}

///|
/// Complete registered params, not a complete fragment or runnable Plan.
/// Context, limits and expression-root evidence remain enclosing obligations.
pub fn emit_ordered_params(
  params : OrderedParams,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  guard @lower.kernel_body(ordered_params_kernel(params))
    is @lower.OrderedBindings(bindings) else {
    raise @encode.InvalidStructure
  }
  @encode.begin_object(out)
  @encode.key(out, "bindings")
  @encode.begin_array(out)
  for (name, expr) in bindings {
    @encode.begin_object(out)
    @encode.key(out, "expr")
    @lower.emit_expression(expr, out)
    @encode.key(out, "name")
    @encode.string_value(out, name)
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "references")
  @lower.emit_ordered_references(params.references, out)
  @encode.key(out, "row_kernel_contract_cid")
  @encode.string_value(out, params.contract.cid)
  @encode.end_object(out)
}
