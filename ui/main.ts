// SigmaTweaks interface.
//
// The backend owns every decision that touches Windows; this file is a view
// over the catalog it serves plus a selection set. Selection is global rather
// than per-page, so a preset can be ticked once and applied in a single batch
// across categories.

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

function el<T extends HTMLElement>(id: string): T {
  const node = document.getElementById(id);
  if (!node) throw new Error(`missing element #${id}`);
  return node as T;
}

const dom = {
  nav: el<HTMLUListElement>('nav'),
  view: el<HTMLDivElement>('view'),
  search: el<HTMLInputElement>('search'),
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
}

let state: AppState;

/* ------------------------------------------------------------------ utils */

function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string,
  );
}

const STATE_LABEL: Record<State, string> = {
  applied: 'APPLIED',
  not_applied: 'OFF',
  partial: 'PARTIAL',
  unknown: 'UNKNOWN',
  not_applicable: 'N/A',
};

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

/** Runs work behind the busy overlay, so a slow batch cannot be double-fired. */
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

function tweaksIn(category: string): Tweak[] {
  return state.catalog.tweaks.filter((tweak) => tweak.category === category);
}

function visibleTweaks(): Tweak[] {
  const needle = state.search.trim().toLowerCase();
  return tweaksIn(state.view).filter((tweak) => {
    if (!needle) return true;
    return (
      tweak.name.toLowerCase().includes(needle) ||
      tweak.description.toLowerCase().includes(needle) ||
      tweak.id.toLowerCase().includes(needle)
    );
  });
}

function isSelectable(tweak: Tweak): boolean {
  return state.statuses.get(tweak.id)?.state !== 'not_applicable';
}

/* ----------------------------------------------------------------- render */

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

      const count = tweaksIn(name).length;
      if (count > 0) {
        const badge = document.createElement('span');
        badge.className = 'count';
        badge.textContent = String(count);
        item.appendChild(badge);
      }
      return item;
    }),
  );
}

function cardMeta(tweak: Tweak, status: TweakStatus | undefined): string {
  const notes: string[] = [tweak.id];
  if (tweak.requires_restart) notes.push('needs a restart');
  if (tweak.restart_explorer) notes.push('restarts Explorer');
  if (tweak.irreversible) notes.push('cannot be undone');
  if (!tweak.requires_admin) notes.push('no admin needed');
  if (status?.reason) notes.push(status.reason);
  return notes.join('  ·  ');
}

function renderTweakCards(tweaks: Tweak[]): string {
  return tweaks
    .map((tweak) => {
      const status = state.statuses.get(tweak.id);
      const tweakState: State = status?.state ?? 'unknown';
      const disabled = tweakState === 'not_applicable';
      const checked = state.selected.has(tweak.id);

      return `
        <article class="card${disabled ? ' disabled' : ''}">
          <input type="checkbox" data-id="${escapeHtml(tweak.id)}"
                 ${checked ? 'checked' : ''} ${disabled ? 'disabled' : ''}
                 aria-label="${escapeHtml(tweak.name)}" />
          <div>
            <h3>${escapeHtml(tweak.name)}</h3>
            <p>${escapeHtml(tweak.description)}</p>
            <div class="meta">${escapeHtml(cardMeta(tweak, status))}</div>
          </div>
          <div class="pills">
            <span class="pill ${tweak.risk}">${tweak.risk.toUpperCase()}</span>
            <span class="pill ${tweakState}">${STATE_LABEL[tweakState]}</span>
          </div>
        </article>`;
    })
    .join('');
}

const CATEGORY_NOTE: Record<string, string> = {
  Debloat:
    'Removing a Store app cannot be undone from here. Anything you want back has to come from the Microsoft Store.',
  Services:
    'Services Windows needs to boot, sign you in, network or stay patched are on a protected list and cannot be changed by SigmaTweaks.',
  Updates:
    'These change when and how updates arrive. SigmaTweaks will not switch Windows Update off.',
  Privacy:
    'Nothing in this category touches Defender, SmartScreen, UAC or the firewall.',
};

function renderCategory(): void {
  const tweaks = visibleTweaks();
  const note =
    CATEGORY_NOTE[state.view] ?? `${tweaks.length} tweak${tweaks.length === 1 ? '' : 's'} in this category.`;

  const body = tweaks.length
    ? renderTweakCards(tweaks)
    : `<p class="empty">${
        state.search ? `Nothing in ${escapeHtml(state.view)} matches “${escapeHtml(state.search)}”.` : 'No tweaks here.'
      }</p>`;

  dom.view.innerHTML = `
    <h2 class="section-title">${escapeHtml(state.view)}</h2>
    <p class="section-note">${escapeHtml(note)}</p>
    ${body}`;
}

