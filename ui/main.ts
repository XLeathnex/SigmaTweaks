// SigmaTweaks interface.
//
// The backend owns every decision that touches Windows; this file is a view
// over the catalog plus a selection set.
//
// Two things shape the design. The whole catalog is scanned once at startup
// rather than a category at a time, because the most useful thing this app can
// tell you is what was already done to the machine before it arrived - and
// that only reads as an answer if every category shows its count at once.
// Selection is global rather than per-page, so a preset is ticked once and
// applied in a single batch.

import * as api from './api';
import type {
  BackupInfo,
  CatalogPayload,
  LogLine,
  MaintenanceAction,
  Mode,
  State,
  SystemInfo,
  Tweak,
  TweakStatus,
} from './types';

const OVERVIEW = 'Overview';
const MAINTENANCE = 'Maintenance';
const BACKUPS = 'Backups';

type Filter = 'all' | 'off' | 'on' | 'recommended';

function el<T extends HTMLElement>(id: string): T {
  const node = document.getElementById(id);
  if (!node) throw new Error(`missing element #${id}`);
  return node as T;
}

const dom = {
  nav: el<HTMLUListElement>('nav'),
  view: el<HTMLDivElement>('view'),
  search: el<HTMLInputElement>('search'),
  filters: el<HTMLDivElement>('filters'),
  selectAll: el<HTMLButtonElement>('select-all'),
  selectNone: el<HTMLButtonElement>('select-none'),
  refresh: el<HTMLButtonElement>('refresh'),
  preset: el<HTMLSelectElement>('preset'),
  restorePoint: el<HTMLInputElement>('restore-point'),
  selectionCount: el<HTMLSpanElement>('selection-count'),
  apply: el<HTMLButtonElement>('apply'),
  revert: el<HTMLButtonElement>('revert'),
  host: el<HTMLDivElement>('host-summary'),
  adminBadge: el<HTMLDivElement>('admin-badge'),
  subtitle: el<HTMLElement>('subtitle'),
  log: el<HTMLPreElement>('log'),
  logToggle: el<HTMLButtonElement>('log-toggle'),
  busy: el<HTMLDivElement>('busy'),
  busyText: el<HTMLParagraphElement>('busy-text'),
  confirm: el<HTMLDialogElement>('confirm'),
  confirmTitle: el<HTMLHeadingElement>('confirm-title'),
  confirmBody: el<HTMLParagraphElement>('confirm-body'),
  confirmYes: el<HTMLButtonElement>('confirm-yes'),
  confirmNo: el<HTMLButtonElement>('confirm-no'),
};

interface AppState {
  catalog: CatalogPayload;
  info: SystemInfo;
  view: string;
  statuses: Map<string, TweakStatus>;
  selected: Set<string>;
  search: string;
  filter: Filter;
}

let state: AppState;

/* ------------------------------------------------------------------- utils */

function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string,
  );
}

function appendLog(line: LogLine): void {
  const row = document.createElement('div');
  row.className = line.level;
  row.textContent = line.message;
  dom.log.appendChild(row);
  dom.log.scrollTop = dom.log.scrollHeight;
}

function showLog(): void {
  dom.log.hidden = false;
  dom.logToggle.setAttribute('aria-expanded', 'true');
}

async function busy<T>(text: string, work: () => Promise<T>): Promise<T> {
  dom.busyText.textContent = text;
  dom.busy.hidden = false;
  try {
    return await work();
  } finally {
    dom.busy.hidden = true;
  }
}

function confirmAction(title: string, body: string, okLabel = 'Continue'): Promise<boolean> {
  dom.confirmTitle.textContent = title;
  dom.confirmBody.textContent = body;
  dom.confirmYes.textContent = okLabel;
  dom.confirm.showModal();

  return new Promise((resolve) => {
    const done = (answer: boolean) => () => {
      dom.confirm.close();
      resolve(answer);
    };
    dom.confirmYes.onclick = done(true);
    dom.confirmNo.onclick = done(false);
    dom.confirm.oncancel = done(false);
  });
}

/* ---------------------------------------------------------------- selectors */

const isCategory = (name: string) => state.catalog.categories.includes(name);

function tweaksIn(category: string): Tweak[] {
  return state.catalog.tweaks.filter((tweak) => tweak.category === category);
}

