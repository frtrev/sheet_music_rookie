#!/usr/bin/env python3
"""Stage additive website changes against the existing GitHub Pages checkout."""
import argparse, pathlib, shutil, html
p=argparse.ArgumentParser();p.add_argument('--source',type=pathlib.Path,default=pathlib.Path('../frtrev.github.io'));a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=root/'release/website/frtrev.github.io'
# Preserve staging edits: refresh only by explicit rerun against the latest source.
shutil.copytree(a.source,out,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.git','.DS_Store'))
assets=out/'assets/sheet-music-rookie';assets.mkdir(parents=True,exist_ok=True)
shutil.copy2(root/'assets/app_icon/app-store-1024.png',assets/'app-icon.png')
base='/sheet-music-rookie/'
nav=f'<a href="{base}">Overview</a><a href="{base}privacy-policy/">Privacy</a><a href="{base}support/">Support</a>'
def page(path,title,content):
    target=out/path/'index.html';target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} | Sheet Music Rookie | NeoTheOne</title><meta name="description" content="{html.escape(title)} for Sheet Music Rookie, an offline music notation app.">
<link rel="canonical" href="https://frtrev.github.io/{path}/"><link rel="icon" href="/assets/sheet-music-rookie/app-icon.png"><link rel="stylesheet" href="/assets/styles.css"></head>
<body><header><div class="shell nav"><a class="brand" href="/">Neo<span>TheOne</span></a><nav aria-label="Sheet Music Rookie navigation">{nav}</nav></div></header>
<main class="shell"><article class="document"><div class="breadcrumbs"><a href="/">Products</a> / <a href="{base}">Sheet Music Rookie</a></div>{content}</article></main>
<footer><div class="shell"><span>© 2026 Francisco Trevino · NeoTheOne</span><a href="/copyright/">Copyright</a><a href="{base}privacy-policy/">Privacy</a><a href="{base}support/">Support</a></div></footer></body></html>''')
privacy='''<p class="eyebrow">Effective 6 November 2026 · Version 1.0.0</p><h1>Privacy Policy</h1>
<p>Sheet Music Rookie is published by Francisco Trevino under NeoTheOne. The app creates musical notation from microphone input and provides score editing, playback, and practice tools.</p>
<h2>Microphone input</h2><p>Microphone permission is requested when you start a listening feature, such as recording, practice, or a melody test. Audio samples are processed on your device to estimate musical pitches and note durations. Live analysis frames and phrase-review audio buffers are held in memory; the app does not save microphone recordings as audio files or send them to a server. Saved compositions contain derived notes, timing, pitch/confidence information, lyrics you enter, and score settings. Denying microphone permission leaves score editing and saved-score use available.</p>
<h2>Local storage and playback</h2><p>Compositions are saved as compressed MusicXML files in the app’s documents directory. Detection and practice settings are stored in local preferences. Imported scores are copied to temporary local storage. Playback uses the bundled GeneralUser GS SoundFont to generate audio locally; this synthesized playback audio is distinct from microphone recordings.</p>
<h2>Data collection and third parties</h2><p>This version has no account system, advertising, analytics, tracking, or developer-operated upload service. Its Flutter plugins provide recording, playback, preferences, file storage, sharing, and screen-awake functions. No third-party analytics or advertising SDK was identified in the inspected dependencies. The app does not collect personal information for the publisher. User-entered titles or lyrics may contain information you choose to include.</p>
<h2>Sharing, backups, and external services</h2><p>Sharing a saved composition opens the operating system’s share interface. If you select another app or service, it receives that file under its own privacy practices. The operating system or device backup settings may back up local documents and preferences. Copies you export, share, or back up are outside this app’s control.</p>
<h2>Retention and deletion</h2><p>Saved compositions and preferences remain until removed from the device. Use the remove button beside a sheet in Sheets to delete that saved file. Clear app storage in Android Settings, or use Delete App on iOS to remove local app data; iOS Offload App retains documents. Remove exported files and backup copies separately. There is no online account to delete.</p>
<h2>Support communications</h2><p>If you email support, your email provider transmits your address, message, and attachments to the publisher. Send only information you choose to share. You can request deletion of support messages by contacting <a href="mailto:ftrevino@yahoo.com">ftrevino@yahoo.com</a>; legal or security obligations may require retention.</p>
<h2>Children and changes</h2><p>The app can be used to learn music without an account. It does not knowingly collect children’s personal information through the app. This policy will be updated if the app’s practices change.</p>
<h2>Contact</h2><p>For privacy questions, email <a href="mailto:ftrevino@yahoo.com?subject=Sheet%20Music%20Rookie%20Privacy">ftrevino@yahoo.com</a>.</p>'''
page('sheet-music-rookie/privacy-policy','Privacy Policy',privacy)
support='''<h1>Sheet Music Rookie Support</h1><p>Turn a melody into sheet music, then edit, play, and practice it offline.</p>
<h2>Get started</h2><ol><li>Tap Create. Choose Treble, Bass, Alto, or Tenor clef, then an octave range.</li><li>Set tempo, key, and time signature for your melody. Start recording when ready and allow microphone access.</li><li>Sing one clear note at a time in a quiet room. Pause to edit pitches, durations, rests, ties, and lyrics. Detection is an estimate; review the score.</li><li>Save and name your composition. Use Sheets to play, share, or remove saved music. Tap a sheet title to reopen it.</li><li>Open compatible MusicXML or MuseScore files from another app with Sheet Music Rookie.</li></ol>
<h2>Microphone troubleshooting</h2><p>On iOS, check Settings → Privacy &amp; Security → Microphone, or the app’s Settings entry. On Android, check Settings → Apps → Sheet Music Rookie → Permissions → Microphone. Also check the system microphone privacy switch. Close other recording apps, enable access, then return and tap Retry in the Microphone unavailable card below the score controls. Reopen the score or restart if needed. Editing works without microphone permission.</p>
<h2>Frequently asked questions</h2><h3>Does it need internet or an account?</h3><p>Core notation, local saving, playback, and practice work offline with no account.</p><h3>Does it record my voice to a file?</h3><p>No microphone audio file is saved. Notes and timing derived from your performance can be stored in a composition. Phrase analysis temporarily buffers audio in memory.</p><h3>Why is a note or rhythm wrong?</h3><p>Use a quiet room, sing one note at a time, choose the correct tempo and range, and adjust detection settings. Polyphonic music and noisy recordings are not reliable inputs. Review and edit the result.</p><h3>Where are my scores?</h3><p>In local app storage. Save before leaving and share a copy before clearing data or deleting the app. There is no cloud account recovery.</p><h3>How do I remove data?</h3><p>Clear app storage on Android or use Delete App on iOS. Exported and backed-up copies must be removed separately. Use the remove button in Sheets to delete individual saved scores.</p>
<h2>Contact</h2><p>Email <a href="mailto:ftrevino@yahoo.com?subject=Sheet%20Music%20Rookie%20Support">ftrevino@yahoo.com</a> with your app version, device model, OS version, and steps to reproduce the issue. Include screenshots only after removing private information.</p>'''
page('sheet-music-rookie/support','Support',support)
shots=''
for name,label in [('01_main_menu','Create or open a composition'),('04_musical_composition','Edit a local sample melody'),('06_insert_note','Insert musical notes')]:
    source=root/'store_assets/android/phone'/f'{name}.png'
    if source.exists():
        shutil.copy2(source,assets/source.name)
        shots+=f'<figure><img src="/assets/sheet-music-rookie/{source.name}" alt="{label}" loading="lazy" style="width:100%;max-width:280px;height:auto"><figcaption>{label}</figcaption></figure>'
page('sheet-music-rookie','Overview',f'''<p class="eyebrow">Music notation · iOS and Android</p><img src="/assets/sheet-music-rookie/app-icon.png" alt="Sheet Music Rookie icon" width="112" height="112" style="border-radius:24px"><h1>Sheet Music Rookie</h1><p class="lede">Sing it. See it. Shape it.</p><p>Create musical notation from a melody using your device microphone. Review notes and rhythms, shape your score, and hear it played back with local instrument sounds.</p><p>Prepared for iPhone, iPad, and Android release. Store download links will be added after publication.</p><h2>Features</h2><ul><li>Treble, Bass, Alto, and Tenor clefs with octave ranges.</li><li>Live note detection and phrase review, processed on your device.</li><li>Pitch, duration, rests, ties, lyrics, and undo/redo controls.</li><li>Tempo, key signature, time signatures, and metronome.</li><li>Instrument playback, practice, and melody tests.</li><li>Local composition saving and sharing; MusicXML and MuseScore import.</li></ul><p>Designed for one clear melody at a time. Review detection results before relying on the notation.</p><section id="screenshots"><h2>Inside the app</h2><div style="display:flex;flex-wrap:wrap;gap:20px">{shots}</div></section><p><a class="button" href="{base}support/">Support and usage help</a> <a href="{base}privacy-policy/">Privacy Policy</a></p><h2>Copyright and credits</h2><p>© 2026 Francisco Trevino · NeoTheOne. All rights reserved. Third-party components remain under their respective licenses, including the bundled GeneralUser GS SoundFont; see the app’s license notices.</p>''')
index=out/'index.html';s=index.read_text()
if 'href="/sheet-music-rookie/"' not in s:
    marker='    <section class="category-section" id="industrial-apps">'
    # Insert in the existing general-app section, immediately before its closing tag.
    at=s.index(marker);end=s.rfind('    </section>',0,at)
    card='''      <article class="directory-card"><div class="directory-card-main"><p class="meta">iOS &amp; Android · Music notation</p><h3>Sheet Music Rookie</h3><p>Turn a melody into sheet music. Edit, play, practice, and save compositions offline.</p><a class="button" href="/sheet-music-rookie/">View product</a></div><nav class="directory-links" aria-label="Sheet Music Rookie links"><a href="/sheet-music-rookie/#screenshots">Screenshots <span>→</span></a><a href="/sheet-music-rookie/privacy-policy/">Privacy policy <span>→</span></a><a href="/sheet-music-rookie/support/">Support <span>→</span></a></nav></article>\n'''
    s=s[:end]+card+s[end:];index.write_text(s)
# The global privacy directory is an existing app index too.
privacyindex=out/'privacy/index.html'
if privacyindex.exists():
    s=privacyindex.read_text()
    if '/sheet-music-rookie/privacy-policy/' not in s:
        s=s.replace('</article>','<p><a href="/sheet-music-rookie/privacy-policy/">Sheet Music Rookie Privacy Policy</a></p></article>');privacyindex.write_text(s)
print(out)
