import {windowGroupSourceSuccesses, windowGroupSourceRefusals} from './window-group-source-input.mjs';
import {sequenceSourceSuccesses, sequenceSourceRefusals} from './sequence-source-input.mjs';
import {temporalJoinSourceSuccesses, temporalJoinSourceRefusals} from './temporal-join-source-input.mjs';
import {timeSeriesPrimarySuccesses, timeSeriesPrimaryRefusals} from './time-series-primary-source-input.mjs';
import {rankingFusionSourceSuccesses, rankingFusionSourceRefusals} from './ranking-fusion-source-input.mjs';
import {carrierContinuationSuccesses, carrierContinuationRefusals} from './carrier-continuation-source-input.mjs';
import {lagSourceSuccesses, lagSourceRefusals} from './lag-source-input.mjs';
import {rowWatermarkSourceSuccesses, rowWatermarkSourceRefusals} from './row-watermark-source-input.mjs';
import {eventDedupeSourceSuccesses, eventDedupeSourceRefusals, eventDedupeSourceExecutionFailures} from './event-dedupe-source-input.mjs';
import {distinctOrderReceiverSuccesses, distinctOrderReceiverRefusals} from './distinct-order-receiver-source-input.mjs';
import {distinctJoinOrderSuccesses, distinctJoinOrderRefusals, distinctJoinOrderExecutionFailures}
  from './distinct-join-order-source-input.mjs';
import {requireDistinctJoinOrderInventory} from './distinct-join-order-inventory.mjs';
import {groupedRowsBoundarySuccesses, groupedRowsBoundaryRefusals} from './grouped-rows-boundary-source-input.mjs';
import {positiveLimitSuccesses, positiveLimitRefusals} from './positive-limit-source-input.mjs';
import {groupOrderRangeAliasSuccesses, groupOrderRangeAliasRefusals} from './group-order-range-alias-source-input.mjs';
import {hexIntegerSuccesses, hexIntegerRefusals} from './hex-integer-source-input.mjs';
import {unpivotMulticolumnSuccesses, unpivotMulticolumnRefusals} from './unpivot-multicolumn-source-input.mjs';
import {cteValueTableSuccesses, cteValueTableRefusals} from './cte-value-table-source-input.mjs';
import {createCteValueTableReceipts, createVerifiedCaseReceipts} from './cte-value-table-receipts.mjs';
import {unpivotRowLabelSuccesses, unpivotRowLabelRefusals} from './unpivot-row-label-source-input.mjs';
import {fromUnpivotSuccesses, fromUnpivotRefusals} from './from-unpivot-source-input.mjs';
import {pipePivotSuccesses, pipePivotRefusals} from './pipe-pivot-source-input.mjs';
import {graphRelationJoinSuccesses, graphRelationJoinRefusals, graphRelationJoinExecutionFailures} from './graph-relation-join-source-input.mjs';
import {traversalJoinSuccesses, traversalJoinRefusals, traversalJoinExecutionFailures} from './traversal-join-source-input.mjs';
import {graphRowsJoinSuccesses, graphRowsJoinRefusals, graphRowsJoinExecutionFailures} from './graph-rows-join-source-input.mjs';
import {betweenSuccesses, betweenRefusals, betweenExecutionFailures} from './between-source-input.mjs';
import {ifnullCoalesceReuseSuccesses, ifnullCoalesceReuseRefusals, ifnullCoalesceReuseExecutionFailures} from './ifnull-coalesce-reuse-source-input.mjs';
import {concatReuseSuccesses, concatReuseRefusals} from './concat-expression-reuse-source-input.mjs';
import {encodeRetainedFixture} from './retained-fixture-values.mjs';
import {groupPropertyReceiverSuccesses, groupPropertyReceiverRefusals} from './group-property-receiver-source-input.mjs';
import {distinctSignedOrderSuccesses, distinctSignedOrderRefusals} from './distinct-signed-order-source-input.mjs';
import {distinctAggregateOrderSuccesses, distinctAggregateOrderRefusals} from './distinct-aggregate-order-source-input.mjs';
import {analyticDistinctFrameSuccesses, analyticDistinctFrameRefusals} from './analytic-distinct-frame-source-input.mjs';
import {countifDistinctSuccesses, countifDistinctRefusals} from './countif-distinct-source-input.mjs';
import {minMaxDistinctSuccesses, minMaxDistinctRefusals} from './min-max-distinct-source-input.mjs';
import {pipeDistinctSuccesses, pipeDistinctRefusals} from './pipe-distinct-source-input.mjs';
import {groupByAllSuccesses, groupByAllRefusals} from './group-by-all-source-input.mjs';
import {correlatedUnnestSuccesses, correlatedUnnestRefusals} from './correlated-unnest-source-input.mjs';
import {unnestCheckedArraySuccesses, unnestCheckedArrayRefusals} from './unnest-checked-array-source-input.mjs';
import {negatedPredicateReuseSuccesses, negatedPredicateReuseRefusals} from './negated-predicate-reuse-source-input.mjs';
import {membershipReuseSuccesses, membershipReuseRefusals} from './membership-expression-reuse-source-input.mjs';
import {inUnnestLiteralArraySuccesses, inUnnestLiteralArrayRefusals,
  inUnnestLiteralArrayExecutionFailures} from './in-unnest-literal-array-source-input.mjs';
import {arrayLiteralSuccesses, arrayLiteralRefusals} from './array-literal-source-input.mjs';
import {unnestSuccesses, unnestRefusals} from './unnest-source-input.mjs';
import {pipeUnpivotSuccesses, pipeUnpivotRefusals} from './pipe-unpivot-source-input.mjs';
import {unnestParameterPathSuccesses, unnestParameterPathRefusals} from './unnest-parameter-path-source-input.mjs';
import {fullJoinScopeSuccesses, fullJoinScopeRefusals} from './full-join-scope-source-input.mjs';
import {characterLengthSuccesses, characterLengthRefusals} from './character-length-source-input.mjs';
import {qualifiedStarSuccesses, qualifiedStarRefusals} from './qualified-star-source-input.mjs';
import {rightJoinSuccesses, rightJoinRefusals} from './right-join-source-input.mjs';
import {joinStarSuccesses, joinStarRefusals, joinStarExecutionFailures} from './join-star-source-input.mjs';
import {pipeJoinInputSuccesses, pipeJoinInputRefusals} from './pipe-join-input.mjs';
import {pipeJoinRangesSuccesses, pipeJoinRangesRefusals} from './pipe-join-ranges.mjs';
import {starReplaceSuccesses, starReplaceRefusals} from './star-replace-source-input.mjs';
import {qualifySuccesses, qualifyRefusals, qualifyExecutionFailures} from './qualify-source-input.mjs';
import {namedWindowSuccesses, namedWindowRefusals} from './named-window-source-input.mjs';
import {upperSuccesses, upperRefusals, upperExecutionFailures} from './upper-source-input.mjs';
import {absSuccesses, absRefusals, absExecutionFailures} from './abs-source-input.mjs';
import {lowerSuccesses, lowerRefusals, lowerExecutionFailures} from './lower-source-input.mjs';
import {replaceCallSuccesses, replaceCallRefusals, replaceCallExecutionFailures}
  from './replace-call-source-input.mjs';
import {selectAllSuccesses, selectAllRefusals} from './select-all-source-input.mjs';
import {starExclusionSuccesses, starExclusionRefusals} from './star-exclusion-source-input.mjs';
import {analyticPartitionExpressionSuccesses, analyticPartitionExpressionRefusals, analyticPartitionExpressionExecutionFailures}
  from './analytic-partition-expression-source-input.mjs';
import {graphSubtractionSourceSuccesses, graphSubtractionSourceRefusals, graphSubtractionSourceExecutionFailures}
  from './graph-subtraction-source-input.mjs';
import {graphUnionSourceSuccesses, graphUnionSourceRefusals, graphUnionSourceExecutionFailures}
  from './graph-union-source-input.mjs';
import {graphGraftSourceSuccesses, graphGraftSourceRefusals, graphGraftSourceExecutionFailures}
  from './graph-graft-source-input.mjs';
import {graphShortestSourceSuccesses, graphShortestSourceRefusals}
  from './graph-shortest-source-input.mjs';
import {graphMeanSourceOracles, graphMeanSourceRefusals}
  from './graph-mean-source-input.mjs';
import {inputStageResultSuccesses} from './input-stage-result.mjs';
import {typedSubscriptSuccesses, typedSubscriptRefusals, typedSubscriptExecutionFailures}
  from './typed-subscript-input.mjs';
import {graphRemainingOperationInputs, graphRemainingOperationCohortInputs}
  from './graph-remaining-operation-inputs.mjs';
import {createRetainedGraphAuthorization, observeRetainedGraphDispatch}
  from './retained-graph-observer.mjs';
import {statisticalAggregateSuccesses, statisticalAggregateRefusals, statisticalAggregateExecutionFailures}
  from './statistical-aggregate-source-input.mjs';
import {limitParameterSuccesses, limitParameterRefusals} from './limit-parameter-source-input.mjs';
import {sqrtSuccesses, sqrtRefusals, sqrtExecutionFailures} from './sqrt-source-input.mjs';
import {ceilingSuccesses, ceilingRefusals, ceilingExecutionFailures}
  from './ceiling-source-input.mjs';
import {unaryPlusSuccesses, unaryPlusRefusals, unaryPlusExecutionFailures}
  from './unary-plus-source-input.mjs';
import {aggregateFilterSuccesses, aggregateFilterRefusals, aggregateFilterExecutionFailures}
  from './aggregate-filter-source-input.mjs';
import {ifnullSuccesses, ifnullRefusals, ifnullExecutionFailures}
  from './ifnull-source-input.mjs';
import {havingObjectPropertySuccesses, havingObjectPropertyRefusals, havingObjectPropertyExecutionFailures}
  from './having-object-property-source-input.mjs';
import {analyticPartitionPropertySuccesses, analyticPartitionPropertyRefusals}
  from './analytic-partition-property-source-input.mjs';
import {aggregatePropertyOrderSuccesses, aggregatePropertyOrderRefusals, aggregatePropertyOrderExecutionFailures}
  from './aggregate-property-order-source-input.mjs';
import {aggregateConditionalOrderSuccesses, aggregateConditionalOrderRefusals}
  from './aggregate-conditional-order-source-input.mjs';
import {aggregateSignedOrderSuccesses, aggregateSignedOrderRefusals}
  from './aggregate-signed-order-source-input.mjs';
import {orderAggregateExpressionSuccesses, orderAggregateExpressionRefusals, orderAggregateExpressionExecutionFailures}
  from './order-aggregate-expression-source-input.mjs';
import {selectAggregateExpressionSuccesses, selectAggregateExpressionRefusals, selectAggregateExpressionExecutionFailures}
  from './select-aggregate-expression-source-input.mjs';
import {havingAggregateSuccesses, havingAggregateRefusals, havingAggregateExecutionFailures}
  from './having-aggregate-source-input.mjs';
import {setByNameListSuccesses, setByNameListRefusals} from './set-by-name-list-source-input.mjs';
import {setCorrespondingSuccesses, setCorrespondingRefusals, setCorrespondingExecutionFailures} from './set-corresponding-source-input.mjs';
import {setJoinSuccesses, setJoinRefusals} from './set-join-source-input.mjs';
import {setInnerByNameSuccesses, setInnerByNameRefusals} from './set-inner-by-name-source-input.mjs';
import {shortRowsSuccesses, shortRowsRefusals} from './short-rows-source-input.mjs';
import {orderWindowSuccesses, orderWindowRefusals} from './order-window-source-input.mjs';
import {windowScalarSuccesses, windowScalarRefusals, windowScalarExecutionFailures}
  from './window-scalar-source-input.mjs';
import {analyticCountifSuccesses, analyticCountifRefusals, analyticCountifExecutionFailures}
  from './analytic-countif-source-input.mjs';
import {analyticStringAggSuccesses, analyticStringAggRefusals, analyticStringAggExecutionFailures}
  from './analytic-string-agg-source-input.mjs';
import {analyticFrameParameterCapacity, analyticFrameParameterSuccesses, analyticFrameParameterRefusals}
  from './analytic-frame-parameter-source-input.mjs';
import {groupedInSuccesses, groupedInRefusals} from './grouped-in-source-input.mjs';
import {subgraphSourceSuccesses, subgraphSourceRefusals, subgraphSourceExecutionFailures}
  from './subgraph-source-input.mjs';
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
import * as publicCheckSdk from '@actql/sdk';
import {exerciseUnaliasedColumnOrigins} from './unaliased-column-origin.mjs';
import {exerciseGraphArgumentChecks, graphArgumentCheckInventory, graphArgumentNoExecution,
  requireGraphArgumentCheckReport} from './graph-argument-check.mjs';
import {openInstalledRemoteHttpHost} from
  '@actql/local-node/http-host';
