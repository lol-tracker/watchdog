async function g(r) {
  r.rcp.preInit("rcp-fe-common-libs", async (i) => {
    window.__RCP_COMMON_PROVIDER = i, await PluginFS.mkdir("output/");
    let s = await (await fetch("/plugin-manager/v2/plugins")).json(), n = [];
    for (let u of s) {
      let l = u.fullName;
      l.startsWith("rcp-fe-") && n.push(new Promise((a, o) => {
        let e = l.replace(/^rcp-fe-/, "");
        console.log(`Dumping ${e}...`), fetch(`/fe/${e}/${l}.js`).then((t) => {
          if (!t.ok) {
            console.error(`Error fetching ${e}!`), console.error(`${t.status}: ${t.statusText}`), o(null);
            return;
          }
          t.text().then((c) => {
            console.log(`Saving ${e}...`), PluginFS.write(`output/${e}.js`, c, !1).then((f) => {
              if (f != !0) {
                console.error(`Error saving ${e}!`), o(null);
                return;
              }
              console.log(`Successfully dumped and saved ${e}!`), a(null);
            });
          });
        });
      }));
    }
    Promise.allSettled(n).then(() => {
      PluginFS.write("status", "1", !1);
    });
  });
}
export {
  g as init
};