function renderOverview(): void {
  const info = state.info;
  const drive = `${info.system_drive} — ${info.free_space_gb} GB free${
    info.is_ssd === null ? '' : info.is_ssd ? ' (SSD)' : ' (HDD)'
  }`;

  const facts: [string, string][] = [
    ['Computer', info.computer_name],
    ['Windows', `${info.os_name} ${info.edition} ${info.display_version} (build ${info.build})`],
    ['Processor', `${info.cpu} — ${info.logical_processors} threads`],
    ['Memory', `${info.memory_gb} GB`],
    ['Graphics', info.gpu],
    ['System drive', drive],
    ['Elevated', info.is_admin ? 'Yes' : 'No — system-wide tweaks will be refused'],
  ];

  dom.view.innerHTML = `
    <h2 class="section-title">Overview</h2>
    <p class="section-note">Pick a category on the left, tick what you want and press Apply. Selection carries across
      categories, so a preset can be applied in one batch. Every change is recorded first and can be reverted.</p>
    <dl class="facts">
      ${facts.map(([k, v]) => `<dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd>`).join('')}
    </dl>
    <p class="section-note">${state.catalog.tweaks.length} tweaks across ${state.catalog.categories.length}
      categories, plus ${state.catalog.actions.length} maintenance actions. SigmaTweaks ${escapeHtml(info.app_version)}.</p>
    <div class="pills">
      <button id="export-profile" class="ghost">Export applied tweaks as a profile</button>
      <button id="open-data" class="ghost">Open data folder</button>
    </div>`;
}

function renderMaintenance(): void {
  const cards = state.catalog.actions
    .map(
      (action: MaintenanceAction) => `
      <article class="card">
        <span></span>
        <div>
          <h3>${escapeHtml(action.name)}</h3>
          <p>${escapeHtml(action.description)}</p>
          <div class="meta">${escapeHtml(action.category)}  ·  ${escapeHtml(action.id)}</div>
        </div>
        <div class="pills"><button data-action="${escapeHtml(action.id)}">Run</button></div>
      </article>`,
    )
    .join('');

  dom.view.innerHTML = `
    <h2 class="section-title">Maintenance</h2>
    <p class="section-note">One-shot jobs rather than settings. These have no state and no revert, so read the
      description before running the ones that ask for confirmation.</p>
    ${cards}`;
}

function renderBackups(backups: BackupInfo[]): void {
  const cards = backups.length
    ? backups
        .map((backup) => {
          let created = backup.created;
          const parsed = new Date(backup.created);
          if (!Number.isNaN(parsed.getTime())) created = parsed.toLocaleString();

          return `
            <article class="card">
              <span></span>
              <div>
                <h3>${escapeHtml(created)} (${escapeHtml(backup.label)})</h3>
                <p>${backup.tweak_count} tweaks, ${backup.entry_count} recorded values</p>
                <div class="meta">${escapeHtml(backup.file_name)}</div>
              </div>
              <div class="pills"><button data-restore="${escapeHtml(backup.path)}">Restore</button></div>
            </article>`;
        })
        .join('')
    : '<p class="empty">No backups yet. One is written automatically the first time you apply something.</p>';

  dom.view.innerHTML = `
    <h2 class="section-title">Backups</h2>
    <p class="section-note">Every apply records the exact values it is about to change. Restoring a snapshot puts those
      values back, whatever they were — which is more accurate than reverting to Windows defaults.</p>
    ${cards}`;
}

function updateSelectionUi(): void {
  const count = state.selected.size;
  dom.selectionCount.textContent = count === 0 ? 'Nothing selected' : `${count} selected`;
  dom.apply.disabled = count === 0;
  dom.revert.disabled = count === 0;
}

/** Loads state for the current category, then paints it. */
async function showView(name: string): Promise<void> {
  state.view = name;
  renderNav();

  const isCategory = state.catalog.categories.includes(name);
  dom.search.disabled = !isCategory;
  dom.selectAll.disabled = !isCategory;
  dom.refresh.disabled = !isCategory;

  if (name === OVERVIEW) {
    renderOverview();
  } else if (name === MAINTENANCE) {
    renderMaintenance();
  } else if (name === BACKUPS) {
    renderBackups(await busy('Reading backups...', api.listBackups));
  } else {
    await refreshStates(name);
    renderCategory();
  }

  updateSelectionUi();
}

/** Reading state costs process launches, so only one category is read at a time. */
async function refreshStates(category: string): Promise<void> {
  const ids = tweaksIn(category).map((tweak) => tweak.id);
  if (ids.length === 0) return;

  const statuses = await busy('Reading current state...', () => api.getStates(ids));
  for (const status of statuses) state.statuses.set(status.id, status);

  // A tweak that turns out not to apply here must not stay in the batch.
  for (const status of statuses) {
    if (status.state === 'not_applicable') state.selected.delete(status.id);
  }
}

/* ----------------------------------------------------------------- actions */