const {createLocalRetainedStore} = await import(new URL(
  './adapters/store-local/files.mjs', import.meta.resolve('@actql/local-node')));
import {exercisePublicQueryInput, querySuccesses, queryRefusals, inferRefusals, sourceRows, sourceFreeSuccesses, sourceFreeRefusals, queryCompositionSuccesses, queryCompositionRefusals, pipeResultSuccesses, pipeResultRefusals, pipeResultExecutionFailures, relationDataSuccesses, relationDataRefusals}
  from './public-query-input.mjs';

import {graphSourceSuccesses, graphSourceExecutionFailures, graphSourceRefusals}
  from "./graph-source-input.mjs";
import {groupStarSuccesses, groupStarRefusals}
  from './group-star-source-input.mjs';
import {aggregatePropertySuccesses, aggregatePropertyRefusals}
  from './aggregate-property-source-input.mjs';
import {groupOrdinalSuccesses, groupOrdinalRefusals}
  from './group-ordinal-source-input.mjs';
import {distinctOrderSuccesses, distinctOrderRefusals}
  from './distinct-order-source-input.mjs';
import {distinctOrderMemberSuccesses, distinctOrderMemberRefusals}
  from './distinct-order-member-source-input.mjs';
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
import {groupPropertySuccesses, groupPropertyRefusals, groupHavingImplicitAliasSuccesses, groupHavingImplicitAliasRefusals, orderGroupedSubexpressionSuccesses, orderGroupedSubexpressionRefusals, groupedImplicitPropertyNameSuccesses, groupedImplicitPropertyNameRefusals, havingGroupedSubexpressionSuccesses, havingGroupedSubexpressionRefusals, sqlGroupedSubexpressionSuccesses, sqlGroupedSubexpressionRefusals, pipeAggregateOrderSuccesses, pipeAggregateOrderRefusals, pipeAggregateExpressionSuccesses, pipeAggregateExpressionRefusals}
  from './group-property-source-input.mjs';
import {uniquePublicQueryCases} from './public-query-cases.mjs';
import {publicQueryProfiles} from './public-query-profiles.mjs';
import {quotedIdentifierSuccesses, quotedIdentifierRefusals}
  from './quoted-identifier-source-input.mjs';
import {orderOrdinalSuccesses, orderOrdinalRefusals}
  from './order-ordinal-source-input.mjs';
import {matchWithProducerSuccesses, matchWithProducerRefusals}
  from './match-with-producer-source-input.mjs';
import {graphMatchSourceSuccesses, graphMatchSourceRefusals}
  from './graph-match-source-input.mjs';
import {sgaOutputNameSuccesses, sgaOutputNameRefusals} from './sga-output-name-source.mjs';
import {graphRowSourceSuccesses, graphRowSourceRefusals}
  from './graph-row-source-input.mjs';
import {graphPropertyPredicateSuccesses, graphPropertyPredicateRefusals}
  from './graph-property-predicate-source-input.mjs';
import {graphQuantifierFormsSuccesses, graphQuantifierFormsRefusals} from './graph-quantifier-forms-source-input.mjs';
import {graphAbbreviatedSuccesses, graphAbbreviatedRefusals} from './graph-abbreviated-edge-source-input.mjs';
import {graphAnyDirectionSuccesses, graphAnyDirectionRefusals, graphAnyDirectionExecutionFailures}
  from './graph-any-direction-source-input.mjs';
import {graphHopNodePredicateSuccesses, graphHopNodePredicateRefusals}
  from './graph-hop-node-predicate-source-input.mjs';
import {graphTraverseSourceSuccesses, graphTraverseSourceRefusals}
  from './graph-traverse-source-input.mjs';
import {graphReachSourceSuccesses, graphReachSourceRefusals}
  from './graph-reach-source-input.mjs';
import {graphTraversePathSuccesses, graphTraversePathRefusals}
  from './graph-traverse-path-source-input.mjs';
import {graphDifferenceSourceSuccesses, graphDifferenceSourceRefusals}
  from './graph-difference-source-input.mjs';
import {graphEqualitySourceSuccesses, graphEqualitySourceRefusals}
  from './graph-equality-source-input.mjs';
import {acquiredDataSuccesses, acquiredGraphSourceSuccesses, acquiredDataRefusals}
  from './acquired-data-source-input.mjs';
import {graphProjectionPropertySuccesses, graphProjectionPropertyRefusals}
  from './graph-projection-property-source-input.mjs';
import {sourceGraphMemberSuccesses, sourceGraphMemberRefusals}
  from './source-graph-member-input.mjs';

import {graphDiagnosticSourceSuccesses, graphDiagnosticSourceRefusals, graphDiagnosticSourceExecutionFailures}
  from './graph-diagnostics-source-input.mjs';

