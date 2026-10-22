///|
fn original_publication_host_wire(
  host : @host.Witness,
  budget : IdentityBudget,
) -> @wire.WireWitness raise UnitBuildFailure {
  let bytes = publication_metadata(
    w => @host.emit(host, w) catch { e => raise Encoding(e) },
    budget,
  )
  identity_charge(budget, bytes.length())
  match
    @wire.admit(bytes, @host.cid(host), {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: budget.depth,
    }) {
    Ok(value) => value
    Err(issue) => raise PublicationWire(issue)
  }
}

///|
test "compiler typed Host projection preserves original bytes and every logical debit" {
  let construction = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = local_construction_fixture(construction)
  let host = @host.create(
    @context.publication_row_limit_host(units[0].publication_rows[0]),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  let original = IdentityBudget::{
    work: 1000000,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  let reused = IdentityBudget::{ ..original, }
  let before = original_publication_host_wire(host, original)
  let after = publication_host_wire(host, reused)
  assert_eq(@wire.cid(after), @wire.cid(before))
  assert_true(physical_equal(after, @host.wire_witness(host)))
  assert_eq(reused.work, original.work)
  assert_eq(reused.bytes, original.bytes)
  assert_eq(reused.nodes, original.nodes)
  let a = @encode.writer(10000, 1000, 100)
  let b = @encode.writer(10000, 1000, 100)
  @wire.emit(before, a)
  @wire.emit(after, b)
  assert_eq(@encode.finish(a), @encode.finish(b))
}
