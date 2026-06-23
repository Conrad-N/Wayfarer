// A tiny DOM builder so views can construct their own subtree concisely (and with
// classes, not shared ids — that's what lets the same view mount in two slots at once).

type Child = Node | string | null | undefined | false;
type Attrs = Record<string, string | number | boolean | EventListener | null | undefined>;

export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs?: Attrs,
  ...children: Child[]
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === "class") el.className = String(v);
      else if (k === "html") el.innerHTML = String(v);
      else if (k.startsWith("on") && typeof v === "function") {
        el.addEventListener(k.slice(2).toLowerCase(), v as EventListener);
      } else if (k === "value") {
        (el as HTMLInputElement).value = String(v);
      } else if (v === true) {
        el.setAttribute(k, "");
      } else {
        el.setAttribute(k, String(v));
      }
    }
  }
  for (const c of children) {
    if (c == null || c === false) continue;
    el.append(c as Node | string);
  }
  return el;
}

/** A KEY · VALUE telemetry row, as an HTML string (for innerHTML batches). */
export const rowHtml = (k: string, v: string) =>
  `<div class="row"><span class="k">${k}</span><span class="v">${v}</span></div>`;

/** Escape a server-supplied string before it goes into innerHTML. "Server-authoritative"
 *  is not "HTML-safe": the moment a name is AI- or player-influenced, raw interpolation is
 *  stored XSS (docs/FIX-SPECS H9). Numbers don't need it, but escaping uniformly is simplest. */
export function esc(s: unknown): string {
  return String(s).replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!,
  );
}

/** Format a number to `dp` decimals, or an em-dash placeholder when it isn't finite — so a
 *  missing/NaN telemetry field renders as a dead segment, never "NaN" (docs/FIX-SPECS H8). */
export function fixed(v: number, dp: number): string {
  return Number.isFinite(v) ? v.toFixed(dp) : "—";
}

/** The ONE time formatter for the whole UI: seconds → DD:HH:mm:ss, ALWAYS all four fields
 *  (days zero-padded to ≥2, never hidden — interplanetary countdowns run to hundreds of days,
 *  so a minutes:seconds field would read as e.g. "868258:10"). Non-finite ⇒ a dead segment. */
export function dhms(seconds: number): string {
  if (!Number.isFinite(seconds)) return "--:--:--:--";
  const s = Math.max(0, Math.floor(seconds));
  const days = Math.floor(s / 86400);
  const hh = Math.floor((s % 86400) / 3600);
  const mm = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  const p2 = (n: number) => String(n).padStart(2, "0");
  return `${p2(days)}:${p2(hh)}:${p2(mm)}:${p2(ss)}`;
}

/** Read an error message off a failed Response without assuming the body is JSON. A non-JSON
 *  4xx/5xx (e.g. an HTML error page) must not throw and get mislabeled as a connection error
 *  by the caller's catch (docs/FIX-SPECS M-jsonerr). */
export async function errText(res: Response): Promise<string> {
  try {
    const ct = res.headers.get("content-type") ?? "";
    if (ct.includes("json")) return (await res.json()).error ?? res.statusText;
  } catch {
    /* fall through to status text */
  }
  return res.statusText || `HTTP ${res.status}`;
}

/** POST JSON, swallowing transient errors (the poll re-syncs next tick). */
export async function post(url: string, body: unknown): Promise<Response | null> {
  try {
    return await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    return null;
  }
}

/** GET JSON, swallowing transient errors (the poll re-syncs next tick). */
export async function get(url: string): Promise<Response | null> {
  try {
    return await fetch(url);
  } catch {
    return null;
  }
}
