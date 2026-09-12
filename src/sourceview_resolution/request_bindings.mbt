///|
pub enum BindingRequest {
  DirectBindingRequest(ParameterizedRequest)
  KeyedBindingRequest(ParameterizedKeyedRequest)
}

///|
pub(all) enum RequestBindingsIssue {
  InvalidLimits
  WorkLimit
  BindingLimit
} derive(Eq, Debug)

///|
/// Outstanding Host admission requirements, not accepted Reference values.
struct RequestBindings {
  request : BindingRequest
  indices : Array[Int]
  work : Int
}

///|
pub fn direct_request_bindings(
  request : ParameterizedRequest,
  max_work : Int,
  max_bindings : Int,
) -> Result[RequestBindings, RequestBindingsIssue] {
  collect_bindings(
    DirectBindingRequest(request),
    request.fields,
    request.host_bindings,
    max_work,
    max_bindings,
  )
}

///|
pub fn keyed_request_bindings(
  request : ParameterizedKeyedRequest,
  max_work : Int,
  max_bindings : Int,
) -> Result[RequestBindings, RequestBindingsIssue] {
  collect_bindings(
    KeyedBindingRequest(request),
    request.fields,
    request.host_bindings,
    max_work,
    max_bindings,
  )
}

///|
fn collect_bindings(
  request : BindingRequest,
  fields : Array[ParameterizedRequestField],
  count : Int,
  max_work : Int,
  max_bindings : Int,
) -> Result[RequestBindings, RequestBindingsIssue] {
  if max_work < 0 || max_bindings < 0 {
    return Err(InvalidLimits)
  }
  if count > max_bindings {
    return Err(BindingLimit)
  }
  // Charge before allocating, without first copying the full request field array.
  if max_work == 0 || fields.length() > max_work - 1 {
    return Err(WorkLimit)
  }
  let indices = []
  for i in 0..<fields.length() {
    if fields[i].value is UnboundHostBinding(_) {
      indices.push(i)
    }
  }
  Ok({ request, indices, work: fields.length() + 1, })
}

///|
pub fn request_bindings_request(v : RequestBindings) -> BindingRequest {
  v.request
}

///|
pub fn request_bindings_count(v : RequestBindings) -> Int {
  v.indices.length()
}

///|
pub fn request_bindings_work(v : RequestBindings) -> Int {
  v.work
}

///|
/// Original request-field index; repeated declaration uses are not deduplicated.
pub fn request_binding_index(v : RequestBindings, i : Int) -> Int? {
  v.indices.get(i)
}

///|
/// The field retains its exact source slot, expected type and Binding declaration.
pub fn request_binding_at(
  v : RequestBindings,
  i : Int,
) -> ParameterizedRequestField? {
  v.indices
  .get(i)
  .bind(index => {
    match v.request {
      DirectBindingRequest(request) => request.fields.get(index)
      KeyedBindingRequest(request) => request.fields.get(index)
    }
  })
}
