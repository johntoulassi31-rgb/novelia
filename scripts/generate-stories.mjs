// Génère une page HTML indexable par histoire publiée + met à jour sitemap.xml.
// Usage : node scripts/generate-stories.mjs   (Node 18+)
// Test hors-ligne : node scripts/generate-stories.mjs --input mock.json
import { readFile, writeFile, mkdir, readdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const BASE = "https://johntoulassi31-rgb.github.io/novelia/";
const SUPABASE_URL = "https://czwaokqpqgrghxeeyguq.supabase.co";
const SUPABASE_KEY = "sb_publishable_ORoXM7DSfxdLF0jz8JRqqA_SISXCNsg"; // clé publique (déjà dans le site)
const OUT_DIR = path.join(ROOT, "histoire");
const STATIC_PAGES = [
  ["", 1.0],
  ["discovery.html", 0.8],
  ["authors.html", 0.7],
  ["novelia-plus.html", 0.6],
];

const esc = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const clip = (s, n) => {
  const t = String(s ?? "").replace(/\s+/g, " ").trim();
  return t.length > n ? t.slice(0, n - 1).trimEnd() + "…" : t;
};
const safeUrl = (u) => (/^https?:\/\//i.test(u || "") ? u : "");

async function rest(table, query) {
  const rows = [];
  for (let from = 0; ; from += 1000) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, {
      headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, Range: `${from}-${from + 999}` },
    });
    if (!res.ok) throw new Error(`${table}: HTTP ${res.status} ${await res.text()}`);
    const page = await res.json();
    rows.push(...page);
    if (page.length < 1000) break;
  }
  return rows;
}

async function loadData() {
  const i = process.argv.indexOf("--input");
  if (i > -1) return JSON.parse(await readFile(process.argv[i + 1], "utf8"));

  const stories = await rest(
    "stories",
    "select=id,title,description,cover_url,story_type,genre,created_at,author_id&status=eq.published&moderation_hidden=eq.false&order=created_at.desc"
  );
  let withChapters = null;
  try {
    const ch = await rest("chapters", "select=story_id&moderation_hidden=eq.false");
    withChapters = new Set(ch.map((c) => String(c.story_id)));
  } catch (e) {
    console.warn("Chapitres illisibles, toutes les histoires publiées sont gardées :", e.message);
  }
  const profiles = await rest("profiles", "select=id,username,display_name");
  return { stories, chapters: withChapters && [...withChapters], profiles };
}

function page(s, author) {
  const type = s.story_type === "webtoon" ? "Webtoon" : "Roman";
  const url = `${BASE}histoire/${encodeURIComponent(s.id)}.html`;
  const read = `${BASE}reader.html?db_story=${encodeURIComponent(s.id)}`;
  const desc = clip(s.description, 155) || `${type} publié sur Novelia.`;
  const cover = safeUrl(s.cover_url);
  const title = `${s.title} – ${type} de ${author} | Novelia`;
  const ld = {
    "@context": "https://schema.org",
    "@type": "CreativeWork",
    name: s.title,
    description: clip(s.description, 300),
    author: { "@type": "Person", name: author },
    genre: s.genre || undefined,
    datePublished: s.created_at ? String(s.created_at).slice(0, 10) : undefined,
    image: cover || undefined,
    url,
    inLanguage: "fr",
  };
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta name="robots" content="index,follow,max-image-preview:large">
<link rel="canonical" href="${esc(url)}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Novelia">
<meta property="og:title" content="${esc(s.title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(url)}">
${cover ? `<meta property="og:image" content="${esc(cover)}">\n` : ""}<script type="application/ld+json">${JSON.stringify(ld).replace(/</g, "\\u003c")}</script>
<style>
body{margin:0;background:#100d19;color:#f8f5ff;font-family:Arial,sans-serif;line-height:1.6}
header{padding:20px;background:#191324;border-bottom:1px solid #39284c}
header a{color:#f8f5ff;text-decoration:none;font-weight:bold;font-size:20px}
main{max-width:760px;margin:0 auto;padding:24px 16px;display:flex;gap:24px;flex-wrap:wrap}
img{width:220px;max-width:100%;border-radius:12px;object-fit:cover;aspect-ratio:2/3;background:#191324}
.info{flex:1;min-width:240px}
h1{margin:0 0 8px}
.meta{color:#bca9d6;font-size:14px;margin-bottom:16px}
.btn{display:inline-block;margin-top:12px;background:#7957a0;color:#fff;padding:12px 20px;border-radius:10px;text-decoration:none;font-weight:bold}
p{white-space:pre-line}
</style>
</head>
<body>
<header><a href="${BASE}">Novelia</a></header>
<main>
${cover ? `<img src="${esc(cover)}" alt="Couverture de ${esc(s.title)}" loading="eager">\n` : ""}<div class="info">
<h1>${esc(s.title)}</h1>
<div class="meta">${esc(type)} · par ${esc(author)}${s.genre ? " · " + esc(s.genre) : ""}</div>
<p>${esc(s.description || "")}</p>
<a class="btn" href="${esc(read)}">Lire sur Novelia</a>
</div>
</main>
</body>
</html>
`;
}

async function main() {
  const data = await loadData();
  const names = new Map(data.profiles.map((p) => [String(p.id), p.display_name || p.username || "Auteur Novelia"]));
  const ok = data.chapters ? new Set(data.chapters.map(String)) : null;
  const stories = data.stories.filter((s) => s.id && s.title && (!ok || ok.has(String(s.id))));

  await mkdir(OUT_DIR, { recursive: true });
  const wanted = new Set();
  for (const s of stories) {
    const file = `${s.id}.html`;
    wanted.add(file);
    await writeFile(path.join(OUT_DIR, file), page(s, names.get(String(s.author_id)) || "Auteur Novelia"));
  }
  for (const f of await readdir(OUT_DIR)) {
    if (f.endsWith(".html") && !wanted.has(f)) await rm(path.join(OUT_DIR, f));
  }

  const today = new Date().toISOString().slice(0, 10);
  let xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n`;
  for (const [p, pr] of STATIC_PAGES)
    xml += `  <url><loc>${BASE}${p}</loc><lastmod>${today}</lastmod><priority>${pr.toFixed(1)}</priority></url>\n`;
  for (const s of stories) {
    const last = String(s.created_at || today).slice(0, 10);
    xml += `  <url><loc>${BASE}histoire/${encodeURIComponent(s.id)}.html</loc><lastmod>${last}</lastmod><priority>0.5</priority></url>\n`;
  }
  xml += `</urlset>\n`;
  await writeFile(path.join(ROOT, "sitemap.xml"), xml);
  console.log(`${stories.length} page(s) histoire générée(s), sitemap mis à jour.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
