import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';
import {validateResourceAccounting} from './validate-local-resource-accounting.mjs';
import {loadResourceAccountingSources} from './local-resource-accounting-sources.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const defaultManifest = path.join(
  root, 'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
);
const manifestPath = process.env.ACTQL_LOCAL_RESOURCE_AUDIT
  ? path.resolve(process.env.ACTQL_LOCAL_RESOURCE_AUDIT)
  : defaultManifest;
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const routesPath = path.resolve(root, manifest.production_routes ?? '');
const routes = fs.existsSync(routesPath)
  ? JSON.parse(fs.readFileSync(routesPath, 'utf8')) : {routes: []};
const defaultGaps = path.join(
  root, 'docs/reviews/2026-09-19-sga-veca-tea-local-gaps.md',
);
const gapsPath = process.env.ACTQL_LOCAL_RESOURCE_GAPS
  ? path.resolve(process.env.ACTQL_LOCAL_RESOURCE_GAPS) : defaultGaps;
const checkSummary = manifestPath === defaultManifest ||
  process.argv.includes('--check-summary');
const result = validateResourceAccounting({
  root, manifest, routes,
  sources: loadResourceAccountingSources({root, manifest, routes}),
  requireBoundaryComplete: process.argv.includes('--require-boundary-complete'),
  checkSummary,
  writeSummary: process.argv.includes('--write-summary'),
  gapsText: checkSummary && fs.existsSync(gapsPath)
    ? fs.readFileSync(gapsPath, 'utf8') : undefined,
});
if (result.summaryReplacement !== undefined) {
  fs.writeFileSync(gapsPath, result.summaryReplacement);
}
if (result.errors.length > 0) {
  for (const error of result.errors) console.error(error);
  process.exitCode = 1;
} else {
  console.log(result.output);
}