/** How many tweaks in a category are already applied, ignoring inapplicable ones. */
function tally(category: string): { applied: number; total: number } {
  let applied = 0;
  let total = 0;
  for (const tweak of tweaksIn(category)) {
    const status = state.statuses.get(tweak.id);
    if (status?.state === 'not_applicable') continue;
    total += 1;
    if (status?.state === 'applied') applied += 1;
  }
  return { applied, total };
}

function passesFilter(tweak: Tweak): boolean {
  const status = state.statuses.get(tweak.id)?.state;
  switch (state.filter) {
    case 'off':
      return status !== 'applied' && status !== 'not_applicable';
    case 'on':
      return status === 'applied' || status === 'partial';
    case 'recommended':
      return tweak.recommended;
    default:
      return true;
  }
}

function visibleTweaks(): Tweak[] {
  const needle = state.search.trim().toLowerCase();
  return tweaksIn(state.view).filter((tweak) => {
    if (!passesFilter(tweak)) return false;
    if (!needle) return true;
    return (
      tweak.name.toLowerCase().includes(needle) ||
      tweak.description.toLowerCase().includes(needle) ||
      tweak.id.toLowerCase().includes(needle)
    );
  });
}

const isSelectable = (tweak: Tweak) =>
  state.statuses.get(tweak.id)?.state !== 'not_applicable';

/* ------------------------------------------------------------------ render */

function renderNav(): void {
  const entries = [OVERVIEW, ...state.catalog.categories, MAINTENANCE, BACKUPS];

  dom.nav.replaceChildren(
    ...entries.map((name) => {
      const item = document.createElement('li');
      item.dataset.view = name;
      item.setAttribute('aria-current', String(name === state.view));
      if (name === MAINTENANCE) item.classList.add('spacer');

      const label = document.createElement('span');
      label.textContent = name;
      item.appendChild(label);

      if (isCategory(name)) {
        const { applied, total } = tally(name);
        const badge = document.createElement('span');
        badge.className = applied === total && total > 0 ? 'tally complete' : 'tally';
        badge.textContent = `${applied}/${total}`;
        badge.title = `${applied} of ${total} already applied`;
        item.appendChild(badge);
      }
      return item;
    }),
  );
}

/** The detail line under a tweak: only the things that are not the default. */
function metaFor(tweak: Tweak, status: TweakStatus | undefined, skipOneWay: boolean): string {
  const notes: string[] = [];

  if (status?.state === 'partial' && status.total > 0) {
    notes.push(`${status.matched} of ${status.total} already set`);
  }
  if (status?.reason) notes.push(status.reason);
  if (tweak.irreversible && !skipOneWay) notes.push('cannot be undone');
  if (tweak.requires_restart) notes.push('needs a restart');
  if (tweak.restart_explorer) notes.push('restarts Explorer');

  return notes.join('  ·  ');
}

const STATUS_TEXT: Partial<Record<State, string>> = {
  applied: 'Applied',
  partial: 'Partial',
  unknown: 'Unknown',
  not_applicable: 'N/A',
};

function renderRows(tweaks: Tweak[]): string {
  // A note every row shares is noise: the section header already said it once.
  // In Debloat that is "cannot be undone" on all 29 rows.
  const allOneWay = tweaks.length > 1 && tweaks.every((tweak) => tweak.irreversible);

  return tweaks
    .map((tweak) => {
      const status = state.statuses.get(tweak.id);
      const tweakState: State = status?.state ?? 'unknown';
      const disabled = tweakState === 'not_applicable';
      const checked = state.selected.has(tweak.id);
      const meta = metaFor(tweak, status, allOneWay);

      // Low risk is the common case and says nothing worth the ink.
      const risk =
        tweak.risk === 'low' ? '' : `<span class="risk ${tweak.risk}">${tweak.risk.toUpperCase()}</span>`;
      const statusText = STATUS_TEXT[tweakState] ?? '';

      const classes = ['row'];
      if (disabled) classes.push('disabled');
      if (checked) classes.push('on');

      return `
        <div class="${classes.join(' ')}" title="${escapeHtml(tweak.id)}">
          <input type="checkbox" data-id="${escapeHtml(tweak.id)}"
                 ${checked ? 'checked' : ''} ${disabled ? 'disabled' : ''}
                 aria-label="${escapeHtml(tweak.name)}" />
          <div>
            <h3>${escapeHtml(tweak.name)}${risk}</h3>
            <p>${escapeHtml(tweak.description)}</p>
            ${meta ? `<div class="meta">${escapeHtml(meta)}</div>` : ''}
          </div>
          <div class="status ${tweakState}">${statusText}</div>
        </div>`;
    })
    .join('');
}

