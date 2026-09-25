// One setup contract for readiness and timing. This does not admit a task or
// turn a supplied estimate into a measured execution cost.
import {benchmarkEnvironment} from './environment.mjs';
import {workloads} from './fixtures.mjs';

// Product selection shared by the Node managed product leg (retained-case)
// and the native product (native-direct-product): the resident DuckDB profile
// is offered to the portable strategy, which still decides per task from its
// estimates and resource ceilings. It is the same for every case; no size or
// case name selects it. Diagnostics that construct their own selection keep
// their explicit inputs.
export const productResidentOffer = true;
// The registered Native pair admission counts one physical attempt per task.
// A resident environment and its imports are further physical attempts, so
// the Native product runs without the resident offer until that admission
// accounts for them. The resident Native Host itself is tested separately.
export const nativeRegisteredResidentOffer = false;

export function managedCaseConfiguration(fixture, contracts, database, directory) {
  const l = fixture.limits;
  const environment = benchmarkEnvironment(fixture);
  const taskCount = fixture.workload === workloads[1] ? 4 : 3;
  const computeTransfer = 3 * l.representationBytes +
    2 * l.intermediateRows * (128 * l.maxColumns + 256) + 8192;
  // Join preflight's validation charge is additional to graph/search work.
  const limits = Object.freeze({planning_work: 100000 + l.cumulativeGuardWork,
    attempts: 12, holdings: 12,
    transfer_bytes: BigInt(3 * l.representationBytes + (taskCount + 1) * computeTransfer),
    retained_bytes: 1073741824n, execution_bytes: 4294967296n});
  const batchBytes = Math.min(l.batchBytes, l.representationBytes);
  const input = Object.freeze({...contracts, database,
    environmentText: environment.text, environmentCid: environment.cid,
    programText: JSON.stringify(fixture.program()), parameterText: JSON.stringify({minimum: fixture.minimum}),
    nativeMilliseconds: '1', localImportWorkMilliseconds: '0', localExportWorkMilliseconds: '0',
    retainedWorkMilliseconds: '0',
    dataProfile: Object.freeze({source_rows: l.sourceRows, task_rows: l.intermediateRows, columns: l.maxColumns,
      value_bytes: l.maxValueBytes, wire_bytes: l.representationBytes,
      value_nodes: l.cumulativeValueNodes, text_bytes: l.cumulativeValueTextBytes,
      work: l.cumulativeGuardWork, entries: l.cumulativeValueNodes, batch_bytes: batchBytes}),
    retainedOutput: Object.freeze({parentDirectory: directory, maxFrameBytes: batchBytes,
      wire: Object.freeze({max_bytes: l.representationBytes, max_nodes: l.cumulativeValueNodes,
        max_depth: 64, max_columns: l.maxColumns, max_order_work: l.cumulativeGuardWork})}),
  });
  return Object.freeze({input, limits, childLimits: Object.freeze({...limits, attempts: 10}),
    finalTask: taskCount, timeoutMs: l.timeoutMs});
}
