///|
pub(all) struct Limits {
  max_work : Int
  max_order_keys : Int
}

///|
pub enum Issue {
  InvalidLimits
  WorkLimit
  OrderLimit
  Decode(@decode.Issue)
  InvalidValue(@decode.Cursor)
  InvalidMetadata(@decode.Cursor)
  Order(@order.Issue)
}

///|
pub(all) enum ScanMode {
  Snapshot
  Changes
} derive(Eq, Debug)

///|
pub struct Declaration {
  stage_index : Int
  input_name : String
  source : @decode.Cursor
  connector : String
  resource : String
  view : String?
  request : @decode.Cursor?
  scan : ScanMode?
  minimum_classification : String?
  priv order : Array[@order.Key]?
}

///|
struct Inputs {
  source : @stages.Source
  entries : Array[Declaration]
  by_name : Map[(Int, String), Declaration]
  work : Int
}

///|
priv struct Budget {
  mut work : Int
  mut orders : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn spend(b : Budget, n : Int) -> Unit raise Stop {
  if n > b.work {
    raise Stop(WorkLimit)
  }
  b.work -= n
}

///|
fn[T] decoded(value : Result[T, @decode.Issue]) -> T raise Stop {
  match value {
    Ok(v) => v
    Err(e) => raise Stop(Decode(e))
  }
}

///|
fn nonempty(at : @decode.Cursor) -> String raise Stop {
  let text = decoded(@decode.text(at))
  if text.is_empty() {
    raise Stop(InvalidValue(at))
  }
  text
}

///|
// Source owns normalized, scalar-valid JSON. Visit nested data only to account
// for work; neither metadata nor request business data is executable syntax.
fn preflight(at : @decode.Cursor, b : Budget) -> Unit raise Stop {
  let pending = [at]
  while pending.pop() is Some(at) {
    spend(b, 1)
    if @decode.object_length(at) is Some(n) {
      spend(b, n)
      for i in 0..<n {
        let (key, child) = @decode.field_at(at, i).unwrap()
        spend(b, key.length())
        pending.push(child)
      }
    } else if @decode.array_length(at) is Some(n) {
      spend(b, n)
      for i in 0..<n {
        pending.push(@decode.element_at(at, i).unwrap())
      }
    } else if @decode.view(at) is TextValue(text) {
      spend(b, text.length())
    }
  }
}

///|
fn read_input(
  at : @decode.Cursor,
  stage_index : Int,
  input_name : String,
  b : Budget,
) -> Declaration raise Stop {
  preflight(at, b)
  let body = decoded(
    @decode.closed_object(at, [
      "connector", "resource", "view", "request", "scan", "minimum_classification",
      "meta", "duplicates",
    ]),
  )
  let connector = nonempty(decoded(@decode.required(body, "connector")))
  let resource = nonempty(decoded(@decode.required(body, "resource")))
  let view = match @decode.lookup(body, "view") {
    None => None
    Some(v) => Some(nonempty(v))
  }
  let request = @decode.lookup(body, "request")
  if request is Some(v) {
    let _ = decoded(@decode.open_object(v))
    if @decode.object_length(v).unwrap() == 0 {
      raise Stop(InvalidValue(v))
    }
  }
  let scan = match @decode.lookup(body, "scan") {
    None => None
    Some(v) => {
      let scan = decoded(@decode.closed_object(v, ["mode"]))
      let mode = decoded(@decode.required(scan, "mode"))
      match decoded(@decode.text(mode)) {
        "snapshot" => Some(Snapshot)
        "changes" => Some(Changes)
        _ => raise Stop(InvalidValue(mode))
      }
    }
  }
  let minimum_classification = match
    @decode.lookup(body, "minimum_classification") {
    None => None
    Some(v) =>
      match decoded(@decode.text(v)) {
        "public" => Some("public")
        "internal" => Some("internal")
        "confidential" => Some("confidential")
        "restricted" => Some("restricted")
        _ => raise Stop(InvalidValue(v))
      }
  }
  if @decode.lookup(body, "meta") is Some(v) {
    let _ = decoded(@decode.open_object(v))
    let n = @decode.object_length(v).unwrap()
    if n == 0 {
      raise Stop(InvalidMetadata(v))
    }
    for i in 0..<n {
      let (key, child) = @decode.field_at(v, i).unwrap()
      if key.has_prefix("actql_") {
        raise Stop(InvalidMetadata(child))
      }
    }
  }
  let order = match @decode.lookup(body, "duplicates") {
    None => None
    Some(v) =>
      if @decode.view(v) is TextValue("reject") {
        None
      } else {
        let policy = decoded(@decode.closed_object(v, ["first_by_order"]))
        let first = decoded(@decode.required(policy, "first_by_order"))
        let first = decoded(@decode.closed_object(first, ["order_by"]))
        let terms = decoded(@decode.required(first, "order_by"))
        let n = match @decode.array_length(terms) {
          Some(n) => n
          None => raise Stop(InvalidValue(terms))
        }
        if n == 0 {
          raise Stop(InvalidValue(terms))
        }
        if n > b.orders {
          raise Stop(OrderLimit)
        }
        b.orders -= n
        let keys = []
        for i in 0..<n {
          let key = match @order.read(@decode.element_at(terms, i).unwrap()) {
            Ok(key) => key
            Err(e) => raise Stop(Order(e))
          }
          spend(b, key.work)
          keys.push(key)
        }
        Some(keys)
      }
  }
  {
    stage_index,
    input_name,
    source: at,
    connector,
    resource,
    view,
    request,
    scan,
    minimum_classification,
    order,
  }
}

///|
/// Collect connector/resource inputs only. Local declarations and stage imports
/// have separate admission. No Catalog selection or authority is inferred.
pub fn collect(
  source : @stages.Source,
  limits : Limits,
) -> Result[Inputs, Issue] {
  if limits.max_work < 0 || limits.max_order_keys < 0 {
    return Err(InvalidLimits)
  }
  let b : Budget = { work: limits.max_work, orders: limits.max_order_keys, }
  try {
    let entries = []
    let by_name : Map[(Int, String), Declaration] = Map([])
    spend(b, @stages.stage_count(source))
    for s in 0..<@stages.stage_count(source) {
      let stage = @stages.stage_at(source, s).unwrap()
      let root = decoded(@decode.open_object(@stage.stage_body(stage)))
      let inputs = decoded(@decode.required(root, "inputs"))
      let n = @decode.object_length(inputs).unwrap()
      spend(b, n)
      for i in 0..<n {
        let (name, at) = @decode.field_at(inputs, i).unwrap()
        spend(b, name.length())
        if @decode.object_length(at) is Some(n) {
          spend(b, n)
          let object = decoded(@decode.open_object(at))
          if @decode.lookup(object, "connector") is Some(_) ||
            @decode.lookup(object, "resource") is Some(_) {
            let declaration = read_input(at, s, name, b)
            entries.push(declaration)
            by_name[(s, name)] = declaration
          }
        }
      }
    }
    Ok({ source, entries, by_name, work: limits.max_work - b.work, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn source(v : Inputs) -> @stages.Source {
  v.source
}

///|
pub fn count(v : Inputs) -> Int {
  v.entries.length()
}

///|
pub fn at(v : Inputs, i : Int) -> Declaration? {
  v.entries.get(i)
}

///|
/// Indexed source-owned lookup; equal names in other stages are distinct slots.
pub fn input_for(v : Inputs, stage_index : Int, name : String) -> Declaration? {
  v.by_name.get((stage_index, name))
}

///|
pub fn work(v : Inputs) -> Int {
  v.work
}

///|
pub fn first_by_order(v : Declaration) -> Array[@order.Key]? {
  v.order.map(xs => xs.copy())
}