const CATEGORY_NOTE: Record<string, string> = {
  Performance: 'Responsiveness and resource usage. Anything that trades battery life or a feature for speed says so.',
  Gaming: 'Frame pacing, input latency and capture overhead. The scheduling and timer settings matter more than the frame-rate counters suggest.',
  Productivity: 'Friction removal for daily use. Nothing here changes how the machine performs, only how much it gets in your way.',
  Privacy: 'Telemetry, tracking and advertising. Nothing in this category touches Defender, SmartScreen, UAC or the firewall.',
  Network: 'Name resolution and TCP behaviour.',
  Explorer: 'The shell: File Explorer, the taskbar and the context menu.',
  Services: 'Services Windows needs to boot, sign you in, network or stay patched are on a protected list and cannot be changed from here.',
  Updates: 'When and how updates arrive. SigmaTweaks will not switch Windows Update off.',
  Power: 'Power schemes and sleep behaviour.',
  Debloat: 'Removing a Store app cannot be undone from here — anything you want back has to come from the Microsoft Store.',
};

function renderCategory(): void {
  const tweaks = visibleTweaks();
  const { applied, total } = tally(state.view);
  const note = CATEGORY_NOTE[state.view] ?? '';

  const summary =
    total === 0
      ? ''
      : applied === total
        ? `All ${total} already applied on this machine.`
        : `${applied} of ${total} already applied on this machine.`;

  const body = tweaks.length
    ? `<div class="rows">${renderRows(tweaks)}</div>`
    : `<p class="empty">${
        state.search || state.filter !== 'all'
          ? 'Nothing here matches the current filter.'
          : 'No tweaks in this category.'
      }</p>`;

  dom.view.innerHTML = `
    <div class="section">
      <h2>${escapeHtml(state.view)}</h2>
      ${note ? `<p>${escapeHtml(note)}</p>` : ''}
      ${summary ? `<p class="summary">${escapeHtml(summary)}</p>` : ''}
    </div>
    ${body}`;
}

function renderOverview(): void {
  const info = state.info;
  let applied = 0;
  let total = 0;
  for (const category of state.catalog.categories) {
    const counts = tally(category);
    applied += counts.applied;
    total += counts.total;
  }

  const drive = `${info.system_drive} — ${info.free_space_gb} GB free${
    info.is_ssd === null ? '' : info.is_ssd ? ' (SSD)' : ' (HDD)'
  }`;
  // ProductName already carries the edition ("Windows 11 Pro"), so appending
  // EditionID as well reads as "Windows 11 Pro Professional".
  const version = [info.os_name, info.display_version].filter(Boolean).join(' ');

  const facts: [string, string][] = [
    ['Computer', info.computer_name],
    ['Windows', `${version} (build ${info.build})`],
    ['Processor', `${info.cpu} — ${info.logical_processors} threads`],
    ['Memory', `${info.memory_gb} GB`],
    ['Graphics', info.gpu],
    ['System drive', drive],
    ['Elevated', info.is_admin ? 'Yes' : 'No — system-wide tweaks will be refused'],
  ];

  dom.view.innerHTML = `
    <div class="section">
      <h2>Overview</h2>
      <p>SigmaTweaks scanned this machine on startup, so the counts below reflect what is already
         in place — whether it was set here, by another tool, or by hand.</p>
    </div>
    <div class="stats">
      <div class="stat accent"><b>${applied}</b><span>already applied</span></div>
      <div class="stat"><b>${total - applied}</b><span>available to apply</span></div>
      <div class="stat"><b>${state.catalog.tweaks.length}</b><span>tweaks in the catalog</span></div>
      <div class="stat"><b>${state.catalog.actions.length}</b><span>maintenance actions</span></div>
    </div>
    <dl class="facts">
      ${facts.map(([k, v]) => `<dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd>`).join('')}
    </dl>
    <div class="actions-row">
      <button id="export-profile" class="quiet">Export applied tweaks as a profile</button>
      <button id="open-data" class="quiet">Open data folder</button>
    </div>`;
}

