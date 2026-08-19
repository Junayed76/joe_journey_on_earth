import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const bodyText = await req.text();
    console.log('RAW BODY:', bodyText);

    if (!bodyText) {
      throw new Error('Empty request body received');
    }

    const { user_id } = JSON.parse(bodyText);

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const { data: history, error: historyError } = await supabase
      .from('messages')
      .select('sender, content')
      .eq('user_id', user_id)
      .order('created_at', { ascending: false })
      .limit(15);

    if (historyError) throw historyError;

    const orderedHistory = (history ?? []).reverse();

    const geminiContents = orderedHistory.map((m) => ({
      role: m.sender === 'user' ? 'user' : 'model',
      parts: [{ text: m.content }],
    }));

    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${Deno.env.get('GEMINI_API_KEY')}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{
              text: "You are JOE, a warm, casual friend chatting with the user in the evening. Ask about their day naturally, like a close friend catching up — not like an assistant. Keep replies short (1-3 sentences), conversational, and curious. Never sound robotic or use bullet points.",
            }],
          },
          contents: geminiContents,
        }),
      }
    );

    const geminiData = await geminiRes.json();
    console.log('GEMINI RAW RESPONSE:', JSON.stringify(geminiData));

    const aiReply =
      geminiData.candidates?.[0]?.content?.parts?.[0]?.text ??
      "Sorry, having trouble replying right now.";

    await supabase.from('messages').insert({
      user_id,
      sender: 'ai',
      content: aiReply,
    });

    return new Response(JSON.stringify({ reply: aiReply }), {
      headers: { ...corsHeaders, 'content-type': 'application/json' },
    });
  } catch (err) {
    console.log('FUNCTION ERROR:', err.message);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, 'content-type': 'application/json' },
    });
  }
});