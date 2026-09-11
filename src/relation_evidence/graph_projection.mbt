///|
fn graph_projection_field(
  source : @decode.Cursor,
  records : @carrier.Knowledge,
  name : @row.FieldName,
  budget : TransferBudget,
) -> KeyField raise Stop {
  spend(budget, source, 1)
  charge(budget, source, name)
  match @carrier.lookup(records, name) {
    Present(field) => plain_key_field(name, field.contract)
    _ => fail(source, InputContractMismatch)
  }
}

///|
/// Graph identity is conditional on graph admission, not a raw row assertion.
/// Semantic source names are aliases of the bridge roles, not extra components.
pub fn graph_projection_keys(
  operation : @projection.CheckedProjection,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @projection.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let kind = @projection.operation(operation)
    if kind != @projection.NodeRows && kind != @projection.EdgeRows {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    let records = @carrier.relation_rows(@projection.output(operation)).unwrap()
    let witnesses : Array[KeyedRelation] = []
    if @projection.input(operation) is @carrier.GraphValue(graph) {
      let names = if kind == @projection.NodeRows {
        [@row.Unqualified("id")]
      } else {
        [
          @row.Unqualified("src"),
          @row.Unqualified("dst"),
          @row.Unqualified("rel"),
        ]
      }
      let source_names = match @carrier.graph_names(graph) {
        None => names
        Some(names) => {
          let (node, src, dst, rel) = @carrier.graph_row_fields(names)
          if kind == @projection.NodeRows {
            [node]
          } else {
            [src, dst, rel.unwrap_or(@row.Unqualified("rel"))]
          }
        }
      }
      let fields : Array[KeyField] = []
      let aliases : Array[Array[KeyField]] = []
      for i in 0..<names.length() {
        let field = graph_projection_field(source, records, names[i], b)
        fields.push(field)
        let copies = [field]
        if source_names[i] != names[i] {
          copies.push(
            graph_projection_field(source, records, source_names[i], b),
          )
        }
        aliases.push(copies)
      }
      witnesses.push({
        origin: GraphProjectionResult,
        producer: Some(GraphProjectionProducer(operation)),
        records,
        declared_records: records,
        declared_fields: fields,
        source,
        fields,
        aliases,
        usage: {
          fields: fields.length(),
          name_bytes: limits.max_name_bytes - b.text,
        },
      })
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}
