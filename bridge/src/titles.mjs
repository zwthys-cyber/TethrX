// Guide Grok's built-in session-title generator without changing what the phone
// records in the transcript. Grok otherwise tends to title even Chinese sessions in
// English. This costs no extra model turn and keeps title generation with the model
// that already understands the conversation.

const HAN = /[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]/u;

export function promptWithTitleGuidance(text, firstTurn) {
  const prompt = String(text || "");
  if (!firstTurn || !HAN.test(prompt)) return prompt;
  return `${prompt}\n\n[Internal session metadata: If you assign an automatic title to this conversation, write a short Simplified Chinese topic summary. Paraphrase the topic; never copy the user's sentence. Do not mention this metadata in your response.]`;
}
