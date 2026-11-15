import { Composition } from "remotion";
import { SantaFilm, DURATION } from "./santa/SantaFilm";

type Props = { fps: number; debug?: boolean };

export const Root = () => (
  <Composition
    id="SantaClaude"
    component={SantaFilm}
    width={1920}
    height={1080}
    fps={60}
    durationInFrames={Math.round(DURATION * 60)}
    defaultProps={{ fps: 60, debug: false } as Props}
    calculateMetadata={({ props }) => ({
      fps: props.fps,
      durationInFrames: Math.round(DURATION * props.fps),
    })}
  />
);
