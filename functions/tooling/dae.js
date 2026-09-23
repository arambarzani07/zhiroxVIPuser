export async function onRequestGet() {
  const url = "https://github.com/ejfkdev/dae/releases/download/v0.1.2/dae-Linux-x64";
  const r = await fetch(url, {
    headers: {
      "User-Agent": "Zhirox-Temporary-Tooling/1.0",
      "Accept": "application/octet-stream"
    },
    redirect: "follow"
  });
  if (!r.ok) {
    return new Response("upstream download failed", { status: 502 });
  }
  const h = new Headers();
  h.set("content-type", "application/octet-stream");
  h.set("content-disposition", "attachment; filename=dae-Linux-x64");
  h.set("cache-control", "no-store");
  return new Response(r.body, { status: 200, headers: h });
}
