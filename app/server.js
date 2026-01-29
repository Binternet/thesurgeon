const http = require('http');

const PORT = process.env.PORT || 8080;
const VERSION = process.env.VERSION || 'dev-local';

const PHRASES = ['I Love Sabich', 'Kama Lasim Bapita?', 'Ein al falafel', 'And Also Tchina!'];

function randomPhrase() {
  return PHRASES[Math.floor(Math.random() * PHRASES.length)];
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (url.pathname === '/version' || url.pathname === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      message: randomPhrase(),
      version: VERSION,
    }));
    return;
  }

  if (url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', message: randomPhrase(), version: VERSION }));
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found\n');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`hcomp-app listening on :${PORT}, version=${VERSION}`);
});
