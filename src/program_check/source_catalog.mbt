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
  references : @environment.CatalogReferences
  usage : SourceCatalogUsage
  depth_limit : Int
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
  prepare_source_catalog_with_reader(environment, limits, prepare_environment)
}

///|
fn prepare_source_catalog_with_reader(
  environment : CheckEnvironment,
  limits : SourceCatalogLimits,
  read : (@environment.WireEnvironment, IdentityBudget) -> (
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
  ) raise EnvironmentFailure,
) -> Result[PreparedSourceCatalog, EnvironmentFailure] {
  let budget = IdentityBudget::{
    work: limits.max_work,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  let (catalog, references) = read(environment.wire, budget) catch {
    failure => return Err(failure)
  }
  Ok({
    environment,
    catalog,
    references,
    usage: {
      work: limits.max_work - budget.work,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    },
    depth_limit: limits.max_depth,
  })
}

///|
// The retained chain proves the same immutable Environment under its original
// bounds. Replay only its aggregate accounting when the current allowance fits.
// A tighter, unproved allowance keeps the existing bounded reader and errors.
fn reuse_source_catalog(
  prepared : PreparedSourceCatalog,
  environment : @environment.WireEnvironment,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  reuse_source_catalog_with_reader(
    prepared, environment, budget, prepare_environment,
  )
}

///|
fn reuse_source_catalog_with_reader(
  prepared : PreparedSourceCatalog,
  environment : @environment.WireEnvironment,
  budget : IdentityBudget,
  read : (@environment.WireEnvironment, IdentityBudget) -> (
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
  ) raise EnvironmentFailure,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  if !physical_equal(prepared.environment.wire, environment) {
    raise ForeignPreparedCatalog
  }
  let used = prepared.usage
  if budget.work < used.work ||
    budget.bytes < used.bytes ||
    budget.nodes < used.nodes ||
    budget.depth < prepared.depth_limit {
    return read(environment, budget)
  }
  budget.work -= used.work
  budget.bytes -= used.bytes
  budget.nodes -= used.nodes
  (prepared.catalog, prepared.references)
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
