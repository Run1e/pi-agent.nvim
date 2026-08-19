import { existsSync } from "fs";

export function findSocket(): string {
  const sessionIdIdx = process.argv.findIndex(
    (value) => value === "--session-id",
  );

  if (sessionIdIdx == -1) {
    throw new Error("[simple-pi] Couldn't find session name");
  }

  const sessionName = process.argv[sessionIdIdx + 1];

  const tmpDir = "/tmp";
  const runtimeDir = process.env.XDG_RUNTIME_DIR;

  let currentCandidate: string;

  if (runtimeDir && runtimeDir.length) {
    currentCandidate = runtimeDir + "/simple-pi/" + sessionName + ".sock";

    if (existsSync(currentCandidate)) {
      return currentCandidate;
    }
  }

  currentCandidate = tmpDir + "/" + sessionName + ".sock";
  if (existsSync(currentCandidate)) {
    return currentCandidate;
  }

  throw new Error("Could not find simple-pi session socket");
}