function renderMaintenance(): void {
  const rows = state.catalog.actions
    .map(
      (action: MaintenanceAction) => `
      <div class="row" title="${escapeHtml(action.id)}">
        <span></span>
        <div>
          <h3>${escapeHtml(action.name)}</h3>
          <p>${escapeHtml(action.description)}</p>
          <div class="meta">${escapeHtml(action.category)}</div>
        </div>
        <button data-action="${escapeHtml(action.id)}">Run</button>
      </div>`,
    )
    .join('');

  dom.view.innerHTML = `
    <div class="section">
      <h2>Maintenance</h2>
      <p>One-shot jobs rather than settings. These have no state and no revert, so read the
         description before running the ones that ask for confirmation.</p>
    </div>
    <div class="rows">${rows}</div>`;
}

function renderBackups(backups: BackupInfo[]): void {
  const rows = backups.length
    ? backups
        .map((backup) => {
          const parsed = new Date(backup.created);
          const created = Number.isNaN(parsed.getTime()) ? backup.created : parsed.toLocaleString();
          return `
            <div class="row" title="${escapeHtml(backup.file_name)}">
              <span></span>
              <div>
                <h3>${escapeHtml(created)}</h3>
                <p>${backup.tweak_count} tweaks, ${backup.entry_count} recorded values (${escapeHtml(backup.label)})</p>
              </div>
              <button data-restore="${escapeHtml(backup.path)}">Restore</button>
            </div>`;
        })
        .join('')
    : '';

  dom.view.innerHTML = `
    <div class="section">
      <h2>Backups</h2>
      <p>Every apply records the exact values it is about to change. Restoring a snapshot puts those
         values back, whatever they were — which is more accurate than reverting to Windows defaults.</p>
    </div>
    ${rows ? `<div class="rows">${rows}</div>` : '<p class="empty">No backups yet. One is written the first time you apply something.</p>'}`;
}

function updateSelectionUi(): void {
  const count = state.selected.size;
  dom.selectionCount.textContent = count === 0 ? 'Nothing selected' : `${count} selected`;
  dom.apply.disabled = count === 0;
  dom.revert.disabled = count === 0;
  dom.selectNone.hidden = count === 0;
}

function renderCurrentView(): void {
  if (state.view === OVERVIEW) renderOverview();
  else if (state.view === MAINTENANCE) renderMaintenance();
  else renderCategory();
}

async function showView(name: string): Promise<void> {
  state.view = name;
  renderNav();

  const category = isCategory(name);
  dom.search.disabled = !category;
  dom.filters.hidden = !category;
  dom.selectAll.disabled = !category;

  if (name === BACKUPS) {
    renderBackups(await busy('Reading backups...', api.listBackups));
  } else {
    renderCurrentView();
  }

  updateSelectionUi();
}

/** Re-reads the state of the whole catalog. Two process launches, not 120. */
async function rescan(message = 'Scanning this machine...'): Promise<void> {
  const statuses = await busy(message, () => api.getStates());
  state.statuses = new Map(statuses.map((status) => [status.id, status]));

  // A tweak that turns out not to apply here must not stay in a batch.
  for (const status of statuses) {
    if (status.state === 'not_applicable') state.selected.delete(status.id);
  }
}

/* ----------------------------------------------------------------- actions */

