/* Barre de navigation du bas, commune à toutes les pages principales (écrans étroits). */
(function () {
  "use strict";
  // Décor saisonnier temporaire : actif jusqu'au 19 janvier 2027 inclus.
  var seasonEnd = new Date(2027, 0, 20, 0, 0, 0, 0);
  if (new Date() < seasonEnd && !document.querySelector('link[data-novelia-season]')) {
    var seasonalCss = document.createElement("link");
    seasonalCss.rel = "stylesheet";
    seasonalCss.href = "christmas.css?v=2026-noel";
    seasonalCss.setAttribute("data-novelia-season", "true");
    document.head.appendChild(seasonalCss);
    document.documentElement.classList.add("novelia-noel");
  }
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
    "discovery.html": "discovery.html", "authors.html": "discovery.html", "community.html": "discovery.html", "contests.html": "discovery.html", "palmares.html": "discovery.html",
    "library.html": "library.html",
    "publish.html": "publish.html", "author-dashboard.html": "publish.html",
    "notifications.html": "notifications.html"
  };
  var SHOW_ON = ["index.html", "discovery.html", "authors.html", "community.html", "contests.html", "palmares.html", "library.html", "publish.html",
    "author-dashboard.html", "notifications.html", "profile.html", "public-profile.html", "novelia-plus.html"];

  // Thème global jour/nuit, mémorisé sur cet appareil.
  var THEME_KEY = "novelia_site_theme_v1";
  function applyNoveliaTheme(theme) {
    var night = theme === "night";
    document.documentElement.classList.toggle("novelia-night", night);
    document.documentElement.setAttribute("data-novelia-theme", night ? "night" : "day");
    var btn = document.getElementById("noveliaThemeToggle");
    if (btn) { btn.textContent = night ? "☀ Mode jour" : "☾ Mode nuit"; btn.setAttribute("aria-pressed", night ? "true" : "false"); }
  }
  var savedTheme = "day"; try { savedTheme = localStorage.getItem(THEME_KEY) === "night" ? "night" : "day"; } catch (e) {}
  applyNoveliaTheme(savedTheme);
  function addThemeToggle() {
    if (document.getElementById("noveliaThemeToggle")) return;
    var header = document.querySelector("header"); if (!header) return;
    var btn = document.createElement("button"); btn.id = "noveliaThemeToggle"; btn.type = "button"; btn.className = "novelia-theme-toggle";
    btn.addEventListener("click", function () { var next = document.documentElement.classList.contains("novelia-night") ? "day" : "night"; try { localStorage.setItem(THEME_KEY, next); } catch (e) {} applyNoveliaTheme(next); });
    header.appendChild(btn); applyNoveliaTheme(savedTheme);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", addThemeToggle); else addThemeToggle();
  var themeStyle = document.createElement("style");
  themeStyle.textContent = ".novelia-theme-toggle{border:1px solid #b99b50;border-radius:999px;padding:8px 11px;background:#f2e8cf;color:#49370d;font-size:12px;font-weight:bold;cursor:pointer;white-space:nowrap}.novelia-night body{background:#171321!important;color:#eee8f7!important}.novelia-night header,.novelia-night footer,.novelia-night .card,.novelia-night .story,.novelia-night .shelf-card,.novelia-night .report-dialog,.novelia-night .nav-menu-panel{background:#211b2d!important;color:#eee8f7!important;border-color:#40364f!important}.novelia-night main,.novelia-night section,.novelia-night article{color:#eee8f7}.novelia-night h1,.novelia-night h2,.novelia-night h3,.novelia-night p,.novelia-night label,.novelia-night .logo,.novelia-night .account-area,.novelia-night .info,.novelia-night .shelf-title,.novelia-night .shelf-meta,.novelia-night .shelf-note{color:#eee8f7!important}.novelia-night a{color:#e4c56d}.novelia-night input,.novelia-night select,.novelia-night textarea{background:#171321!important;color:#f7f1ff!important;border-color:#514562!important}.novelia-night .filter,.novelia-night .account-button,.novelia-night .nav-menu summary{background:#30263d!important;color:#f2d98b!important;border-color:#514562!important}.novelia-night .hero{background:#282036!important}.novelia-night .nb{background:#211b2d!important;border-color:#40364f!important}.novelia-night .nb a{color:#c9bdd8!important}.novelia-night .nb a[aria-current=page]{color:#f0d47e!important}.novelia-night .novelia-theme-toggle{background:#3a3048;color:#f4dc91;border-color:#79643a}";
  document.head.appendChild(themeStyle);
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
    ".nb-badge{position:absolute;top:0;left:calc(50% + 6px);min-width:17px;height:17px;padding:0 4px;border-radius:9px;background:#d1432d;color:#fff;font:bold 10px/17px Arial,sans-serif;text-align:center}" +
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

  // Pastille de notifications non lues (lecture directe, sans second client Supabase)
  var SB_URL = "https://czwaokqpqgrghxeeyguq.supabase.co";
  var SB_KEY = "sb_publishable_ORoXM7DSfxdLF0jz8JRqqA_SISXCNsg";
  function setBadge(n) {
    var a = nav.querySelector('a[href="notifications.html"]');
    if (!a) return;
    var el = a.querySelector(".nb-badge");
    if (!n) { if (el) el.remove(); return; }
    if (!el) { el = document.createElement("b"); el.className = "nb-badge"; a.appendChild(el); }
    el.textContent = n > 9 ? "9+" : String(n);
  }
  function refreshBadge() {
    try {
      var raw = localStorage.getItem("sb-czwaokqpqgrghxeeyguq-auth-token");
      if (!raw) { setBadge(0); return; }
      var s = JSON.parse(raw);
      if (!s || !s.access_token || !s.user || (s.expires_at && s.expires_at * 1000 < Date.now())) return;
      fetch(SB_URL + "/rest/v1/notifications?select=id&recipient_id=eq." + encodeURIComponent(s.user.id) + "&is_read=eq.false", {
        method: "HEAD",
        headers: { apikey: SB_KEY, Authorization: "Bearer " + s.access_token, Prefer: "count=exact", Range: "0-0" }
      }).then(function (r) {
        var cr = r.headers.get("content-range") || "";
        var n = parseInt(cr.split("/")[1], 10);
        if (!isNaN(n)) { sessionStorage.setItem("nb_unread", String(n)); setBadge(n); }
      }).catch(function () {});
    } catch (e) {}
  }
  var cached = parseInt(sessionStorage.getItem("nb_unread") || "0", 10);
  if (cached) setBadge(cached);
  refreshBadge();
  document.addEventListener("visibilitychange", function () { if (!document.hidden) refreshBadge(); });
  window.addEventListener("pageshow", refreshBadge);
})();
