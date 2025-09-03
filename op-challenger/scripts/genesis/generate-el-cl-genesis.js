#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Configuration from input file
function loadConfig(configPath) {
  try {
    const configData = fs.readFileSync(configPath, 'utf8');
    return JSON.parse(configData);
  } catch (error) {
    console.error(`❌ Failed to load config from ${configPath}:`, error.message);
    process.exit(1);
  }
}

function ensureDirectoryExists(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
    console.log(`📁 Created directory: ${dirPath}`);
  }
}

function generateDevAccounts() {
  return {
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": {
      "balance": "0x21e19e0c9bab2400000"
    },
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8": {
      "balance": "0x21e19e0c9bab2400000"
    },
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC": {
      "balance": "0x21e19e0c9bab2400000"
    },
    "0x4e59b44847b379578588920cA78FbF26c0B4956C": {
      "balance": "0x0",
      "code": "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3",
      "storage": {},
      "nonce": "0x1"
    }
  };
}

function generateL1Deployments() {
  return {
    "SystemConfig": "0x4e59b44847b379578588920cA78FbF26c0B4956C",
    "OptimismPortal": "0x4e59b44847b379578588920cA78FbF26c0B4956C",
    "L1StandardBridge": "0x4e59b44847b379578588920cA78FbF26c0B4956C"
  };
}

function generateDeployConfig(config, currentTimestamp) {
  return {
    l1ChainID: config.l1ChainID,
    l2ChainID: config.l2ChainID,
    l2GenesisBlockNumber: 0,
    l2GenesisBlockTimestamp: currentTimestamp,
    l2GenesisBlockGasLimit: config.l1GenesisGasLimit,
    l2GenesisBlockBaseFeePerGas: config.l1GenesisBaseFee,
    l2GenesisBlockDifficulty: config.l1GenesisDifficulty,
    l2GenesisBlockNonce: "0",
    l2GenesisBlockGasUsed: "0",
    l2GenesisBlockParentHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
    l2GenesisBlockMixHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
    l1GenesisBlockTimestamp: currentTimestamp,
    l1GenesisBlockGasLimit: config.l1GenesisGasLimit,
    l1GenesisBlockBaseFeePerGas: config.l1GenesisBaseFee,
    l1GenesisBlockDifficulty: config.l1GenesisDifficulty,
    l1CancunTimeOffset: 0,
    l1PragueTimeOffset: null,
    fundDevAccounts: true
  };
}

function generateEthereumGenesis(config, allocs, currentTimestamp) {
  return {
    config: {
      chainId: config.l1ChainID,
      homesteadBlock: 0,
      eip150Block: 0,
      eip155Block: 0,
      eip158Block: 0,
      byzantiumBlock: 0,
      constantinopleBlock: 0,
      petersburgBlock: 0,
      istanbulBlock: 0,
      muirGlacierBlock: 0,
      berlinBlock: 0,
      londonBlock: 0,
      arrowGlacierBlock: 0,
      grayGlacierBlock: 0,
      shanghaiTime: 0,
      cancunTime: 0,
      mergeNetsplitBlock: 0,
      terminalTotalDifficulty: 0
    },
    nonce: `0x${config.l1GenesisBlockNonce.toString(16)}`,
    timestamp: `0x${currentTimestamp.toString(16)}`,
    extraData: "0x",
    gasLimit: `0x${config.l1GenesisBlockGasLimit.toString(16)}`,
    difficulty: config.l1GenesisBlockDifficulty,
    mixHash: config.l1GenesisBlockMixHash,
    coinbase: config.l1GenesisBlockCoinbase,
    number: `0x${config.l1GenesisBlockNumber.toString(16)}`,
    gasUsed: `0x${config.l1GenesisBlockGasUsed.toString(16)}`,
    parentHash: config.l1GenesisBlockParentHash,
    baseFeePerGas: config.l1GenesisBlockBaseFeePerGas,
    excessBlobGas: config.l1GenesisBlockExcessBlobGas ? `0x${config.l1GenesisBlockExcessBlobGas.toString(16)}` : undefined,
    blobGasUsed: config.l1GenesisBlockBlobGasUsed ? `0x${config.l1GenesisBlockBlobGasUsed.toString(16)}` : undefined,
    alloc: allocs
  };
}

