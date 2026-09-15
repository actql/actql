///|
/// Owned static components of the shared requirement. This is deliberately not
/// a complete requirement/Plan: Program identity and logical guard selection
/// must be connected separately, without a placeholder requirement CID.
struct QueryMaterial {
  owner : @query.QuerySequence
  request : @encode.EncodedDocument
  request_cid : String
  filter_cid : String
  parameter_values_cid : String
  work : Int
  bytes : Int
  nodes : Int
}

///|
pub(all) struct QueryMaterialLimits {
  max_work : Int
  max_fields : Int
  max_parameters : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum QueryMaterialIssue {
  InvalidLimits
  WorkLimit
  FieldLimit
  ParameterLimit
  InvalidQuery
  UnboundRequest
  MissingParameter(String)
  Encoding(@encode.EncodeFailure)
}

///|
struct QueryMaterialBudget {
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  depth : Int
}

///|
priv suberror QueryMaterialStop {
  QueryMaterialStop(QueryMaterialIssue)
}

///|
fn material_spend(
  b : QueryMaterialBudget,
  work : Int,
) -> Unit raise QueryMaterialStop {
  if work < 0 || work > b.work {
    raise QueryMaterialStop(WorkLimit)
  }
  b.work -= work
}

///|
fn material_select_parameter(
  names : Map[String, Unit],
  name : String,
  limit : Int,
  budget : QueryMaterialBudget,
) -> Unit raise QueryMaterialStop {
  material_spend(budget, 1)
  material_spend(budget, name.length())
  if !names.contains(name) {
    if names.length() >= limit {
      raise QueryMaterialStop(ParameterLimit)
    }
    names[name] = ()
  }
}

///|
fn material_hash(
  budget : QueryMaterialBudget,
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(budget.bytes, budget.nodes, budget.depth)
  emit(writer)
  let (hash, bytes, nodes) = @encode.finish_hash_usage(writer)
  budget.bytes -= bytes
  budget.nodes -= nodes
  "sha256:" + hash
}

///|
/// No request parsing, name resolution or predicate evaluation is repeated.
/// Substitution follows only the checked request field's binding tag. The
/// complete selected Parameter map uses the shared typed value emitter.
pub fn prepare_query_material(
  owner : @query.QuerySequence,
  limits : QueryMaterialLimits,
) -> Result[QueryMaterial, QueryMaterialIssue] {
  if limits.max_work < 0 ||
    limits.max_fields < 0 ||
    limits.max_parameters < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let budget = {
    work: limits.max_work,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  try {
    material_spend(budget, 1)
    let query = @query.query_sequence_requirement(owner)
    guard @acquisition.pipeline_request_at(
        @acquisition.query_acquisition_owner(query),
        @acquisition.query_acquisition_source_index(query),
      )
      is Some(@acquisition.Direct(_, request)) else {
      return Err(InvalidQuery)
    }
    if @acquisition.parameterized_request_host_binding_count(request) != 0 {
      return Err(UnboundRequest)
    }
    let count = @acquisition.parameterized_request_field_count(request)
    if count > limits.max_fields {
      return Err(FieldLimit)
    }
    material_spend(budget, count)
    let fields : Array[(String, @admitted.Value)] = []
    let used : Map[String, Unit] = Map([])
    for i in 0..<count {
      let field = @acquisition.parameterized_request_field_at(request, i).unwrap()
      let name = field.field.slot.field_name
      material_spend(budget, name.length())
      let value = match field.value {
        CheckedLiteral(checked) => checked.value
        BoundParameter(parameter) => {
          material_select_parameter(
            used,
            parameter.name,
            limits.max_parameters,
            budget,
          )
          parameter.value.value
        }
        UnboundHostBinding(_) => return Err(UnboundRequest)
      }
      // Request member order is not trusted as canonical order. Bound every
      // comparison before insertion; duplicate fields cannot be silently merged.
      let mut position = fields.length()
      while position > 0 {
        let previous = fields[position - 1].0
        material_spend(budget, 1)
        material_spend(budget, previous.length())
        material_spend(budget, name.length())
        let cmp = @canonical.compare_utf16(previous, name)
        if cmp == 0 {
          return Err(InvalidQuery)
        }
        if cmp < 0 {
          break
        }
        position -= 1
      }
      fields.push((name, value))
      for j = fields.length() - 1; j > position; j = j - 1 {
        fields[j] = fields[j - 1]
      }
      fields[position] = (name, value)
    }
    let filter = @acquisition.query_acquisition_filter(query)
    // binding_at copies references. Conservatively precharge the checker's
    // complete operation work before that copy, not after allocating it.
    material_spend(budget, @relation.work_used(filter))
    guard @relation.binding_count(filter) == 1 &&
      @relation.binding_at(filter, 0) is Some(binding) else {
      return Err(InvalidQuery)
    }
    let expression = @typing.expression(binding.expression)
    let occurrences = match
      @expression.collect_parameter_occurrences(
        expression,
        max_work=budget.work,
      ) {
      Ok(value) => value
      Err(_) => return Err(WorkLimit)
    }
    material_spend(budget, @expression.parameter_occurrence_work(occurrences))
    for i in 0..<@expression.parameter_occurrence_count(occurrences) {
      material_select_parameter(
        used,
        @expression.parameter_occurrence_at(occurrences, i).unwrap().name,
        limits.max_parameters,
        budget,
      )
    }
    let parameters = @acquisition.request_parameter_values(
      @acquisition.parameterized_request_parameters(request),
    )
    material_spend(budget, @parameter.bound_value_count(parameters))
    let selected : Array[@parameter.BoundParameter] = []
    // BoundValues already uses canonical declaration-name order. Repeated
    // occurrences select one value; binding origin and unused names stay out.
    for i in 0..<@parameter.bound_value_count(parameters) {
      let parameter = @parameter.bound_value_at(parameters, i).unwrap()
      material_spend(budget, parameter.name.length())
      if used.contains(parameter.name) {
        selected.push(parameter)
        used.remove(parameter.name)
      }
    }
    if used.length() != 0 {
      // At most max_parameters names were retained under the work budget.
      for name, _ in used {
        return Err(MissingParameter(name))
      }
    }
    let artifacts = try {
      let filter_cid = material_hash(budget, writer => {
        @expression.emit_source(expression, writer)
      })
      let parameter_values_cid = material_hash(budget, writer => {
        @encode.begin_object(writer)
        @encode.key(writer, "values")
        @encode.begin_object(writer)
        for parameter in selected {
          @encode.key(writer, parameter.name)
          @parameter.emit_value_identity(parameter, writer)
        }
        @encode.end_object(writer)
        @encode.key(writer, "version")
        @encode.string_value(writer, "actql-parameter-values/0.1")
        @encode.end_object(writer)
      })
      // Reserve both equally sized traversals before constructing the document.
      let request_writer = @encode.writer(
        budget.bytes / 2,
        budget.nodes / 2,
        budget.depth,
      )
      @encode.begin_object(request_writer)
      for (name, value) in fields {
        @encode.key(request_writer, name)
        @admitted.emit_wire_value(value, request_writer)
      }
      @encode.end_object(request_writer)
      let request = @encode.finish_document(request_writer)
      // Charge both encoding and hashing, rather than hiding the retained request
      // text. The second pass obtains exact writer node usage as well as its CID.
      let before_nodes = budget.nodes
      let request_cid = material_hash(budget, writer => {
        @encode.emit_document(writer, request)
      })
      let bytes = @encode.document_bytes(request)
      budget.bytes -= bytes
      budget.nodes -= before_nodes - budget.nodes
      Ok((request, request_cid, filter_cid, parameter_values_cid))
    } catch {
      issue => Err(issue)
    }
    let (request, request_cid, filter_cid, parameter_values_cid) = match
      artifacts {
      Ok(value) => value
      Err(issue) => return Err(Encoding(issue))
    }
    Ok({
      owner,
      request,
      request_cid,
      filter_cid,
      parameter_values_cid,
      work: limits.max_work - budget.work,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    })
  } catch {
    QueryMaterialStop(issue) => Err(issue)
  }
}

///|
pub fn query_material_owner(value : QueryMaterial) -> @query.QuerySequence {
  value.owner
}

///|
pub fn query_material_request(value : QueryMaterial) -> @encode.EncodedDocument {
  value.request
}

///|
pub fn query_material_cids(value : QueryMaterial) -> (String, String, String) {
  (value.request_cid, value.filter_cid, value.parameter_values_cid)
}

///|
pub fn query_material_usage(value : QueryMaterial) -> (Int, Int, Int) {
  (value.work, value.bytes, value.nodes)
}
