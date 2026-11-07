#!/usr/bin/env python3
import json,pathlib
root=pathlib.Path(__file__).resolve().parents[1];out=root/'store_assets/metadata'
base='https://frtrev.github.io/sheet-music-rookie/'
description='''Turn a melody into sheet music, one note at a time.

Sheet Music Rookie listens through your device microphone and estimates musical notes and rhythms on your device. Review your melody, edit the score, and hear it played back with instrument sounds.

CREATE AND SHAPE YOUR MUSIC
• Choose Treble, Bass, Alto, or Tenor clef and an octave range.
• Capture a single melody live or review a phrase before adding it.
• Edit pitches and durations, insert notes and rests, add ties and lyrics, and use undo and redo.
• Set tempo, key signature, and time signatures.

LISTEN AND PRACTICE
• Play your score with local instrument sounds.
• Use the metronome, practice tools, and melody tests.
• Adjust detection settings to suit your voice and environment.

KEEP YOUR SCORES
• Save compositions locally and reopen them later.
• Share saved compressed MusicXML files through your device’s share interface.
• Open compatible MusicXML and MuseScore files from other apps.

Core features work offline without an account. Microphone access is used for listening features. Microphone audio is processed locally rather than uploaded or saved as a voice recording. Saved scores contain musical notes and timing, and may include titles or lyrics you enter.

For best results, sing one clear note at a time in a quiet room and set a suitable tempo. Detection is an estimate: review and edit the notation. This app is intended for a single melody, rather than transcription of a full band or polyphonic recording.'''
common={'support_url':base+'support/','privacy_policy_url':base+'privacy-policy/','copyright':'2026 Francisco Trevino · NeoTheOne'}
google={**common,'title':'Sheet Music Rookie','short_description':'Turn a melody into sheet music. Edit, play, and practice offline.','full_description':description,'category':'Music & Audio','suggested_tags':['Music','Musical instruments','Education'],'support_email':'ftrevino@yahoo.com'}
apple={**common,'name':'Sheet Music Rookie','subtitle':'Sing, edit, and practice music','promotional_text':'Create notation from a melody, shape your score, and practice it offline. Choose your clef, edit notes and rhythms, then listen with instrument playback.','description':description,'keywords':'notation,compose,melody,singing,clef,pitch,rhythm,metronome,musicxml,practice,score','marketing_url':base,'primary_category':'Music','secondary_category':'Education','review_notes':'''No account, login, server, or subscription is required. Create → choose a clef → choose an octave range opens the score editor. Start a listening feature to trigger microphone permission; sing one clear note at a time in a quiet room. Core editing and local playback remain usable without microphone access. Use Insert Note to create notes without audio input. Save names the composition; Open lists locally saved scores. Compatible MusicXML/MuseScore files can be opened from another app. Detection is approximate and results are editable. No microphone recording is uploaded. Simulator screenshots use a locally saved original sample exercise, with no fabricated listening state.'''}
limits={'google':{'title':30,'short_description':80,'full_description':4000},'apple':{'name':30,'subtitle':30,'promotional_text':170,'description':4000,'keywords':100}}
report=[]
for platform,data in [('google',google),('apple',apple)]:
    folder=out/platform;folder.mkdir(parents=True,exist_ok=True)
    (folder/'listing.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    for k,v in data.items():
        if isinstance(v,str):(folder/(k+'.txt')).write_text(v+'\n')
    for k,limit in limits[platform].items():
        n=len(data[k]);assert n<=limit,(k,n,limit);report.append({'platform':platform,'field':k,'characters':n,'limit':limit,'status':'PASS'})
(root/'store_assets/validation/metadata.json').write_text(json.dumps(report,indent=2)+'\n')
print('Store metadata written; all length checks passed')
