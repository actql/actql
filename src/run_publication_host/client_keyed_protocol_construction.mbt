///|
// Ephemeral original construction state, not authority, a new Owner or a
// reservation. Only its original lookup may reconcile it, once.
priv struct KeyedProtocolConstruction {
  lookup : ClientKeyedLookupInput
  basis_retained : Int64
  basis_execution : Int64
  controls : Int64
  mut finished : Bool
}

///|
priv struct KeyedProtocolBuilt[T] {
  value : T
  contracts : Array[@publication.PublicationContract]
  evidence : Array[@publication.RunEvidenceValue]
  texts : Array[String]
  dependency_bodies : Array[@publication.CapturedEffectDependencyBody]?
}

///|
// This internal exit can only be issued after original adoption and successful
// reconciliation. It conveys no current authorization or physical-close ACK.
priv struct SettledKeyedProtocolMetadata[T] {
  value : T
}

///|
fn[T] keyed_protocol_built(
  value : T,
  contracts? : Array[@publication.PublicationContract] = [],
  evidence? : Array[@publication.RunEvidenceValue] = [],
  texts? : Array[String] = [],
  dependency_bodies? : Array[@publication.CapturedEffectDependencyBody]? = None,
) -> KeyedProtocolBuilt[T] {
  { value, contracts, evidence, texts, dependency_bodies, }
}

///|
// Preserve the original lookup's mutation fence across synchronous build and
// adoption. Internal body growth preserves that fence; external reentry cannot
// begin a second construction or clean up the live frame. No raw value escapes
// on an extent, settlement or final-current failure, while its adopted backing
// remains owned by the same lookup and its existing cleanup path.
// Callbacks obey the declared no-raise Result contract. A foreign ABI panic
// remains a whole-Host fault/cleanup-only obligation, never a settled exit or
// physical cleanup ACK from this portable boundary.
fn[T] with_keyed_protocol_construction(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  slots : Int64,
  max_nodes : Int,
  max_depth : Int,
  build : () -> Result[KeyedProtocolBuilt[T], ClientKeyedRequestIssue],
  adopt : (T) -> Result[Unit, ClientKeyedRequestIssue],
  extra_controls? : Int64 = 0L,
  copies? : Int = 1,
) -> Result[SettledKeyedProtocolMetadata[T], ClientKeyedRequestIssue] {
  let phase = match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      max_bytes,
      slots,
      extra_controls~,
      copies~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  lookup.growing = true
  defer {
    lookup.growing = false
  }
  let built = build()
  let adopted = match built {
    Err(issue) => Err(issue)
    Ok(built) =>
      if lookup.closed || lookup.left.lookup_issue is Some(_) {
        Err(Assembly("retired_protocol_construction"))
      } else {
        match adopt(built.value) {
          Err(issue) => Err(issue)
          Ok(_) => Ok(built)
        }
      }
  }
  lookup.growing = false
  let built = match adopted {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  finish_keyed_lookup_protocol_metadata(
    lookup,
    phase,
    max_nodes,
    max_depth,
    built.contracts,
    evidence=built.evidence,
    texts=built.texts,
    dependency_bodies=built.dependency_bodies,
  ).map(_ => { value: built.value, })
}
