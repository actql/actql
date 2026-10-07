import type {HostInstallation} from './index.js';
export type {HostCapacityPolicy} from './host-policy.js';
export type InstalledRemoteHostOptions = HostInstallation & Readonly<{
  directory: string;
  /** Stable service Workspace ID. Omission refuses asserted Workspace connections. */
  workspaceId?: string;
  /** Enforce an actual numeric loopback HTTP listener and peer before auth.
   * The application still creates, explicitly binds and closes its server. */
  loopbackHttp?: boolean;
  authenticate: (authorization: string | undefined) => string | undefined | Promise<string | undefined>;
  beforeDispatch?: (...args: any[]) => any;
  effectInstallation?: Readonly<Record<string, unknown>>;
}>;
export declare function openInstalledRemoteHttpHost(options: InstalledRemoteHostOptions): Promise<Readonly<{
  /** Attach directly to a Node HTTP(S) server. */
  handler: (request: any, response: any) => void;
  close: () => Promise<unknown>;
}>>;
