(() => {
  "use strict";
  const CONSENT_KEY = "novelia_analytics_consent_v1";
  const VISITOR_KEY = "novelia_analytics_visitor_v1";
  const SESSION_KEY = "novelia_analytics_session_v1";
  const PROJECT_REF = "czwaokqpqgrghxeeyguq";
  const API_URL = "https://" + PROJECT_REF + ".supabase.co/rest/v1/rpc/novelia_track_visit";
  const API_KEY = "sb_publishable_ORoXM7DSfxdLF0jz8JRqqA_SISXCNsg";

  function uuid() {
    if (window.crypto && crypto.getRandomValues) {
      const b = new Uint8Array(16);
      crypto.getRandomValues(b);
      b[6] = (b[6] & 15) | 64;
      b[8] = (b[8] & 63) | 128;
      const h = [...b].map(x => x.toString(16).padStart(2, "0")).join("");
      return h.slice(0,8)+"-"+h.slice(8,12)+"-"+h.slice(12,16)+"-"+h.slice(16,20)+"-"+h.slice(20);
    }
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
      const r = Math.random() * 16 | 0;
      return (c === "x" ? r : (r & 3 | 8)).toString(16);
    });
  }

  function consentBanner() {
    if (document.getElementById("noveliaAnalyticsConsent")) return;
    const style = document.createElement("style");
    style.textContent = "#noveliaAnalyticsConsent{position:fixed;z-index:99999;left:12px;right:12px;bottom:12px;max-width:560px;margin:auto;padding:14px;background:#fffdf7;color:#352808;border:1px solid #d9c58e;border-radius:14px;box-shadow:0 8px 30px #0003;font:14px/1.45 Arial,sans-serif}#noveliaAnalyticsConsent p{margin:0 0 10px}#noveliaAnalyticsConsent .na-actions{display:flex;gap:8px;flex-wrap:wrap}#noveliaAnalyticsConsent button{border:0;border-radius:8px;padding:9px 13px;font-weight:bold;cursor:pointer}#noveliaAnalyticsConsent .na-yes{background:#c3941c;color:#201a0b}#noveliaAnalyticsConsent .na-no{background:#eee8da;color:#352808}#noveliaAnalyticsConsent a{color:#705410}";
    document.head.appendChild(style);
    const box = document.createElement("section");
    box.id = "noveliaAnalyticsConsent";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-label", "Choix des statistiques de fréquentation");
    box.innerHTML = '<p>Novelia souhaite mesurer sa fréquentation pour améliorer la plateforme. Ces statistiques utilisent un identifiant aléatoire et ne collectent ni adresse IP, ni nom, ni adresse e-mail. Tu peux refuser.</p><p><a href="./confidentialite.html">En savoir plus sur la confidentialité</a></p><div class="na-actions"><button type="button" class="na-yes">Accepter</button><button type="button" class="na-no">Refuser</button></div>';
    document.body.appendChild(box);
    box.querySelector(".na-yes").addEventListener("click", () => {
      try { localStorage.setItem(CONSENT_KEY, "yes"); } catch {}
      box.remove();
      track();
    });
    box.querySelector(".na-no").addEventListener("click", () => {
      try { localStorage.setItem(CONSENT_KEY, "no"); } catch {}
      box.remove();
    });
  }

  function getVisitorId() {
    let id = localStorage.getItem(VISITOR_KEY);
    if (!id) {
      id = uuid();
      localStorage.setItem(VISITOR_KEY, id);
    }
    return id;
  }

  function getSessionId() {
    let id = sessionStorage.getItem(SESSION_KEY);
    if (!id) {
      id = uuid();
      sessionStorage.setItem(SESSION_KEY, id);
    }
    return id;
  }

  function classifyReferrer(host) {
    if (!host) return "direct";
    const h = host.toLowerCase();
    if (h.includes("novelia") || h.includes("github.io")) return "internal";
    if (/google|bing|yahoo|duckduckgo|ecosia/.test(h)) return "search";
    if (/tiktok|facebook|instagram|whatsapp|telegram|x\.com|twitter|pinterest|reddit/.test(h)) return "social";
    return "referral";
  }

  async function track() {
    if (localStorage.getItem(CONSENT_KEY) !== "yes" || !navigator.onLine) return;
    try {
      const visitorId = getVisitorId();
      const sessionId = getSessionId();
      const referrer = document.referrer ? new URL(document.referrer).hostname : "";
      let source = sessionStorage.getItem("novelia_analytics_source_v1");
      let referrerHost = sessionStorage.getItem("novelia_analytics_referrer_v1");
      if (!source) {
        source = classifyReferrer(referrer);
        referrerHost = source === "direct" || source === "internal" ? "" : referrer;
        sessionStorage.setItem("novelia_analytics_source_v1", source);
        sessionStorage.setItem("novelia_analytics_referrer_v1", referrerHost);
      }
      let path = location.pathname || "/";
      if (path.endsWith("/reader.html")) {
        const story = new URLSearchParams(location.search).get("db_story");
        if (story && /^[0-9a-f-]{36}$/i.test(story)) path += "/story/" + story;
      }
      let authorization = "Bearer " + API_KEY;
      try {
        const key = "sb-" + PROJECT_REF + "-auth-token";
        const raw = localStorage.getItem(key);
        const session = raw ? JSON.parse(raw) : null;
        if (session && session.access_token) authorization = "Bearer " + session.access_token;
      } catch {}
      await fetch(API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": API_KEY,
          "Authorization": authorization
        },
        body: JSON.stringify({
          p_visitor_id: visitorId,
          p_session_id: sessionId,
          p_page_path: path,
          p_source: source,
          p_referrer_host: referrerHost || null
        }),
        keepalive: true
      });
    } catch (error) {
      console.debug("Statistiques Novelia indisponibles.", error);
    }
  }

  function start() {
    let choice = null;
    try { choice = localStorage.getItem(CONSENT_KEY); } catch {}
    if (choice === "yes") track();
    else if (choice !== "no") consentBanner();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
})();
