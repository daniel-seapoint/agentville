import { AbsoluteFill, Audio, Img, staticFile } from "remotion";
import { useTime, clamp01 } from "../kit/time";
import { CUES, DURATION, FOOTAGE } from "./cues";
import { AGENTS_Y, BASE, CAST, FRAME, ICON, LOUNGE, NAVY, SLEIGH_Y, WORLD, sleighX } from "./layout";

export { DURATION };

type Cam = { x: number; y: number; zoom: number };
type Ease = (p: number) => number;
const io: Ease = (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
const easeIn: Ease = (p) => p * p;
const easeOut: Ease = (p) => 1 - (1 - p) * (1 - p);
const outCubic: Ease = (p) => 1 - Math.pow(1 - p, 3);
const inCubic: Ease = (p) => p * p * p;
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;

/** Keys [t, x, y, zoom]; each segment eases with the ease of the key it arrives at. Zoom moves in log space. */
type Key = readonly [number, number, number, number, Ease?];
function keyed(t: number, keys: readonly Key[]): Cam {
  if (t <= keys[0][0]) return { x: keys[0][1], y: keys[0][2], zoom: keys[0][3] };
  for (let i = 1; i < keys.length; i++) {
    const [t1, x1, y1, z1, ease = io] = keys[i];
    const [t0, x0, y0, z0] = keys[i - 1];
    if (t <= t1) {
      const p = ease(clamp01((t - t0) / (t1 - t0)));
      return { x: lerp(x0, x1, p), y: lerp(y0, y1, p), zoom: Math.exp(lerp(Math.log(z0), Math.log(z1), p)) };
    }
  }
  const last = keys[keys.length - 1];
  return { x: last[1], y: last[2], zoom: last[3] };
}

/** Keep the view inside the footage. */
function clampCam(c: Cam): Cam {
  const halfW = FRAME.width / 2 / (BASE * c.zoom);
  const halfH = FRAME.height / 2 / (BASE * c.zoom);
  // The recording has a black window margin and rounded corners; stay inside them (measured: ~40 px).
  const inset = 90;
  const x = Math.min(WORLD.width - inset - halfW, Math.max(inset + halfW, c.x));
  const y = Math.min(WORLD.height - inset - halfH, Math.max(inset + halfH, c.y));
  if (halfW + inset >= WORLD.width / 2) return { ...c, x: WORLD.width / 2, y: WORLD.height / 2 };
  return { ...c, x, y };
}

const footageFrame = (t: number, clip: "working" | "idle") => {
  const { frames, offset } = FOOTAGE[clip];
  return Math.min(frames - 1, Math.max(0, Math.round((t + offset) * FOOTAGE.fps)));
};

const TRACK_ZOOM = 2.2;
/** Riding along with the sleigh: it flies in from the left, the camera follows until the right edge. */
const sleighCam = (t: number): Cam =>
  // Framed a little above the sleigh, so the agents at work ride along at the top of the shot.
  clampCam({ x: sleighX(footageFrame(t, "working")), y: SLEIGH_Y - 170, zoom: TRACK_ZOOM });

const WIDE: Cam = { x: WORLD.width / 2, y: WORLD.height / 2, zoom: 1.1 };

function workingCam(t: number): Cam {
  const push = keyed(t, [
    [CUES.revealOpen, WIDE.x, WIDE.y, WIDE.zoom],
    [CUES.sleighStart, 1500, 900, 1.3, easeOut],
  ]);
  if (t < CUES.sleighStart) return clampCam(push);
  if (t < CUES.sleighStart + 1) {
    const ride = sleighCam(t);
    const p = io(clamp01(t - CUES.sleighStart));
    return clampCam({
      x: lerp(push.x, ride.x, p),
      y: lerp(push.y, ride.y, p),
      zoom: Math.exp(lerp(Math.log(push.zoom), Math.log(ride.zoom), p)),
    });
  }
  if (t < CUES.stationsStart) return sleighCam(t);
  const from = sleighCam(CUES.stationsStart);
  return clampCam(
    keyed(t, [
      [CUES.stationsStart, from.x, from.y, from.zoom],
      [CUES.stationsStart + 1, 2625, AGENTS_Y, 2.5, easeIn],
      [CUES.castStart, 1000, AGENTS_Y, 2.5, easeOut],
    ]),
  );
}

function loungeCam(t: number): Cam {
  return clampCam(
    keyed(t, [
      [CUES.loungeStart, LOUNGE.fireplaceX, LOUNGE.y, 2.6],
      [CUES.wideStart - 0.5, LOUNGE.treeX, LOUNGE.y, 2.6, io],
      [CUES.revealClose, WIDE.x, WIDE.y, WIDE.zoom, io],
    ]),
  );
}

function Floor({ clip, t, cam }: { clip: "working" | "idle"; t: number; cam: Cam }) {
  const index = String(footageFrame(t, clip)).padStart(4, "0");
  const s = BASE * cam.zoom;
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <Img
        src={staticFile(`footage/santa/${clip}/f${index}.jpg`)}
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: WORLD.width,
          height: WORLD.height,
          transformOrigin: "0 0",
          transform: `translate(${FRAME.width / 2}px, ${FRAME.height / 2}px) scale(${s}) translate(${-cam.x}px, ${-cam.y}px)`,
        }}
      />
    </AbsoluteFill>
  );
}

