///|
/// Bounds for reusing the checker's existing Catalog admission before query
/// name binding. These are preparation bounds, not execution capacity.
pub(all) struct SourceCatalogLimits {
  max_work : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) struct SourceCatalogUsage {
  work : Int
  bytes : Int
  nodes : Int
} derive(Eq, Debug)

///|
// Retain the selected checker and the Catalog owner it actually admitted.
// This handle does not grant read permission or seal a checked Program.
pub struct PreparedSourceCatalog {
  environment : CheckEnvironment
  catalog : @environment.SourceRequestContracts
  usage : SourceCatalogUsage
}

///|
/// Reuse common Catalog interpretation without a second Frontend reader.
/// Source declarations must subsequently be registered against their own
/// admitted Program/Stage. Model, request, capacity and execution checks remain
/// separate; a successful Catalog preparation cannot replace them.
pub fn prepare_source_catalog(
  environment : CheckEnvironment,
  limits : SourceCatalogLimits,
) -> Result[PreparedSourceCatalog, EnvironmentFailure] {
  let budget = IdentityBudget::{
    work: limits.max_work,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  let (catalog, _) = prepare_environment(environment.wire, budget) catch {
    failure => return Err(failure)
  }
  Ok({
    environment,
    catalog,
    usage: {
      work: limits.max_work - budget.work,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    },
  })
}

///|
pub fn source_catalog_owner(
  prepared : PreparedSourceCatalog,
) -> CheckEnvironment {
  prepared.environment
}

///|
pub fn source_catalog_contracts(
  prepared : PreparedSourceCatalog,
) -> @environment.SourceRequestContracts {
  prepared.catalog
}

///|
pub fn source_catalog_usage(
  prepared : PreparedSourceCatalog,
) -> SourceCatalogUsage {
  prepared.usage
}
