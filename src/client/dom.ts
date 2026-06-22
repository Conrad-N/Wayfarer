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
