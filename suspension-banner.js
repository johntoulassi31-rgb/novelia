/* Affiche un bandeau si le compte connecté est suspendu (lecture seule). */
(async function () {
  try {
    var URL = "https://czwaokqpqgrghxeeyguq.supabase.co";
    var KEY = "sb_publishable_ORoXM7DSfxdLF0jz8JRqqA_SISXCNsg";
    var raw = localStorage.getItem("sb-czwaokqpqgrghxeeyguq-auth-token");
    if (!raw) return;
    var s = JSON.parse(raw);
    if (!s || !s.access_token || (s.expires_at && s.expires_at * 1000 < Date.now())) return;
    var res = await fetch(URL + "/rest/v1/rpc/novelia_my_suspension", {
      method: "POST",
      headers: { apikey: KEY, Authorization: "Bearer " + s.access_token, "Content-Type": "application/json" },
      body: "{}"
    });
    if (!res.ok) return;
    var d = await res.json();
    if (!d || !d.suspended) return;
    var box = document.createElement("div");
    box.setAttribute("role", "alert");
    box.style.cssText = "background:#fbe3df;border-bottom:2px solid #d1432d;color:#7a1f12;padding:12px 16px;font:14px/1.5 Arial,sans-serif;position:relative;z-index:90";
    var t = "Ton compte est suspendu";
    if (d.until) t += " jusqu'au " + new Date(d.until).toLocaleString("fr-FR", { dateStyle: "long", timeStyle: "short" });
    t += ". Tu peux lire, mais pas publier, commenter, aimer ni suivre.";
    if (d.reason) t += " Motif : " + d.reason;
    box.textContent = t;
    document.body.insertBefore(box, document.body.firstChild);
  } catch (e) { /* on ne bloque jamais la page */ }
})();