/** A small hop: up and back down over `length` seconds, starting at `start`. */
const hop = (t: number, start: number, height: number, length = 0.36) => {
  const p = (t - start) / length;
  return p <= 0 || p >= 1 ? 0 : -height * Math.sin(Math.PI * p);
};

function Icon({ t, scale, opacity }: { t: number; scale: number; opacity: number }) {
  const hops = [...CUES.iconHops, ...CUES.endHops];
  const y = hops.reduce((sum, h) => sum + hop(t, h, 34), 0);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <Img
        src={staticFile("stills/santa-icon.png")}
        style={{ width: ICON.size, height: ICON.size, translate: `0 ${y}px`, scale: `${scale}`, opacity }}
      />
    </AbsoluteFill>
  );
}

/** When each cast member pops in: six on eighth notes, then the last three on beats as the pan reaches them. */
const castPop = (i: number) => (i < 6 ? CUES.castStart + 0.25 * i : CUES.castStart + 2.5 + 0.5 * (i - 6));

function Cast({ t }: { t: number }) {
  const k = CAST.scale * CAST.shown;
  const width = CAST.width * CAST.shown;
  const height = CAST.height * CAST.shown;
  const slot = CAST.slotWidth * k;
  const slotLeft = (i: number) => (CAST.margin + i * CAST.slotWidth) * k;
  // Pan across the line-up: hold on the first six, then glide to the last three.
  const viewSlots = FRAME.width / slot;
  const from = CAST.margin * k - 40;
  const to = width - FRAME.width - CAST.margin * k + 40;
  const pan = io(clamp01((t - (CUES.castStart + 1.5)) / 1.5));
  const x = -lerp(from, to, pan);
  const top = (CAST.margin + CAST.titleHeight - 4) * k;
  const titleOpacity = outCubic(clamp01((t - CUES.castStart) / 0.25));
  const sheet = staticFile("stills/cast-northPole.png");
  // Everyone already on stage hops in a ripple on every beat of the second bar.
  const hopBeats = [0, 1, 2, 3].map((n) => CUES.castStart + 2 + 0.5 * n);
  void viewSlots;
  return (
    <AbsoluteFill style={{ background: NAVY }}>
      <div style={{ position: "absolute", left: 0, top: (FRAME.height - height) / 2, width, height, translate: `${x}px 0` }}>
        {/* The sheet's own title, SANTA CLAUDE. */}
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width,
            height: top,
            opacity: titleOpacity,
            backgroundImage: `url(${sheet})`,
            backgroundSize: `${width}px ${height}px`,
          }}
        />
        {Array.from({ length: CAST.count }, (_, i) => {
          const start = castPop(i);
          const p = clamp01((t - start) / 0.22);
          const appear = outCubic(p);
          const pop = 1 + 0.08 * Math.sin(Math.PI * p) * (1 - p);
          const y = hopBeats
            .filter((h) => h > start + 0.3)
            .reduce((sum, h) => sum + hop(t, h + i * 0.03, 22, 0.3), 0);
          const left = slotLeft(i);
          return (
            <div
              key={i}
              style={{
                position: "absolute",
                left,
                top,
                width: slot,
                height: height - top,
                backgroundImage: `url(${sheet})`,
                backgroundSize: `${width}px ${height}px`,
                backgroundPosition: `${-left}px ${-top}px`,
                transformOrigin: "50% 70%",
                scale: `${appear * pop}`,
                translate: `0 ${y + (1 - appear) * 40}px`,
                opacity: appear,
              }}
            />
          );
        })}
      </div>
    </AbsoluteFill>
  );
}

/** A circle centred on the frame, through which the floor shows. */
const circle = (r: number) => `circle(${r}px at 50% 50%)`;
const FULL_RADIUS = Math.hypot(FRAME.width, FRAME.height) / 2 + 20;

export const SantaFilm = () => {
  const t = useTime();
  const inCast = t >= CUES.castStart && t < CUES.castEnd;
  const inLounge = t >= CUES.loungeStart;

  // The iris: opens out of the icon on bar 2, closes back into it on bar 12 beat 3.
  const open = outCubic(clamp01((t - CUES.revealOpen) / CUES.revealLength));
  const close = inCubic(clamp01((t - CUES.revealClose) / 0.5));
  const radius = (open - close) * FULL_RADIUS;

  const iconOut = clamp01((t - CUES.revealOpen) / 0.35);
  const iconBack = outCubic(clamp01((t - CUES.revealClose - 0.25) / 0.5));
  const iconScale = t < CUES.revealClose ? 1 - outCubic(iconOut) : iconBack;
  // The final chord: a small landing squash as it comes back.
  const land = hop(t, CUES.finalChord, -0.03, 0.3);

  const floor =
    radius <= 0 || inCast ? null : (
      <AbsoluteFill style={{ clipPath: radius >= FULL_RADIUS ? undefined : circle(radius) }}>
        {inLounge ? <Floor clip="idle" t={t} cam={loungeCam(t)} /> : <Floor clip="working" t={t} cam={workingCam(t)} />}
      </AbsoluteFill>
    );

  return (
    <AbsoluteFill style={{ background: NAVY }}>
      <Audio src={staticFile("audio/santa/music/santa-edit.wav")} />
      {floor}
      {inCast ? <Cast t={t} /> : null}
      {iconScale > 0.001 ? <Icon t={t} scale={iconScale * (1 + land)} opacity={1} /> : null}
    </AbsoluteFill>
  );
};

export const FILM_LENGTH = DURATION;
