const CACHE = "jandali-market-landing-v2";
const PREFIX = "jandali-market-shell-";
const SHELL = ["./", "./index.html"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key.startsWith(PREFIX) && key !== CACHE).map((key) => caches.delete(key)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || !url.pathname.startsWith("/Jandali-Syria-Marketplace/")) return;
  const isLanding = url.pathname.endsWith("/Jandali-Syria-Marketplace/") ||
    url.pathname.endsWith("/Jandali-Syria-Marketplace/index.html");
  if (!isLanding) {
    event.respondWith(fetch(request));
    return;
  }
  event.respondWith(
    fetch(request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy));
      }
      return response;
    }).catch(() => caches.match("./index.html"))
  );
});
