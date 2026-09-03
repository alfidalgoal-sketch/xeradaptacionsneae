export async function onRequestPost(context) {
  const corsHeaders = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };

  try {
    const { env, request } = context;
    const apiKey = env.GEMINI_API_KEY || env["GEMINI-API-KEY"];

    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "Falta a variable GEMINI_API_KEY no panel de Cloudflare Pages." }),
        { status: 500, headers: corsHeaders }
      );
    }

    let body;
    try {
      body = await request.json();
    } catch (e) {
      return new Response(
        JSON.stringify({ error: "O corpo da petición JSON é inválido." }),
        { status: 400, headers: corsHeaders }
      );
    }

    const geminiEndpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;

    const googleResponse = await fetch(geminiEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: body.prompt }] }]
      }),
    });

    const data = await googleResponse.json();

    if (data.error) {
      return new Response(
        JSON.stringify({ error: `Erro na API de Gemini: ${data.error.message}` }),
        { status: googleResponse.status || 500, headers: corsHeaders }
      );
    }

    const outputText = data.candidates?.[0]?.content?.parts?.[0]?.text || "Non se puido xerar contido.";

    return new Response(
      JSON.stringify({ text: outputText }),
      { status: 200, headers: corsHeaders }
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ error: `Erro no servidor: ${err.message}` }),
      { status: 502, headers: corsHeaders }
    );
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}
