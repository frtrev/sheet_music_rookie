# Website browser QA

Local static server: http://127.0.0.1:8780/sheet-music-rookie/

Executed through the Codex in-app browser:
- Product page rendered using the existing shared NeoTheOne CSS and icon.
- Mobile viewport 390×844: title/content wrapped inside the document card; DOM scroll width 375, viewport width 390 (no horizontal overflow); no broken images.
- Desktop viewport 1440×900: DOM scroll width 1425, viewport width 1440 (no horizontal overflow).
- Privacy and Support navigation opened the correct dedicated pages, with publisher/contact information matching the existing website.
- Temporary viewport override reset after inspection.

The final screenshot gallery is populated after successful Android capture. Local link checking is rerun after packaging. No production deployment or live HTTPS verification is claimed.

After adding the final screenshot gallery, the mobile 390×844 check was repeated: all four images (icon plus three app captures) loaded, gallery images measured 213px wide, and document width remained 375px with a 390px viewport. No horizontal overflow was introduced by the gallery. The actual website checkout also passes all 244 local links across 20 HTML files.
