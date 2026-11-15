/* Barre de navigation du bas, commune à toutes les pages principales (écrans étroits). */
(function () {
  "use strict";
  var ICONS = {
    home: '<path d="M3 10.5 12 3l9 7.5V21H3z"/><path d="M9 21v-6h6v6"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    library: '<path d="M2 5.5C4.5 4 8 4 12 6c4-2 7.5-2 10-.5V19c-2.5-1.5-6-1.5-10 .5-4-2-7.5-2-10-.5z"/><path d="M12 6v13.5"/>',
    write: '<path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
    bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>'
  };
  var ITEMS = [
    ["index.html", "Accueil", "home"],
    ["discovery.html", "Découvrir", "search"],
    ["library.html", "Bibliothèque", "library"],
    ["publish.html", "Écrire", "write"],
    ["notifications.html", "Alertes", "bell"]
  ];
  // Page affichée -> onglet à mettre en évidence
  var ACTIVE = {
    "index.html": "index.html",
    "discovery.html": "discovery.html", "authors.html": "discovery.html", "community.html": "discovery.html",
    "library.html": "library.html",
    "publish.html": "publish.html", "author-dashboard.html": "publish.html",
    "notifications.html": "notifications.html"
  };
  var SHOW_ON = ["index.html", "discovery.html", "authors.html", "community.html", "library.html", "publish.html",
    "author-dashboard.html", "notifications.html", "profile.html", "public-profile.html", "novelia-plus.html"];

  var page = location.pathname.split("/").pop() || "index.html";
  if (SHOW_ON.indexOf(page) === -1) return;
  var current = ACTIVE[page] || "";

  var css = document.createElement("style");
  css.textContent =
    ".nb{display:none}" +
    "@media(max-width:699px){" +
    "body.has-nb{padding-bottom:calc(76px + env(safe-area-inset-bottom,0px))}" +
    ".nb{position:fixed;left:0;right:0;bottom:0;z-index:80;display:grid;grid-template-columns:repeat(5,minmax(0,1fr));" +
    "background:#f9f4ea;border-top:1px solid #f2e9d2;padding:6px 4px calc(6px + env(safe-area-inset-bottom,0px))}" +
    ".nb a{position:relative;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;" +
    "padding:6px 1px 9px;color:#796a44;text-decoration:none;font:10px Arial,sans-serif;min-width:0}" +
    ".nb svg{width:24px;height:24px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}" +
    ".nb a[aria-current=page]{color:#926f15}" +
    ".nb a[aria-current=page] svg{fill:rgba(146,111,21,.22)}" +
    ".nb a[aria-current=page]::after{content:'';position:absolute;bottom:0;left:25%;right:25%;height:3px;border-radius:3px 3px 0 0;background:#926f15}" +
    "}";
  document.head.appendChild(css);

  var nav = document.createElement("nav");
  nav.className = "nb";
  nav.setAttribute("aria-label", "Navigation rapide");
  ITEMS.forEach(function (it) {
    var a = document.createElement("a");
    a.href = it[0];
    if (it[0] === current) a.setAttribute("aria-current", "page");
    a.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">' + ICONS[it[2]] + "</svg><span>" + it[1] + "</span>";
    nav.appendChild(a);
  });
  document.body.appendChild(nav);
  document.body.classList.add("has-nb");
})();
