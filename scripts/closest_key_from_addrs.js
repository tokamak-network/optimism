const fs = require("fs");

const SEED = process.argv[2];
const ADDRS_PATH = process.argv[3];

if (!SEED || !ADDRS_PATH) {
  console.error("Usage: node scripts/closest_key_from_addrs.js <SEED_HEX> <ADDRS_JSON>");
  process.exit(1);
}

function hexToBigInt(hex) {
  return BigInt(hex.startsWith("0x") ? hex : "0x" + hex);
}

function padAddressToBytes32(addr) {
  const a = addr.toLowerCase().replace(/^0x/, "");
  const hex = a.padStart(40, "0");
  return "0x" + hex.padStart(64, "0");
}

function distance(a, b) {
  return a > b ? a - b : b - a;
}

function main() {
  const seedBig = hexToBigInt(SEED);
  const addrs = JSON.parse(fs.readFileSync(ADDRS_PATH, "utf8"));
  if (!Array.isArray(addrs) || addrs.length === 0) {
    throw new Error("ADDRS_JSON must be a non-empty array of addresses");
  }

  let closestAddr = null;
  let minDist = null;
  let farthestAddr = null;
  let maxDist = null;

  for (const addr of addrs) {
    if (typeof addr !== "string" || !addr.startsWith("0x") || addr.length < 42) continue;
    const keyBig = hexToBigInt(addr);
    const dist = distance(seedBig, keyBig);

    if (minDist === null || dist < minDist) {
      minDist = dist;
      closestAddr = addr;
    }
    if (maxDist === null || dist > maxDist) {
      maxDist = dist;
      farthestAddr = addr;
    }
  }

  console.log(
    JSON.stringify(
      {
        seed: SEED,
        closestKey: closestAddr ? padAddressToBytes32(closestAddr) : null,
        closestAddress: closestAddr,
        closestDistance: minDist !== null ? minDist.toString() : null,
        farthestKey: farthestAddr ? padAddressToBytes32(farthestAddr) : null,
        farthestAddress: farthestAddr,
        farthestDistance: maxDist !== null ? maxDist.toString() : null,
      },
      null,
      2
    )
  );
}

try {
  main();
} catch (err) {
  console.error("Error:", err && err.message ? err.message : err);
  process.exit(1);
}

