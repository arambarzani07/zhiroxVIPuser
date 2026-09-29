Deno.serve((_req: Request) =>
  new Response(
    JSON.stringify({
      error: "disabled",
      message: "Legacy Netlify deployment helper is retired.",
    }),
    {
      status: 410,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
      },
    },
  )
);
