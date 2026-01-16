const http = require('http');

const SEED = process.argv[2];
const RPC_URL = process.env.RPC_URL || process.argv[3] || 'http://127.0.0.1:32816';

if (!SEED) {
    console.error("Usage: RPC_URL=<L2_RPC> node scripts/find_closest_key.js <SEED_HEX> [RPC_URL]");
    process.exit(1);
}

// Convert hex string to BigInt
function hexToBigInt(hex) {
    return BigInt(hex.startsWith('0x') ? hex : '0x' + hex);
}

function padAddressToBytes32(addr) {
    const a = addr.toLowerCase().replace(/^0x/, '');
    // 20 bytes address => 40 hex chars
    const hex = a.padStart(40, '0');
    return '0x' + hex.padStart(64, '0');
}

// Calculate NUMERIC distance (Absolute Difference) per RAT.sol _distance()
function distance(a, b) {
    return a > b ? a - b : b - a;
}

function fetchDump() {
    return new Promise((resolve, reject) => {
        const req = http.request(RPC_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        }, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                try {
                    resolve(JSON.parse(data));
                } catch (e) {
                    reject(e);
                }
            });
        });

        req.on('error', reject);
        req.write(JSON.stringify({
            jsonrpc: "2.0",
            method: "debug_dumpBlock",
            params: ["latest"],
            id: 1
        }));
        req.end();
    });
}

async function main() {
    try {
        console.error("Fetching state dump from Watchdog Node...");
        const response = await fetchDump();

        if (response.error) {
            throw new Error(response.error.message);
        }

        const accountMap = response.result.accounts || response.result;

        let closestAddr = null;
        let minDist = null;

        let farthestAddr = null;
        let maxDist = null;
        let seedBig = hexToBigInt(SEED);

        let count = 0;

        for (const [addr, data] of Object.entries(accountMap)) {
            if (!addr.startsWith('0x') || addr.length < 40) continue;

            // Our on-chain RAT logic treats "key" as an address (bytes32 with address in low 20 bytes).
            // Therefore, in e2e we compute distances over account addresses, not the state-trie hashed keys.
            let keyBig = hexToBigInt(addr);
            let dist = distance(seedBig, keyBig);

            if (minDist === null || dist < minDist) {
                minDist = dist;
                closestAddr = addr;
            }
            if (maxDist === null || dist > maxDist) {
                maxDist = dist;
                farthestAddr = addr;
            }
            count++;
        }

        console.error(`Scanned ${count} accounts.`);
        console.error(`Method: Numeric Distance (Absolute Difference)`); // Explicit log

        console.log(JSON.stringify({
            seed: SEED,
            closestKey: closestAddr ? padAddressToBytes32(closestAddr) : null,
            closestAddress: closestAddr,
            closestDistance: minDist !== null ? minDist.toString() : null,
            farthestKey: farthestAddr ? padAddressToBytes32(farthestAddr) : null,
            farthestAddress: farthestAddr,
            farthestDistance: maxDist !== null ? maxDist.toString() : null
        }, null, 2));

    } catch (error) {
        console.error("Error:", error);
        process.exit(1);
    }
}

main();
