import { createClient } from "npm:@supabase/supabase-js@2.109.0";
import { CinetPayClient, parseNotification, verifyNotification } from "npm:cinetpay-js@0.1.0";

const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const apiKey = Deno.env.get("CINETPAY_API_KEY_TG");
    const apiPassword = Deno.env.get("CINETPAY_API_PASSWORD_TG");
    if (!serviceKey || !apiKey || !apiPassword) return response({ error: "Webhook not configured" }, 503);

    const notification = parseNotification(await req.text());
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: purchase, error } = await admin
      .from("novelia_chapter_purchases")
      .select("id,client_transaction_id,provider_transaction_id,notify_token,status,gross_amount_xof,author_share_bps,provider_fee_bps,payment_method")
      .eq("client_transaction_id", notification.merchantTransactionId)
      .maybeSingle();

    if (error || !purchase || !purchase.notify_token ||
        !verifyNotification(purchase.notify_token, notification.notifyToken)) {
      return response({ error: "Invalid notification" }, 401);
    }
    if (purchase.status === "paid" || purchase.status === "refunded") {
      return response({ ok: true, duplicate: true });
    }
    if (purchase.status !== "pending") return response({ ok: true, ignored: true });

    const client = new CinetPayClient({ credentials: { TG: { apiKey, apiPassword } } });
    const status = await client.payment.getStatus(notification.transactionId, "TG");
    if (status.merchantTransactionId !== purchase.client_transaction_id ||
        status.transactionId !== notification.transactionId) {
      return response({ error: "Transaction mismatch" }, 400);
    }
    if (status.status === "PENDING" || status.status === "INITIATED") {
      return response({ ok: true, pending: true });
    }
    if (status.status !== "SUCCESS") {
      await admin.from("novelia_chapter_purchases")
        .update({ status: "failed" })
        .eq("id", purchase.id)
        .eq("status", "pending");
      return response({ ok: true, failed: true });
    }

    const gross = Number(purchase.gross_amount_xof);
    const providerFee = Math.ceil(gross * Number(purchase.provider_fee_bps) / 10000);
    const net = gross - providerFee;
    const platformFee = Math.floor(net * (10000 - Number(purchase.author_share_bps)) / 10000);
    const authorEarning = net - platformFee;

    const { error: updateError } = await admin.from("novelia_chapter_purchases")
      .update({
        status: "paid",
        provider_transaction_id: notification.transactionId,
        provider_fee_xof: providerFee,
        platform_fee_xof: platformFee,
        author_earning_xof: authorEarning,
        paid_at: new Date().toISOString(),
      })
      .eq("id", purchase.id)
      .eq("status", "pending");
    if (updateError) return response({ error: "Unable to finalize purchase" }, 500);
    return response({ ok: true, paid: true });
  } catch {
    return response({ error: "Invalid or unverifiable CinetPay notification" }, 400);
  }
});