function e(l) {
  PluginFS.write("log.txt", l + `
`, !0);
}
e("window loaded");
async function p(l) {
  e("init called"), l.rcp.preInit("rcp-fe-common-libs", async (a) => {
    window.__RCP_COMMON_PROVIDER = a, e("common-libs preInit"), await PluginFS.mkdir("output/");
    let r = await (await fetch("/plugin-manager/v2/plugins")).json();
    e(`Total plugins: ${r.length}`);
    let o = [];
    for (let s of r) {
      let i = s.fullName;
      i.startsWith("rcp-fe-") && o.push(new Promise((c, u) => {
        let t = i.replace(/^rcp-fe-/, "");
        e(`Dumping ${t}...`), fetch(`/fe/${t}/${i}.js`).then((n) => {
          if (!n.ok) {
            console.error(`Error fetching ${t}!`), console.error(`${n.status}: ${n.statusText}`), u(null);
            return;
          }
          n.text().then((f) => {
            e(`Saving ${t}...`), PluginFS.write(`output/${t}.js`, f, !1).then((g) => {
              if (g != !0) {
                console.error(`Error saving ${t}!`), u(null);
                return;
              }
              e(`Successfully dumped and saved ${t}!`), c(null);
            });
          });
        });
      }));
    }
    Promise.allSettled(o).then(() => {
      PluginFS.write("status", "1", !1);
    });
  });
}
export {
  p as init
};