async function runBatch(mode: Mode): Promise<void> {
  const chosen = state.catalog.tweaks.filter(
    (tweak) => state.selected.has(tweak.id) && isSelectable(tweak),
  );
  if (chosen.length === 0) return;

  const oneWay = chosen.filter((tweak) => tweak.irreversible);
  let body = `${mode === 'apply' ? 'Apply' : 'Revert'} ${chosen.length} tweak${chosen.length === 1 ? '' : 's'}?`;
  if (mode === 'apply' && oneWay.length > 0) {
    const names = oneWay.slice(0, 6).map((tweak) => `  • ${tweak.name}`).join('\n');
    const more = oneWay.length > 6 ? `\n  …and ${oneWay.length - 6} more` : '';
    body += `\n\n${oneWay.length} of these cannot be undone by SigmaTweaks:\n${names}${more}`;
  }

  if (!(await confirmAction(mode === 'apply' ? 'Apply tweaks' : 'Revert tweaks', body))) return;

  showLog();
  const outcome = await busy(`${mode === 'apply' ? 'Applying' : 'Reverting'}...`, () =>
    api.runBatch(chosen.map((tweak) => tweak.id), mode, dom.restorePoint.checked),
  );

  // Successes leave the batch; failures stay ticked so they can be retried
  // once whatever blocked them is dealt with.
  for (const result of outcome.results) {
    if (result.success) state.selected.delete(result.id);
  }

  await rescan('Re-reading state...');
  renderNav();
  renderCurrentView();
  updateSelectionUi();

  if (outcome.restart_required) {
    const restart = await confirmAction(
      'Restart required',
      'Some of those changes only take effect after a restart.\n\nRestart now? Windows will give you 15 seconds.',
      'Restart now',
    );
    if (restart) await api.restartWindows();
  }
}

async function runMaintenance(id: string): Promise<void> {
  const action = state.catalog.actions.find((candidate) => candidate.id === id);
  if (!action) return;

  if (action.confirm && !(await confirmAction(action.name, `${action.description}\n\nRun this now?`, 'Run'))) {
    return;
  }

  showLog();
  try {
    await busy(action.name, () => api.runMaintenance(id));
  } catch (error) {
    appendLog({ level: 'error', message: api.describeError(error) });
  }
}

async function restoreBackup(path: string): Promise<void> {
  if (!(await confirmAction('Restore backup', `Put back every value recorded in this backup?\n\n${path}`, 'Restore'))) {
    return;
  }

  showLog();
  try {
    await busy('Restoring backup...', () => api.restoreBackup(path));
  } catch (error) {
    appendLog({ level: 'error', message: api.describeError(error) });
  }
  await rescan('Re-reading state...');
  await showView(BACKUPS);
}

function applyPreset(key: string): void {
  const preset = state.catalog.presets.find((candidate) => candidate.key === key);
  if (!preset) return;

  // Selecting across the whole catalog rather than the current page: the batch
  // runs in one go, and anything already applied is skipped as a no-op.
  let added = 0;
  let already = 0;
  for (const id of preset.tweaks) {
    if (state.statuses.get(id)?.state === 'applied') {
      already += 1;
      continue;
    }
    if (state.statuses.get(id)?.state === 'not_applicable') continue;
    state.selected.add(id);
    added += 1;
  }

  appendLog({
    level: 'info',
    message: `Preset “${preset.name}”: ${added} selected, ${already} already applied.`,
  });
  renderCurrentView();
  updateSelectionUi();
}

/* ------------------------------------------------------------------ wiring */

