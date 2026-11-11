///|
/// Construction DATA from the same original Task and exact Carrier contracts.
/// The Fragment contains only contract CIDs; their separate construction
/// extents cannot be replaced by those fixed identity widths. Nothing here
/// grants capacity or replaces real contract/graph/Run admission.
pub(all) struct ClientTaskFragmentConstruction {
  pipeline_geometry : @encode.EncodingConstructionGeometry?
  fragment_geometry : @encode.EncodingConstructionGeometry?
  output_contract_geometry : @encode.EncodingConstructionGeometry?
  initial_pipeline : (Int, Int, Int)
  pipeline : (Int, Int, Int)
  fragment : (Int, Int, Int)
  input_contracts : Array[(Int, Int, Int)]
  output_contract : (Int, Int, Int)
  output_carrier : String
  node_id : String
  output_port : String
} derive(Eq, Debug)

///|
fn measure_client_task_carrier_contract(
  carrier : @carrier.Carrier,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (Int, Int, Int)? {
  guard client_task_contract_source(carrier) is Some(source) else {
    return None
  }
  match source {
    ObjectRelation(row) =>
      try {
        let writer = @encode.measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
        @contract.emit_checked(row, writer)
        Some(@encode.finish_measurement_usage(writer))
      } catch {
        _ => None
      }
    PresenceRelation(schema) =>
      @execution.measure_relation_schema_identity(schema, {
        max_fields: max_nodes,
        max_bytes: max_wire_bytes,
        max_nodes,
        max_depth,
      }).to_option()
    GraphCarrier(original) =>
      @graph_contract.measure(original, {
        max_bytes: max_wire_bytes,
        max_nodes,
        max_depth,
      }).to_option()
    RecordCarrier(original, row) =>
      try {
        let writer = @encode.measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
        if !emit_client_task_record_carrier_body(original, row, writer) {
          return None
        }
        Some(@encode.finish_measurement_usage(writer))
      } catch {
        _ => None
      }
  }
}

///|
// One typed selection for both real identity construction and geometry. Kind,
// complete schema and conditional presence are not reinterpreted by a second
// measuring table. These borrowed inputs carry no contract identity/grant.
priv enum ClientTaskContractSource {
  ObjectRelation(@contract.Contract)
  PresenceRelation(@schema.Schema)
  GraphCarrier(@carrier.Carrier)
  RecordCarrier(@carrier.Carrier, @contract.Contract)
}

///|
fn client_task_contract_source(
  carrier : @carrier.Carrier,
) -> ClientTaskContractSource? {
  match @carrier.kind(carrier) {
    RelationKind => {
      guard @carrier.relation_rows(carrier) is Some(rows) &&
        @carrier.complete_schema(rows) is Some(schema) else {
        return None
      }
      if !@schema.all_fields_required(schema) {
        return Some(PresenceRelation(schema))
      }
      @schema.as_object(schema).map(row => ObjectRelation(row))
    }
    GraphKind => Some(GraphCarrier(carrier))
    EventsKind | VectorsKind => {
      let records = match carrier {
        @carrier.EventValue(events) => @carrier.event_records(events)
        @carrier.VectorValue(vectors) => @carrier.vector_records(vectors)
        _ => return None
      }
      guard @carrier.complete_schema(records) is Some(schema) &&
        @schema.as_object(schema) is Some(row) else {
        return None
      }
      Some(RecordCarrier(carrier, row))
    }
  }
}
