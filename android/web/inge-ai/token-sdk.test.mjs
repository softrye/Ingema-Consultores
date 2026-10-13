import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GoogleGenAI } from '@google/genai';
test('official SDK converts locked Live credentials to the actual Google wire schema', async () => {
  let sent;
  const client = new GoogleGenAI({apiKey:'test-only-key', httpOptions:{apiVersion:'v1beta',
    fetch:async (url, init) => { sent = {url:String(url), body:JSON.parse(init.body)}; return Response.json({name:'auth_tokens/test'}); },
  }});
  const token = await client.authTokens.create({config:{uses:1,
    expireTime: new Date(Date.now()+600000).toISOString(),
    newSessionExpireTime:new Date(Date.now()+60000).toISOString(),
    liveConnectConstraints:{model:'gemini-3.8-live', config:{responseModalities:['AUDIO'], inputAudioTranscription:{}, outputAudioTranscription:{}, systemInstruction:{parts:[{text:'InGe+ IA'}]}}},
  }});
  assert.equal(token.name, 'auth_tokens/test'); assert.match(sent.url,/v1beta\/auth_tokens/);
  assert.equal(sent.body.uses, 1);
  assert.equal(sent.body.bidiGenerateContentSetup.model,'models/gemini-3.8-live');
  assert.deepEqual(sent.body.bidiGenerateContentSetup.generationConfig.responseModalities,['AUDIO']);
  // No field mask is the SDK's default: the entire setup is locked.
  assert.equal(sent.body.fieldMask, undefined);
  assert.equal(sent.body.bidiGenerateContentSetup.systemInstruction.parts[0].text, 'InGe+ IA');
});
