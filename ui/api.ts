// Typed wrappers over the Tauri command bridge. Every backend call in the app
// goes through here so the command names exist in exactly one place.

import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import type {
  BackupInfo,
  BatchOutcome,
  CatalogPayload,
  LogLine,
  Mode,
  SystemInfo,
  TweakStatus,
} from './types';

export const getSystemInfo = () => invoke<SystemInfo>('get_system_info');

export const getCatalog = () => invoke<CatalogPayload>('get_catalog');

/** Builds the package and scheduled-task snapshots before the first scan. */
export const warmInventory = () => invoke<void>('warm_inventory');

/** State for the given ids, or the whole catalog when omitted. */
export const getStates = (ids?: string[]) =>
  invoke<TweakStatus[]>('get_states', { ids: ids ?? null });

export const runBatch = (ids: string[], mode: Mode, createRestorePoint: boolean) =>
  invoke<BatchOutcome>('run_batch', { ids, mode, createRestorePoint });

export const runMaintenance = (id: string) => invoke<string>('run_maintenance', { id });

export const listBackups = () => invoke<BackupInfo[]>('list_backups');

export const restoreBackup = (path: string) => invoke<string>('restore_backup', { path });

export const exportProfile = () => invoke<string>('export_profile');

export const relaunchElevated = () => invoke<void>('relaunch_elevated');

export const openDataDirectory = () => invoke<string>('open_data_directory');

export const restartWindows = () => invoke<void>('restart_windows');

/** Subscribes to the backend's progress stream. */
export const onLog = (handler: (line: LogLine) => void): Promise<UnlistenFn> =>
  listen<LogLine>('sigma://log', (event) => handler(event.payload));

/** Tauri rejects with the backend's Error type, which serialises as a string. */
export function describeError(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  return JSON.stringify(error);
}
