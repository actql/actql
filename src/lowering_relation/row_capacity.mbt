///|
/// A cardinality fact about the original checked node, not execution authority.
/// Unknown/expanding operations deliberately return None. Input occurrences are
/// positional, so repeated Append inputs contribute independently.
pub fn node_row_count_bound(node : PreparedNode, inputs : Array[Int]) -> Int? {
  if inputs.length()!=node.input_targets.length() {return None}
  for count in inputs {if count<0 {return None}}
  match node.payload {
    Values(values) => Some(@values.row_count(values))
    Derive(_) | Where(_) | Select(_) | Limit(_) | TopK(_) | TopKBy(_)
    | Distinct(_) | Dedupe(_) | Sort(_) | AssertRows(_) =>
      if inputs.length()==1 {Some(inputs[0])} else {None}
    CountGroup(_) => if inputs.length()==1 {Some(Int::max(1,inputs[0]))} else {None}
    AppendRows(_) => {
      let mut total=0L
      for count in inputs {total+=count.to_int64()}
      if total>2147483647L {None} else {Some(total.to_int())}
    }
    _ => None
  }
}

///|
/// Work-bounded closed-pipeline cardinality certificate. The returned work is
/// debited by a caller composing multiple original owners; external inputs or
/// unknown cardinality operations cannot borrow an assumed row count.
pub fn prepared_closed_row_bound(prepared : Prepared,max_work : Int) -> (Int,Int)? {
  if max_work<0 || preparation_input_count(prepared)!=0 {return None}
  let count=node_count(prepared)
  if count>max_work {return None}
  let mut remaining=max_work-count
  let bounds : Array[Int]=[]
  let mut maximum=0
  for index in 0..<count {
    guard node_at(prepared,index) is Some(node) else {return None}
    let ports=node_input_count(node)
    if ports>remaining {return None}
    remaining-=ports
    let inputs : Array[Int]=[]
    for port in 0..<ports {
      guard node_input_target(node,port) is Some(@pipeline.Step(step)) && bounds.get(step) is Some(rows) else {return None}
      inputs.push(rows)
    }
    guard node_row_count_bound(node,inputs) is Some(rows) else {return None}
    bounds.push(rows)
    maximum=Int::max(maximum,rows)
  }
  Some((maximum,max_work-remaining))
}