async function runBatch(mode: Mode): Promise<void> {
  const ids = [...state.selected].filter((id) => {
    const tweak = state.catalog.tweaks.find((candidate) => candidate.id === id);
    return tweak !== undefined && isSelectable(tweak);
  });
  if (ids.length === 0) return;

  const chosen = state.catalog.tweaks.filter((tweak) => ids.includes(tweak.id));
  const oneWay = chosen.filter((tweak) => tweak.irreversible);

  let body = `${mode === 'apply' ? 'Apply' : 'Revert'} ${ids.length} tweak${ids.length === 1 ? '' : 's'}?`;
  if (mode === 'apply' && oneWay.length > 0) {
    const names = oneWay.slice(0, 6).map((tweak) => `  • ${tweak.name}`).join('\n');
    const more = oneWay.length > 6 ? `\n  …and ${oneWay.length - 6} more` : '';
    body += `\n\n${oneWay.length} of these cannot be undone by SigmaTweaks:\n${names}${more}`;
  }

  if (!(await confirmAction(mode === 'apply' ? 'Apply tweaks' : 'Revert tweaks', body))) return;

  showLog();
  const outcome = await busy(`${mode === 'apply' ? 'Applying' : 'Reverting'}...`, () =>
    api.runBatch(ids, mode, dom.restorePoint.checked),
  );

  // Everything that succeeded leaves the batch; failures stay ticked so they
  // can be retried once the reason is dealt with.
  for (const result of outcome.results) {
    if (result.success) state.selected.delete(result.id);
  }

  await showView(state.view);

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
  const ok = await confirmAction(
    'Restore backup',
    `Put back every value recorded in this backup?\n\n${path}`,
    'Restore',
  );
  if (!ok) return;

  showLog();
  try {
    await busy('Restoring backup...', () => api.restoreBackup(path));
  } catch (error) {
    appendLog({ level: 'error', message: api.describeError(error) });
  }
  await showView(BACKUPS);
}

function applyPreset(key: string): void {
  const preset = state.catalog.presets.find((candidate) => candidate.key === key);
  if (!preset) return;

  // Selecting across the whole catalog, not just this page: the batch runs in
  // one go and the backend skips anything that does not apply here.
  for (const id of preset.tweaks) state.selected.add(id);

  appendLog({
    level: 'info',
    message: `Preset “${preset.name}” selected ${preset.tweaks.length} tweaks. Review them, then press Apply.`,
  });
  showLog();

  if (state.catalog.categories.includes(state.view)) renderCategory();
  updateSelectionUi();
}

/* ------------------------------------------------------------------- wiring */

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
        .then((path) => {
          appendLog({ level: 'success', message: `Profile written to ${path}` });
          showLog();
        })
        .catch((error) => appendLog({ level: 'error', message: api.describeError(error) }));
    }

    if (target.id === 'open-data') {
      void api
        .openDataDirectory()
        .then((path) => {
          appendLog({ level: 'info', message: `Opened ${path}` });
          showLog();
        })
        .catch((error) => appendLog({ level: 'error', message: api.describeError(error) }));
    }
  });

  dom.search.addEventListener('input', () => {
    state.search = dom.search.value;
    if (state.catalog.categories.includes(state.view)) renderCategory();
  });

  dom.selectAll.addEventListener('click', () => {
    for (const tweak of visibleTweaks()) {
      if (isSelectable(tweak)) state.selected.add(tweak.id);
    }
    renderCategory();
    updateSelectionUi();
  });

  dom.selectNone.addEventListener('click', () => {
    state.selected.clear();
    if (state.catalog.categories.includes(state.view)) renderCategory();
    updateSelectionUi();
  });

  dom.refresh.addEventListener('click', () => void showView(state.view));

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
}

function renderHeader(): void {
  const info = state.info;
  dom.subtitle.textContent = info.is_windows11 ? 'Windows 11 optimization' : 'Windows optimization';
  dom.host.textContent = `${info.os_name} ${info.display_version} · ${info.cpu} · ${info.memory_gb} GB RAM`;

  const badge = document.createElement('span');
  if (info.is_admin) {
    badge.className = 'badge ok';
    badge.textContent = 'ADMINISTRATOR';
  } else {
    badge.className = 'badge warn';
    badge.textContent = 'NOT ELEVATED — CLICK TO RESTART AS ADMIN';
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
  };

  renderHeader();

  dom.preset.replaceChildren(new Option('Preset…', ''), ...catalog.presets.map((preset) => {
    const option = new Option(`${preset.name} (${preset.tweaks.length})`, preset.key);
    option.title = preset.description;
    return option;
  }));

  wireEvents();
  await showView(OVERVIEW);

  if (!info.is_admin) {
    appendLog({
      level: 'warn',
      message: 'Running without administrator rights. System-wide tweaks will be refused.',
    });
  }
}

main().catch((error: unknown) => {
  document.body.innerHTML =
    `<div class="overlay"><p>SigmaTweaks could not start</p><small>${
      escapeHtml(api.describeError(error))
    }</small></div>`;
});
