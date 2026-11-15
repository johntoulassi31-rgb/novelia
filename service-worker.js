
const CACHE_NAME = "novelia-shell-v6";
const CACHE_PREFIX = "novelia-shell-";
const CDN_CACHE = "novelia-cdn-v1";
const CDN_ORIGIN = "https://cdn.jsdelivr.net";

const APP_FILES = [
  "./",
  "./index.html",
  "./reader.html",
  "./offline.html",
  "./bottom-nav.js",
  "./manifest.webmanifest",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png"
];

// Installation du Service Worker
self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_FILES))
      .then(() => self.skipWaiting())
  );
});

// Activation et nettoyage des anciens caches
self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys
          .filter(key =>
            key.startsWith(CACHE_PREFIX) &&
            key !== CACHE_NAME
          )
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

// Gestion des requêtes
self.addEventListener("fetch", event => {
  const request = event.request;

  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // Bibliothèque Supabase (versions fixées) : cache d'abord, pour fonctionner hors ligne
  if (url.origin === CDN_ORIGIN && url.pathname.startsWith("/npm/")) {
    event.respondWith((async () => {
      const cached = await caches.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      if (response.ok) {
        const cache = await caches.open(CDN_CACHE);
        await cache.put(request, response.clone());
      }
      return response;
    })());
    return;
  }

  // Ne pas intercepter Supabase ni les autres domaines externes
  if (url.origin !== self.location.origin) return;

  // Gestion des pages HTML
  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);

        if (response.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put(request, response.clone());
        }

        return response;
      } catch (error) {
        return (
          await caches.match(request) ||
          await caches.match("./offline.html")
        );
      }
    })());

    return;
  }

  // Gestion des ressources statiques
  event.respondWith((async () => {
    const cached = await caches.match(request);

    if (cached) return cached;

    try {
      const response = await fetch(request);

      if (response.ok) {
        const cache = await caches.open(CACHE_NAME);
        await cache.put(request, response.clone());
      }

      return response;
    } catch (error) {
      return Response.error();
    }
  })());
});
