import type {BenchmarkPackageManifest} from '../../node-benchmark-evidence.mjs';

type CohortSelection = Readonly<{manifestPath: string; manifestSha256: string; sourceSha: string; sourceTree: string}>;

export const externalInstalledPackages: readonly string[];
export function verifyExternalRestTarballs(manifest: BenchmarkPackageManifest, manifestPath: string, packageNames?: readonly string[]): Promise<readonly {
  name: string; path: string; bytes: number; sha256: string; integrity: string;
}[]>;
export function prepareExternalRestCohort(input: CohortSelection, options?: {external?: boolean}): Promise<{
  manifest: BenchmarkPackageManifest & Pick<CohortSelection, 'sourceSha' | 'sourceTree'>;
  artifactManifestPath: string;
  originalBindings: readonly Readonly<{path: string; bytes: number; sha256: string}>[];
  offeredTarballs: readonly Readonly<{name: string; path: string; bytes: number; sha256: string; integrity: string}>[];
  hostPackageVersion: string;
}>;
