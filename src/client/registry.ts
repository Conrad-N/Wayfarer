import type { ViewDef } from "./types";
import { createNavView } from "./nav-panel";
import { createSystemMapView } from "./system-map";
import { createFlightView } from "./flight-panel";
import { createManeuverView } from "./maneuver-panel";
import { createTargetView } from "./target-panel";
import { createStationView } from "./station-panel";
import { createCargoView } from "./cargo-panel";
import { createAiView } from "./ai-console";

// Every display the operator can mount into a slot. Order = the order they appear in each
// slot's switcher menu. Color travels with the view (so a slot recolours to whatever it
// currently holds).
export const VIEWS: ViewDef[] = [
  { id: "nav", label: "NAV · ORBITAL TELEMETRY", color: "amber", create: createNavView },
  { id: "map", label: "SYSTEM MAP · HELIOCENTRIC", color: "cyan", create: createSystemMapView },
  { id: "flight", label: "FLIGHT · ATTITUDE", color: "cyan", create: createFlightView },
  { id: "maneuver", label: "MANEUVER · FLIGHT PLAN", color: "violet", create: createManeuverView },
  { id: "target", label: "TARGET · RENDEZVOUS", color: "rose", create: createTargetView },
  { id: "station", label: "STATION · DOCK", color: "cyan", create: createStationView },
  { id: "cargo", label: "CARGO · HOLD", color: "steel", create: createCargoView },
  { id: "ai", label: "SHIP AI · CONSOLE", color: "green", create: createAiView },
];
