# Natural Earth map source

`countries.json` is generated from Natural Earth vector release v5.1.2,
specifically the 1:110m Admin 0 Countries with boundary lakes dataset. The
pinned source URL and SHA-256 checksum live in
`scripts/build-map-data.mjs`.

Natural Earth map data is public domain. Its terms permit modification and
redistribution without required attribution:
<https://www.naturalearthdata.com/about/terms-of-use/>.

Regenerate and verify the derived map data with:

```bash
node scripts/build-map-data.mjs
node scripts/build-map-data.mjs --check
```
