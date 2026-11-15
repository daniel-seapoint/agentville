import { at, type Grid } from "../kit/time";

/**
 * The beat sheet. "Jingle Bells" (Kevin MacLeod, CC BY 3.0), measured at 120 BPM
 * (scripts/beats.py, grid spread 2.6 ms). The edit (public/audio/santa/music/santa-edit.wav)
 * is song bars 5-16 then the song's last bar 49, so the film runs 13 bars of 2 s.
 */
export const GRID: Grid = { bpm: 120, firstBeat: 0, pickupBeats: 0, beatsPerBar: 4 };
export const b = (bar: number, beat = 1, fraction = 0) => at(GRID, bar, beat, fraction);
export const BEAT = 0.5;

export const DURATION = b(14); // 26 s

export const CUES = {
  // Bar 1: the Santa Claude icon, hopping on beats 2-4.
  iconHops: [b(1, 2), b(1, 3), b(1, 4)],
  // Bar 2: the floor opens out of the icon.
  revealOpen: b(2),
  revealLength: 0.6,
  // Bars 3-5: the sleigh crosses; the camera rides along.
  sleighStart: b(3),
  sleighEnd: b(6),
  // Bars 6-7: down among the agents at their stations.
  stationsStart: b(6),
  // Bars 8-9: the cast, one per eighth note, then hopping on the beat.
  castStart: b(8),
  castEnd: b(10),
  // Bars 10-11: the lounge, fireplace to the tree, everyone asleep.
  loungeStart: b(10),
  // Bar 12: pull out wide, then close into the icon on beat 3.
  wideStart: b(12),
  revealClose: b(12, 3),
  // Bar 13: the final chord; the icon lands and comes to rest as it started.
  finalChord: b(13),
  endHops: [b(13, 2), b(13, 3)],
} as const;

/** Footage clocks: film seconds -> recorded seconds (both clips are 30 fps). */
export const FOOTAGE = {
  fps: 30,
  working: { frames: 1200, offset: 3.33 },
  idle: { frames: 360, offset: -16.5 },
} as const;
