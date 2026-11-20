
const CACHE_NAME = "novelia-shell-v67";
const CACHE_PREFIX = "novelia-shell-";
const CDN_CACHE = "novelia-cdn-v1";
const CDN_ORIGIN = "https://cdn.jsdelivr.net";

const APP_FILES = [
  "./",
  "./index.html",
  "./library.html",
  "./contests.html",
  "./palmares.html",
  "./contest-admin.html",
  "./contest-jury.html",
  "./notifications.html",
  "./reader.html",
  "./publish.html",
  "./profile.html",
  "./public-profile.html",
  "./earnings.html",
  "./earnings-admin.html",
  "./monetization-info.html",
  "./payment-result.html",
  "./purchases.html",
  "./downloads.html",
  "./copyright.html",
  "./protection.html",
  "./offline.html",
  "./bottom-nav.js",
  "./theme-gold.css",
  "./christmas.css",
  "./manifest.webmanifest",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png"
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_FILES))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys
          .filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;

  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // Les dépendances CDN sont versionnées : cache-first pour le mode hors ligne.
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

  // Les appels Supabase et les autres domaines restent gérés par le navigateur.
  if (url.origin !== self.location.origin) return;

  // Navigation : réseau en priorité, page en cache si hors ligne.
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
        // Les lecteurs hors ligne utilisent des paramètres (db_story, local_story).
        // On sert donc la page mise en cache sans tenir compte de la query string.
        const shellCache = await caches.open(CACHE_NAME);
        return await shellCache.match(request, { ignoreSearch: true }) ||
          await caches.match("./offline.html") ||
          Response.error();
      }
    })());
    return;
  }

  // Ressources statiques : réponse immédiate depuis le cache,
  // puis actualisation en arrière-plan pour éviter les anciennes versions.
  const cachedResponse = caches.match(request);
  const networkResponse = fetch(request).then(async response => {
    if (response.ok && response.type === "basic") {
      const cache = await caches.open(CACHE_NAME);
      await cache.put(request, response.clone());
    }
    return response;
  }).catch(() => null);

  event.waitUntil(networkResponse.then(() => undefined));

  event.respondWith((async () => {
    const cached = await cachedResponse;
    if (cached) return cached;

    const response = await networkResponse;
    return response || Response.error();
  })());
});
