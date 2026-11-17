import type {HostInstallation} from './index.js';
import type {HostObservationConnection} from './observation.js';
export type {HostCapacityPolicy, HostLookupExecutionPolicy} from './host-policy.js';
export type InstalledRemoteHostOptions = HostInstallation & Readonly<{
  directory: string;
  /** Stable service Workspace ID. Omission refuses asserted Workspace connections. */
  workspaceId?: string;
  /** Enforce an actual numeric loopback HTTP listener and peer before auth.
   * The application still creates, explicitly binds and closes its server. */
  loopbackHttp?: boolean;
  /** Explicit encoded HTTP body limit (default 65536). Larger selections still
   * require the same Request's current Resource admission before allocation.
   * This is not a query/Run limit or an execution permission. */
  maxRequestBytes?: number;
  authenticate: (authorization: string | undefined) => string | undefined | Promise<string | undefined>;
  beforeDispatch?: (...args: any[]) => any;
  effectInstallation?: Readonly<Record<string, unknown>>;
}>;
export declare function openInstalledRemoteHttpHost(options: InstalledRemoteHostOptions): Promise<Readonly<{
  /** Attach directly to a Node HTTP(S) server. */
  handler: (request: any, response: any) => void;
  observationStatus: HostObservationConnection['status'];
  close: () => Promise<unknown>;
}>>;
