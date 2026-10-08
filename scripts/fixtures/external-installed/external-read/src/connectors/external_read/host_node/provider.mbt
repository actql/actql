// A separately compiled provider. Only bytes, strings and integers cross its
// JS boundary; every declaration, acquisition and capture handle stays in
// the injected common Host runtime.

///|
fn refused() -> String {
  ({ "refused": "InvalidExternalReadPage" } : Json).stringify()
}

///|
fn field(fields : Array[@source.Field], name : String) -> @source.Value? {
  for item in fields {
    if item.key == name {
      return Some(item.value.value)
    }
  }
  None
}

///|
#export_name("externalReadRequestJson")
pub fn external_read_request_json(page : Int) -> String {
  if page < 0 || page > 1 {
    return refused()
  }
  ({ "path": ("/records?page=" + page.to_string()).to_json() } : Json).stringify()
}

///|
#export_name("externalReadPageJson")
pub fn external_read_page_json(body : Bytes, page : Int) -> String {
  if page < 0 || page > 1 {
    return refused()
  }
  guard @source.parse_json_bytes_preserving(body, {
      max_input_bytes: 4096,
      max_nodes: 32,
      max_depth: 4,
    })
    is Ok(node) else {
    return refused()
  }
  guard node.value is Object(root) && root.length() == 2 else {
    return refused()
  }
  guard field(root, "items") is Some(Array(items)) && items.length() <= 2 else {
    return refused()
  }
  let rows : Array[Json] = []
  for item in items {
    guard item.value is Object(fields) && fields.length() == 2 else {
      return refused()
    }
    guard field(fields, "key") is Some(String(id)) &&
      !id.is_empty() &&
      id.length() <= 64 else {
      return refused()
    }
    guard field(fields, "amount") is Some(Number(amount)) else {
      return refused()
    }
    rows.push({ "id": id.to_json(), "amount": amount.to_json() })
  }
  let next : Json = match field(root, "next") {
    Some(Null) => Json::null()
    Some(Number(value)) if page == 0 && value == 1.0 => (1).to_json()
    _ => return refused()
  }
  ({ "rows": rows.to_json(), "next": next } : Json).stringify()
}
