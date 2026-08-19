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
    const { user_id } = JSON.parse(await req.text());

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // আজকের সব message আনো
    const today = new Date().toISOString().split('T')[0];
    const { data: messages, error: msgError } = await supabase
      .from('messages')
      .select('sender, content')
      .eq('user_id', user_id)
      .gte('created_at', `${today}T00:00:00`)
      .order('created_at', { ascending: true });

    if (msgError) throw msgError;
    if (!messages || messages.length === 0) {
      throw new Error('No messages found for today');
    }

    const conversationText = messages
      .map((m) => `${m.sender === 'user' ? 'User' : 'Friend'}: ${m.content}`)
      .join('\n');

    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${Deno.env.get('GEMINI_API_KEY')}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{
              text: "You are a journal writer. Based on the conversation below between a user and their AI friend, write a short third-person narrative journal entry (3-5 sentences) capturing what happened in the user's day, their mood, and any notable events. Write it like a warm, reflective diary entry — not a summary or transcript. Use the person's actual name if mentioned, otherwise refer to them as 'they'. Do not mention the AI or the chat itself.",
            }],
          },
          contents: [{ role: 'user', parts: [{ text: conversationText }] }],
        }),
      }
    );

    const geminiData = await geminiRes.json();
    console.log('GEMINI JOURNAL RESPONSE:', JSON.stringify(geminiData));

    const journalText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!journalText) throw new Error('Failed to generate journal text');

    const { error: upsertError } = await supabase
      .from('journal_entries')
      .upsert(
        { user_id, entry_date: today, content: journalText },
        { onConflict: 'user_id,entry_date' }
      );

    if (upsertError) throw upsertError;

    return new Response(JSON.stringify({ entry: journalText }), {
      headers: { ...corsHeaders, 'content-type': 'application/json' },
    });
  } catch (err) {
    console.log('JOURNAL FUNCTION ERROR:', err.message);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, 'content-type': 'application/json' },
    });
  }
});