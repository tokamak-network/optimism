const http = require('http');

const SEED = process.argv[2];
const RPC_URL = 'http://127.0.0.1:32816';

if (!SEED) {
    console.error("Usage: node find_closest_key.js <SEED_HEX>");
    process.exit(1);
}

// Convert hex string to BigInt
function hexToBigInt(hex) {
    return BigInt(hex.startsWith('0x') ? hex : '0x' + hex);
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

        let closestKey = null;
        let closestAddr = null;
        let minDist = null;
        let seedBig = hexToBigInt(SEED);

        let count = 0;

        for (const [addr, data] of Object.entries(accountMap)) {
            if (!addr.startsWith('0x') || addr.length < 40) continue;

            let key = data.key;
            if (!key) continue;

            let keyBig = hexToBigInt(key);
            let dist = distance(seedBig, keyBig);

            if (minDist === null || dist < minDist) {
                minDist = dist;
                closestKey = key;
                closestAddr = addr;
            }
            count++;
        }

        console.error(`Scanned ${count} accounts.`);
        console.error(`Method: Numeric Distance (Absolute Difference)`); // Explicit log

        console.log(JSON.stringify({
            seed: SEED,
            closestKey: closestKey,
            closestAddress: closestAddr,
            distance: minDist.toString() // Print as decimal for magnitude check
        }, null, 2));

    } catch (error) {
        console.error("Error:", error);
        process.exit(1);
    }
}

main();
