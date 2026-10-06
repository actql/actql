import {optionalOutputAsSuccesses, optionalOutputAsRefusals, optionalOutputAsExecutionFailures}
  from './optional-output-as-source-input.mjs';
import {booleanCastSuccesses, booleanCastRefusals, booleanCastExecutionFailures}
  from './boolean-cast-source-input.mjs';
import {graphDeltaSourceControls, graphDeltaSourceRefusals, graphDeltaSourceExecutionFailures}
  from './graph-delta-source-input.mjs';
import {limitParameterSuccesses, limitParameterRefusals} from './limit-parameter-source-input.mjs';
import {ifnullSuccesses, ifnullRefusals, ifnullExecutionFailures}
  from './ifnull-source-input.mjs';
import {havingObjectPropertySuccesses, havingObjectPropertyRefusals, havingObjectPropertyExecutionFailures}
  from './having-object-property-source-input.mjs';
import {analyticPartitionPropertySuccesses, analyticPartitionPropertyRefusals}
  from './analytic-partition-property-source-input.mjs';
import {aggregatePropertyOrderSuccesses, aggregatePropertyOrderRefusals, aggregatePropertyOrderExecutionFailures}
  from './aggregate-property-order-source-input.mjs';
import {analyticCountifSuccesses, analyticCountifRefusals, analyticCountifExecutionFailures}
  from './analytic-countif-source-input.mjs';
import {analyticFrameParameterCapacity, analyticFrameParameterSuccesses, analyticFrameParameterRefusals}
  from './analytic-frame-parameter-source-input.mjs';
import {groupedInSuccesses, groupedInRefusals} from './grouped-in-source-input.mjs';
import {subgraphSourceSuccesses, subgraphSourceRefusals, subgraphSourceExecutionFailures}
  from './subgraph-source-input.mjs';
import {jsonLiteralSourceSuccesses, jsonLiteralSourceRefusals}
  from './json-literal-source-input.mjs';
import {typedJsonLiteralSuccesses, typedJsonLiteralRefusals}
  from './typed-json-literal-input.mjs';
import {analyticOffsetSuccesses, analyticOffsetRefusals}
  from './analytic-offset-source-input.mjs';
// Copied unchanged into the external tarball installation by the driver.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from
  '@actql/local-node/http-host';
import {exercisePublicQueryInput, querySuccesses, queryRefusals, inferRefusals, sourceRows, sourceFreeSuccesses, sourceFreeRefusals, queryCompositionSuccesses, queryCompositionRefusals, pipeResultSuccesses, pipeResultRefusals, pipeResultExecutionFailures, relationDataSuccesses, relationDataRefusals}
  from './public-query-input.mjs';

import {propertyGraphSourceSuccesses, propertyGraphSourceExecutionFailures, propertyGraphSourceRefusals}
  from "./property-graph-source-input.mjs";
import {groupStarSuccesses, groupStarRefusals}
  from './group-star-source-input.mjs';
import {aggregatePropertySuccesses, aggregatePropertyRefusals}
  from './aggregate-property-source-input.mjs';
import {groupOrdinalSuccesses, groupOrdinalRefusals}
  from './group-ordinal-source-input.mjs';
import {distinctOrderSuccesses, distinctOrderRefusals}
  from './distinct-order-source-input.mjs';
import {joinPropertySuccesses, joinPropertyRefusals}
  from './join-property-source-input.mjs';
import {orderPropertySuccesses, orderPropertyRefusals}
  from './order-property-source-input.mjs';
import {analyticOrderObjectReproduction, analyticOrderSuccesses, analyticOrderRefusals, analyticOrderExecutionFailures}
  from './analytic-order-source-input.mjs';
import {analyticPropertySuccesses, analyticPropertyRefusals}
  from './analytic-property-source-input.mjs';
import {groupSelectScopeSuccesses, groupSelectScopeRefusals}
  from './group-select-scope-source-input.mjs';
import {havingProjectionSuccesses, havingProjectionRefusals}
  from './having-projection-source-input.mjs';
import {implicitPropertySuccesses, implicitPropertyRefusals}
  from './implicit-property-source-input.mjs';
import {computedObjectPropertySuccesses, computedObjectPropertyRefusals, computedObjectPropertyExecutionFailures}
  from './computed-object-property-source-input.mjs';
import {groupPropertySuccesses, groupPropertyRefusals}
  from './group-property-source-input.mjs';
import {uniquePublicQueryCases} from './public-query-cases.mjs';
import {publicQueryProfiles} from './public-query-profiles.mjs';
import {quotedIdentifierSuccesses, quotedIdentifierRefusals}
  from './quoted-identifier-source-input.mjs';
import {orderOrdinalSuccesses, orderOrdinalRefusals}
  from './order-ordinal-source-input.mjs';
import {graphMatchSourceSuccesses, graphMatchSourceRefusals}
  from './graph-match-source-input.mjs';
import {graphRowSourceSuccesses, graphRowSourceRefusals}
  from './property-graph-row-source-input.mjs';
import {graphPropertyPredicateSuccesses, graphPropertyPredicateRefusals}
  from './graph-property-predicate-source-input.mjs';
import {graphTraverseSourceSuccesses, graphTraverseSourceRefusals}
  from './property-graph-traverse-source-input.mjs';
import {graphTraversePathSuccesses, graphTraversePathRefusals}
  from './property-graph-traverse-path-source-input.mjs';
import {graphDifferenceSourceSuccesses, graphDifferenceSourceRefusals}
  from './property-graph-difference-source-input.mjs';
