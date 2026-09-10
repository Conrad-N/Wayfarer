// Which view ids are currently mounted in a slot, with counts (a view can be open in
// more than one slot). Slots keep this current on mount/swap; views read it to adapt to
// what else is on screen — e.g. NAV drops its mini target block when a full TARGET panel
// is up. Counting (not a bool) so closing one of two duplicates keeps it "open".

const counts = new Map<string, number>();

export function mountView(id: string): void {
  counts.set(id, (counts.get(id) ?? 0) + 1);
}

export function unmountView(id: string): void {
  const n = (counts.get(id) ?? 0) - 1;
  if (n > 0) counts.set(id, n);
  else counts.delete(id);
}

export function isViewOpen(id: string): boolean {
  return (counts.get(id) ?? 0) > 0;
}