import {transportWorker, requireCompleteInventory, sourceFixturePaths} from './packed-query-transport-owner.mjs';
const transport = process.env.ACTQL_TEST_QUERY_TRANSPORT;
assert.ok(transport === undefined || ['local', 'remote', 'tail'].includes(transport));
const worker = transport === 'local' || transport === 'remote' ? transportWorker() : undefined;
if (process.env.ACTQL_TEST_TWO_SOURCE_ONLY === '1') {
  await import('./packed-two-source-public-query.mjs');
} else {
const typedJsonOnly = process.env.ACTQL_TEST_TYPED_JSON_LITERAL_ONLY === '1';
const havingObjectPropertyOnly = process.env.ACTQL_TEST_HAVING_OBJECT_PROPERTY_ONLY === '1';
const graphOnly = process.env.ACTQL_TEST_GRAPH_SOURCE_ONLY === "1";
const graphAnyDirectionOnly = process.env.ACTQL_TEST_GRAPH_ANY_DIRECTION_ONLY === '1';
const graphAbbreviatedOnly = process.env.ACTQL_TEST_GRAPH_ABBREVIATED_ONLY === '1';
const graphQuantifierFormsOnly = process.env.ACTQL_TEST_GRAPH_QUANTIFIER_FORMS_ONLY === '1';
const graphPropertyPredicateOnly = process.env.ACTQL_TEST_GRAPH_PROPERTY_PREDICATE_ONLY === '1';
const orderAggregateExpressionOnly = process.env.ACTQL_TEST_ORDER_AGGREGATE_EXPRESSION_ONLY === '1';
const selectAggregateExpressionOnly = process.env.ACTQL_TEST_SELECT_AGGREGATE_EXPRESSION_ONLY === '1';
const havingAggregateOnly = process.env.ACTQL_TEST_HAVING_AGGREGATE_ONLY === '1';
const groupedRowsBoundaryOnly = process.env.ACTQL_TEST_GROUPED_ROWS_BOUNDARY_ONLY === '1';
const positiveLimitOnly = process.env.ACTQL_TEST_POSITIVE_LIMIT_ONLY === '1';
const limitParameterOnly = process.env.ACTQL_TEST_LIMIT_PARAMETER_ONLY === '1';
const pipePivotOnly = process.env.ACTQL_TEST_PIPE_PIVOT_ONLY === '1';
const betweenOnly = process.env.ACTQL_TEST_BETWEEN_ONLY === '1';
const hexIntegerOnly = process.env.ACTQL_TEST_HEX_INTEGER_ONLY === '1';
const aggregateFilterOnly = process.env.ACTQL_TEST_AGGREGATE_FILTER_ONLY === '1';
const ifnullOnly = process.env.ACTQL_TEST_IFNULL_ONLY === '1';
const ifnullCoalesceReuseOnly = process.env.ACTQL_TEST_IFNULL_COALESCE_REUSE_ONLY === '1';
const setCorrespondingOnly = process.env.ACTQL_TEST_SET_CORRESPONDING_ONLY === '1';
const setInnerByNameOnly = process.env.ACTQL_TEST_SET_INNER_BY_NAME_ONLY === '1';
const setByNameListOnly = process.env.ACTQL_TEST_SET_BY_NAME_LIST_ONLY === '1';
const shortRowsOnly = process.env.ACTQL_TEST_SHORT_ROWS_ONLY === '1';
const orderWindowOnly = process.env.ACTQL_TEST_ORDER_WINDOW_ONLY === '1';
const windowScalarOnly = process.env.ACTQL_TEST_WINDOW_SCALAR_ONLY === '1';
const analyticStringAggOnly = process.env.ACTQL_TEST_ANALYTIC_STRING_AGG_ONLY === '1';
const analyticCountifOnly = process.env.ACTQL_TEST_ANALYTIC_COUNTIF_ONLY === '1';
const groupedInOnly = process.env.ACTQL_TEST_GROUPED_IN_ONLY === '1';
const subgraphOnly = process.env.ACTQL_TEST_SUBGRAPH_ONLY === '1';
const analyticOffsetOnly = process.env.ACTQL_TEST_ANALYTIC_OFFSET_ONLY === '1';
const graphDiagnosticsOnly = process.env.ACTQL_TEST_GRAPH_DIAGNOSTICS_ONLY === '1';
const graphArgumentChecksSelected = graphDiagnosticsOnly ||
  process.env.ACTQL_TEST_QUERY_EXPECT_FULL_CORPUS === '1';
const graphArgumentCheckModes = new Set();
const matchWithProducerOnly = process.env.ACTQL_TEST_MATCH_WITH_PRODUCER_ONLY === '1';
const graphMatchOnly = process.env.ACTQL_TEST_GRAPH_MATCH_ONLY === '1';
const graphRelationJoinOnly = process.env.ACTQL_TEST_GRAPH_RELATION_JOIN_ONLY === '1';
const traversalJoinOnly = process.env.ACTQL_TEST_TRAVERSAL_JOIN_ONLY === '1';
const graphRowsJoinOnly = process.env.ACTQL_TEST_GRAPH_ROWS_JOIN_ONLY === '1';
const graphRowsOnly = process.env.ACTQL_TEST_GRAPH_ROWS_ONLY === '1';
const graphDifferenceOnly = process.env.ACTQL_TEST_GRAPH_DIFFERENCE_ONLY === '1';
const graphEqualityOnly = process.env.ACTQL_TEST_GRAPH_EQUALITY_ONLY === '1';
const quotedIdentifiersOnly = process.env.ACTQL_TEST_QUOTED_IDENTIFIERS_ONLY === '1';
const graphProjectionPropertyOnly = process.env.ACTQL_TEST_GRAPH_PROJECTION_PROPERTY_ONLY === '1';
const sourceGraphMemberOnly = process.env.ACTQL_TEST_SOURCE_GRAPH_MEMBER_ONLY === '1';
const orderOrdinalOnly = process.env.ACTQL_TEST_ORDER_ORDINAL_ONLY === '1';
const concatReuseOnly = process.env.ACTQL_TEST_CONCAT_REUSE_ONLY === '1';
const distinctOrderOnly = process.env.ACTQL_TEST_DISTINCT_ORDER_ONLY === '1';
const analyticPropertyOnly = process.env.ACTQL_TEST_ANALYTIC_PROPERTY_ONLY === '1';
const graphRemainingOperationsOnly = process.env.ACTQL_TEST_GRAPH_REMAINING_OPERATIONS_ONLY === '1';
const timeSeriesPrimaryOnly = process.env.ACTQL_TEST_TIME_SERIES_PRIMARY_ONLY === '1';
const windowGroupOnly = process.env.ACTQL_TEST_WINDOW_GROUP_ONLY === '1';
const sequenceSourceOnly = process.env.ACTQL_TEST_SEQUENCE_SOURCE_ONLY === '1';
const carrierContinuationOnly = process.env.ACTQL_TEST_CARRIER_CONTINUATION_ONLY === '1';
const temporalJoinOnly = process.env.ACTQL_TEST_TEMPORAL_JOIN_ONLY === '1';
const rankingFusionOnly = process.env.ACTQL_TEST_RANKING_FUSION_ONLY === '1';
const lagOnly = process.env.ACTQL_TEST_LAG_ONLY === '1';
const rowWatermarkOnly = process.env.ACTQL_TEST_ROW_WATERMARK_ONLY === '1';
const eventDedupeOnly = process.env.ACTQL_TEST_EVENT_DEDUPE_ONLY === '1';
const graphMeanOnly = process.env.ACTQL_TEST_GRAPH_MEAN_ONLY === '1';
const graphReachOnly = process.env.ACTQL_TEST_GRAPH_REACH_ONLY === '1';
const graphTraverseOnly = process.env.ACTQL_TEST_GRAPH_TRAVERSE_ONLY === '1' || graphReachOnly || graphMeanOnly || graphRemainingOperationsOnly;
const graphTraversePathsOnly = process.env.ACTQL_TEST_GRAPH_TRAVERSE_PATHS_ONLY === '1';
const scopedOrderOnly = process.env.ACTQL_TEST_SCOPED_ORDER_ONLY === '1';
const negatedPredicateReuseOnly = process.env.ACTQL_TEST_NEGATED_PREDICATE_REUSE_ONLY === '1';
const membershipReuseOnly = process.env.ACTQL_TEST_MEMBERSHIP_REUSE_ONLY === '1';
const inUnnestLiteralArrayOnly = process.env.ACTQL_TEST_IN_UNNEST_LITERAL_ARRAY_ONLY === '1';
const arrayLiteralOnly = process.env.ACTQL_TEST_ARRAY_LITERAL_ONLY === '1';
const correlatedUnnestOnly = process.env.ACTQL_TEST_CORRELATED_UNNEST_ONLY === '1';
const unnestCheckedArrayOnly = process.env.ACTQL_TEST_UNNEST_CHECKED_ARRAY_ONLY === '1';
const unnestParameterPathOnly = process.env.ACTQL_TEST_UNNEST_PARAMETER_PATH_ONLY === '1';
const unpivotMulticolumnOnly = process.env.ACTQL_TEST_UNPIVOT_MULTICOLUMN_ONLY === '1';
const unpivotRowLabelOnly = process.env.ACTQL_TEST_UNPIVOT_ROW_LABEL_ONLY === '1';
const fromUnpivotOnly = process.env.ACTQL_TEST_FROM_UNPIVOT_ONLY === '1';
const pipeUnpivotOnly = process.env.ACTQL_TEST_PIPE_UNPIVOT_ONLY === '1';
const unnestOnly = process.env.ACTQL_TEST_UNNEST_SOURCE_ONLY === '1';
const inputStageResultOnly = process.env.ACTQL_TEST_INPUT_STAGE_RESULT_ONLY === '1';
const typedSubscriptOnly = process.env.ACTQL_TEST_TYPED_SUBSCRIPT_ONLY === '1';
const sourceFreeOnly = process.env.ACTQL_TEST_SOURCE_FREE_ONLY === '1' || inputStageResultOnly || typedSubscriptOnly;
const inferOnly = process.env.ACTQL_TEST_INFER_REFUSAL_ONLY === '1';
const joinOnly = process.env.ACTQL_TEST_JOIN_ORDER_ONLY === '1';
const groupOnly = process.env.ACTQL_TEST_GROUP_SCOPE_ONLY === '1';
const groupSelectScopeOnly = process.env.ACTQL_TEST_GROUP_SELECT_SCOPE_ONLY === '1';
const implicitPropertyOnly = process.env.ACTQL_TEST_IMPLICIT_PROPERTY_ONLY === '1';
const computedObjectPropertyOnly = process.env.ACTQL_TEST_COMPUTED_OBJECT_PROPERTY_ONLY === '1';
const groupOrderRangeAliasOnly = process.env.ACTQL_TEST_GROUP_ORDER_RANGE_ALIAS_ONLY === '1';
const orderGroupedSubexpressionOnly = process.env.ACTQL_TEST_ORDER_GROUPED_SUBEXPRESSION_ONLY === '1';
const groupHavingImplicitAliasesOnly = process.env.ACTQL_TEST_GROUP_HAVING_IMPLICIT_ALIASES_ONLY === '1';
const groupedImplicitPropertyNamesOnly = process.env.ACTQL_TEST_GROUPED_IMPLICIT_PROPERTY_NAMES_ONLY === '1';
const havingGroupedSubexpressionOnly = process.env.ACTQL_TEST_HAVING_GROUPED_SUBEXPRESSION_ONLY === '1';
const sqlGroupedSubexpressionOnly = process.env.ACTQL_TEST_SQL_GROUPED_SUBEXPRESSION_ONLY === '1';
const pipeAggregateExpressionOnly = process.env.ACTQL_TEST_PIPE_AGGREGATE_EXPRESSION_ONLY === '1';
const pipeAggregateOrderOnly = process.env.ACTQL_TEST_PIPE_AGGREGATE_ORDER_ONLY === '1';
const groupByAllOnly = process.env.ACTQL_TEST_GROUP_BY_ALL_ONLY === '1';
const groupPropertyOnly = process.env.ACTQL_TEST_GROUP_PROPERTY_ONLY === '1' || pipeAggregateOrderOnly || pipeAggregateExpressionOnly || sqlGroupedSubexpressionOnly || havingGroupedSubexpressionOnly || orderGroupedSubexpressionOnly || groupedImplicitPropertyNamesOnly || groupHavingImplicitAliasesOnly;
const havingProjectionOnly = process.env.ACTQL_TEST_HAVING_PROJECTION_ONLY === '1';
const groupStarOnly = process.env.ACTQL_TEST_GROUP_STAR_ONLY === '1';
const aggregatePropertyOrderOnly = process.env.ACTQL_TEST_AGGREGATE_PROPERTY_ORDER_ONLY === '1';
const aggregatePropertyOnly = process.env.ACTQL_TEST_AGGREGATE_PROPERTY_ONLY === '1';
const groupOrdinalOnly = process.env.ACTQL_TEST_GROUP_ORDINAL_ONLY === '1';
const cteValueTableOnly = process.env.ACTQL_TEST_CTE_VALUE_TABLE_ONLY === '1';
const compositionOnly = process.env.ACTQL_TEST_QUERY_COMPOSITION_ONLY === '1';
const resultOnly = process.env.ACTQL_TEST_PIPE_RESULT_ONLY === '1';
const dataOnly = process.env.ACTQL_TEST_RELATION_DATA_ONLY === '1';
const acquiredDataOnly = process.env.ACTQL_TEST_ACQUIRED_DATA_ONLY === '1';
const dataSetStrategyOnly = process.env.ACTQL_TEST_DATA_SET_STRATEGY_ONLY === '1';
const orderPropertyOnly = process.env.ACTQL_TEST_ORDER_PROPERTY_ONLY === '1';
const analyticProfilesOnly = process.env.ACTQL_TEST_ANALYTIC_PROFILES_ONLY === '1';
const analyticPartitionExpressionOnly = process.env.ACTQL_TEST_ANALYTIC_PARTITION_EXPRESSION_ONLY === '1';
const analyticPartitionPropertyOnly = process.env.ACTQL_TEST_ANALYTIC_PARTITION_PROPERTY_ONLY === '1';
const analyticOrderOnly = process.env.ACTQL_TEST_ANALYTIC_ORDER_ONLY === '1';
const joinPropertyOnly = process.env.ACTQL_TEST_JOIN_PROPERTY_ONLY === '1';
const analyticFrameParameterOnly = process.env.ACTQL_TEST_ANALYTIC_FRAME_PARAMETER_ONLY === '1';
const minMaxDistinctOnly = process.env.ACTQL_TEST_MIN_MAX_DISTINCT_ONLY === '1';
const statisticalAggregateOnly = process.env.ACTQL_TEST_STATISTICAL_AGGREGATE_ONLY === '1';
const graphSubtractionOnly = process.env.ACTQL_TEST_GRAPH_SUBTRACTION_ONLY === '1';
const graphUnionOnly = process.env.ACTQL_TEST_GRAPH_UNION_ONLY === '1';
const graphGraftOnly = process.env.ACTQL_TEST_GRAPH_GRAFT_ONLY === '1';
const selectAllOnly = process.env.ACTQL_TEST_SELECT_ALL_ONLY === '1';
const starExclusionOnly = process.env.ACTQL_TEST_STAR_EXCLUSION_ONLY === '1';
const characterLengthOnly = process.env.ACTQL_TEST_CHARACTER_LENGTH_ONLY === '1';
const upperOnly = process.env.ACTQL_TEST_UPPER_ONLY === '1';
const absOnly = process.env.ACTQL_TEST_ABS_ONLY === '1';
const pipeDistinctOnly = process.env.ACTQL_TEST_PIPE_DISTINCT_ONLY === "1";
const lowerOnly = process.env.ACTQL_TEST_LOWER_ONLY === '1';
const replaceCallOnly = process.env.ACTQL_TEST_REPLACE_CALL_ONLY === '1';
const sqrtOnly = process.env.ACTQL_TEST_SQRT_ONLY === '1';
const ceilingOnly = process.env.ACTQL_TEST_CEILING_ONLY === '1';
const unaryPlusOnly = process.env.ACTQL_TEST_UNARY_PLUS_ONLY === '1';
const qualifiedStarOnly = process.env.ACTQL_TEST_QUALIFIED_STAR_ONLY === '1';
const fullJoinScopeOnly = process.env.ACTQL_TEST_FULL_JOIN_SCOPE_ONLY === '1';
const rightJoinOnly = process.env.ACTQL_TEST_RIGHT_JOIN_ONLY === '1';
const joinStarOnly = process.env.ACTQL_TEST_JOIN_STAR_ONLY === '1';
const pipeJoinRangesOnly = process.env.ACTQL_TEST_PIPE_JOIN_RANGES_ONLY === '1';
const pipeJoinInputOnly = process.env.ACTQL_TEST_PIPE_JOIN_INPUT_ONLY === '1';
const starReplaceOnly = process.env.ACTQL_TEST_STAR_REPLACE_ONLY === '1';
const qualifyOnly = process.env.ACTQL_TEST_QUALIFY_ONLY === '1';
const namedWindowOnly = process.env.ACTQL_TEST_NAMED_WINDOW_ONLY === '1';
const countifDistinctOnly = process.env.ACTQL_TEST_COUNTIF_DISTINCT_ONLY === '1';
const analyticDistinctFrameOnly = process.env.ACTQL_TEST_ANALYTIC_DISTINCT_FRAME_ONLY === '1';
const distinctAggregateOrderOnly = process.env.ACTQL_TEST_DISTINCT_AGGREGATE_ORDER_ONLY === '1';
const distinctOrderReceiverOnly = process.env.ACTQL_TEST_DISTINCT_ORDER_RECEIVER_ONLY === '1';
const distinctJoinOrderOnly = process.env.ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY === '1';
const scopeOnly = distinctJoinOrderOnly || windowGroupOnly || sequenceSourceOnly || rankingFusionOnly || temporalJoinOnly || timeSeriesPrimaryOnly || carrierContinuationOnly || lagOnly || rowWatermarkOnly || eventDedupeOnly || aggregateFilterOnly || distinctOrderReceiverOnly || groupOrderRangeAliasOnly || groupedRowsBoundaryOnly || positiveLimitOnly || hexIntegerOnly || unpivotMulticolumnOnly || unpivotRowLabelOnly || fromUnpivotOnly || pipePivotOnly || pipeUnpivotOnly || matchWithProducerOnly || betweenOnly || ifnullCoalesceReuseOnly || negatedPredicateReuseOnly || concatReuseOnly || absOnly || distinctAggregateOrderOnly || analyticDistinctFrameOnly || countifDistinctOnly || minMaxDistinctOnly || pipeDistinctOnly || setCorrespondingOnly || setInnerByNameOnly || groupByAllOnly || setByNameListOnly || lowerOnly || shortRowsOnly || orderWindowOnly || upperOnly || windowScalarOnly || analyticStringAggOnly || sqrtOnly || unnestCheckedArrayOnly || inUnnestLiteralArrayOnly || correlatedUnnestOnly || graphAnyDirectionOnly || arrayLiteralOnly || graphQuantifierFormsOnly || graphAbbreviatedOnly || pipeJoinRangesOnly || pipeJoinInputOnly || unnestOnly || unnestParameterPathOnly || ceilingOnly || fullJoinScopeOnly || orderAggregateExpressionOnly || selectAggregateExpressionOnly || havingAggregateOnly || unaryPlusOnly || replaceCallOnly || characterLengthOnly || selectAllOnly || starExclusionOnly || typedJsonOnly || analyticPartitionExpressionOnly || graphSubtractionOnly || graphUnionOnly || graphGraftOnly || statisticalAggregateOnly || graphDifferenceOnly || limitParameterOnly || ifnullOnly || aggregatePropertyOrderOnly || computedObjectPropertyOnly || havingObjectPropertyOnly || analyticPartitionPropertyOnly || analyticCountifOnly || analyticFrameParameterOnly || analyticOffsetOnly || joinPropertyOnly || analyticProfilesOnly || analyticOrderOnly || process.env.ACTQL_TEST_PIPE_SCOPE_ONLY === '1' || scopedOrderOnly || inferOnly || joinOnly || groupOnly || groupSelectScopeOnly || groupPropertyOnly || havingProjectionOnly || implicitPropertyOnly || groupStarOnly || groupOrdinalOnly || sourceFreeOnly || cteValueTableOnly || compositionOnly || resultOnly || dataOnly || acquiredDataOnly || dataSetStrategyOnly || graphOnly || graphRowsOnly || graphTraverseOnly || orderOrdinalOnly || distinctOrderOnly || graphPropertyPredicateOnly || graphProjectionPropertyOnly || sourceGraphMemberOnly || orderPropertyOnly || quotedIdentifiersOnly || graphEqualityOnly || graphDiagnosticsOnly || graphTraversePathsOnly || graphMatchOnly || aggregatePropertyOnly || analyticPropertyOnly || subgraphOnly || groupedInOnly || qualifiedStarOnly || starReplaceOnly || qualifyOnly || namedWindowOnly || rightJoinOnly || joinStarOnly || membershipReuseOnly || graphRowsJoinOnly || traversalJoinOnly || graphRelationJoinOnly;
const joinOrder = JSON.parse(await readFile('join-order-cases.json', 'utf8'));
const joinChain = JSON.parse(await readFile('join-chain-cases.json', 'utf8'));
const groupScope = JSON.parse(await readFile('group-scope-cases.json', 'utf8'));
const scope = JSON.parse(await readFile('pipe-scope-cases.json', 'utf8'));
assert.deepEqual(scope.source_rows, sourceRows);
const dataSetStrategyInputs = {
  // Retain main's independent JSON control once. The WITH binding source group shares
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
const scopeInputs = distinctJoinOrderOnly ? {successes: distinctJoinOrderSuccesses,
  refusals: distinctJoinOrderRefusals, executionFailures: distinctJoinOrderExecutionFailures}
: timeSeriesPrimaryOnly ? {successes: timeSeriesPrimarySuccesses, refusals: timeSeriesPrimaryRefusals}
: carrierContinuationOnly ? {successes: carrierContinuationSuccesses, refusals: carrierContinuationRefusals}
  : distinctOrderReceiverOnly ? {successes: distinctOrderReceiverSuccesses, refusals: distinctOrderReceiverRefusals}
  : hexIntegerOnly ? {successes: hexIntegerSuccesses, refusals: hexIntegerRefusals}
  : inputStageResultOnly ? {successes: inputStageResultSuccesses, refusals: []}
  : typedSubscriptOnly ? {successes: typedSubscriptSuccesses, refusals: typedSubscriptRefusals,
    executionFailures: typedSubscriptExecutionFailures}
  : graphRemainingOperationsOnly ? graphRemainingOperationInputs
  : concatReuseOnly ? {successes: concatReuseSuccesses, refusals: concatReuseRefusals}
  : analyticDistinctFrameOnly ? {successes: analyticDistinctFrameSuccesses, refusals: analyticDistinctFrameRefusals}
  : countifDistinctOnly ? {successes: countifDistinctSuccesses, refusals: countifDistinctRefusals}
  : minMaxDistinctOnly ? {successes: minMaxDistinctSuccesses, refusals: minMaxDistinctRefusals}
  : graphRelationJoinOnly ? {successes: graphRelationJoinSuccesses, refusals: graphRelationJoinRefusals, executionFailures: graphRelationJoinExecutionFailures}
  : traversalJoinOnly ? {successes: traversalJoinSuccesses, refusals: traversalJoinRefusals, executionFailures: traversalJoinExecutionFailures}
  : graphRowsJoinOnly ? {successes: graphRowsJoinSuccesses, refusals: graphRowsJoinRefusals, executionFailures: graphRowsJoinExecutionFailures}
  : pipePivotOnly ? {successes: pipePivotSuccesses, refusals: pipePivotRefusals, executionFailures: []}
  : betweenOnly ? {successes: betweenSuccesses, refusals: betweenRefusals, executionFailures: betweenExecutionFailures}
  : ifnullCoalesceReuseOnly ? {successes: ifnullCoalesceReuseSuccesses, refusals: ifnullCoalesceReuseRefusals, executionFailures: ifnullCoalesceReuseExecutionFailures}
  : negatedPredicateReuseOnly ? {successes: negatedPredicateReuseSuccesses, refusals: negatedPredicateReuseRefusals}
  : membershipReuseOnly ? {successes: membershipReuseSuccesses, refusals: membershipReuseRefusals}
  : inUnnestLiteralArrayOnly ? {successes: inUnnestLiteralArraySuccesses, refusals: inUnnestLiteralArrayRefusals,
    executionFailures: inUnnestLiteralArrayExecutionFailures}
  : arrayLiteralOnly ? {successes: arrayLiteralSuccesses, refusals: arrayLiteralRefusals}
  : graphQuantifierFormsOnly ? {successes: graphQuantifierFormsSuccesses, refusals: graphQuantifierFormsRefusals}
  : graphAbbreviatedOnly ? {successes: graphAbbreviatedSuccesses, refusals: graphAbbreviatedRefusals}
  : graphAnyDirectionOnly ? {successes: graphAnyDirectionSuccesses, refusals: graphAnyDirectionRefusals,
  executionFailures: graphAnyDirectionExecutionFailures}
  : pipeJoinRangesOnly ? {successes: pipeJoinRangesSuccesses, refusals: pipeJoinRangesRefusals}
  : pipeJoinInputOnly ? {successes: pipeJoinInputSuccesses, refusals: pipeJoinInputRefusals}
  : correlatedUnnestOnly ? {successes: correlatedUnnestSuccesses, refusals: correlatedUnnestRefusals}
  : unnestCheckedArrayOnly ? {successes: unnestCheckedArraySuccesses, refusals: unnestCheckedArrayRefusals}
  : unnestParameterPathOnly ? {successes: unnestParameterPathSuccesses, refusals: unnestParameterPathRefusals}
  : unpivotMulticolumnOnly ? {successes: unpivotMulticolumnSuccesses, refusals: unpivotMulticolumnRefusals}
  : unpivotRowLabelOnly ? {successes: unpivotRowLabelSuccesses, refusals: unpivotRowLabelRefusals}
  : fromUnpivotOnly ? {successes: fromUnpivotSuccesses, refusals: fromUnpivotRefusals}
  : pipeUnpivotOnly ? {successes: pipeUnpivotSuccesses, refusals: pipeUnpivotRefusals}
  : unnestOnly ? {successes: unnestSuccesses, refusals: unnestRefusals}
  : fullJoinScopeOnly ? {successes: fullJoinScopeSuccesses, refusals: fullJoinScopeRefusals}
  : namedWindowOnly ? {successes: namedWindowSuccesses, refusals: namedWindowRefusals}
  : qualifyOnly ? {successes: qualifySuccesses, refusals: qualifyRefusals, executionFailures: qualifyExecutionFailures}
  : joinStarOnly ? {successes: joinStarSuccesses, refusals: joinStarRefusals, executionFailures: joinStarExecutionFailures}
  : rightJoinOnly ? {successes: rightJoinSuccesses, refusals: rightJoinRefusals}
  : orderAggregateExpressionOnly ? {successes: orderAggregateExpressionSuccesses, refusals: orderAggregateExpressionRefusals, executionFailures: orderAggregateExpressionExecutionFailures}
  : qualifiedStarOnly ? {successes: qualifiedStarSuccesses, refusals: qualifiedStarRefusals}
  : starReplaceOnly ? {successes: starReplaceSuccesses, refusals: starReplaceRefusals}
  : selectAggregateExpressionOnly ? {successes: selectAggregateExpressionSuccesses, refusals: selectAggregateExpressionRefusals, executionFailures: selectAggregateExpressionExecutionFailures}
  : havingAggregateOnly ? {successes: havingAggregateSuccesses, refusals: havingAggregateRefusals, executionFailures: havingAggregateExecutionFailures}
  : sqrtOnly ? {successes: sqrtSuccesses, refusals: sqrtRefusals, executionFailures: sqrtExecutionFailures}
  : ceilingOnly ? {successes: ceilingSuccesses, refusals: ceilingRefusals, executionFailures: ceilingExecutionFailures}
  : unaryPlusOnly ? {successes: unaryPlusSuccesses, refusals: unaryPlusRefusals, executionFailures: unaryPlusExecutionFailures}
  : absOnly ? {successes: absSuccesses, refusals: absRefusals, executionFailures: absExecutionFailures}
  : pipeDistinctOnly ? {successes: pipeDistinctSuccesses, refusals: pipeDistinctRefusals}
  : lowerOnly ? {successes: lowerSuccesses, refusals: lowerRefusals, executionFailures: lowerExecutionFailures}
  : upperOnly ? {successes: upperSuccesses, refusals: upperRefusals, executionFailures: upperExecutionFailures}
  : replaceCallOnly ? {successes: replaceCallSuccesses, refusals: replaceCallRefusals, executionFailures: replaceCallExecutionFailures}
  : characterLengthOnly ? {successes: characterLengthSuccesses, refusals: characterLengthRefusals}
  : selectAllOnly ? {successes: selectAllSuccesses, refusals: selectAllRefusals} : starExclusionOnly ? {successes: starExclusionSuccesses, refusals: starExclusionRefusals} : typedJsonOnly ? {successes: typedJsonLiteralSuccesses, refusals: typedJsonLiteralRefusals} : analyticPartitionExpressionOnly ? {successes: analyticPartitionExpressionSuccesses, refusals: analyticPartitionExpressionRefusals, executionFailures: analyticPartitionExpressionExecutionFailures} : graphSubtractionOnly ? {successes: graphSubtractionSourceSuccesses, refusals: graphSubtractionSourceRefusals, executionFailures: graphSubtractionSourceExecutionFailures} : graphGraftOnly ? {successes: graphGraftSourceSuccesses, refusals: graphGraftSourceRefusals, executionFailures: graphGraftSourceExecutionFailures} : graphUnionOnly ? {successes: graphUnionSourceSuccesses, refusals: graphUnionSourceRefusals, executionFailures: graphUnionSourceExecutionFailures} : statisticalAggregateOnly ? {successes: statisticalAggregateSuccesses, refusals: statisticalAggregateRefusals, executionFailures: statisticalAggregateExecutionFailures} : groupedRowsBoundaryOnly ? {successes: groupedRowsBoundarySuccesses, refusals: groupedRowsBoundaryRefusals}
  : positiveLimitOnly ? {successes: positiveLimitSuccesses, refusals: positiveLimitRefusals}
  : limitParameterOnly ? {successes: limitParameterSuccesses, refusals: limitParameterRefusals} : havingObjectPropertyOnly ? {successes: havingObjectPropertySuccesses, refusals: havingObjectPropertyRefusals, executionFailures: havingObjectPropertyExecutionFailures}
  : analyticPartitionPropertyOnly ? {successes: analyticPartitionPropertySuccesses, refusals: analyticPartitionPropertyRefusals}
  : setCorrespondingOnly ? {successes: [...setCorrespondingSuccesses, ...setJoinSuccesses], refusals: [...setCorrespondingRefusals, ...setJoinRefusals], executionFailures: setCorrespondingExecutionFailures}
  : setInnerByNameOnly ? {successes: setInnerByNameSuccesses, refusals: setInnerByNameRefusals}
  : setByNameListOnly ? {successes: setByNameListSuccesses, refusals: setByNameListRefusals}
  : shortRowsOnly ? {successes: shortRowsSuccesses, refusals: shortRowsRefusals}
  : orderWindowOnly ? {successes: orderWindowSuccesses, refusals: orderWindowRefusals}
  : windowScalarOnly ? {successes: windowScalarSuccesses, refusals: windowScalarRefusals, executionFailures: windowScalarExecutionFailures}
  : distinctAggregateOrderOnly ? {successes: [...distinctAggregateOrderSuccesses, ...distinctSignedOrderSuccesses], refusals: [...distinctAggregateOrderRefusals, ...distinctSignedOrderRefusals]}
  : analyticStringAggOnly ? {successes: analyticStringAggSuccesses, refusals: analyticStringAggRefusals, executionFailures: analyticStringAggExecutionFailures}
  : analyticCountifOnly ? {successes: analyticCountifSuccesses, refusals: analyticCountifRefusals, executionFailures: analyticCountifExecutionFailures}
  : analyticFrameParameterOnly ? {successes: analyticFrameParameterSuccesses, refusals: analyticFrameParameterRefusals}
  : groupedInOnly ? {successes: groupedInSuccesses, refusals: groupedInRefusals}
  : analyticProfilesOnly ? {
  successes: [...analyticOrderInputs, ...analyticPropertySuccesses, ...analyticOffsetSuccesses],
  refusals: [...analyticOrderRefusals, ...analyticPropertyRefusals, ...analyticOffsetRefusals],
  executionFailures: analyticOrderExecutionFailures}
  : analyticOrderOnly ? {successes: analyticOrderInputs, refusals: analyticOrderRefusals, executionFailures: analyticOrderExecutionFailures}
  : aggregateFilterOnly ? {successes: aggregateFilterSuccesses, refusals: aggregateFilterRefusals, executionFailures: aggregateFilterExecutionFailures}
  : ifnullOnly ? {successes: ifnullSuccesses, refusals: ifnullRefusals, executionFailures: ifnullExecutionFailures}
  : analyticOffsetOnly ? {successes: analyticOffsetSuccesses, refusals: analyticOffsetRefusals}
  : joinPropertyOnly ? {successes: joinPropertySuccesses, refusals: joinPropertyRefusals}
  : aggregatePropertyOnly ? {successes: aggregatePropertySuccesses, refusals: aggregatePropertyRefusals}
  : analyticPropertyOnly ? {successes: analyticPropertySuccesses, refusals: analyticPropertyRefusals}
  : subgraphOnly ? {successes: subgraphSourceSuccesses, refusals: subgraphSourceRefusals, executionFailures: subgraphSourceExecutionFailures}
  : graphDiagnosticsOnly ? {successes: graphDiagnosticSourceSuccesses, refusals: graphDiagnosticSourceRefusals, executionFailures: graphDiagnosticSourceExecutionFailures}
  : aggregatePropertyOrderOnly ? {successes: [...aggregatePropertyOrderSuccesses, ...aggregateSignedOrderSuccesses, ...aggregateConditionalOrderSuccesses],
    refusals: [...aggregatePropertyOrderRefusals, ...aggregateSignedOrderRefusals, ...aggregateConditionalOrderRefusals], executionFailures: aggregatePropertyOrderExecutionFailures}
  : orderPropertyOnly ? {successes: orderPropertySuccesses, refusals: orderPropertyRefusals}
  : sourceGraphMemberOnly ? {successes: sourceGraphMemberSuccesses, refusals: sourceGraphMemberRefusals}
  : graphProjectionPropertyOnly ? {successes: graphProjectionPropertySuccesses, refusals: graphProjectionPropertyRefusals}
  : graphPropertyPredicateOnly ? {successes: [...graphPropertyPredicateSuccesses, ...graphHopNodePredicateSuccesses],
    refusals: [...graphPropertyPredicateRefusals, ...graphHopNodePredicateRefusals]}
  : implicitPropertyOnly ? {successes: implicitPropertySuccesses, refusals: implicitPropertyRefusals}
  : computedObjectPropertyOnly ? {successes: computedObjectPropertySuccesses,
    refusals: computedObjectPropertyRefusals, executionFailures: computedObjectPropertyExecutionFailures}
  : groupOrdinalOnly ? {successes: groupOrdinalSuccesses, refusals: groupOrdinalRefusals}
  : groupOrderRangeAliasOnly ? {successes: groupOrderRangeAliasSuccesses, refusals: groupOrderRangeAliasRefusals}
  : orderGroupedSubexpressionOnly ? {successes: orderGroupedSubexpressionSuccesses, refusals: orderGroupedSubexpressionRefusals}
  : groupHavingImplicitAliasesOnly ? {successes: groupHavingImplicitAliasSuccesses, refusals: groupHavingImplicitAliasRefusals}
  : groupedImplicitPropertyNamesOnly ? {successes: groupedImplicitPropertyNameSuccesses, refusals: groupedImplicitPropertyNameRefusals}
  : havingGroupedSubexpressionOnly ? {successes: havingGroupedSubexpressionSuccesses, refusals: havingGroupedSubexpressionRefusals}
  : sqlGroupedSubexpressionOnly ? {successes: sqlGroupedSubexpressionSuccesses, refusals: sqlGroupedSubexpressionRefusals}
  : pipeAggregateExpressionOnly ? {successes: pipeAggregateExpressionSuccesses, refusals: pipeAggregateExpressionRefusals}
  : pipeAggregateOrderOnly ? {successes: pipeAggregateOrderSuccesses, refusals: pipeAggregateOrderRefusals}
  : groupByAllOnly ? {successes: [...groupByAllSuccesses, ...groupPropertyReceiverSuccesses], refusals: [...groupByAllRefusals, ...groupPropertyReceiverRefusals]}
  : groupPropertyOnly ? {successes: groupPropertySuccesses, refusals: groupPropertyRefusals}
  : havingProjectionOnly ? {successes: havingProjectionSuccesses, refusals: havingProjectionRefusals}
  : groupSelectScopeOnly ? {successes: groupSelectScopeSuccesses, refusals: groupSelectScopeRefusals}
  : groupStarOnly ? {successes: groupStarSuccesses, refusals: groupStarRefusals}
  : quotedIdentifiersOnly ? {successes: quotedIdentifierSuccesses, refusals: quotedIdentifierRefusals}
  : orderOrdinalOnly ? {successes: orderOrdinalSuccesses, refusals: orderOrdinalRefusals}
  : distinctOrderOnly ? {successes: [...distinctOrderSuccesses, ...distinctOrderMemberSuccesses], refusals: [...distinctOrderRefusals, ...distinctOrderMemberRefusals]}
  : graphTraversePathsOnly ? {successes: [...graphTraverseSourceSuccesses, ...graphTraversePathSuccesses],
    refusals: [...graphTraverseSourceRefusals, ...graphTraversePathRefusals]}
  : temporalJoinOnly ? {successes: temporalJoinSourceSuccesses, refusals: temporalJoinSourceRefusals, executionFailures: []}
  : rankingFusionOnly ? {successes: rankingFusionSourceSuccesses, refusals: rankingFusionSourceRefusals, executionFailures: []}
  : windowGroupOnly ? {successes: windowGroupSourceSuccesses, refusals: windowGroupSourceRefusals, executionFailures: []}
  : sequenceSourceOnly ? {successes: sequenceSourceSuccesses, refusals: sequenceSourceRefusals, executionFailures: []}
  : lagOnly ? {successes: lagSourceSuccesses, refusals: lagSourceRefusals, executionFailures: []}
  : rowWatermarkOnly ? {successes: rowWatermarkSourceSuccesses, refusals: rowWatermarkSourceRefusals, executionFailures: []}
  : eventDedupeOnly ? {successes: eventDedupeSourceSuccesses, refusals: eventDedupeSourceRefusals, executionFailures: eventDedupeSourceExecutionFailures}
  : graphMeanOnly ? {successes: graphMeanSourceOracles, refusals: graphMeanSourceRefusals}
  : process.env.ACTQL_TEST_GRAPH_SHORTEST_ONLY === '1'
    ? {successes: graphShortestSourceSuccesses, refusals: graphShortestSourceRefusals}
  : graphTraverseOnly ? (graphReachOnly
    ? {successes: graphReachSourceSuccesses, refusals: graphReachSourceRefusals}
    : {successes: graphTraverseSourceSuccesses, refusals: graphTraverseSourceRefusals})
  : matchWithProducerOnly ? {successes: matchWithProducerSuccesses, refusals: matchWithProducerRefusals}
  : graphMatchOnly ? {successes: [...graphMatchSourceSuccesses, ...sgaOutputNameSuccesses], refusals: [...graphMatchSourceRefusals, ...sgaOutputNameRefusals]}
  : graphRowsOnly ? {successes: graphRowSourceSuccesses, refusals: graphRowSourceRefusals}
  : graphDifferenceOnly ? {successes: graphDifferenceSourceSuccesses, refusals: graphDifferenceSourceRefusals}
  : graphEqualityOnly ? {successes: graphEqualitySourceSuccesses, refusals: graphEqualitySourceRefusals}
  : scopedOrderOnly ? {
  successes: scope.successes.filter(item => item.name.startsWith('scoped-order-')),
  refusals: scope.refusals.filter(item => item.name.startsWith('scoped-order-')),
} : graphOnly ? {successes: [...graphSourceSuccesses, ...graphRowSourceSuccesses],
  executionFailures: graphSourceExecutionFailures, refusals: [...graphSourceRefusals, ...graphRowSourceRefusals]}
  : acquiredDataOnly ? {successes: [...acquiredDataSuccesses, ...acquiredGraphSourceSuccesses],
    refusals: acquiredDataRefusals}
  : dataOnly ? {successes: [...relationDataSuccesses,
  ...dataSetStrategyInputs.successes], refusals: relationDataRefusals}
  : dataSetStrategyOnly ? dataSetStrategyInputs
  : sourceFreeOnly ? {successes: sourceFreeSuccesses, refusals: sourceFreeRefusals}
  : resultOnly ? {successes: pipeResultSuccesses, refusals: pipeResultRefusals,
    executionFailures: pipeResultExecutionFailures}
  : cteValueTableOnly ? {successes: cteValueTableSuccesses, refusals: cteValueTableRefusals}
  : compositionOnly ? {successes: queryCompositionSuccesses, refusals: queryCompositionRefusals}
  : inferOnly ? {successes: [querySuccesses[0]], refusals: inferRefusals}
  : groupOnly ? groupScope : joinOnly ? joinOrder : scopeOnly ? {successes: scope.successes,
  refusals: scope.refusals} : {successes: [...dataSetStrategyInputs.successes, ...querySuccesses, ...sourceFreeSuccesses, ...queryCompositionSuccesses, ...pipeResultSuccesses, ...relationDataSuccesses, ...acquiredDataSuccesses, ...acquiredGraphSourceSuccesses, ...graphSourceSuccesses, ...scope.successes, ...joinOrder.successes, ...groupStarSuccesses, ...groupOrdinalSuccesses],
  refusals: [...queryRefusals, ...sourceFreeRefusals, ...queryCompositionRefusals, ...pipeResultRefusals, ...relationDataRefusals, ...acquiredDataRefusals, ...graphSourceRefusals, ...scope.refusals, ...inferRefusals, ...joinOrder.refusals, ...groupStarRefusals, ...groupOrdinalRefusals],
  executionFailures: [...pipeResultExecutionFailures, ...graphSourceExecutionFailures]};
if (!scopeOnly) {
  scopeInputs.successes.push(...timeSeriesPrimarySuccesses);
  scopeInputs.refusals.push(...timeSeriesPrimaryRefusals);
  scopeInputs.successes.push(...carrierContinuationSuccesses);
  scopeInputs.refusals.push(...carrierContinuationRefusals);
  scopeInputs.successes.push(...hexIntegerSuccesses);
  scopeInputs.refusals.push(...hexIntegerRefusals);
  scopeInputs.successes.push(...cteValueTableSuccesses);
  scopeInputs.refusals.push(...cteValueTableRefusals);
  scopeInputs.successes.push(...pipePivotSuccesses);
  scopeInputs.refusals.push(...pipePivotRefusals);
  scopeInputs.successes.push(...graphRelationJoinSuccesses);
  scopeInputs.refusals.push(...graphRelationJoinRefusals);
  scopeInputs.executionFailures.push(...graphRelationJoinExecutionFailures);
  scopeInputs.successes.push(...traversalJoinSuccesses);
  scopeInputs.refusals.push(...traversalJoinRefusals);
  scopeInputs.executionFailures.push(...traversalJoinExecutionFailures);
  scopeInputs.successes.push(...graphRowsJoinSuccesses);
  scopeInputs.refusals.push(...graphRowsJoinRefusals);
  scopeInputs.executionFailures.push(...graphRowsJoinExecutionFailures);
  scopeInputs.successes.push(...betweenSuccesses);
  scopeInputs.refusals.push(...betweenRefusals);
  scopeInputs.executionFailures.push(...betweenExecutionFailures);
  scopeInputs.successes.push(...ifnullCoalesceReuseSuccesses);
  scopeInputs.refusals.push(...ifnullCoalesceReuseRefusals);
  scopeInputs.executionFailures.push(...ifnullCoalesceReuseExecutionFailures);
  scopeInputs.refusals.push(...aggregateSignedOrderRefusals);
  scopeInputs.refusals.push(...aggregateConditionalOrderRefusals);
  scopeInputs.successes.push(...aggregateConditionalOrderSuccesses);
  scopeInputs.successes.push(...aggregateSignedOrderSuccesses);
  scopeInputs.refusals.push(...analyticDistinctFrameRefusals);
  scopeInputs.successes.push(...analyticDistinctFrameSuccesses);
  scopeInputs.refusals.push(...countifDistinctRefusals);
  scopeInputs.successes.push(...countifDistinctSuccesses);
  scopeInputs.successes.push(...minMaxDistinctSuccesses);
  scopeInputs.refusals.push(...minMaxDistinctRefusals);
  scopeInputs.successes.push(...groupOrderRangeAliasSuccesses);
  scopeInputs.refusals.push(...groupOrderRangeAliasRefusals);
  scopeInputs.successes.push(...groupByAllSuccesses);
  scopeInputs.successes.push(...groupPropertyReceiverSuccesses);
  scopeInputs.refusals.push(...groupPropertyReceiverRefusals);
  scopeInputs.refusals.push(...groupByAllRefusals);
  scopeInputs.successes.push(...correlatedUnnestSuccesses);
  scopeInputs.refusals.push(...correlatedUnnestRefusals);
  scopeInputs.successes.push(...negatedPredicateReuseSuccesses);
  scopeInputs.refusals.push(...negatedPredicateReuseRefusals);
  scopeInputs.successes.push(...membershipReuseSuccesses);
  scopeInputs.refusals.push(...membershipReuseRefusals);
  scopeInputs.successes.push(...inUnnestLiteralArraySuccesses);
  scopeInputs.refusals.push(...inUnnestLiteralArrayRefusals);
  scopeInputs.executionFailures.push(...inUnnestLiteralArrayExecutionFailures);
  scopeInputs.successes.push(...arrayLiteralSuccesses);
  scopeInputs.refusals.push(...arrayLiteralRefusals);
  scopeInputs.successes.push(...unpivotMulticolumnSuccesses);
  scopeInputs.refusals.push(...unpivotMulticolumnRefusals);
  scopeInputs.successes.push(...unpivotRowLabelSuccesses);
  scopeInputs.refusals.push(...unpivotRowLabelRefusals);
  scopeInputs.successes.push(...fromUnpivotSuccesses);
  scopeInputs.refusals.push(...fromUnpivotRefusals);
  scopeInputs.successes.push(...pipeUnpivotSuccesses);
  scopeInputs.refusals.push(...pipeUnpivotRefusals);
  scopeInputs.successes.push(...unnestSuccesses);
  scopeInputs.refusals.push(...unnestRefusals);
  scopeInputs.successes.push(...fullJoinScopeSuccesses);
  scopeInputs.refusals.push(...fullJoinScopeRefusals);
  scopeInputs.successes.push(...namedWindowSuccesses);
  scopeInputs.refusals.push(...namedWindowRefusals);
  scopeInputs.successes.push(...qualifySuccesses);
  scopeInputs.refusals.push(...qualifyRefusals);
  scopeInputs.executionFailures.push(...qualifyExecutionFailures);
  scopeInputs.successes.push(...pipeJoinRangesSuccesses);
  scopeInputs.refusals.push(...pipeJoinRangesRefusals);
  scopeInputs.successes.push(...pipeJoinInputSuccesses);
  scopeInputs.refusals.push(...pipeJoinInputRefusals);
  scopeInputs.successes.push(...joinStarSuccesses);
  scopeInputs.refusals.push(...joinStarRefusals);
  scopeInputs.executionFailures.push(...joinStarExecutionFailures);
  scopeInputs.successes.push(...rightJoinSuccesses);
  scopeInputs.refusals.push(...rightJoinRefusals);
  scopeInputs.successes.push(...starReplaceSuccesses);
  scopeInputs.refusals.push(...starReplaceRefusals);
  scopeInputs.successes.push(...qualifiedStarSuccesses);
  scopeInputs.refusals.push(...qualifiedStarRefusals);
  scopeInputs.successes.push(...orderAggregateExpressionSuccesses);
  scopeInputs.refusals.push(...orderAggregateExpressionRefusals);
  scopeInputs.executionFailures.push(...orderAggregateExpressionExecutionFailures);
  scopeInputs.successes.push(...selectAggregateExpressionSuccesses);
  scopeInputs.refusals.push(...selectAggregateExpressionRefusals);
  scopeInputs.executionFailures.push(...selectAggregateExpressionExecutionFailures);
  scopeInputs.successes.push(...havingAggregateSuccesses);
  scopeInputs.refusals.push(...havingAggregateRefusals);
  scopeInputs.executionFailures.push(...havingAggregateExecutionFailures);
  scopeInputs.successes.push(...sqrtSuccesses);
  scopeInputs.refusals.push(...sqrtRefusals);
  scopeInputs.executionFailures.push(...sqrtExecutionFailures);
  scopeInputs.successes.push(...ceilingSuccesses);
  scopeInputs.refusals.push(...ceilingRefusals);
  scopeInputs.executionFailures.push(...ceilingExecutionFailures);
  scopeInputs.successes.push(...unaryPlusSuccesses);
  scopeInputs.refusals.push(...unaryPlusRefusals);
  scopeInputs.executionFailures.push(...unaryPlusExecutionFailures);
  scopeInputs.successes.push(...upperSuccesses);
  scopeInputs.successes.push(...absSuccesses);
  scopeInputs.refusals.push(...absRefusals);
  scopeInputs.executionFailures.push(...absExecutionFailures);
  scopeInputs.successes.push(...pipeDistinctSuccesses);
  scopeInputs.refusals.push(...pipeDistinctRefusals);
  scopeInputs.successes.push(...lowerSuccesses);
  scopeInputs.refusals.push(...upperRefusals);
  scopeInputs.refusals.push(...lowerRefusals);
  scopeInputs.executionFailures.push(...upperExecutionFailures);
  scopeInputs.executionFailures.push(...lowerExecutionFailures);
  scopeInputs.successes.push(...replaceCallSuccesses);
  scopeInputs.refusals.push(...replaceCallRefusals);
  scopeInputs.executionFailures.push(...replaceCallExecutionFailures);
  scopeInputs.successes.push(...characterLengthSuccesses);
  scopeInputs.refusals.push(...characterLengthRefusals);
  scopeInputs.successes.push(...selectAllSuccesses);
  scopeInputs.refusals.push(...selectAllRefusals);
  scopeInputs.successes.push(...starExclusionSuccesses);
  scopeInputs.refusals.push(...starExclusionRefusals);
  scopeInputs.successes.push(...analyticPartitionExpressionSuccesses);
  scopeInputs.refusals.push(...analyticPartitionExpressionRefusals);
  scopeInputs.executionFailures.push(...analyticPartitionExpressionExecutionFailures);
  scopeInputs.successes.push(...graphSubtractionSourceSuccesses);
  scopeInputs.refusals.push(...graphSubtractionSourceRefusals);
  scopeInputs.executionFailures.push(...graphSubtractionSourceExecutionFailures);
  scopeInputs.successes.push(...graphUnionSourceSuccesses);
  scopeInputs.refusals.push(...graphUnionSourceRefusals);
  scopeInputs.executionFailures.push(...graphUnionSourceExecutionFailures);
  scopeInputs.successes.push(...graphGraftSourceSuccesses);
  scopeInputs.refusals.push(...graphGraftSourceRefusals);
  scopeInputs.executionFailures.push(...graphGraftSourceExecutionFailures);
  scopeInputs.successes.push(...graphReachSourceSuccesses);
  scopeInputs.refusals.push(...graphReachSourceRefusals);
  scopeInputs.successes.push(...graphShortestSourceSuccesses);
  scopeInputs.refusals.push(...graphShortestSourceRefusals);
  scopeInputs.successes.push(...temporalJoinSourceSuccesses);
  scopeInputs.refusals.push(...temporalJoinSourceRefusals);
  scopeInputs.successes.push(...rankingFusionSourceSuccesses);
  scopeInputs.refusals.push(...rankingFusionSourceRefusals);
  scopeInputs.successes.push(...windowGroupSourceSuccesses);
  scopeInputs.refusals.push(...windowGroupSourceRefusals);
  scopeInputs.successes.push(...sequenceSourceSuccesses);
  scopeInputs.refusals.push(...sequenceSourceRefusals);
  scopeInputs.successes.push(...lagSourceSuccesses);
  scopeInputs.refusals.push(...lagSourceRefusals);
  scopeInputs.successes.push(...rowWatermarkSourceSuccesses);
  scopeInputs.refusals.push(...rowWatermarkSourceRefusals);
  scopeInputs.successes.push(...eventDedupeSourceSuccesses);
  scopeInputs.refusals.push(...eventDedupeSourceRefusals);
  scopeInputs.executionFailures.push(...eventDedupeSourceExecutionFailures);
  scopeInputs.successes.push(...graphMeanSourceOracles);
  scopeInputs.refusals.push(...graphMeanSourceRefusals);
  scopeInputs.successes.push(...statisticalAggregateSuccesses);
  scopeInputs.refusals.push(...statisticalAggregateRefusals);
  scopeInputs.executionFailures.push(...statisticalAggregateExecutionFailures);
  scopeInputs.successes.push(...typedJsonLiteralSuccesses);
  scopeInputs.refusals.push(...typedJsonLiteralRefusals);
  scopeInputs.successes.push(...limitParameterSuccesses);
  scopeInputs.successes.push(...groupedRowsBoundarySuccesses);
  scopeInputs.refusals.push(...groupedRowsBoundaryRefusals);
  scopeInputs.successes.push(...positiveLimitSuccesses);
  scopeInputs.refusals.push(...limitParameterRefusals);
  scopeInputs.refusals.push(...positiveLimitRefusals);
  scopeInputs.successes.push(...aggregateFilterSuccesses);
  scopeInputs.refusals.push(...aggregateFilterRefusals);
  scopeInputs.executionFailures.push(...aggregateFilterExecutionFailures);
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
  scopeInputs.successes.push(...setCorrespondingSuccesses, ...setJoinSuccesses);
  scopeInputs.refusals.push(...setCorrespondingRefusals, ...setJoinRefusals);
  scopeInputs.executionFailures.push(...setCorrespondingExecutionFailures);
  scopeInputs.successes.push(...setInnerByNameSuccesses);
  scopeInputs.refusals.push(...setInnerByNameRefusals);
  scopeInputs.successes.push(...setByNameListSuccesses);
  scopeInputs.refusals.push(...setByNameListRefusals);
  scopeInputs.successes.push(...shortRowsSuccesses);
  scopeInputs.refusals.push(...shortRowsRefusals);
  scopeInputs.successes.push(...orderWindowSuccesses);
  scopeInputs.refusals.push(...orderWindowRefusals);
  scopeInputs.successes.push(...windowScalarSuccesses);
  scopeInputs.refusals.push(...windowScalarRefusals);
  scopeInputs.executionFailures.push(...windowScalarExecutionFailures);
  scopeInputs.successes.push(...distinctAggregateOrderSuccesses);
  scopeInputs.successes.push(...distinctSignedOrderSuccesses);
  scopeInputs.refusals.push(...distinctSignedOrderRefusals);
  scopeInputs.refusals.push(...distinctAggregateOrderRefusals);
  scopeInputs.successes.push(...analyticStringAggSuccesses);
  scopeInputs.refusals.push(...analyticStringAggRefusals);
  scopeInputs.executionFailures.push(...analyticStringAggExecutionFailures);
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
  scopeInputs.successes.push(...sourceGraphMemberSuccesses);
  scopeInputs.refusals.push(...sourceGraphMemberRefusals);
  scopeInputs.successes.push(...graphProjectionPropertySuccesses);
  scopeInputs.refusals.push(...graphProjectionPropertyRefusals);
  scopeInputs.successes.push(...graphAnyDirectionSuccesses);
  scopeInputs.successes.push(...graphAbbreviatedSuccesses);
  scopeInputs.successes.push(...graphQuantifierFormsSuccesses);
  scopeInputs.refusals.push(...graphAnyDirectionRefusals);
  scopeInputs.refusals.push(...graphAbbreviatedRefusals);
  scopeInputs.refusals.push(...graphQuantifierFormsRefusals);
  scopeInputs.executionFailures.push(...graphAnyDirectionExecutionFailures);
  scopeInputs.successes.push(...graphPropertyPredicateSuccesses, ...graphHopNodePredicateSuccesses);
  scopeInputs.refusals.push(...graphPropertyPredicateRefusals, ...graphHopNodePredicateRefusals);
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
  scopeInputs.successes.push(...concatReuseSuccesses);
  scopeInputs.refusals.push(...concatReuseRefusals);
  scopeInputs.successes.push(...distinctOrderSuccesses);
  scopeInputs.refusals.push(...distinctOrderRefusals);
  scopeInputs.successes.push(...distinctOrderMemberSuccesses);
  scopeInputs.refusals.push(...distinctOrderMemberRefusals);
  scopeInputs.successes.push(...distinctOrderReceiverSuccesses);
  scopeInputs.refusals.push(...distinctOrderReceiverRefusals);
  scopeInputs.successes.push(...graphRowSourceSuccesses);
  scopeInputs.refusals.push(...graphRowSourceRefusals);
  scopeInputs.successes.push(...matchWithProducerSuccesses);
  scopeInputs.refusals.push(...matchWithProducerRefusals);
  scopeInputs.successes.push(...graphMatchSourceSuccesses);
  scopeInputs.successes.push(...sgaOutputNameSuccesses);
  scopeInputs.refusals.push(...sgaOutputNameRefusals);
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
  scopeInputs.successes.push(...graphSubtractionSourceSuccesses);
  scopeInputs.refusals.push(...graphSubtractionSourceRefusals);
  scopeInputs.executionFailures.push(...graphSubtractionSourceExecutionFailures);
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
// A completed public case retains its Run, Results and read evidence. Client
// close releases live owners but deliberately preserves those durable objects.
// Bound independent fixture cohorts; a whole case, including attach/resend,
// always stays in one installation. This does not change a Host capacity.
function publicQueryCohorts(inputs) {
  const cohorts = [];
  let current = {successes: [], executionFailures: [], refusals: []};
  // Count distinct references before any content-address deduplication. The
  // Store owner allows 8R + 11 for publication; each read retains a grant,
  // attempt, two records and receipt, and describe retains one manifest grant.
  // Also reserve one fresh-process read/describe per Result for every case
  // (only the first/last are exercised), plus the existing String restart.
  const maxObjects = 10000;
  const publicationObjects = results => 8 * results + 11;
  // Each fresh delivery performs two complete prior-attempt scans. Keeping
  // N(N-1) <= 4096 bounds those admission scans across a cohort; this is a
  // harness work bound, not a product limit or an allowance for parallel work.
  const maxDeliveryContractVisits = 4096;
  const maxDeliveryAttempts = Math.floor((1 + Math.sqrt(1 +
    4 * maxDeliveryContractVisits)) / 2);
  const deliveryObjects = 5;
  const descriptionObjects = 1;
  let retainedObjectAllowance = 0;
  let deliveryAttemptAllowance = 0;
  for (const kind of ['successes', 'executionFailures', 'refusals']) {
    for (const item of inputs[kind] ?? []) {
      const results = kind === 'successes'
        ? Math.max(1, Object.keys(item.results ?? {answer: null}).length)
        : kind === 'executionFailures' ? Math.max(1, item.resultNames.length) : 0;
      const allowance = kind === 'refusals' ? 0 : publicationObjects(results) +
        results * (3 * deliveryObjects + 2 * descriptionObjects) +
        (item.name === 'sql' ? deliveryObjects : 0) +
        (item.name === 'exact-string-values' ? deliveryObjects + descriptionObjects : 0);
      const deliveries = 3 * results +
        (item.name === 'sql' ? 1 : 0) + (item.name === 'exact-string-values' ? 1 : 0);
      assert.ok(allowance <= maxObjects && deliveries <= maxDeliveryAttempts,
        `Public query case ${item.name} exceeds an indivisible cohort budget: ` +
        `${allowance}/${maxObjects} objects, ${deliveries}/${maxDeliveryAttempts} deliveries`);
      if (retainedObjectAllowance !== 0 &&
          (retainedObjectAllowance + allowance > maxObjects ||
            deliveryAttemptAllowance + deliveries > maxDeliveryAttempts)) {
        cohorts.push(current);
        current = {successes: [], executionFailures: [], refusals: []};
        retainedObjectAllowance = 0;
        deliveryAttemptAllowance = 0;
      }
      // Never split an authored multi-Result case or lower its own limits.
      current[kind].push(item);
      retainedObjectAllowance += allowance;
      deliveryAttemptAllowance += deliveries;
    }
  }
  if (Object.values(current).some(items => items.length > 0) || cohorts.length === 0) cohorts.push(current);
  for (const kind of ['successes', 'executionFailures', 'refusals']) {
    assert.deepEqual(cohorts.flatMap(cohort => cohort[kind]), inputs[kind] ?? [],
      'cohorts preserve every authored case in original order');
  }
  for (const cohort of cohorts) for (const kind of ['successes', 'executionFailures']) {
    assert.equal(new Set(cohort[kind].map(item => item.name)).size, cohort[kind].length,
      'independent accepted cases cannot reuse a submission nonce within one cohort');
  }
  return cohorts;
}
const retainedCohorts = [];
const timeSeriesPrimaryReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'time-series-primary', version: 'actql-time-series-primary-acceptance/0.1',
});
const carrierContinuationReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'carrier-continuation', version: 'actql-carrier-continuation-acceptance/0.1',
});
const cteValueTableReceipts = createCteValueTableReceipts(transport ?? 'both', writeFile);
const temporalJoinReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'temporal-join', version: 'actql-temporal-join-acceptance/0.1',
});
const rankingFusionReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'ranking-fusion', version: 'actql-ranking-fusion-acceptance/0.1',
});
const quotedIdentifierReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'quoted-identifier', version: 'actql-quoted-identifier-acceptance/0.1',
});
const windowGroupReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'window-group', version: 'actql-window-group-acceptance/0.1',
});
const sequenceReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'sequence-source', version: 'actql-sequence-source-acceptance/0.1',
});
const lagReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'lag', version: 'actql-lag-acceptance/0.1',
});
const unpivotMulticolumnReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'unpivot-multicolumn', version: 'actql-unpivot-multicolumn-acceptance/0.1',
});
const unpivotRowLabelReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'unpivot-row-label', version: 'actql-unpivot-row-label-acceptance/0.1',
});
const fromUnpivotReceipts = createVerifiedCaseReceipts(transport ?? 'both', writeFile, {
  prefix: 'from-unpivot', version: 'actql-from-unpivot-acceptance/0.1',
});
let expectedRetainedCohorts = 0;
const expectedInventory = [], completedInventory = [];
const inventoryKeys = (profile, inputs, offsets = {}) => ['successes', 'executionFailures', 'refusals']
  .flatMap(kind => {
    const offset = offsets[kind] ?? 0, values = inputs[kind] ?? [];
    offsets[kind] = offset + values.length;
    return values.map((item, index) => JSON.stringify([profile, kind, offset + index, item.name,
      createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')]));
  });
// Host profiles are immutable within an installation. Keep each fixture's
// declared analytic envelope, including when the full corpus combines profiles.
for (const {name: profileName, capacity: analyticCapacity, inputs: profileInputs}
  of publicQueryProfiles(scopeInputs)) {
if (transport === 'tail' && profileName !== 'standard') continue;
const completedOffsets = {};
const scopeInputs = profileInputs;
const cohorts = graphRemainingOperationsOnly
  ? graphRemainingOperationCohortInputs(scopeInputs).flatMap(publicQueryCohorts)
  : publicQueryCohorts(scopeInputs);
if (transport !== 'tail') {
  const expectedOffsets = {};
  expectedInventory.push(...(graphRemainingOperationsOnly
    ? cohorts.flatMap(cohort => inventoryKeys(profileName, cohort, expectedOffsets))
    : inventoryKeys(profileName, profileInputs)));
  if (distinctJoinOrderOnly) requireDistinctJoinOrderInventory(expectedInventory);
}
if (transport !== 'tail') expectedRetainedCohorts += cohorts.filter(cohort => cohort.successes.length > 0).length;
// The independent fresh-process String regression uses these original roots.
if (scopeInputs.successes.some(item => item.name === 'exact-string-values')) {
  assert.ok(cohorts[0].successes.some(item => item.name === 'exact-string-values'));
}
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
const hostCapacityPolicy = {...base.host_policy_profile.capacity, ...analyticCapacity};
environment.host_policy_profile = {...base.host_policy_profile, capacity: hostCapacityPolicy};
environment.connector_capabilities[0].capability_contract_cids = [
  'sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d',
  'sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929',
];
environment.connector_capabilities[0].capability_contract_cids.sort();
delete environment.evidence_bundle_cid;
environment.evidence_bundle_cid = 'sha256:' + createHash('sha256')
  .update(canonical(environment)).digest('hex');
const {database, sourceProfilePath} = sourceFixturePaths(transport, profileName);
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
  for (const {targets} of scopeOnly || profileName !== 'standard' ||
      (transport !== undefined && transport !== 'tail') ? [] : exactTargetPairs) {
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
  worker?.check();
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
// Graph CHECK uses these same installed packages, transport ownership and Source
// profile. Its absent/denied publications get independent immutable installations.
async function exercisePackedGraphArgumentChecks(mode) {
  assert.equal(profileName, 'standard');
  assert.equal(graphArgumentCheckModes.has(mode), false, 'one Graph CHECK matrix per transport');
  graphArgumentCheckModes.add(mode);
  const reportPath = `graph-argument-check.${mode}.json`;
  const report = {version: 'actql-graph-argument-check/0.1', mode,
    expectedInventory: [...graphArgumentCheckInventory], completedInventory: [], cases: [],
    noExecution: null, beforeDispatchCalls: mode === 'remote' ? 0 : null,
    complete: false, primaryError: null};
  const sourceProfile = JSON.parse(await readFile(sourceProfilePath, 'utf8'));
  const directories = [], clients = {}, cleanup = [];
  const before = {sourceIo, sourceReads, sourceReadSessions};
  let sourceOpens = 0, primary;
  const create = DuckDBInstance.create;
  DuckDBInstance.create = async function(path, ...args) {
    if (path === database) sourceOpens++;
    return Reflect.apply(create, this, [path, ...args]);
  };
  const counts = () => {
    const value = {runs: 0, dispatchReservations: 0, physicalReservations: 0,
      sourceOpens, sourceIo: sourceIo - before.sourceIo, sourceReads: sourceReads - before.sourceReads,
      sourceReadSessions: sourceReadSessions - before.sourceReadSessions};
    for (const directory of directories) {
      const journal = new DatabaseSync(resolve(directory, 'requests',
        'client-requests.sqlite3'), {readOnly: true});
      try {
        const row = journal.prepare(`SELECT COUNT(*) AS runs,
          COALESCE(SUM(dispatch_reserved), 0) AS dispatchReservations,
          COALESCE(SUM(physical_start_reserved), 0) AS physicalReservations
          FROM client_requests`).get();
        for (const key of ['runs', 'dispatchReservations', 'physicalReservations']) value[key] += row[key];
      } finally { journal.close(); }
    }
    return value;
  };
  const save = () => writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
  try {
    await save();
    for (const name of ['denied', 'absent']) {
      const directory = resolve(`graph-check-${mode}-${name}-state`);
      const profile = resolve(`graph-check-${mode}-${name}-profile.json`);
      const account = JSON.parse(sourceProfile.accountConfigurationWire);
      for (const entry of account.entries) entry.outcome = 'deny';
      await writeFile(profile, canonical({...sourceProfile,
        queryAliases: name === 'absent' ? [] : sourceProfile.queryAliases,
        accountConfigurationWire: canonical(account)}), {flag: 'wx'});
      const installation = {directory, sourceProfilePath: profile, hostCapacityPolicy};
      if (mode === 'local') {
        clients[name] = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
        cleanup.push(() => clients[name].close());
      } else {
        const host = await openInstalledRemoteHttpHost({...installation,
          beforeDispatch() { report.beforeDispatchCalls++; throw new Error('UnexpectedGraphCheckDispatch'); },
          authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
        cleanup.push(() => host.close());
        const server = createServer({key: await readFile('remote.key'),
          cert: await readFile('remote.crt')}, host.handler);
        await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
        cleanup.push(async () => {
          server.closeAllConnections();
          await new Promise(resolve => server.close(resolve));
        });
        clients[name] = await connect({mode: 'remote', durability: 'durable',
          endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-token'});
        cleanup.push(() => clients[name].close());
      }
      directories.push(directory);
    }
    await exerciseGraphArgumentChecks(clients, publicCheckSdk, async id => {
      worker?.check();
      assert.equal(id, graphArgumentCheckInventory[report.completedInventory.length]);
      const noExecution = counts();
      assert.deepEqual(noExecution, graphArgumentNoExecution, id);
      assert.equal(report.beforeDispatchCalls, mode === 'remote' ? 0 : null, id);
      report.completedInventory.push(id);
      report.cases.push({id, noExecution});
      await save();
    });
    report.noExecution = counts();
    report.complete = true;
    requireGraphArgumentCheckReport(report, mode);
  } catch (error) {
    primary = error;
  } finally {
    try { report.noExecution = counts(); }
    catch (error) {
      if (primary === undefined) primary = error;
      else primary.evidenceError = error;
    }
    for (const close of cleanup.reverse()) {
      try { await close(); }
      catch (error) {
        (report.cleanupErrors ??= []).push(error.message);
        primary ??= error;
      }
    }
    DuckDBInstance.create = create;
    report.complete = primary === undefined && report.complete;
    report.primaryError = primary?.message ?? null;
    try { await save(); }
    catch (error) {
      if (primary === undefined) primary = error;
      else primary.evidenceError = error;
    }
  }
  if (primary !== undefined) throw primary;
}
// Public check must also work from installed tarballs, without repository imports.
async function exercisePublicCheck(options) {
  const client = await connect(options);
  try {
  const first = await client.check('SELECT 1 AS n', {kind: 'text', scope: 'bound_input', format: 'sql'});
  assert.equal(first.report.verdict, 'verified');
  assert.deepEqual(await client.check('SELECT 1 AS n', {kind: 'text', scope: 'bound_input', format: 'sql'}), first);
  const invalid = await client.check('SELECT missing AS n', {kind: 'text', scope: 'bound_input', format: 'sql'});
  assert.equal(invalid.report.verdict, 'invalid');
  assert.notEqual(invalid.report.context_ref, first.report.context_ref);
  const directory = options.mode === 'remote' ? remoteDirectory : localDirectory;
  const beforeColumnChecks = observe(directory)();
  await exerciseUnaliasedColumnOrigins(client, publicCheckSdk);
  assert.deepEqual(observe(directory)(), beforeColumnChecks,
    'column diagnostics must not admit a Run or perform provider I/O');
  for (const pair of [['e\u0301', 'é'], ['\r', '\n']]) {
    const refs = [];
    for (const x of pair) {
      const result = await client.check('SELECT @x AS n', {kind: 'text', scope: 'bound_input', format: 'sql',
        parameterDeclarations: {x: {type: 'string'}}, parameters: {x}});
      assert.equal(result.report.verdict, 'verified');
      refs.push(result.report.context_ref);
    }
    assert.notEqual(refs[0], refs[1]);
  }
  const budget = await client.check('SELECT id FROM never_configured', {kind: 'text', scope: 'bound_input',
    format: 'sql', parameterDeclarations: {x: {type: 'array', items: {type: 'number'}}},
    parameters: {x: Array(9000).fill(1)}});
  assert.equal(budget.report.verdict, 'undetermined');
  assert.deepEqual(budget.report.reasons, []);
  assert.deepEqual(budget.report.coverage, {
    limits: [{code: 'analysis_budget_exhausted'}],
    unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
  if (graphArgumentChecksSelected && profileName === 'standard') {
    await exercisePackedGraphArgumentChecks(options.mode);
  }
  console.log(`packed public check ${options.mode} passed`);
  } finally { await client.close(); }
}
if (transport === undefined || transport === 'local') await exercisePublicCheck({mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: localDirectory, sourceProfilePath, hostCapacityPolicy}});
// Extend the same public harness; no second lifecycle/fault matrix. Each
// physical spelling has independently authored rows and its own explicit Host.
async function exerciseExactPhysicalTargets() {
  const baseProfile = JSON.parse(await readFile(sourceProfilePath, 'utf8'));
  for (const {field, targets} of exactTargetPairs) {
    const path = resolve(`exact-${field}-source.json`);
    const firstDirectory = resolve(`exact-${field}-local-0`);
    const firstOptions = {mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: firstDirectory, sourceProfilePath: path, hostCapacityPolicy}};
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
      const options = {...firstOptions, installation: {directory, sourceProfilePath: path, hostCapacityPolicy}};
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
        sourceProfilePath: path, hostCapacityPolicy, authenticate: header => header === 'Bearer fixture-token'
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
const cohortDirectory = (root, index) => index === 0 ? root : `${root}-cohort-${index + 1}`;
const cohortRunCount = cohort => cohort.successes.length + cohort.executionFailures.length;
function observeInputStageStore(authorization, leases) {
  if (!inputStageResultOnly) return authorization;
  Object.assign(authorization.faultInjection, {async localSnapshotStoreFactory({key,bytes,frame,parentDirectory}) {
    const store = await createLocalRetainedStore({parentDirectory,
      capacityBytes:bytes,maxFrameBytes:frame,maxEntries:1});
    leases.push({key,store});
    return store;
  }});
  return authorization;
}
function verifyInputStageStore(leases) {
  if (!inputStageResultOnly) return;
  assert.ok(leases.some(lease => lease.key === 'task-1'),
    'Input-only task must transfer its output through the real retained Store');
  for (const {store} of leases) {
    assert.equal(store.status().reservedBytes,0);
    assert.equal(store.status().cleanupPending,false);
  }
}
// The Source profile's account admits its physical read, not public Run/Result
// observation. Install only this operator's declared fixture targets at HTTPS.
function createPublicQueryHttpAuthorization(cohort) {
  const results = [...new Set(cohort.successes.flatMap(item =>
    Object.keys(item.results ?? {[cohort.primaryResultName ?? 'answer']: null})))].sort();
  return {accountConfiguration: canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'packed-query-http',
    entries: [{entry_id: 'read-original', outcome: 'allow',
      principal: {any_of: [userInfo().username]},
      connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['run', ...results.map(name => 'result/' + name)].sort()},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'request-original', outcome: 'allow',
      principal: {any_of: [userInfo().username]},
      connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['duckdb-acquired']},
      operation: {any_of: ['write']}, exclusions: []}],
  })};
}
const recordCohort = (mode, directory, cohort, authorization) => {
  // Save independently authored boundary oracles for the existing fresh-process
  // public Client regression; it never imports or reruns the partition helper.
  const boundaryNames = new Set([cohort.successes[0]?.name,
    cohort.successes.at(-1)?.name]);
  const saved = {mode, profileName, directory, sourceProfilePath, hostCapacityPolicy, samples: []};
  if (inputStageResultOnly) saved.retainedRelationOutput = true;
  if (graphRemainingOperationsOnly || inputStageResultOnly || typedSubscriptOnly) {
    saved.expectedSampleNames = [...boundaryNames];
  }
  if (authorization !== undefined) saved.authorization = authorization;
  if (cohort.successes.length > 0) retainedCohorts.push(saved);
  return async item => {
    recordString(mode)(item);
    if (item.name.startsWith('time-series-primary-')) await timeSeriesPrimaryReceipts.record(item, mode);
    if (item.name.startsWith('carrier-continuation-')) await carrierContinuationReceipts.record(item, mode);
    if (item.name.startsWith('temporal-')) await temporalJoinReceipts.record(item, mode);
    if (item.name.startsWith('ranking-fusion-')) await rankingFusionReceipts.record(item, mode);
    if (item.name.startsWith('quoted-identifier-') || item.name.startsWith('identifier-role-')) {
      await quotedIdentifierReceipts.record(item, mode);
    }
    if (item.name.startsWith('window-group-')) await windowGroupReceipts.record(item, mode);
    if (item.name.startsWith('sequence-')) await sequenceReceipts.record(item, mode);
    if (item.name.startsWith('lag-')) await lagReceipts.record(item, mode);
    if (item.name.startsWith('unpivot-multicolumn-')) await unpivotMulticolumnReceipts.record(item, mode);
    if (item.name.startsWith('unpivot-row-label-')) await unpivotRowLabelReceipts.record(item, mode);
    if (item.name.startsWith('from-unpivot-')) await fromUnpivotReceipts.record(item, mode);
    if (item.name.startsWith('cte-value-table-')) {
      // Persist after each verified case so a later failure keeps actual Run
      // and read values. No resubmission, extra read or test oracle is added.
      await cteValueTableReceipts.record(item, mode);
    }
    if (boundaryNames.has(item.name)) {
      saved.samples.push({source: cohort.successes.find(source => source.name === item.name),
        ref: item.ref, submissionRef: item.submissionRef});
    }
  };
};
try {
if (transport === undefined || transport === 'local') {
let localAcceptedRuns = 0;
for (const [index, cohort] of cohorts.entries()) {
  const directory = cohortDirectory(localDirectory, index);
  const authorization = graphRemainingOperationsOnly || inputStageResultOnly || typedSubscriptOnly
    ? createRetainedGraphAuthorization() : undefined;
  const physicalDispatches = [];
  const retainedLeases = [];
  await exercisePublicQueryInput(connect, {mode: 'local', owner: 'local',
    durability: 'durable', installation: {directory,
      sourceProfilePath, hostCapacityPolicy,
      ...(inputStageResultOnly ? {retainedRelationOutput:true} : {}),
      ...(authorization === undefined ? {} : {
        authorization: observeInputStageStore(
          observeRetainedGraphDispatch(authorization, physicalDispatches),retainedLeases)})}}, {requestPrefix: 'packed-local',
    observe: observe(directory), prepareCase,
    completedCase: recordCohort('local', directory, cohort, authorization), ...cohort});
  if (authorization !== undefined) assert.ok(physicalDispatches.includes('physical_start_reserved'),
    'Initial retained execution proves the actual dispatch hook is live');
  verifyInputStageStore(retainedLeases);
  const acceptedRuns = observe(directory)().acceptedRuns;
  assert.equal(acceptedRuns, cohortRunCount(cohort));
  localAcceptedRuns += acceptedRuns;
  completedInventory.push(...inventoryKeys(profileName, cohort, completedOffsets));
}
assert.equal(localAcceptedRuns, expectedQueryRuns);
assert.ok(sourceIo >= expectedSourceReads);
console.log(`packed raw SQL/Pipe Embedded Local ${profileName} acceptance passed`);
}
if (transport === undefined || transport === 'remote') {
const beforeRemote = sourceIo;
let remoteAcceptedRuns = 0;
  for (const [index, cohort] of cohorts.entries()) {
    const directory = cohortDirectory(remoteDirectory, index);
    const authorization = graphRemainingOperationsOnly || inputStageResultOnly || typedSubscriptOnly
      ? createRetainedGraphAuthorization() : undefined;
    const physicalDispatches = [];
    const retainedLeases = [];
    const httpAuthorization = authorization === undefined
      ? createPublicQueryHttpAuthorization(cohort)
      : observeInputStageStore(observeRetainedGraphDispatch(authorization, physicalDispatches), retainedLeases);
    const host = await openInstalledRemoteHttpHost({
      directory, sourceProfilePath, hostCapacityPolicy,
      ...(inputStageResultOnly ? {retainedRelationOutput:true} : {}),
      authorization: httpAuthorization,
      authenticate: header => header === 'Bearer fixture-token'
        ? userInfo().username : undefined,
    });
    const server = createServer({key: await readFile('remote.key'),
      cert: await readFile('remote.crt')}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
      const options = {mode: 'remote',
        endpoint: `https://127.0.0.1:${server.address().port}/`,
        token: 'fixture-token', durability: 'durable'};
      if (index === 0) await exercisePublicCheck(options);
      await exercisePublicQueryInput(connect, options,
        {requestPrefix: 'packed-http', observe: observe(directory), prepareCase,
          completedCase: recordCohort('remote', directory, cohort, authorization ?? httpAuthorization), ...cohort});
      if (authorization !== undefined) assert.ok(physicalDispatches.includes('physical_start_reserved'),
        'Initial Graph execution proves the actual dispatch hook is live');
      const acceptedRuns = observe(directory)().acceptedRuns;
      assert.equal(acceptedRuns, cohortRunCount(cohort));
      remoteAcceptedRuns += acceptedRuns;
      if (transport === 'remote') completedInventory.push(...inventoryKeys(profileName, cohort, completedOffsets));
    } finally {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
      await host.close();
    }
    verifyInputStageStore(retainedLeases);
  }
  assert.equal(remoteAcceptedRuns, expectedQueryRuns);
  assert.ok(sourceIo >= beforeRemote + expectedSourceReads);
  console.log(`packed raw SQL/Pipe HTTP ${profileName} acceptance passed`);
}
  if (!scopeOnly && profileName === 'standard' &&
      (transport === undefined || transport === 'tail')) await exerciseExactPhysicalTargets();
} finally {
  DuckDBPreparedStatement.prototype.stream = stream;
  DuckDBConnection.prototype.extractStatements = extract;
  DuckDBExtractedStatements.prototype.prepare = prepare;
}
if ((transport === undefined && retainedStrings.local && retainedStrings.remote) ||
    (transport !== undefined && retainedStrings[transport])) {
  // Reopening this installation must preserve its explicitly selected policy.
  await writeFile(transport === undefined ? 'retained-string-results.json' :
    `retained-string-results.${transport}.json`, JSON.stringify({
    ...retainedStrings, hostCapacityPolicy, sourceProfilePaths: {
      ...(retainedStrings.local ? {local: sourceProfilePath} : {}),
      ...(retainedStrings.remote ? {remote: sourceProfilePath} : {}),
    },
  }));

}
}
if (transport !== 'tail') {
  if (graphArgumentChecksSelected) assert.deepEqual([...graphArgumentCheckModes],
    transport === undefined ? ['local', 'remote'] : [transport]);
  requireCompleteInventory(expectedInventory, completedInventory);
  await timeSeriesPrimaryReceipts.complete();
  await carrierContinuationReceipts.complete();
  await windowGroupReceipts.complete();
  await sequenceReceipts.complete();
  await temporalJoinReceipts.complete();
  await rankingFusionReceipts.complete();
  await quotedIdentifierReceipts.complete();
  await lagReceipts.complete();
  await cteValueTableReceipts.complete();
  await fromUnpivotReceipts.complete();
  await unpivotRowLabelReceipts.complete();
  await unpivotMulticolumnReceipts.complete();
  assert.equal(retainedCohorts.length, expectedRetainedCohorts * (transport === undefined ? 2 : 1));
  if (graphRemainingOperationsOnly) for (const cohort of retainedCohorts) {
    assert.deepEqual(cohort.samples.map(sample => sample.source.name), cohort.expectedSampleNames,
      'Every authored Graph restart boundary must be retained before producer exit');
  }
  await writeFile(transport === undefined ? 'retained-cohort-results.json' :
    `retained-cohort-results.${transport}.json`, encodeRetainedFixture(retainedCohorts));
  if (transport !== undefined) await writeFile(`transport-completion.${transport}.json`,
    JSON.stringify({mode: transport, expectedInventory, completedInventory, expectedRetainedCohorts,
      needsTail: !scopeOnly, complete: true}) + '\n', {flag: 'wx'});
}
if (!scopeOnly && (transport === undefined || transport === 'tail'))
  await import('./packed-two-source-public-query.mjs');
}
