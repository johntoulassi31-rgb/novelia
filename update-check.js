(() => {
  "use strict";
  if (window.__noveliaUpdateCheckStarted || !window.NoveliaNativeApp ||
      typeof window.NoveliaNativeApp.getVersionCode !== "function") return;
  window.__noveliaUpdateCheckStarted = true;

  const manifestUrl = "./updates.json?check=" + Date.now();
  fetch(manifestUrl, { cache: "no-store" })
    .then(response => {
      if (!response.ok) throw new Error("Mise à jour indisponible");
      return response.json();
    })
    .then(update => {
      const installedCode = Number(window.NoveliaNativeApp.getVersionCode());
      const latestCode = Number(update.versionCode);
      if (!Number.isFinite(latestCode) || latestCode <= installedCode ||
          !update.downloadUrl || document.getElementById("novelia-update-banner")) return;

      const style = document.createElement("style");
      style.textContent = `
        #novelia-update-banner{position:fixed;z-index:2147483000;left:12px;right:12px;bottom:calc(18px + env(safe-area-inset-bottom));max-width:560px;margin:auto;padding:17px;background:#170d35;color:#fff8e8;border:1px solid #c99b36;border-radius:16px;box-shadow:0 10px 35px #0005;font:14px Arial,sans-serif}
        #novelia-update-banner h3{margin:0 28px 7px 0;color:#f3cf75;font-size:17px}
        #novelia-update-banner p{margin:0 0 12px;line-height:1.45;color:#eee4cf}
        #novelia-update-banner .novelia-update-actions{display:flex;gap:9px;flex-wrap:wrap}
        #novelia-update-banner a,#novelia-update-banner button{border:0;border-radius:9px;padding:10px 13px;font-weight:bold;font-size:13px;text-decoration:none;cursor:pointer}
        #novelia-update-banner a{background:#d8ad4c;color:#241a08}
        #novelia-update-banner button{background:#382b56;color:#fff}
        #novelia-update-banner .novelia-update-close{position:absolute;right:10px;top:9px;padding:5px 9px;background:transparent;color:#fff;font-size:20px}
      `;
      document.head.appendChild(style);

      const banner = document.createElement("section");
      banner.id = "novelia-update-banner";
      banner.setAttribute("role", "dialog");
      banner.setAttribute("aria-label", "Mise à jour de Novelia disponible");
      const notes = Array.isArray(update.releaseNotes) ? update.releaseNotes.slice(0, 3).join(" · ") : "";
      banner.innerHTML = `
        <button class="novelia-update-close" type="button" aria-label="Fermer">×</button>
        <h3>Une nouvelle version de Novelia est disponible</h3>
        <p>Version ${String(update.versionName || latestCode)}.${notes ? " " + notes : ""}</p>
        <div class="novelia-update-actions">
          <a href="${String(update.downloadUrl).replace(/"/g, "%22")}" rel="noopener">Télécharger la mise à jour</a>
          <button type="button" class="novelia-update-later">Plus tard</button>
        </div>`;
      document.body.appendChild(banner);
      banner.querySelector(".novelia-update-close").addEventListener("click", () => banner.remove());
      banner.querySelector(".novelia-update-later").addEventListener("click", () => banner.remove());
    })
    .catch(error => console.info("Novelia : vérification des mises à jour ignorée.", error));
})();
