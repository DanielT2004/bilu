import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const page = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Bilu Support</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #f7f4ef; color: #1e1b18; }
    main { max-width: 680px; margin: 0 auto; padding: 64px 24px; }
    h1 { font-size: 42px; margin: 0 0 12px; }
    h2 { margin-top: 36px; }
    p, li { font-size: 18px; line-height: 1.6; }
    a { color: #9b3f24; }
    .card { background: #fff; border-radius: 20px; padding: 24px; box-shadow: 0 8px 30px #0000000d; }
    @media (prefers-color-scheme: dark) {
      body { background: #161412; color: #f7f1e8; }
      .card { background: #24211e; }
      a { color: #ff9b78; }
    }
  </style>
</head>
<body>
  <main>
    <h1>Bilu Support</h1>
    <p>Need help with Bilu? We are happy to help.</p>
    <div class="card">
      <h2>Contact</h2>
      <p>Email <a href="mailto:susakesimon@gmail.com">susakesimon@gmail.com</a>. Include your iPhone model, iOS version, and a short description of what happened. Please do not send sensitive personal information.</p>
      <h2>Common help</h2>
      <ul>
        <li>If nearby results are incorrect, check Bilu's Location permission in iOS Settings or enter an area manually.</li>
        <li>If a search cannot connect, check your internet connection and try again after a moment.</li>
        <li>You can remove saved places and vibes from inside Bilu.</li>
      </ul>
      <h2>Privacy and data requests</h2>
      <p>To request deletion of server-side data associated with your Bilu installation, email us with the subject “Bilu Data Request.” See the <a href="https://yysxjtexwlnvoptxcxlp.supabase.co/functions/v1/privacy-policy">Bilu Privacy Policy</a> for details.</p>
    </div>
  </main>
</body>
</html>`;

serve((request: Request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: { "Allow": "GET, HEAD" },
    });
  }

  return new Response(request.method === "HEAD" ? null : page, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });
});
