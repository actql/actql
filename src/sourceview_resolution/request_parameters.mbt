///|
pub(all) enum RequestParameterIssue {
  InvalidLimits
  ForeignDeclarations
  ForeignRequest
  WorkLimit
  MissingParameter(String)
} derive(Eq, Debug)

///|
struct RequestParameters {
  context : RequestContext
  values : @references.PreparedValues
  work : Int
}

///|
pub enum ParameterizedRequestValue {
  CheckedLiteral(@value.CheckedValue)
  BoundParameter(@parameters.BoundParameter)
  UnboundHostBinding(@bindings.Declaration)
}

///|
pub struct ParameterizedRequestField {
  field : RequestField
  value : ParameterizedRequestValue
}

///|
struct ParameterizedRequest {
  request : DirectRequest
  parameters : RequestParameters
  fields : Array[ParameterizedRequestField]
  work : Int
  host_bindings : Int
}

///|
struct ParameterizedKeyedRequest {
  request : KeyedRequest
  parameters : RequestParameters
  fields : Array[ParameterizedRequestField]
  work : Int
  host_bindings : Int
}

///|
/// Creates one reusable binding index for the exact request declaration owner.
pub fn prepare_request_parameters(
  context : RequestContext,
  values : @parameters.BoundValues,
  max_work : Int,
) -> Result[RequestParameters, RequestParameterIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(
      @parameters.bound_declarations(values),
      @stages.declarations(@slots.source(context.slots)),
    ) {
    return Err(ForeignDeclarations)
  }
  if context.work > max_work {
    return Err(WorkLimit)
  }
  let indexed = match
    @references.prepare_values(values, max_work=max_work - context.work) {
    Ok(v) => v
    Err(_) => return Err(WorkLimit)
  }
  Ok({
    context,
    values: indexed,
    work: context.work + @references.prepared_work(indexed),
  })
}

///|
/// Binds Parameter occurrences only. Retains typed Parameter rules and leaves
/// Host bindings explicit; this is neither wire materialization nor authority.
pub fn bind_request_parameters(
  parameters : RequestParameters,
  request : DirectRequest,
  max_work : Int,
) -> Result[ParameterizedRequest, RequestParameterIssue] {
  bind_request_fields(parameters, request.data, max_work).map(result => {
    let (fields, work, host_bindings) = result
    { request, parameters, fields, work, host_bindings, }
  })
}

///|
pub fn bind_keyed_request_parameters(
  parameters : RequestParameters,
  request : KeyedRequest,
  max_work : Int,
) -> Result[ParameterizedKeyedRequest, RequestParameterIssue] {
  bind_request_fields(parameters, request.data, max_work).map(result => {
    let (fields, work, host_bindings) = result
    { request, parameters, fields, work, host_bindings, }
  })
}

///|
fn bind_request_fields(
  parameters : RequestParameters,
  request : RequestData,
  max_work : Int,
) -> Result[(Array[ParameterizedRequestField], Int, Int), RequestParameterIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(parameters.context, request.context) {
    return Err(ForeignRequest)
  }
  let mut remaining = max_work
  let mut host_bindings = 0
  let fields = []
  for field in request.fields {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let value = match field.value {
      LiteralValue(value) => CheckedLiteral(value)
      ParameterValue(declaration) => {
        if declaration.name.length() > remaining {
          return Err(WorkLimit)
        }
        remaining -= declaration.name.length()
        let value = match
          @references.prepared_value_for(
            parameters.values,
            @stages.declarations(@slots.source(parameters.context.slots)),
            declaration.name,
          ) {
          Some(v) => v
          None => return Err(MissingParameter(declaration.name))
        }
        BoundParameter(value)
      }
      BindingValue(declaration) => {
        host_bindings += 1
        UnboundHostBinding(declaration)
      }
    }
    fields.push({ field, value, })
  }
  Ok((fields, max_work - remaining, host_bindings))
}

///|
pub fn parameterized_keyed_request(
  v : ParameterizedKeyedRequest,
) -> KeyedRequest {
  v.request
}

///|
pub fn parameterized_keyed_request_parameters(
  v : ParameterizedKeyedRequest,
) -> RequestParameters {
  v.parameters
}

///|
pub fn parameterized_keyed_request_field_count(
  v : ParameterizedKeyedRequest,
) -> Int {
  v.fields.length()
}

///|
pub fn parameterized_keyed_request_field_at(
  v : ParameterizedKeyedRequest,
  i : Int,
) -> ParameterizedRequestField? {
  v.fields.get(i)
}

///|
pub fn parameterized_keyed_request_work(v : ParameterizedKeyedRequest) -> Int {
  v.work
}

///|
pub fn parameterized_keyed_request_host_binding_count(
  v : ParameterizedKeyedRequest,
) -> Int {
  v.host_bindings
}

///|
pub fn request_parameter_context(v : RequestParameters) -> RequestContext {
  v.context
}

///|
pub fn request_parameter_values(
  v : RequestParameters,
) -> @parameters.BoundValues {
  @references.prepared_values(v.values)
}

///|
pub fn request_parameter_work(v : RequestParameters) -> Int {
  v.work
}

///|
pub fn parameterized_request(v : ParameterizedRequest) -> DirectRequest {
  v.request
}

///|
pub fn parameterized_request_parameters(
  v : ParameterizedRequest,
) -> RequestParameters {
  v.parameters
}

///|
pub fn parameterized_request_field_count(v : ParameterizedRequest) -> Int {
  v.fields.length()
}

///|
pub fn parameterized_request_field_at(
  v : ParameterizedRequest,
  i : Int,
) -> ParameterizedRequestField? {
  v.fields.get(i)
}

///|
pub fn parameterized_request_work(v : ParameterizedRequest) -> Int {
  v.work
}

///|
pub fn parameterized_request_host_binding_count(
  v : ParameterizedRequest,
) -> Int {
  v.host_bindings
}
