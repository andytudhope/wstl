import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { setTimeout } from 'node:timers/promises';
import { Contract, JsonRpcProvider } from 'ethers';
import { artifact, IDS, fail } from './common.mjs';

// Run the actual Solidity renderer in a temporary local EVM. No key or mainnet RPC.
const server = createServer();
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
await new Promise(resolve => server.close(resolve));
const url = `http://127.0.0.1:${port}`;
const anvil = spawn('anvil', ['--host', '127.0.0.1', '--port', String(port), '--silent'], { stdio: 'ignore' });
let startupError;
anvil.on('error', error => { startupError = error; });
let rpc;
try {
  for (let attempt = 0; ; ++attempt) {
    try {
      await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_chainId', params: [] }) });
      break;
    } catch {
      if (startupError || attempt === 100) throw new Error('Cannot start Anvil; install Foundry first');
      await setTimeout(50);
    }
  }
  rpc = new JsonRpcProvider(url, undefined, { batchMaxCount: 1 });
  const compiled = artifact();
  const address = '0x0000000000000000000000000000000000001000';
  await rpc.send('anvil_setCode', [address, compiled.deployedBytecode.object]);
  const renderer = new Contract(address, compiled.abi, rpc);
  mkdirSync('artwork', { recursive: true });
  const images = new Set();
  for (const id of IDS) {
    const svg = await renderer.artwork(id);
    const background = svg.replace(/<title>.*?<\/title>/, '');
    if (images.has(background)) throw new Error(`Duplicate artwork #${id}`);
    images.add(background);
    writeFileSync(`artwork/${id}.svg`, svg + '\n');
  }
  const decode = uri => Buffer.from(uri.slice(uri.indexOf(',') + 1), 'base64').toString();
  const collection = JSON.parse(decode(await renderer.contractURI()));
  writeFileSync('artwork/collection.json', JSON.stringify(collection, null, 2) + '\n');
  writeFileSync('artwork/collection.svg', decode(collection.image) + '\n');
  writeFileSync('artwork/banner.svg', decode(collection.banner_image) + '\n');
  writeFileSync('artwork/index.html', `<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Status Lovers (Still) — 50 hearts</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#09101c;color:#fff;font:14px system-ui,sans-serif}
main{max-width:1600px;margin:auto;padding:64px 32px}header{margin-bottom:40px}
h1{font-size:40px;letter-spacing:-1.5px;margin:0 0 10px}p{opacity:.6;margin:0;line-height:1.6}
section{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:24px 16px}
figure{margin:0}img{display:block;width:100%;height:auto;aspect-ratio:1}figcaption{padding-top:10px;opacity:.65}
a{color:inherit;text-decoration:none}@media(max-width:900px){section{grid-template-columns:repeat(3,1fr)}}
@media(max-width:540px){main{padding:32px 16px}section{grid-template-columns:repeat(2,1fr)}}
</style><main><header><h1>Status Lovers (Still)</h1>
<p>50 hearts · December 2017 originals · New generative artwork<br>
Official Status heart and palette. Each background is seeded by its token ID.</p></header>
<p style="margin-bottom:24px"><a href="collection.json">Collection metadata</a> · <a href="banner.svg">Banner</a></p>
<section>${IDS.map(id => `<figure><a href="${id}.svg"><img src="${id}.svg" alt="Status Lovers #${id}" width="3000" height="3000"></a><figcaption>#${String(id).padStart(2, '0')}</figcaption></figure>`).join('\n')}</section></main></html>\n`);
  console.log('Generated 50 SVGs at artwork/0.svg … artwork/49.svg. Open artwork/index.html.');
} catch (error) { fail(error); }
finally { await rpc?.destroy(); anvil.kill(); }
