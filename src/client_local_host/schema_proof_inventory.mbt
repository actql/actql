///|
/// One work-bounded inventory per original prepared owner. Shared task views
/// reuse checked schema facts, never storage: repeated ports remain counted.
priv struct ClientLocalSchemaProofInventory {
  original_count : Int
  owner_count : Int
  work_used : Int
  max_node_width : Int64
  max_name_width : Int64
  fields : Int
  names : Int
  ports : Int
  bindings : Int
  closed_rows : Int?
}

///|
fn client_local_schema_proof_work() -> Int {
  // This proof phase has its own counter, like the existing graph preparation
  // phase. It is not represented as aggregate compiler/Run work consumption.
  @publication_host.client_standard_program_preparation_limits().max_graph_work
}

///|
fn client_local_schema_proof_inventory(
  sequences : Array[@execution.GeneratedSequence],
  max_work? : Int = client_local_schema_proof_work(),
  graph? : @strategy.CheckedDAG? = None,
  scalar_only? : Bool = true,
) -> ClientLocalSchemaProofInventory? {
  if sequences.is_empty() || max_work < 1 || sequences.length() > max_work { return None }
  if graph is Some(original) && sequences.length()!=@strategy.graph_task_count(original) { return None }
  let mut remaining=max_work
  let seen : Array[@lower.BoundPrepared]=[]
  let mut nodes=1L
  let mut names_total=0L
  let mut fields=0
  let mut names=0
  let mut ports=0
  let mut bindings=0
  let mut closed_rows : Int?=Some(0)
  for index,sequence in sequences {
    if remaining<1 {return None}
    remaining-=1
    let owner=@execution.generated_sequence_owner(sequence)
    if graph is Some(original) && !(@strategy.graph_task_owner(original,index) is Some(expected) && physical_equal(owner,expected)) {return None}
    let mut found=false
    for previous in seen {
      if remaining<1 {return None}
      remaining-=1
      if physical_equal(previous,owner) {found=true;break}
    }
    if found {continue}
    seen.push(owner)
    let prepared=@lower.bound_preparation(owner)
    let inputs=@lower.preparation_input_count(prepared)
    let rows : Array[Int?]=[]
    if inputs!=0 {closed_rows=None}
    ports=Int::max(ports,inputs)
    bindings=Int::max(bindings,inputs)
    let mut input_nodes=0L
    let mut output_nodes=0L
    let mut input_names=0L
    let mut output_names=0L
    for input in 0..<inputs {
      guard @lower.preparation_input_schema(prepared,input) is Some(schema) else {return None}
      let width=@schema.field_count(schema)
      if remaining<1 || width>remaining-1 {return None}
      remaining-=width+1
      if scalar_only && client_local_scalar_schema_width(schema) is None {return None}
      let name_bytes=@schema.field_reference_name_bytes(schema)
      if name_bytes<0 {return None}
      fields=Int::max(fields,width);names=Int::max(names,name_bytes)
      input_nodes+=width.to_int64()+1L;output_nodes+=width.to_int64()+1L
      input_names+=name_bytes.to_int64();output_names+=name_bytes.to_int64()
    }
    for node_index in 0..<@lower.node_count(prepared) {
      guard @lower.node_at(prepared,node_index) is Some(node) && @lower.node_relation_schema(node) is Some(schema) else {return None}
      let row_ports=@lower.node_input_count(node)
      if row_ports>remaining {return None}
      remaining-=row_ports
      let input_rows : Array[Int]=[]
      let mut known=true
      for port in 0..<row_ports {
        match @lower.node_input_target(node,port) {
          Some(@pipeline.Step(index)) => match rows.get(index) {Some(Some(count)) => input_rows.push(count); _ => known=false}
          _ => known=false
        }
      }
      let bound=if known {@lower.node_row_count_bound(node,input_rows)} else {None}
      rows.push(bound)
      closed_rows=match (closed_rows,bound) {(Some(previous),Some(count))=>Some(Int::max(previous,count)); _=>None}
      let width=@schema.field_count(schema)
      if remaining<1 || width>remaining-1 {return None}
      remaining-=width+1
      if scalar_only && client_local_scalar_schema_width(schema) is None {return None}
      let name_bytes=@schema.field_reference_name_bytes(schema)
      if name_bytes<0 {return None}
      fields=Int::max(fields,width);names=Int::max(names,name_bytes)
      output_nodes+=width.to_int64()+1L;output_names+=name_bytes.to_int64()
      let count=@lower.node_input_count(node)
      ports=Int::max(ports,count);bindings=Int::max(bindings,count)
      for port in 0..<count {
        guard @lower.node_input_target(node,port) is Some(target) && @lower.preparation_schema_at(prepared,target) is Some(input_schema) else {return None}
        let width=@schema.field_count(input_schema)
        if remaining<1 || width>remaining-1 {return None}
        remaining-=width+1
        if scalar_only && client_local_scalar_schema_width(input_schema) is None {return None}
        let name_bytes=@schema.field_reference_name_bytes(input_schema)
        if name_bytes<0 {return None}
        input_nodes+=width.to_int64()+1L;input_names+=name_bytes.to_int64()
      }
    }
    nodes=Int64::max(nodes,Int64::max(input_nodes,output_nodes))
    names_total=Int64::max(names_total,Int64::max(input_names,output_names))
  }
  Some({original_count:sequences.length(),owner_count:seen.length(),work_used:max_work-remaining,max_node_width:nodes,max_name_width:names_total,fields,names,ports,bindings,closed_rows})
}

///|
fn client_local_inventory_nodes(inventory : ClientLocalSchemaProofInventory,max_rows : Int) -> Int? {
  client_local_scalar_product(inventory.max_node_width,max_rows,3)
}

///|
fn client_local_inventory_names(inventory : ClientLocalSchemaProofInventory,max_rows : Int) -> Int? {
  client_local_scalar_product(inventory.max_name_width,max_rows,0)
}
