import type { StateResponse, ViewInstance } from "./types";
import { h } from "./dom";

// The SHIP AI console view — a chat log + an input. The conversation is held per-instance
// (so a second AI panel is a fresh session). It talks to /api/ai/chat; the bridge runs the
// tool-use loop server-side (docs/03 Keystone 2).

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

interface AiStatus {
  available: boolean;
  personas: Array<{ id: string; label: string }>;
  defaultPersona: string;
}

export function createAiView(): ViewInstance {
  const history: ChatMessage[] = [];
  let busy = false;
  let persona = "officer"; // overwritten by /api/ai/status once it loads

  // Status header — a state dot + label, and a persona selector. Replaces the old
  // one-line banner; the persona only changes the AI's voice, not its behavior.
  const dot = h("span", { class: "ai-dot" });
  const statusText = h("span", { class: "ai-status-text" }, "connecting…");
  const personaSelect = h("select", { class: "ai-persona", title: "AI persona" }) as HTMLSelectElement;
  const header = h(
    "div",
    { class: "ai-header" },
    h("span", { class: "ai-indicator" }, dot, statusText),
    personaSelect,
  );

  const log = h("div", { class: "ai-log scrollarea" });
  const input = h("input", { type: "text", class: "ai-input", placeholder: "talk to the ship…" }) as HTMLInputElement;
  const form = h("form", { class: "ai-form", autocomplete: "off" }, h("span", { class: "prompt" }, ">"), input);
  const root = h("div", { class: "view ai-view" }, header, log, form);

  function append(role: "user" | "assistant" | "system", text: string): HTMLElement {
    const line = h("div", { class: `ai-line ${role}` }, role === "user" ? `> ${text}` : text);
    log.append(line);
    log.scrollTop = log.scrollHeight;
    return line;
  }

  function setStatus(state: "online" | "offline" | "unknown", label: string): void {
    dot.classList.remove("online", "offline", "unknown");
    dot.classList.add(state);
    statusText.textContent = label;
  }

  personaSelect.addEventListener("change", () => {
    persona = personaSelect.value;
    const label = personaSelect.options[personaSelect.selectedIndex]?.text ?? persona;
    append("system", `[persona: ${label}]`);
  });

  fetch("/api/ai/status")
    .then((r) => r.json())
    .then((s: AiStatus) => {
      personaSelect.replaceChildren(
        ...(s.personas ?? []).map((p) => h("option", { value: p.id }, p.label)),
      );
      persona = s.defaultPersona ?? s.personas?.[0]?.id ?? persona;
      personaSelect.value = persona;
      personaSelect.disabled = !s.available;
      if (s.available) {
        setStatus("online", "online");
      } else {
        setStatus("offline", "offline");
        append("system", "[ship AI offline — set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY, then reload]");
      }
    })
    .catch(() => {
      setStatus("unknown", "unavailable");
      personaSelect.disabled = true;
    });

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const text = input.value.trim();
    if (!text || busy) return;

    input.value = "";
    append("user", text);
    history.push({ role: "user", content: text });

    busy = true;
    const pending = append("assistant", "…");
    try {
      const res = await fetch("/api/ai/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ messages: history, persona }),
      });
      const data = await res.json();
      if (res.ok) {
        pending.textContent = data.reply;
        history.push({ role: "assistant", content: data.reply });
      } else {
        pending.textContent = `[${data.error ?? "error"}]`;
        pending.className = "ai-line system";
      }
    } catch {
      pending.textContent = "[connection error]";
      pending.className = "ai-line system";
    } finally {
      busy = false;
      input.focus();
    }
  });

  // The AI console is event-driven, not poll-driven; render is a no-op.
  return { root, render: (_state: StateResponse) => {} };
}
