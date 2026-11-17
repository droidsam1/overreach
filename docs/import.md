# Importing your training history

Overreach imports history from one CSV format — the one Strong exports (ADR-0011). Three starting points:

## From Strong

1. In Strong: **Settings → Export Strong Data**. Save the CSV to Files or share it to Overreach.
2. In Overreach: **Settings → Import → Strong CSV**, pick the file and confirm the weight unit you used in
   Strong (the file does not include it).
3. Review the preview: sessions, sets, and any exercise names Overreach does not know. They are imported as
   custom exercises without muscles, so their volume does not count yet.
4. Open **Settings → Exercises** (the badge shows how many need muscles). For each one, assign its muscles
   (or copy them from a similar catalog exercise), or **merge** it into a catalog exercise: its history moves
   there and its name becomes an alias, so importing the same file again maps it directly.

Importing the same file again does not create duplicates.

## Starting from zero

Nothing to import. Overreach ships with a catalog of common exercises (English names in Strong's style, with
Spanish aliases) and you can add your own at any time.

## From notes (Notes app, notebook, spreadsheet…)

Ask ChatGPT or Claude to convert your notes into the CSV format, then import the result:

1. Copy the prompt below (the app has a **Copy prompt** button).
2. Paste it into ChatGPT or Claude, followed by your notes.
3. Copy the CSV it returns and import it in Overreach (**Settings → Import → Paste CSV**). You will see a
   preview before anything is saved.

### Prompt

```text
Convert my workout notes below into a CSV with exactly this header:

Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE

Rules:
- One row per set. Expand shorthand: "3x8 @ 60kg" becomes 3 rows of 8 reps at 60.
- Date: yyyy-MM-dd HH:mm:ss. If there is no time, use 12:00:00. If the year is missing, ask me.
- Workout Name: the session name if I wrote one, otherwise "Workout".
- Duration: like "1h 5m" or "45m" if I wrote it, otherwise leave it empty.
- Exercise Name: use the standard English name with the equipment in parentheses, e.g.
  "Bench Press (Barbell)", "Squat (Barbell)", "Lateral Raise (Dumbbell)", "Pull Up", "Plank".
  Keep my original name if you are not sure what it is.
- Set Order: 1, 2, 3… for working sets; W for warm-up sets; F for sets to failure; D for drop sets.
- Weight: a number, in the unit I used (tell me which unit you assumed). 0 for bodyweight.
- Reps: a number. 0 for timed sets.
- Seconds: duration of timed sets (planks, holds), otherwise 0.
- Distance: 0 unless the set has a distance.
- RPE: only if I wrote it (e.g. "@8" or "RPE 8"), otherwise leave empty.
- Quote any field that contains a comma.
- Do not invent sets, weights or dates. If something is ambiguous, list your questions after the CSV.

Return only the CSV in a code block, followed by any questions.

My notes:
```

### Example

Notes:

```text
10/11/2026 Torso A
Press banca: calentamiento 40x10, luego 3x6 con 80 (la última @8)
Dominadas 3x8
Plancha 3x45s
```

CSV:

```csv
Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE
2026-11-10 12:00:00,Torso A,,Bench Press (Barbell),W,40,10,0,0,
2026-11-10 12:00:00,Torso A,,Bench Press (Barbell),1,80,6,0,0,
2026-11-10 12:00:00,Torso A,,Bench Press (Barbell),2,80,6,0,0,
2026-11-10 12:00:00,Torso A,,Bench Press (Barbell),3,80,6,0,0,8
2026-11-10 12:00:00,Torso A,,Pull Up,1,0,8,0,0,
2026-11-10 12:00:00,Torso A,,Pull Up,2,0,8,0,0,
2026-11-10 12:00:00,Torso A,,Pull Up,3,0,8,0,0,
2026-11-10 12:00:00,Torso A,,Plank,1,0,0,0,45,
2026-11-10 12:00:00,Torso A,,Plank,2,0,0,0,45,
2026-11-10 12:00:00,Torso A,,Plank,3,0,0,0,45,
```

## Developers: testing with a real export

The importer has a test that runs only when you point it at a real export on your machine:

```bash
OVERREACH_STRONG_EXPORT=~/Downloads/strong.csv swift test --package-path Packages/OverreachCore \
  --filter importsARealExportWithoutLosingRows
```

Never commit real exports; the `.gitignore` blocks `strong*.csv` outside test fixtures.
