// The fork distributes its tested bridge through GitHub Releases. The npm
// package-name release belongs to a different publishing pipeline and can lag.
export const BRIDGE_INSTALL_COMMAND = "npm i -g --prefer-online https://github.com/zwthys-cyber/TethrX/releases/download/bridge-latest/tethrx-bridge.tgz";
const MANIFEST_URL = "https://github.com/zwthys-cyber/TethrX/releases/download/bridge-latest/bridge-version.json";
const VERSION = /^\d+\.\d+\.\d+$/;

export function isNewerBridgeVersion(candidate, current) {
  if (!VERSION.test(candidate || "") || !VERSION.test(current || "")) return false;
  const left = candidate.split(".").map(Number);
  const right = current.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return left[i] > right[i];
  }
  return false;
}

export async function fetchLatestBridgeVersion(fetcher = fetch) {
  try {
    const response = await fetcher(MANIFEST_URL, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) return null;
    const { version } = await response.json();
    return typeof version === "string" && VERSION.test(version) ? version : null;
  } catch {
    return null; // Release checks must never stop an otherwise usable bridge.
  }
}
