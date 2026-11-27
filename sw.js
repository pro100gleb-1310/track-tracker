/* Offline support for the home-screen (iPhone) version.
   The app page is fetched from the network first so updates arrive right away; the cached copy is used when there is no connection.
   Fonts and other files from other sites are served from cache and refreshed in the background. */
const CACHE = "uchet-v1";
const CORE = ["./", "./manifest.webmanifest", "./icons/apple-touch-icon.png", "./icons/icon-192.png", "./icons/icon-512.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

function timeout(ms) { return new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), ms)); }

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin === location.origin) {
    const key = req.mode === "navigate" ? "./" : req;
    e.respondWith((async () => {
      const cache = await caches.open(CACHE);
      const net = fetch(req).then(r => { if (r.ok) cache.put(key, r.clone()); return r; });
      try { return await Promise.race([net, timeout(4000)]); }
      catch (_) {
        const hit = await cache.match(key, { ignoreSearch: true });
        if (hit) return hit;
        return net;
      }
    })());
    return;
  }
  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const hit = await cache.match(req);
    const net = fetch(req).then(r => { if (r.ok || r.type === "opaque") cache.put(req, r.clone()); return r; }).catch(() => hit);
    if (hit) { e.waitUntil(net); return hit; }
    return net;
  })());
});
