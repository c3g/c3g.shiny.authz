"""Stand-in for oauth2-proxy in tests/e2e/shiny-browser.R.

Forwards HTTP and WebSocket traffic to a Shiny app and, like oauth2-proxy, sets
X-Forwarded-Groups on every request from the browser's session cookie (here, a plain
`e2e_groups` cookie instead of a signed session). A client-supplied X-Forwarded-Groups is
always dropped, as a real proxy must.

Usage: python groups_proxy.py <listen-port> <upstream-url>
"""

import asyncio
import sys

import aiohttp
from aiohttp import web

HOP_BY_HOP = {"connection", "keep-alive", "upgrade", "transfer-encoding", "host",
              "content-length", "sec-websocket-key", "sec-websocket-version",
              "sec-websocket-extensions", "sec-websocket-accept"}


def upstream_headers(request: web.Request) -> dict:
    headers = {k: v for k, v in request.headers.items()
               if k.lower() not in HOP_BY_HOP and k.lower() != "x-forwarded-groups"}
    groups = request.cookies.get("e2e_groups")
    if groups:
        headers["X-Forwarded-Groups"] = groups
    return headers


async def handle(request: web.Request) -> web.StreamResponse:
    upstream = request.app["upstream"]
    session: aiohttp.ClientSession = request.app["session"]
    url = upstream + request.rel_url.path_qs

    if request.headers.get("upgrade", "").lower() == "websocket":
        ws_client = web.WebSocketResponse()
        await ws_client.prepare(request)
        async with session.ws_connect(url, headers=upstream_headers(request)) as ws_upstream:
            async def pump(src, dst):
                async for msg in src:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        await dst.send_str(msg.data)
                    elif msg.type == aiohttp.WSMsgType.BINARY:
                        await dst.send_bytes(msg.data)
                    else:
                        break
                await dst.close()
            await asyncio.gather(pump(ws_client, ws_upstream), pump(ws_upstream, ws_client))
        return ws_client

    async with session.request(request.method, url, headers=upstream_headers(request),
                               data=await request.read(), allow_redirects=False) as resp:
        body = await resp.read()
        headers = {k: v for k, v in resp.headers.items() if k.lower() not in HOP_BY_HOP
                   and k.lower() != "content-encoding"}
        return web.Response(status=resp.status, headers=headers, body=body)


async def main(port: int, upstream: str) -> None:
    app = web.Application()
    app["upstream"] = upstream.rstrip("/")
    app["session"] = aiohttp.ClientSession(auto_decompress=True)
    app.router.add_route("*", "/{tail:.*}", handle)
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, "127.0.0.1", port).start()
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1]), sys.argv[2]))
