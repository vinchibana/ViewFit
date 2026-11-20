// No content scripts or page access: Chrome performs the zoom itself.
export function parseState(value) {
  if (!value || typeof value.enabled !== "boolean" ||
      typeof value.chromeEnabled !== "boolean" ||
      typeof value.externalConnected !== "boolean" ||
      typeof value.chromeZoom !== "number" || !Number.isFinite(value.chromeZoom) ||
      value.chromeZoom < 0.25 || value.chromeZoom > 5 ||
      !Number.isSafeInteger(value.generation)) return null;
  return {
    enabled: value.enabled,
    chromeEnabled: value.chromeEnabled,
    externalConnected: value.externalConnected,
    // The internal-display profile is always exactly 100%, even if a stale
    // configured external factor accidentally arrives in the host's message.
    chromeZoom: value.externalConnected ? value.chromeZoom : 1,
    generation: value.generation,
  };
}

export class ZoomController {
  constructor(tabs, onResult = () => {}) {
    this.tabs = tabs;
    this.onResult = onResult;
    this.state = null;
    this.applied = new Map();
    this.pending = new Map();
  }

  profileKey() { return JSON.stringify(this.state); }
  isEnabled() { return Boolean(this.state?.enabled && this.state?.chromeEnabled); }
  disconnect() { this.state = null; this.applied.clear(); }
  forgetTab(id) { this.applied.delete(id); }

  async acceptState(message) {
    const state = parseState(message);
    if (!state) return false;
    const changed = JSON.stringify(state) !== this.profileKey();
    this.state = state;
    if (changed) {
      this.applied.clear();
      await this.applyAll();
    }
    return true;
  }

  async applyAll() {
    if (!this.isEnabled()) return;
    try {
      const tabs = await this.tabs.query({});
      await Promise.all(tabs.filter(tab => !tab.discarded && tab.status !== "unloaded")
        .map(tab => this.applyTab(tab.id)));
    } catch (error) { this.onResult({ ok: false, error: String(error.message || error) }); }
  }

  applyTab(id, force = false) {
    if (!Number.isInteger(id) || id < 0) return Promise.resolve();
    const previous = this.pending.get(id) || Promise.resolve();
    const next = previous.catch(() => {}).then(() => this.perform(id, force));
    this.pending.set(id, next);
    next.finally(() => { if (this.pending.get(id) === next) this.pending.delete(id); });
    return next;
  }

  async perform(id, force) {
    if (!this.isEnabled()) return;
    let key = this.profileKey();
    if (!force && this.applied.get(id) === key) return;
    try {
      // Navigation resets Chrome's per-tab scope. Establish it before every
      // target change so we never write the user's persistent per-site zoom.
      await this.tabs.setZoomSettings(id, { mode: "automatic", scope: "per-tab" });
      if (!this.isEnabled()) return;
      // Read AFTER the awaited API call: unplugging during it must not apply
      // an obsolete external-screen factor.
      key = this.profileKey();
      const factor = this.state.chromeZoom;
      await this.tabs.setZoom(id, factor);
      if (this.profileKey() === key) this.applied.set(id, key);
      this.onResult({ ok: true, tabId: id, factor });
    } catch (error) {
      // Restricted chrome:// pages, closing/discarded tabs and other extension
      // pages can reject zoom. Do not count them as applied or stop other tabs.
      this.applied.delete(id);
      this.onResult({ ok: false, tabId: id, error: String(error.message || error) });
    }
  }
}