function wireEvents(): void {
  dom.nav.addEventListener('click', (event) => {
    const item = (event.target as HTMLElement).closest<HTMLLIElement>('li[data-view]');
    if (item?.dataset.view) void showView(item.dataset.view);
  });

  dom.view.addEventListener('change', (event) => {
    const box = event.target as HTMLInputElement;
    if (box.type !== 'checkbox' || !box.dataset.id) return;

    if (box.checked) state.selected.add(box.dataset.id);
    else state.selected.delete(box.dataset.id);
    box.closest('.row')?.classList.toggle('on', box.checked);
    updateSelectionUi();
  });

  dom.view.addEventListener('click', (event) => {
    const target = event.target as HTMLElement;

    const action = target.closest<HTMLButtonElement>('[data-action]');
    if (action?.dataset.action) return void runMaintenance(action.dataset.action);

    const restore = target.closest<HTMLButtonElement>('[data-restore]');
    if (restore?.dataset.restore) return void restoreBackup(restore.dataset.restore);

    if (target.id === 'export-profile') {
      void busy('Reading current state...', api.exportProfile)
        .then((path) => appendLog({ level: 'success', message: `Profile written to ${path}` }))
        .catch((error) => appendLog({ level: 'error', message: api.describeError(error) }))
        .finally(showLog);
    }

    if (target.id === 'open-data') {
      void api
        .openDataDirectory()
        .then((path) => appendLog({ level: 'info', message: `Opened ${path}` }))
        .catch((error) => appendLog({ level: 'error', message: api.describeError(error) }))
        .finally(showLog);
    }
  });

  dom.search.addEventListener('input', () => {
    state.search = dom.search.value;
    if (isCategory(state.view)) renderCategory();
  });

  dom.filters.addEventListener('click', (event) => {
    const chip = (event.target as HTMLElement).closest<HTMLButtonElement>('[data-filter]');
    if (!chip?.dataset.filter) return;

    state.filter = chip.dataset.filter as Filter;
    for (const button of dom.filters.querySelectorAll('button')) {
      button.setAttribute('aria-pressed', String(button === chip));
    }
    if (isCategory(state.view)) renderCategory();
  });

  dom.selectAll.addEventListener('click', () => {
    for (const tweak of visibleTweaks()) {
      if (isSelectable(tweak)) state.selected.add(tweak.id);
    }
    renderCurrentView();
    updateSelectionUi();
  });

  dom.selectNone.addEventListener('click', () => {
    state.selected.clear();
    renderCurrentView();
    updateSelectionUi();
  });

  dom.refresh.addEventListener('click', () => {
    void rescan().then(() => {
      renderNav();
      renderCurrentView();
    });
  });

  dom.preset.addEventListener('change', () => {
    const key = dom.preset.value;
    dom.preset.selectedIndex = 0;
    if (key) applyPreset(key);
  });

  dom.apply.addEventListener('click', () => void runBatch('apply'));
  dom.revert.addEventListener('click', () => void runBatch('revert'));

  dom.logToggle.addEventListener('click', () => {
    const open = dom.log.hidden;
    dom.log.hidden = !open;
    dom.logToggle.setAttribute('aria-expanded', String(open));
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'f' && (event.ctrlKey || event.metaKey) && !dom.search.disabled) {
      event.preventDefault();
      dom.search.focus();
      dom.search.select();
    }
    if (event.key === 'Escape' && document.activeElement === dom.search) {
      dom.search.value = '';
      state.search = '';
      if (isCategory(state.view)) renderCategory();
    }
  });
}

function renderHeader(): void {
  const info = state.info;
  dom.subtitle.textContent = info.is_windows11 ? 'Windows 11 optimization' : 'Windows optimization';
  dom.host.textContent = `${info.os_name} ${info.display_version} · ${info.cpu} · ${info.memory_gb} GB`;

  const badge = document.createElement('span');
  if (info.is_admin) {
    badge.className = 'badge ok';
    badge.textContent = 'Administrator';
  } else {
    badge.className = 'badge warn';
    badge.textContent = 'Not elevated — click to restart as admin';
    badge.title = 'Most tweaks change machine-wide settings and need administrator rights.';
    badge.addEventListener('click', () => {
      void api.relaunchElevated().catch((error) => {
        appendLog({ level: 'error', message: api.describeError(error) });
        showLog();
      });
    });
  }
  dom.adminBadge.replaceChildren(badge);
}

async function main(): Promise<void> {
  await api.onLog(appendLog);

  const [catalog, info] = await Promise.all([api.getCatalog(), api.getSystemInfo()]);
  state = {
    catalog,
    info,
    view: OVERVIEW,
    statuses: new Map(),
    selected: new Set(),
    search: '',
    filter: 'all',
  };

  renderHeader();
  dom.preset.replaceChildren(
    new Option('Preset…', ''),
    ...catalog.presets.map((preset) => {
      const option = new Option(`${preset.name} (${preset.tweaks.length})`, preset.key);
      option.title = preset.description;
      return option;
    }),
  );
  wireEvents();

  // The package and task snapshots are the slow part; build them once, up
  // front, so the first scan and every later one are cheap.
  await busy('Reading installed apps and scheduled tasks...', api.warmInventory);
  await rescan();

  await showView(OVERVIEW);

  if (!info.is_admin) {
    appendLog({
      level: 'warn',
      message: 'Running without administrator rights. System-wide tweaks will be refused.',
    });
  }
}

main().catch((error: unknown) => {
  document.body.innerHTML = `<div class="overlay"><p>SigmaTweaks could not start</p><small>${escapeHtml(
    api.describeError(error),
  )}</small></div>`;
});
