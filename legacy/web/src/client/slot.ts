import { h } from "./dom";
import { mountView, unmountView } from "./mounted";
import type { PanelColor, StateResponse, ViewDef, ViewInstance } from "./types";

// A SLOT is one of the fixed panel frames. It owns the panel chrome (border, scanlines,
// title) and a switcher (▾) that can mount ANY registered view into it — including a view
// already shown in another slot (duplicates are fine, the operator asked for that). The
// mounted view builds its own DOM, so two instances never collide.

const COLORS: PanelColor[] = ["amber", "cyan", "violet", "green", "rose", "steel"];

export interface Slot {
  element: HTMLElement;
  render(state: StateResponse): void;
}

export function createSlot(registry: ViewDef[], defaultId: string): Slot {
  let current: ViewInstance | null = null;
  let currentDef: ViewDef | null = null;

  const title = h("span", { class: "slot-title" });
  const switchBtn = h(
    "button",
    { class: "slot-switch", type: "button", title: "switch display", "aria-label": "switch display" },
    "▾",
  );
  const menu = h("ul", { class: "slot-menu", hidden: true });
  const header = h("header", { class: "panel-title slot-header" }, switchBtn, title, menu);
  const body = h("div", { class: "slot-body" });
  const section = h("section", { class: "panel" }, header, body);

  const closeMenu = () => {
    menu.hidden = true;
    switchBtn.classList.remove("open");
  };

  function mount(def: ViewDef): void {
    if (current?.destroy) current.destroy();
    if (currentDef) unmountView(currentDef.id);
    current = def.create();
    currentDef = def;
    mountView(def.id);
    body.replaceChildren(current.root);
    title.textContent = `◄ ${def.label} ►`;
    for (const c of COLORS) section.classList.remove(c);
    section.classList.add(def.color);
    // reflect the active choice in the menu
    menu.querySelectorAll<HTMLButtonElement>("button").forEach((b) => {
      b.classList.toggle("active", b.dataset.id === def.id);
    });
  }

  for (const def of registry) {
    menu.append(
      h(
        "li",
        {},
        h(
          "button",
          {
            class: "slot-menu-item",
            type: "button",
            "data-id": def.id,
            onClick: () => {
              closeMenu();
              mount(def);
            },
          },
          def.label,
        ),
      ),
    );
  }

  switchBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    if (menu.hidden) {
      menu.hidden = false;
      switchBtn.classList.add("open");
    } else {
      closeMenu();
    }
  });
  // close when clicking anywhere outside this header
  document.addEventListener("click", (e) => {
    if (!header.contains(e.target as Node)) closeMenu();
  });

  mount(registry.find((d) => d.id === defaultId) ?? registry[0]);

  return {
    element: section,
    render(state) {
      current?.render(state);
    },
  };
}
