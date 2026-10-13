import { createHandler } from './handler.mjs';
import { GoogleGenAI } from 'npm:@google/genai@2.27.0';
Deno.serve(createHandler({ env: (name: string) => Deno.env.get(name),
  issueToken: async (config: any, apiKey: string) => {
    try {
      const client = new GoogleGenAI({ apiKey, httpOptions: { apiVersion: 'v1beta', timeout: 30000 } });
      const token = await client.authTokens.create({ config });
      return Response.json({ name: token.name });
    } catch (failure) {
      const status = Number((failure as { status?: number }).status);
      // Same shape as Google's error body: handler.providerFailure() keeps only a
      // sanitized, truncated summary (never the API key or the request).
      const message = String((failure as { message?: string }).message ?? '').slice(0, 400);
      return Response.json({ error: { status: (failure as { name?: string }).name ?? 'Error', message } },
        { status: status >= 400 && status < 600 ? status : 502 });
    }
  },
}));
