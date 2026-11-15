/** World = recorded footage pixels (Agentville --record at --snapshot-scale 4). */
export const WORLD = { width: 4000, height: 2240 } as const;
export const FRAME = { width: 1920, height: 1080 } as const;
/** Screen pixels per world pixel at zoom 1 (the floor fills the frame's width). */
export const BASE = FRAME.width / WORLD.width;

/** The app's own night navy: the cast sheet's and icon's background (decoded, 13,26,48). */
export const NAVY = "#0d1a30";

/**
 * The middle of the sleigh team, measured from the working clip (frames 90-600, tiles 0.5 s apart):
 * Santa at 16 f - 3160 (120 pt/s at 4x), the team centred ~300 px ahead of him. It now flies low
 * over the snow (FloorScene.addSleigh, flightY ground + 27, size 1.6), clear of the stations.
 */
export const sleighX = (frame: number) => 16 * frame - 3160 + 300;
export const SLEIGH_Y = 1170;

/** Measured from the idle clip's first frame. */
export const LOUNGE = { fireplaceX: 1150, treeX: 2840, y: 1790 } as const;
/** The agents' row under the stations in the working clip. */
export const AGENTS_Y = 880;

/** The Santa Claude icon (AppIcon.render, northPole:santa, 1024 px; art spans 100-924). */
export const ICON = { size: 620 } as const;

/** Cast sheet (Wardrobe.writeCasts at 6x): 4656 x 1188, nine slots of 80 pt from a 28 pt margin. */
export const CAST = {
  width: 4656,
  height: 1188,
  scale: 6,
  margin: 28,
  slotWidth: 80,
  titleHeight: 30,
  count: 9,
  shown: 0.7, // sheet pixels -> screen pixels
} as const;
