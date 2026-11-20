import { createClient } from "npm:@supabase/supabase-js@2.109.0";
import { CinetPayClient } from "npm:cinetpay-js@0.1.0";

const cors = {
  "Access-Control-Allow-Origin": "https://johntoulassi31-rgb.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const apiKey = Deno.env.get("CINETPAY_API_KEY_TG");
    const apiPassword = Deno.env.get("CINETPAY_API_PASSWORD_TG");
    if (!publicKey || !serviceKey || !apiKey || !apiPassword) {
      return json({ error: "Le paiement en ligne n’est pas encore configuré." }, 503);
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);

    const userClient = createClient(supabaseUrl, publicKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    const user = userData.user;
    if (userError || !user) return json({ error: "Session invalide. Reconnecte-toi." }, 401);

    const body = await req.json();
    const chapterId = String(body.chapter_id ?? "");
    const firstName = String(body.first_name ?? "").trim();
    const lastName = String(body.last_name ?? "").trim();
    const phone = String(body.phone_number ?? "").trim();
    const method = String(body.payment_method ?? "");
    if (!chapterId || firstName.length < 2 || lastName.length < 2 ||
        !/^\+228[0-9]{8}$/.test(phone) || !["MOOV_TG", "TMONEY_TG"].includes(method)) {
      return json({ error: "Informations de paiement invalides." }, 400);
    }
    if (!user.email) return json({ error: "Une adresse e-mail vérifiée est nécessaire." }, 400);

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: chapter, error: chapterError } = await admin
      .from("chapters")
      .select("id,story_id,title,price_xof,is_premium,moderation_hidden,stories!inner(author_id,title,status,moderation_hidden)")
      .eq("id", chapterId)
      .single();
    if (chapterError || !chapter || !chapter.is_premium || chapter.moderation_hidden ||
        chapter.stories?.status !== "published" || chapter.stories?.moderation_hidden ||
        chapter.stories?.author_id === user.id || !chapter.price_xof) {
      return json({ error: "Ce chapitre n’est pas disponible à l’achat." }, 404);
    }

    const { data: existing } = await admin
      .from("novelia_chapter_purchases")
      .select("id,status,checkout_url")
      .eq("buyer_id", user.id)
      .eq("chapter_id", chapter.id)
      .in("status", ["pending", "paid"])
      .maybeSingle();
    if (existing?.status === "paid") return json({ error: "Tu possèdes déjà ce chapitre." }, 409);
    if (existing?.status === "pending") {
      if (existing.checkout_url) return json({ purchase_id: existing.id, payment_url: existing.checkout_url, resumed: true });
      return json({ error: "Un paiement pour ce chapitre est déjà en préparation. Réessaie dans quelques instants." }, 409);
    }

    const merchantTransactionId = "NV" + crypto.randomUUID().replaceAll("-", "").slice(0, 22);
    const { data: purchase, error: purchaseError } = await admin
      .from("novelia_chapter_purchases")
      .insert({
        buyer_id: user.id,
        author_id: chapter.stories.author_id,
        story_id: chapter.story_id,
        chapter_id: chapter.id,
        payment_provider: "cinetpay",
        payment_method: method,
        client_transaction_id: merchantTransactionId,
        gross_amount_xof: chapter.price_xof,
        status: "pending",
      })
      .select("id,gross_amount_xof")
      .single();
    if (purchaseError || !purchase) {
      return json({ error: purchaseError?.message ?? "Impossible de créer le paiement." }, 400);
    }

    try {
      const client = new CinetPayClient({
        credentials: { TG: { apiKey, apiPassword } },
      });
      const base = "https://johntoulassi31-rgb.github.io/novelia";
      const payment = await client.payment.initialize({
        currency: "XOF",
        merchantTransactionId,
        amount: Number(purchase.gross_amount_xof),
        lang: "fr",
        designation: ("Novelia - " + chapter.stories.title + " - " + chapter.title).slice(0, 120),
        clientEmail: user.email,
        clientFirstName: firstName,
        clientLastName: lastName,
        clientPhoneNumber: phone,
        successUrl: base + "/payment-result.html?purchase=" + purchase.id,
        failedUrl: base + "/payment-result.html?purchase=" + purchase.id + "&failed=1",
        notifyUrl: supabaseUrl + "/functions/v1/cinetpay-webhook",
        channel: "PUSH",
        paymentMethod: method as 'MOOV_TG' | 'TMONEY_TG',
      }, "TG");

      const { error: updateError } = await admin
        .from("novelia_chapter_purchases")
        .update({
          notify_token: payment.notifyToken,
          provider_transaction_id: payment.transactionId,
          checkout_url: payment.paymentUrl,
        })
        .eq("id", purchase.id)
        .eq("status", "pending");
      if (updateError) throw updateError;

      return json({ purchase_id: purchase.id, payment_url: payment.paymentUrl });
    } catch (paymentError) {
      await admin.from("novelia_chapter_purchases")
        .update({ status: "failed" }).eq("id", purchase.id).eq("status", "pending");
      throw paymentError;
    }
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Erreur de paiement." }, 500);
  }
});