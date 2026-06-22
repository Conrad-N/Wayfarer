import { defineConfig } from "vite";

// The browser client talks to the authoritative sim server (docs/03 Keystone 1)
// only through the API. In dev, Vite proxies /api/* to the Node backend so the
// client never needs to know the backend's port.
export default defineConfig({
  server: {
    proxy: {
      "/api": "http://localhost:8787",
    },
  },
});
