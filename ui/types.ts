// Mirrors the serde representation of src-tauri/src/model.rs. Serde is
// configured to emit snake_case for enum variants, so these string unions are
// exactly what crosses the bridge.

export type Risk = 'low' | 'medium' | 'high';

export type State = 'applied' | 'not_applied' | 'partial' | 'unknown' | 'not_applicable';

export type Mode = 'apply' | 'revert';

export interface Requires {
  windows11: boolean;
  min_build: number | null;
  ssd: boolean;
}

export interface Tweak {
  id: string;
  name: string;
  category: string;
  description: string;
  risk: Risk;
  recommended: boolean;
  requires_restart: boolean;
  restart_explorer: boolean;
  irreversible: boolean;
  requires_admin: boolean;
  requires: Requires | null;
}

export interface Preset {
  key: string;
  name: string;
  description: string;
  tweaks: string[];
}

export interface MaintenanceAction {
  id: string;
  name: string;
  category: string;
  description: string;
  confirm: boolean;
}

export interface CatalogPayload {
  tweaks: Tweak[];
  presets: Preset[];
  categories: string[];
  actions: MaintenanceAction[];
}

export interface TweakStatus {
  id: string;
  state: State;
  /** Why the tweak is not applicable here, when it is not. */
  reason: string | null;
  /** How many of the tweak's checkable changes are already in place… */
  matched: number;
  /** …out of how many there are. Renders as "3 of 4 already set". */
  total: number;
}

export interface SystemInfo {
  computer_name: string;
  user_name: string;
  os_name: string;
  display_version: string;
  edition: string;
  build: number;
  is_windows11: boolean;
  cpu: string;
  logical_processors: number;
  memory_gb: number;
  gpu: string;
  system_drive: string;
  free_space_gb: number;
  is_admin: boolean;
  is_ssd: boolean | null;
  app_version: string;
}

export interface TweakResult {
  id: string;
  name: string;
  success: boolean;
  message: string;
}

export interface BatchOutcome {
  results: TweakResult[];
  succeeded: number;
  failed: number;
  backup: string | null;
  restart_required: boolean;
}

export interface BackupInfo {
  path: string;
  file_name: string;
  created: string;
  label: string;
  tweak_count: number;
  entry_count: number;
}

export interface LogLine {
  level: 'info' | 'success' | 'warn' | 'error';
  message: string;
}
