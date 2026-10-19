# Brand assets

The supplied square Taste & See badge is stored here as **`logo.png`**.

It is referenced by:
- `../index.html` — header, hero medallion, footer, favicon, social preview
- `../admin.html` — header, favicon
- `../baker.html` — header, favicon
- `../../README.md` — project logo

Until the file exists, each spot gracefully falls back to an emoji.

## Menu photos

The menu cards look for one photo per flavour here:

- `classic.jpg` — Classic
- `tiramisu.jpg` — Tiramisu
- `biscoff.jpg` — Biscoff
- `oreo.jpg` — Oreo

`.png`, `.webp`, and `.jpeg` are also tried automatically if the `.jpg` file is missing. When none of them exist, the card keeps its emoji artwork.