function main() {
  const args = process.argv.slice(2);
  
  if (args.length !== 1) {
    console.error("Usage: node generate-el-cl-genesis.js <config.json>");
    process.exit(1);
  }

  const configPath = args[0];
  
  // Load configuration
  const config = loadConfig(configPath);
  
  // Setup paths
  const scriptDir = __dirname;
  const projectRoot = path.resolve(scriptDir, '../..');
  const outputDir = path.join(projectRoot, 'genesis-sync');

  console.log(`🔍 프로젝트 루트: ${projectRoot}`);
  console.log(`📁 제네시스 출력 디렉토리: ${outputDir}`);

  // Create output directory
  console.log('📁 디렉토리 생성 중...');
  ensureDirectoryExists(outputDir);

  // Generate current timestamp
  const currentTimestamp = Math.floor(Date.now() / 1000);
  console.log(`🕐 현재 타임스탬프: ${currentTimestamp}`);

  console.log('⚙️  설정 정보:');
  console.log(`- L1 체인 ID: ${config.l1ChainID}`);
  console.log(`- L2 체인 ID: ${config.l2ChainID}`);
  console.log(`- 가스 한도: ${config.l1GenesisBlockGasLimit}`);
  console.log(`- 기본 가스비: ${config.l1GenesisBlockBaseFeePerGas} wei`);
  console.log(`- 난이도: ${config.l1GenesisBlockDifficulty}`);

  // Generate components
  const devAccounts = generateDevAccounts();
  const l1Deployments = generateL1Deployments();
  const deployConfig = generateDeployConfig(config, currentTimestamp);
  const ethereumGenesis = generateEthereumGenesis(config, devAccounts, currentTimestamp);

  // Save files
  console.log('🔄 EL/CL 동기화된 제네시스 생성 중...');

  try {
    // Save configuration files
    fs.writeFileSync(path.join(outputDir, 'config.json'), JSON.stringify(deployConfig, null, 2));
    fs.writeFileSync(path.join(outputDir, 'allocs.json'), JSON.stringify(devAccounts, null, 2));
    fs.writeFileSync(path.join(outputDir, 'l1-deployments.json'), JSON.stringify(l1Deployments, null, 2));
    fs.writeFileSync(path.join(outputDir, 'genesis.json'), JSON.stringify(ethereumGenesis, null, 2));

    console.log('');
    console.log('🎉 EL Genesis 생성 완료!');
    console.log('📁 생성된 파일들:');
    
    const files = fs.readdirSync(outputDir).filter(f => f.endsWith('.json'));
    files.forEach(file => {
      const filePath = path.join(outputDir, file);
      const stats = fs.statSync(filePath);
      console.log(`  ${file} (${stats.size} bytes)`);
    });

    console.log('');
    console.log('📋 사용 방법:');
    console.log('1. genesis.json - EL (Geth)용 genesis 파일');
    console.log('2. 이 설정으로 ethereum-genesis-generator를 실행하여 동일한 genesis.ssz 생성 필요');
    console.log('');
    console.log('🔍 생성된 genesis 설정:');
    console.log(`- 체인 ID: ${config.l1ChainID}`);
    console.log(`- 타임스탬프: ${currentTimestamp} (${new Date(currentTimestamp * 1000).toISOString()})`);
    console.log(`- 가스 한도: ${config.l1GenesisBlockGasLimit}`);
    console.log(`- 기본 가스비: ${config.l1GenesisBlockBaseFeePerGas} wei`);

  } catch (error) {
    console.error('❌ Genesis 생성 실패:', error.message);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}