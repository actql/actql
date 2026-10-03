import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { executions, closeExecutor, root } from '../execute.mjs';
// The caller has restored its observer/mutation sources and completed all
// observations. Preserve receipts before transferring the live fixture slot.
export function finishCapacityCampaign(report, targets) {
  report.executions = executions;
  writeFileSync(join(root, '.artifacts/relation-pipeline/capacity',
    `${targets.length === 1 ? 'js' : 'all'}.json`), JSON.stringify(report, null, 2) + '\n');
  closeExecutor();
}