import {graphEqualitySourceSuccesses, graphEqualitySourceRefusals}
  from './property-graph-equality-source-input.mjs';
import {acquiredDataSuccesses, acquiredGraphSourceSuccesses, acquiredDataRefusals}
  from './acquired-data-source-input.mjs';
import {graphProjectionPropertySuccesses, graphProjectionPropertyRefusals}
  from './graph-projection-property-source-input.mjs';

import {graphDiagnosticSourceSuccesses, graphDiagnosticSourceRefusals, graphDiagnosticSourceExecutionFailures}
  from './property-graph-diagnostics-source-input.mjs';

if (process.env.ACTQL_TEST_TWO_SOURCE_ONLY === '1') {
  await import('./packed-two-source-public-query.mjs');
} else {
const graphDeltaOnly = process.env.ACTQL_TEST_GRAPH_DELTA_SOURCE_ONLY === '1';
const graphDeltaSourceSuccesses = await graphDeltaSourceControls(new URL('./fixtures/', import.meta.url));
const jsonSourceOnly = process.env.ACTQL_TEST_JSON_LITERAL_SOURCE_ONLY === '1';
const typedJsonOnly = process.env.ACTQL_TEST_TYPED_JSON_LITERAL_ONLY === '1';
const havingObjectPropertyOnly = process.env.ACTQL_TEST_HAVING_OBJECT_PROPERTY_ONLY === '1';
const propertyGraphOnly = process.env.ACTQL_TEST_PROPERTY_GRAPH_SOURCE_ONLY === "1";
const graphPropertyPredicateOnly = process.env.ACTQL_TEST_GRAPH_PROPERTY_PREDICATE_ONLY === '1';
const limitParameterOnly = process.env.ACTQL_TEST_LIMIT_PARAMETER_ONLY === '1';
const optionalOutputAsOnly = process.env.ACTQL_TEST_OPTIONAL_OUTPUT_AS_ONLY === '1';
const booleanCastOnly = process.env.ACTQL_TEST_BOOLEAN_CAST_ONLY === '1';
const ifnullOnly = process.env.ACTQL_TEST_IFNULL_ONLY === '1';
const analyticCountifOnly = process.env.ACTQL_TEST_ANALYTIC_COUNTIF_ONLY === '1';
const groupedInOnly = process.env.ACTQL_TEST_GROUPED_IN_ONLY === '1';
const subgraphOnly = process.env.ACTQL_TEST_SUBGRAPH_ONLY === '1';
const analyticOffsetOnly = process.env.ACTQL_TEST_ANALYTIC_OFFSET_ONLY === '1';
const graphDiagnosticsOnly = process.env.ACTQL_TEST_GRAPH_DIAGNOSTICS_ONLY === '1';
const graphMatchOnly = process.env.ACTQL_TEST_GRAPH_MATCH_ONLY === '1';
const graphRowsOnly = process.env.ACTQL_TEST_GRAPH_ROWS_ONLY === '1';
const graphDifferenceOnly = process.env.ACTQL_TEST_GRAPH_DIFFERENCE_ONLY === '1';
const graphEqualityOnly = process.env.ACTQL_TEST_GRAPH_EQUALITY_ONLY === '1';
const quotedIdentifiersOnly = process.env.ACTQL_TEST_QUOTED_IDENTIFIERS_ONLY === '1';
const graphProjectionPropertyOnly = process.env.ACTQL_TEST_GRAPH_PROJECTION_PROPERTY_ONLY === '1';
const orderOrdinalOnly = process.env.ACTQL_TEST_ORDER_ORDINAL_ONLY === '1';
const distinctOrderOnly = process.env.ACTQL_TEST_DISTINCT_ORDER_ONLY === '1';
const analyticPropertyOnly = process.env.ACTQL_TEST_ANALYTIC_PROPERTY_ONLY === '1';
const graphTraverseOnly = process.env.ACTQL_TEST_GRAPH_TRAVERSE_ONLY === '1';
const graphTraversePathsOnly = process.env.ACTQL_TEST_GRAPH_TRAVERSE_PATHS_ONLY === '1';
const scopedOrderOnly = process.env.ACTQL_TEST_SCOPED_ORDER_ONLY === '1';
const sourceFreeOnly = process.env.ACTQL_TEST_SOURCE_FREE_ONLY === '1';
const inferOnly = process.env.ACTQL_TEST_INFER_REFUSAL_ONLY === '1';
const joinOnly = process.env.ACTQL_TEST_JOIN_ORDER_ONLY === '1';
const groupOnly = process.env.ACTQL_TEST_GROUP_SCOPE_ONLY === '1';
const groupSelectScopeOnly = process.env.ACTQL_TEST_GROUP_SELECT_SCOPE_ONLY === '1';
const implicitPropertyOnly = process.env.ACTQL_TEST_IMPLICIT_PROPERTY_ONLY === '1';
const computedObjectPropertyOnly = process.env.ACTQL_TEST_COMPUTED_OBJECT_PROPERTY_ONLY === '1';
const groupPropertyOnly = process.env.ACTQL_TEST_GROUP_PROPERTY_ONLY === '1';
const havingProjectionOnly = process.env.ACTQL_TEST_HAVING_PROJECTION_ONLY === '1';
const groupStarOnly = process.env.ACTQL_TEST_GROUP_STAR_ONLY === '1';
const aggregatePropertyOrderOnly = process.env.ACTQL_TEST_AGGREGATE_PROPERTY_ORDER_ONLY === '1';
const aggregatePropertyOnly = process.env.ACTQL_TEST_AGGREGATE_PROPERTY_ONLY === '1';
const groupOrdinalOnly = process.env.ACTQL_TEST_GROUP_ORDINAL_ONLY === '1';
const compositionOnly = process.env.ACTQL_TEST_QUERY_COMPOSITION_ONLY === '1';
const resultOnly = process.env.ACTQL_TEST_PIPE_RESULT_ONLY === '1';
const dataOnly = process.env.ACTQL_TEST_RELATION_DATA_ONLY === '1';
const acquiredDataOnly = process.env.ACTQL_TEST_ACQUIRED_DATA_ONLY === '1';
const dataSetStrategyOnly = process.env.ACTQL_TEST_DATA_SET_STRATEGY_ONLY === '1';
const orderPropertyOnly = process.env.ACTQL_TEST_ORDER_PROPERTY_ONLY === '1';
const analyticProfilesOnly = process.env.ACTQL_TEST_ANALYTIC_PROFILES_ONLY === '1';
const analyticPartitionPropertyOnly = process.env.ACTQL_TEST_ANALYTIC_PARTITION_PROPERTY_ONLY === '1';
const analyticOrderOnly = process.env.ACTQL_TEST_ANALYTIC_ORDER_ONLY === '1';
const joinPropertyOnly = process.env.ACTQL_TEST_JOIN_PROPERTY_ONLY === '1';
const analyticFrameParameterOnly = process.env.ACTQL_TEST_ANALYTIC_FRAME_PARAMETER_ONLY === '1';
const scopeOnly = optionalOutputAsOnly || booleanCastOnly || graphDifferenceOnly || graphDeltaOnly || jsonSourceOnly || limitParameterOnly || typedJsonOnly || ifnullOnly || aggregatePropertyOrderOnly || computedObjectPropertyOnly || havingObjectPropertyOnly || analyticPartitionPropertyOnly || analyticCountifOnly || analyticFrameParameterOnly || analyticOffsetOnly || joinPropertyOnly || analyticProfilesOnly || analyticOrderOnly || process.env.ACTQL_TEST_PIPE_SCOPE_ONLY === '1' || scopedOrderOnly || inferOnly || joinOnly || groupOnly || groupSelectScopeOnly || groupPropertyOnly || havingProjectionOnly || implicitPropertyOnly || groupStarOnly || groupOrdinalOnly || sourceFreeOnly || compositionOnly || resultOnly || dataOnly || acquiredDataOnly || dataSetStrategyOnly || propertyGraphOnly || graphRowsOnly || graphTraverseOnly || orderOrdinalOnly || distinctOrderOnly || graphPropertyPredicateOnly || graphProjectionPropertyOnly || orderPropertyOnly || quotedIdentifiersOnly || graphEqualityOnly || graphDiagnosticsOnly || graphTraversePathsOnly || graphMatchOnly || aggregatePropertyOnly || analyticPropertyOnly || subgraphOnly || groupedInOnly;
const joinOrder = JSON.parse(await readFile('join-order-cases.json', 'utf8'));
const joinChain = JSON.parse(await readFile('join-chain-cases.json', 'utf8'));
const groupScope = JSON.parse(await readFile('group-scope-cases.json', 'utf8'));
const scope = JSON.parse(await readFile('pipe-scope-cases.json', 'utf8'));
assert.deepEqual(scope.source_rows, sourceRows);
const dataSetStrategyInputs = {
  // Retain main's independent JSON control once. The DATA source group shares
  // this input rather than duplicating the same machine Program and run.
  successes: [{name: 'independent-ordered-data-set', format: 'json',
    text: await readFile('data-set-strategy-program.json', 'utf8'),
    sourceReadCount: 0,
    results: {nodes: {rows: [{id: 1}], columns: [
      {name: 'id', contract: {type: 'number', nullable: false}},
    ]}}}],
  refusals: [],
};
// Retain the original generated Program as a reproduction, not an independent
// expected Program. Both source and JSON use the same hand-authored rows/types.
const analyticOrderInputs = [...analyticOrderSuccesses,
  analyticOrderObjectReproduction(await readFile('analytic-order-property-repro.program.json', 'utf8'))];
const scopeInputs = limitParameterOnly ? {successes: limitParameterSuccesses, refusals: limitParameterRefusals}
  : jsonSourceOnly ? {successes: jsonLiteralSourceSuccesses, refusals: jsonLiteralSourceRefusals}
  : typedJsonOnly ? {successes: typedJsonLiteralSuccesses, refusals: typedJsonLiteralRefusals}
  : graphDeltaOnly ? {successes: graphDeltaSourceSuccesses, refusals: graphDeltaSourceRefusals, executionFailures: graphDeltaSourceExecutionFailures}
  : havingObjectPropertyOnly ? {successes: havingObjectPropertySuccesses, refusals: havingObjectPropertyRefusals, executionFailures: havingObjectPropertyExecutionFailures}
  : analyticPartitionPropertyOnly ? {successes: analyticPartitionPropertySuccesses, refusals: analyticPartitionPropertyRefusals}
  : analyticCountifOnly ? {successes: analyticCountifSuccesses, refusals: analyticCountifRefusals, executionFailures: analyticCountifExecutionFailures}
  : analyticFrameParameterOnly ? {successes: analyticFrameParameterSuccesses, refusals: analyticFrameParameterRefusals}
  : groupedInOnly ? {successes: groupedInSuccesses, refusals: groupedInRefusals}
  : analyticProfilesOnly ? {
  successes: [...analyticOrderInputs, ...analyticPropertySuccesses, ...analyticOffsetSuccesses],
  refusals: [...analyticOrderRefusals, ...analyticPropertyRefusals, ...analyticOffsetRefusals],
  executionFailures: analyticOrderExecutionFailures}
  : analyticOrderOnly ? {successes: analyticOrderInputs, refusals: analyticOrderRefusals, executionFailures: analyticOrderExecutionFailures}
  : optionalOutputAsOnly ? {successes: optionalOutputAsSuccesses, refusals: optionalOutputAsRefusals, executionFailures: optionalOutputAsExecutionFailures}
  : booleanCastOnly ? {successes: booleanCastSuccesses, refusals: booleanCastRefusals, executionFailures: booleanCastExecutionFailures}
  : ifnullOnly ? {successes: ifnullSuccesses, refusals: ifnullRefusals, executionFailures: ifnullExecutionFailures}
  : analyticOffsetOnly ? {successes: analyticOffsetSuccesses, refusals: analyticOffsetRefusals}
  : joinPropertyOnly ? {successes: joinPropertySuccesses, refusals: joinPropertyRefusals}
  : aggregatePropertyOnly ? {successes: aggregatePropertySuccesses, refusals: aggregatePropertyRefusals}
  : analyticPropertyOnly ? {successes: analyticPropertySuccesses, refusals: analyticPropertyRefusals}
  : subgraphOnly ? {successes: subgraphSourceSuccesses, refusals: subgraphSourceRefusals, executionFailures: subgraphSourceExecutionFailures}
  : graphDiagnosticsOnly ? {successes: graphDiagnosticSourceSuccesses, refusals: graphDiagnosticSourceRefusals, executionFailures: graphDiagnosticSourceExecutionFailures}
  : aggregatePropertyOrderOnly ? {successes: aggregatePropertyOrderSuccesses, refusals: aggregatePropertyOrderRefusals, executionFailures: aggregatePropertyOrderExecutionFailures}
  : orderPropertyOnly ? {successes: orderPropertySuccesses, refusals: orderPropertyRefusals}
  : graphProjectionPropertyOnly ? {successes: graphProjectionPropertySuccesses, refusals: graphProjectionPropertyRefusals}
  : graphPropertyPredicateOnly ? {successes: graphPropertyPredicateSuccesses, refusals: graphPropertyPredicateRefusals}
  : implicitPropertyOnly ? {successes: implicitPropertySuccesses, refusals: implicitPropertyRefusals}
  : computedObjectPropertyOnly ? {successes: computedObjectPropertySuccesses,
    refusals: computedObjectPropertyRefusals, executionFailures: computedObjectPropertyExecutionFailures}
  : groupOrdinalOnly ? {successes: groupOrdinalSuccesses, refusals: groupOrdinalRefusals}
  : groupPropertyOnly ? {successes: groupPropertySuccesses, refusals: groupPropertyRefusals}
  : havingProjectionOnly ? {successes: havingProjectionSuccesses, refusals: havingProjectionRefusals}
  : groupSelectScopeOnly ? {successes: groupSelectScopeSuccesses, refusals: groupSelectScopeRefusals}
  : groupStarOnly ? {successes: groupStarSuccesses, refusals: groupStarRefusals}
  : quotedIdentifiersOnly ? {successes: quotedIdentifierSuccesses, refusals: quotedIdentifierRefusals}
  : orderOrdinalOnly ? {successes: orderOrdinalSuccesses, refusals: orderOrdinalRefusals}
  : distinctOrderOnly ? {successes: distinctOrderSuccesses, refusals: distinctOrderRefusals}
  : graphTraversePathsOnly ? {successes: [...graphTraverseSourceSuccesses, ...graphTraversePathSuccesses],
    refusals: [...graphTraverseSourceRefusals, ...graphTraversePathRefusals]}
  : graphTraverseOnly ? {successes: graphTraverseSourceSuccesses, refusals: graphTraverseSourceRefusals}
  : graphMatchOnly ? {successes: graphMatchSourceSuccesses, refusals: graphMatchSourceRefusals}
  : graphRowsOnly ? {successes: graphRowSourceSuccesses, refusals: graphRowSourceRefusals}
  : graphDifferenceOnly ? {successes: graphDifferenceSourceSuccesses, refusals: graphDifferenceSourceRefusals}
  : graphEqualityOnly ? {successes: graphEqualitySourceSuccesses, refusals: graphEqualitySourceRefusals}
  : scopedOrderOnly ? {
  successes: scope.successes.filter(item => item.name.startsWith('scoped-order-')),
  refusals: scope.refusals.filter(item => item.name.startsWith('scoped-order-')),
} : propertyGraphOnly ? {successes: [...propertyGraphSourceSuccesses, ...graphRowSourceSuccesses],
  executionFailures: propertyGraphSourceExecutionFailures, refusals: [...propertyGraphSourceRefusals, ...graphRowSourceRefusals]}
  : acquiredDataOnly ? {successes: [...acquiredDataSuccesses, ...acquiredGraphSourceSuccesses],
    refusals: acquiredDataRefusals}
  : dataOnly ? {successes: [...relationDataSuccesses,
  ...dataSetStrategyInputs.successes], refusals: relationDataRefusals}
  : dataSetStrategyOnly ? dataSetStrategyInputs
  : sourceFreeOnly ? {successes: sourceFreeSuccesses, refusals: sourceFreeRefusals}
  : resultOnly ? {successes: pipeResultSuccesses, refusals: pipeResultRefusals,
    executionFailures: pipeResultExecutionFailures}
  : compositionOnly ? {successes: queryCompositionSuccesses, refusals: queryCompositionRefusals}
  : inferOnly ? {successes: [querySuccesses[0]], refusals: inferRefusals}
  : groupOnly ? groupScope : joinOnly ? joinOrder : scopeOnly ? {successes: scope.successes,
  refusals: scope.refusals} : {successes: [...dataSetStrategyInputs.successes, ...querySuccesses, ...sourceFreeSuccesses, ...queryCompositionSuccesses, ...pipeResultSuccesses, ...relationDataSuccesses, ...acquiredDataSuccesses, ...acquiredGraphSourceSuccesses, ...propertyGraphSourceSuccesses, ...scope.successes, ...joinOrder.successes, ...groupStarSuccesses, ...groupOrdinalSuccesses],
  refusals: [...queryRefusals, ...sourceFreeRefusals, ...queryCompositionRefusals, ...pipeResultRefusals, ...relationDataRefusals, ...acquiredDataRefusals, ...propertyGraphSourceRefusals, ...scope.refusals, ...inferRefusals, ...joinOrder.refusals, ...groupStarRefusals, ...groupOrdinalRefusals],
  executionFailures: [...pipeResultExecutionFailures, ...propertyGraphSourceExecutionFailures]};
if (!scopeOnly) {
  scopeInputs.successes.push(...graphDeltaSourceSuccesses);
  scopeInputs.refusals.push(...graphDeltaSourceRefusals);
  scopeInputs.executionFailures.push(...graphDeltaSourceExecutionFailures);
  scopeInputs.successes.push(...jsonLiteralSourceSuccesses);
  scopeInputs.refusals.push(...jsonLiteralSourceRefusals);
  scopeInputs.successes.push(...typedJsonLiteralSuccesses);
  scopeInputs.refusals.push(...typedJsonLiteralRefusals);
  scopeInputs.successes.push(...limitParameterSuccesses);
  scopeInputs.refusals.push(...limitParameterRefusals);
  scopeInputs.successes.push(...optionalOutputAsSuccesses);
  scopeInputs.refusals.push(...optionalOutputAsRefusals);
  scopeInputs.executionFailures.push(...optionalOutputAsExecutionFailures);
  scopeInputs.successes.push(...booleanCastSuccesses);
  scopeInputs.refusals.push(...booleanCastRefusals);
  scopeInputs.executionFailures.push(...booleanCastExecutionFailures);
  scopeInputs.successes.push(...ifnullSuccesses);
  scopeInputs.refusals.push(...ifnullRefusals);
  scopeInputs.executionFailures.push(...ifnullExecutionFailures);
  scopeInputs.successes.push(...havingObjectPropertySuccesses);
  scopeInputs.refusals.push(...havingObjectPropertyRefusals);
  scopeInputs.executionFailures.push(...havingObjectPropertyExecutionFailures);
  scopeInputs.successes.push(...analyticPartitionPropertySuccesses);
  scopeInputs.refusals.push(...analyticPartitionPropertyRefusals);
  scopeInputs.successes.push(...computedObjectPropertySuccesses);
  scopeInputs.refusals.push(...computedObjectPropertyRefusals);
  scopeInputs.executionFailures.push(...computedObjectPropertyExecutionFailures);
  scopeInputs.successes.push(...aggregatePropertyOrderSuccesses);
  scopeInputs.refusals.push(...aggregatePropertyOrderRefusals);
  scopeInputs.executionFailures.push(...aggregatePropertyOrderExecutionFailures);
  scopeInputs.successes.push(...analyticCountifSuccesses);
  scopeInputs.refusals.push(...analyticCountifRefusals);
  scopeInputs.executionFailures.push(...analyticCountifExecutionFailures);
  scopeInputs.successes.push(...groupedInSuccesses);
  scopeInputs.refusals.push(...groupedInRefusals);
  scopeInputs.successes.push(...analyticOffsetSuccesses);
  scopeInputs.refusals.push(...analyticOffsetRefusals);
  scopeInputs.successes.push(...analyticOrderInputs);
  scopeInputs.refusals.push(...analyticOrderRefusals);
  scopeInputs.executionFailures.push(...analyticOrderExecutionFailures);
  scopeInputs.successes.push(...joinPropertySuccesses);
  scopeInputs.refusals.push(...joinPropertyRefusals);
  scopeInputs.successes.push(...analyticFrameParameterSuccesses);
  scopeInputs.refusals.push(...analyticFrameParameterRefusals);
  scopeInputs.successes.push(...subgraphSourceSuccesses);
  scopeInputs.refusals.push(...subgraphSourceRefusals);
  scopeInputs.executionFailures.push(...subgraphSourceExecutionFailures);
  scopeInputs.successes.push(...orderPropertySuccesses);
  scopeInputs.refusals.push(...orderPropertyRefusals);
  scopeInputs.successes.push(...aggregatePropertySuccesses);
  scopeInputs.refusals.push(...aggregatePropertyRefusals);
  scopeInputs.successes.push(...graphProjectionPropertySuccesses);
  scopeInputs.refusals.push(...graphProjectionPropertyRefusals);
  scopeInputs.successes.push(...graphPropertyPredicateSuccesses);
  scopeInputs.refusals.push(...graphPropertyPredicateRefusals);
  scopeInputs.successes.push(...implicitPropertySuccesses);
  scopeInputs.refusals.push(...implicitPropertyRefusals);
  scopeInputs.successes.push(...groupPropertySuccesses);
  scopeInputs.refusals.push(...groupPropertyRefusals);
  scopeInputs.successes.push(...analyticPropertySuccesses);
  scopeInputs.refusals.push(...analyticPropertyRefusals);
  scopeInputs.successes.push(...havingProjectionSuccesses);
  scopeInputs.refusals.push(...havingProjectionRefusals);
  scopeInputs.successes.push(...groupSelectScopeSuccesses);
  scopeInputs.refusals.push(...groupSelectScopeRefusals);
  scopeInputs.successes.push(...quotedIdentifierSuccesses);
  scopeInputs.refusals.push(...quotedIdentifierRefusals);
  scopeInputs.successes.push(...orderOrdinalSuccesses);
  scopeInputs.refusals.push(...orderOrdinalRefusals);
  scopeInputs.successes.push(...distinctOrderSuccesses);
  scopeInputs.refusals.push(...distinctOrderRefusals);
  scopeInputs.successes.push(...graphRowSourceSuccesses);
  scopeInputs.refusals.push(...graphRowSourceRefusals);
  scopeInputs.successes.push(...graphMatchSourceSuccesses);
  scopeInputs.refusals.push(...graphMatchSourceRefusals);
  scopeInputs.successes.push(...graphDiagnosticSourceSuccesses);
  scopeInputs.refusals.push(...graphDiagnosticSourceRefusals);
  scopeInputs.executionFailures.push(...graphDiagnosticSourceExecutionFailures);
  scopeInputs.successes.push(...graphTraverseSourceSuccesses);
  scopeInputs.refusals.push(...graphTraverseSourceRefusals);
  scopeInputs.successes.push(...graphTraversePathSuccesses);
  scopeInputs.refusals.push(...graphTraversePathRefusals);
  scopeInputs.successes.push(...graphDifferenceSourceSuccesses);
  scopeInputs.refusals.push(...graphDifferenceSourceRefusals);
  scopeInputs.successes.push(...graphEqualitySourceSuccesses);
  scopeInputs.refusals.push(...graphEqualitySourceRefusals);
}
if (!scopeOnly) {
  scopeInputs.successes.push(...joinChain.successes);
  scopeInputs.refusals.push(...joinChain.refusals);
  scopeInputs.successes.push(...groupScope.successes);
  scopeInputs.refusals.push(...groupScope.refusals);
}
scopeInputs.successes = uniquePublicQueryCases(scopeInputs.successes);
if (scopedOrderOnly) {
  assert.equal(scopeInputs.successes.length, 4);
  assert.equal(scopeInputs.refusals.length, 1);
}
// Host profiles are immutable within an installation. Keep each fixture's
// declared analytic envelope, including when the full corpus combines profiles.
for (const {name: profileName, capacity: analyticCapacity, inputs: profileInputs}
  of publicQueryProfiles(scopeInputs)) {
const scopeInputs = profileInputs;
if (analyticFrameParameterOnly) assert.deepEqual(analyticCapacity, analyticFrameParameterCapacity);
const suffix = profileName === 'standard' ? '' : `-${profileName}`;
const localDirectory = resolve(`local-state${suffix}`);
const remoteDirectory = resolve(`remote-state${suffix}`);
const expectedQueryRuns = scopeInputs.successes.length + (scopeInputs.executionFailures?.length ?? 0);
const expectedSourceReads = [...scopeInputs.successes, ...(scopeInputs.executionFailures ?? [])]
  .reduce((count, item) => count + (item.sourceReadCount ?? item.sourceReadSessionCount ?? 1), 0);

assert.equal(spawnSync('moon', ['version']).error?.code, 'ENOENT');
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const environment = JSON.parse(await readFile('source-environment.json', 'utf8'));
const base = JSON.parse(await readFile('base-environment.json', 'utf8'));
environment.host_policy_profile = {...base.host_policy_profile,
  capacity: {...base.host_policy_profile.capacity, ...analyticCapacity}};
environment.connector_capabilities[0].capability_contract_cids.push(
  'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89');
environment.connector_capabilities[0].capability_contract_cids.sort();
delete environment.evidence_bundle_cid;
environment.evidence_bundle_cid = 'sha256:' + createHash('sha256')
  .update(canonical(environment)).digest('hex');
const database = resolve(`records${suffix}.duckdb`);
const {DuckDBInstance, DuckDBPreparedStatement, DuckDBConnection,
  DuckDBExtractedStatements} = createRequire(
  new URL('./node_modules/@actql/local-node/package.json', import.meta.url))(
  '@duckdb/node-api');
// Provider-confirmed independent rows for canonically equivalent physical names.
const exactTargetPairs = [
  {field: 'table', targets: [
    {schema: 'main', table: 'caf\u00e9', rows: [{id: 101, amount: 11}]},
    {schema: 'main', table: 'cafe\u0301', rows: [{id: 202, amount: 22}]},
  ]},
  {field: 'schema', targets: [
    {schema: 'caf\u00e9', table: 'records', rows: [{id: 303, amount: 33}]},
    {schema: 'cafe\u0301', table: 'records', rows: [{id: 404, amount: 44}]},
  ]},
];
const physicalSqlName = target => `"${target.schema}"."${target.table}"`;
const instance = await DuckDBInstance.create(database);
const connection = await instance.connect();
try {
  await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
  for (const row of sourceRows) {
    await connection.run('INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
  }
  for (const {targets} of scopeOnly || profileName !== 'standard' ? [] : exactTargetPairs) {
    for (const target of targets) {
      if (target.schema !== 'main') await connection.run(`CREATE SCHEMA "${target.schema}"`);
      await connection.run(`CREATE TABLE ${physicalSqlName(target)}(id DOUBLE, amount DOUBLE)`);
      for (const row of target.rows) await connection.run(
        `INSERT INTO ${physicalSqlName(target)} VALUES (?, ?)`, [row.id, row.amount]);
      const observed = await connection.runAndReadAll(
        `SELECT id, amount FROM ${physicalSqlName(target)} ORDER BY id`);
      assert.deepEqual(observed.getRowObjectsJS(), target.rows);
    }
  }
} finally {
  connection.closeSync();
  instance.closeSync();
}
// Install hand-authored rows in the real DuckDB source before each case.
// Source identity/schema stay fixed; the ordinary acquisition captures the
// current contents. No rows are injected into the Client or frontend.
let installedRows = sourceRows;
async function prepareCase(rows = sourceRows) {
  if (JSON.stringify(rows) === JSON.stringify(installedRows)) return;
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('DELETE FROM records');
    for (const row of rows) {
      await connection.run('INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
    }
    installedRows = rows;
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
}
const view = environment.source_views[0];
const sourceProfilePath = resolve(`source-profile${suffix}.json`);
await writeFile(sourceProfilePath, canonical({
  acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    version: 'actql-installed-duckdb-source/0.1', database,
  schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v',
  queryAliases: [{name: 'records', sourceRef: 'connector://crm/main/r#v',
    sourceViewContractCid: view.contract_cid,
    schemaContractCid: view.output.schema.cid}],
  checkEnvironmentWire: canonical(environment),
  accountConfigurationWire: canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'packed-query',
    entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read']}, exclusions: []}]}),
}));
// Observe actual native execution, never a diagnostic notification.
let sourceIo = 0, sourceReads = 0, sourceReadSessions = 0;
const sourceReadCommands = [];
const extractedSql = new WeakMap(), preparedSql = new WeakMap();
const extractedConnection = new WeakMap(), preparedConnection = new WeakMap();
const readSessions = new WeakMap();
const extract = DuckDBConnection.prototype.extractStatements;
const prepare = DuckDBExtractedStatements.prototype.prepare;
DuckDBConnection.prototype.extractStatements = async function(sql) {
  const statements = await Reflect.apply(extract, this, [sql]);
  extractedSql.set(statements, sql);
  extractedConnection.set(statements, this);
  return statements;
};
DuckDBExtractedStatements.prototype.prepare = async function(index) {
  const statement = await Reflect.apply(prepare, this, [index]);
  preparedSql.set(statement, extractedSql.get(this));
  preparedConnection.set(statement, extractedConnection.get(this));
  return statement;
};
const stream = DuckDBPreparedStatement.prototype.stream;
DuckDBPreparedStatement.prototype.stream = function(...args) {
  sourceIo++;
  // Distinguish the real source-table acquisition from identity/metadata I/O
  // and Local resident computation. This observes emitted physical SQL only.
  if (/\bFROM\s+(?:"main"\.)?"records"(?=\s|$)/iu.test(preparedSql.get(this) ?? '')) {
    sourceReads++;
    // withSourceAcquisition opens one private connection/read view per owner.
    // Native acquisition intentionally uses two row receipts in that same
    // connection (validation_scan and native_result); count those transfers
    // separately from repeated acquisition sessions.
    const connection = preparedConnection.get(this);
    assert.ok(connection, 'source statement retains its actual native connection');
    if (!readSessions.has(connection)) readSessions.set(connection, ++sourceReadSessions);
    sourceReadCommands.push({session: readSessions.get(connection), sql: preparedSql.get(this),
      columns: Array.from({length: this.columnCount}, (_, index) => this.columnName(index))});
  }
  return Reflect.apply(stream, this, args);
};
const observe = directory => () => {
  const journal = new DatabaseSync(resolve(directory, 'requests',
    'client-requests.sqlite3'), {readOnly: true});
  try {
    return {sourceIo, sourceReads, sourceReadSessions, sourceReadCommands, acceptedRuns: journal.prepare(
      'SELECT COUNT(*) AS count FROM client_requests').get().count};
  } finally { journal.close(); }
};
// Current Graph acceptance runs in the driver's shared public Host regression:
// constructor/MATCH/TRAIL, physical snapshot roundtrip and inventory-derived
// pre-admission refusals. Retired SGA fixtures are not execution coverage.
// Public check must also work from installed tarballs, without repository imports.
async function exercisePublicCheck(options) {
  const client = await connect(options);
  const first = await client.check('SELECT 1 AS n', {format: 'sql'});
  assert.equal(first.report.verdict, 'verified');
  assert.deepEqual(await client.check('SELECT 1 AS n', {format: 'sql'}), first);
  const invalid = await client.check('SELECT missing AS n', {format: 'sql'});
  assert.equal(invalid.report.verdict, 'invalid');
  assert.notEqual(invalid.report.context_ref, first.report.context_ref);
  for (const pair of [['e\u0301', 'é'], ['\r', '\n']]) {
    const refs = [];
    for (const x of pair) {
      const result = await client.check('SELECT @x AS n', {format: 'sql',
        parameterDeclarations: {x: {type: 'string'}}, parameters: {x}});
      assert.equal(result.report.verdict, 'verified');
      refs.push(result.report.context_ref);
    }
    assert.notEqual(refs[0], refs[1]);
  }
  const budget = await client.check('SELECT id FROM never_configured', {
    format: 'sql', parameterDeclarations: {x: {type: 'array', items: {type: 'number'}}},
    parameters: {x: Array(9000).fill(1)}});
  assert.equal(budget.report.verdict, 'undetermined');
  assert.deepEqual(budget.report.reasons, []);
  assert.deepEqual(budget.report.coverage, {
    limits: [{code: 'analysis_budget_exhausted'}],
    unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
  console.log(`packed public check ${options.mode} passed`);
}
await exercisePublicCheck({mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: localDirectory, sourceProfilePath}});
// Extend the same public harness; no second lifecycle/fault matrix. Each
// physical spelling has independently authored rows and its own explicit Host.
async function exerciseExactPhysicalTargets() {
  const baseProfile = JSON.parse(await readFile(sourceProfilePath, 'utf8'));
  for (const {field, targets} of exactTargetPairs) {
    const path = resolve(`exact-${field}-source.json`);
    const firstDirectory = resolve(`exact-${field}-local-0`);
    const firstOptions = {mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: firstDirectory, sourceProfilePath: path}};
    for (const [index, target] of targets.entries()) {
      const profile = {...baseProfile, schema: target.schema, table: target.table};
      await writeFile(path, JSON.stringify(profile));
      if (index === 1) {
        const before = observe(firstDirectory)();
        await assert.rejects(connect(firstOptions),
          {name: 'TypeError', message: 'InstalledHostConfigurationMismatch'});
        assert.deepEqual(observe(firstDirectory)(), before,
          'changing only the physical target must refuse without provider I/O');
      }
      const directory = resolve(`exact-${field}-local-${index}`);
      const options = {...firstOptions, installation: {directory, sourceProfilePath: path}};
      const fixture = {name: `exact-${field}-${index}`, format: 'sql',
        text: 'SELECT id, amount FROM records ORDER BY id',
        expected: target.rows, columns: [
          {name: 'id', contract: {type: 'number', nullable: false}},
          {name: 'amount', contract: {type: 'number', nullable: true}},
        ]};
      await exercisePublicQueryInput(connect, options, {
        requestPrefix: 'exact-local', observe: observe(directory),
        successes: [fixture], refusals: []});
      const before = observe(directory)();
      await writeFile(path, JSON.stringify(Object.fromEntries(
        Object.entries(profile).reverse()), null, 2) + '\n');
      const unchanged = await connect(options);
      unchanged.close();
      assert.deepEqual(observe(directory)(), before,
        'unchanged target with reordered JSON must reuse without provider I/O');
      const remoteDirectory = resolve(`exact-${field}-remote-${index}`);
      const remoteHost = await openInstalledRemoteHttpHost({directory: remoteDirectory,
        sourceProfilePath: path, authenticate: header => header === 'Bearer fixture-token'
          ? userInfo().username : undefined});
      const remoteServer = createServer({key: await readFile('remote.key'),
        cert: await readFile('remote.crt')}, remoteHost.handler);
      try {
        await new Promise(resolve => remoteServer.listen(0, '127.0.0.1', resolve));
        await exercisePublicQueryInput(connect, {mode: 'remote',
          endpoint: `https://127.0.0.1:${remoteServer.address().port}/`,
          token: 'fixture-token', durability: 'durable'}, {
          requestPrefix: 'exact-http', observe: observe(remoteDirectory),
          successes: [fixture], refusals: []});
      } finally {
        remoteServer.closeAllConnections();
        await new Promise(resolve => remoteServer.close(resolve));
        await remoteHost.close();
      }
    }
  }
}
const retainedStrings = {};
const recordString = mode => item => {
  if (item.name === 'exact-string-values') retainedStrings[mode] = item;
};
await exercisePublicQueryInput(connect, {mode: 'local', owner: 'local',
  durability: 'durable', installation: {directory: localDirectory,
    sourceProfilePath}}, {requestPrefix: 'packed-local',
  observe: observe(localDirectory), prepareCase, completedCase: recordString('local'), ...scopeInputs});
assert.equal(observe(localDirectory)().acceptedRuns, expectedQueryRuns);
assert.ok(sourceIo >= expectedSourceReads);
console.log(`packed raw SQL/Pipe Embedded Local ${profileName} acceptance passed`);
const beforeRemote = sourceIo;
const host = await openInstalledRemoteHttpHost({
  directory: remoteDirectory, sourceProfilePath,
  authenticate: header => header === 'Bearer fixture-token'
    ? userInfo().username : undefined,
});
const server = createServer({key: await readFile('remote.key'),
  cert: await readFile('remote.crt')}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  await exercisePublicCheck({mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-token'});
  await exercisePublicQueryInput(connect, {mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'fixture-token', durability: 'durable'},
  {requestPrefix: 'packed-http', observe: observe(remoteDirectory), prepareCase, completedCase: recordString('remote'), ...scopeInputs});
  assert.equal(observe(remoteDirectory)().acceptedRuns, expectedQueryRuns);
  assert.ok(sourceIo >= beforeRemote + expectedSourceReads);
  console.log(`packed raw SQL/Pipe HTTP ${profileName} acceptance passed`);
  if (!scopeOnly && profileName === 'standard') await exerciseExactPhysicalTargets();
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
  DuckDBPreparedStatement.prototype.stream = stream;
  DuckDBConnection.prototype.extractStatements = extract;
  DuckDBExtractedStatements.prototype.prepare = prepare;
}
if (retainedStrings.local && retainedStrings.remote) {
  await writeFile('retained-string-results.json', JSON.stringify(retainedStrings));

}
}
if (!scopeOnly) await import('./packed-two-source-public-query.mjs');
}
