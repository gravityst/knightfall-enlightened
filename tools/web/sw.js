// Knightfall's service worker: keeps the game's files in the browser's own storage, so a second
// visit starts without downloading anything. Every file it keeps is named by its content
// (tools/web/finalize.py fills in FILES), so a kept file can never be out of date; the page itself
// always comes from the network, so a new version is picked up straight away.
const FILES = [];
const CACHE = 'knightfall-files';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		const cache = await caches.open(CACHE);
		for (const req of await cache.keys()) {
			if (!FILES.includes(new URL(req.url).pathname.split('/').pop())) {
				await cache.delete(req);          // left over from an older version
			}
		}
		await self.clients.claim();
	})());
});

self.addEventListener('fetch', (event) => {
	const req = event.request;
	if (req.method !== 'GET') {
		return;
	}
	const url = new URL(req.url);
	if (url.origin !== self.location.origin || !FILES.includes(url.pathname.split('/').pop())) {
		return;
	}
	event.respondWith((async () => {
		const cache = await caches.open(CACHE);
		const key = url.origin + url.pathname;
		const hit = await cache.match(key);
		if (hit) {
			return hit;
		}
		const res = await fetch(req);
		if (res.status === 200) {
			event.waitUntil(cache.put(key, res.clone()).catch(() => {}));
		}
		return res;
	})());
});
