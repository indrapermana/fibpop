import { Hono } from 'hono';

const app = new Hono();

app.get('/api/health', (context) =>
  context.json({
    status: 'ok',
    rulesVersion: '2.1.0',
    catalogVersion: '1.0.0',
    protocolVersion: 2,
  }),
);

export default app;
