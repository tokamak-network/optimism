# 출력 Cannon 본드 비용 측정 - 테스트 분석 보고서

## 테스트 구성

- **테스트 소요 시간**: 361.41초 (약 6분)
- **가스 가격**: 0.7656 gwei (765625001 wei)
- **스플릿 깊이**: 14 (Output Bisection → Execution Trace 전환 지점)
- **최대 깊이**: 50

## 참가자

- **정직한 챌린저 (Alice)**: `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65`
- **악의적인 프로포저 (Bob)**: `0x71562b71999873DB5b286dF957af199Ec94617F7`

## 게임 요약

- **총 클레임 수**: 51개
- **도달한 최대 깊이**: 50 ✓
- **최종 게임 상태**: Challenger Won ✓
- **게임 종료 방식**: 시간 경과 후 정상적으로 CloseGame 수행

## 본드 요약

### 챌린저 본드
- **클레임 수**: 25개
- **총 필요 본드**: 225.621709 ETH (225,621,708,600,000,000,000 wei)

### 프로포저 본드
- **클레임 수**: 26개
- **총 필요 본드**: 257.562190 ETH (257,562,189,600,000,000,000 wei)

### 총합
- **총 필요 본드**: 483.183898 ETH (483,183,898,200,000,000,000 wei)

## 단계별 요약

### Output Bisection 단계 (깊이 0-14)
- **클레임 수**: 15개
- **설명**: L2 출력 루트를 이분 탐색하여 불일치 지점을 찾는 구간

### Execution Trace 단계 (깊이 15-50)
- **클레임 수**: 36개
- **설명**: VM 실행 트레이스를 이분 탐색하여 특정 명령어를 추적하는 구간

## 세부 클레임 목록

| 클레임 | 깊이 | 단계 | 역할 | 본드 (ETH) | 본드 (wei) |
|------:|------:|:------|:-----|----------:|:-----------|
| #0 | 0 | Output Bisection | 프로포저 | 0.000000 | 0 |
| #1 | 1 | Output Bisection | 챌린저 | 0.091325 | 91,325,200,000,000,000 |
| #2 | 2 | Output Bisection | 프로포저 | 0.104254 | 104,253,800,000,000,000 |
| #3 | 3 | Output Bisection | 챌린저 | 0.119013 | 119,012,600,000,000,000 |
| #4 | 4 | Output Bisection | 프로포저 | 0.135861 | 135,861,000,000,000,000 |
| #5 | 5 | Output Bisection | 챌린저 | 0.155094 | 155,094,200,000,000,000 |
| #6 | 6 | Output Bisection | 프로포저 | 0.177050 | 177,050,400,000,000,000 |
| #7 | 7 | Output Bisection | 챌린저 | 0.202115 | 202,115,000,000,000,000 |
| #8 | 8 | Output Bisection | 프로포저 | 0.230728 | 230,727,600,000,000,000 |
| #9 | 9 | Output Bisection | 챌린저 | 0.263391 | 263,391,000,000,000,000 |
| #10 | 10 | Output Bisection | 프로포저 | 0.300678 | 300,678,400,000,000,000 |
| #11 | 11 | Output Bisection | 챌린저 | 0.343244 | 343,244,400,000,000,000 |
| #12 | 12 | Output Bisection | 프로포저 | 0.391836 | 391,836,200,000,000,000 |
| #13 | 13 | Output Bisection | 챌린저 | 0.447307 | 447,307,200,000,000,000 |
| #14 | 14 | Output Bisection | 프로포저 | 0.510631 | 510,630,800,000,000,000 |
| #15 | 15 | Execution Trace | 챌린저 | 0.582919 | 582,919,200,000,000,000 |
| #16 | 16 | Execution Trace | 프로포저 | 0.665441 | 665,441,000,000,000,000 |
| #17 | 17 | Execution Trace | 챌린저 | 0.759645 | 759,645,200,000,000,000 |
| #18 | 18 | Execution Trace | 프로포저 | 0.867185 | 867,185,400,000,000,000 |
| #19 | 19 | Execution Trace | 챌린저 | 0.989950 | 989,950,000,000,000,000 |
| #20 | 20 | Execution Trace | 프로포저 | 1.130094 | 1,130,093,800,000,000,000 |
| #21 | 21 | Execution Trace | 챌린저 | 1.290077 | 1,290,077,200,000,000,000 |
| #22 | 22 | Execution Trace | 프로포저 | 1.472709 | 1,472,709,000,000,000,000 |
| #23 | 23 | Execution Trace | 챌린저 | 1.681195 | 1,681,195,200,000,000,000 |
| #24 | 24 | Execution Trace | 프로포저 | 1.919196 | 1,919,196,200,000,000,000 |
| #25 | 25 | Execution Trace | 챌린저 | 2.190890 | 2,190,890,200,000,000,000 |
| #26 | 26 | Execution Trace | 프로포저 | 2.501047 | 2,501,046,800,000,000,000 |
| #27 | 27 | Execution Trace | 챌린저 | 2.855111 | 2,855,111,400,000,000,000 |
| #28 | 28 | Execution Trace | 프로포저 | 3.259300 | 3,259,299,600,000,000,000 |
| #29 | 29 | Execution Trace | 챌린저 | 3.720707 | 3,720,707,400,000,000,000 |
| #30 | 30 | Execution Trace | 프로포저 | 4.247435 | 4,247,435,000,000,000,000 |
| #31 | 31 | Execution Trace | 챌린저 | 4.848730 | 4,848,729,600,000,000,000 |
| #32 | 32 | Execution Trace | 프로포저 | 5.535147 | 5,535,147,400,000,000,000 |
| #33 | 33 | Execution Trace | 챌린저 | 6.318739 | 6,318,739,000,000,000,000 |
| #34 | 34 | Execution Trace | 프로포저 | 7.213261 | 7,213,260,800,000,000,000 |
| #35 | 35 | Execution Trace | 챌린저 | 8.234417 | 8,234,417,200,000,000,000 |
| #36 | 36 | Execution Trace | 프로포저 | 9.400135 | 9,400,135,000,000,000,000 |
| #37 | 37 | Execution Trace | 챌린저 | 10.730879 | 10,730,879,400,000,000,000 |
| #38 | 38 | Execution Trace | 프로포저 | 12.250013 | 12,250,012,800,000,000,000 |
| #39 | 39 | Execution Trace | 챌린저 | 13.984205 | 13,984,204,600,000,000,000 |
| #40 | 40 | Execution Trace | 프로포저 | 15.963900 | 15,963,899,800,000,000,000 |
| #41 | 41 | Execution Trace | 챌린저 | 18.223854 | 18,223,853,800,000,000,000 |
| #42 | 42 | Execution Trace | 프로포저 | 20.803741 | 20,803,741,400,000,000,000 |
| #43 | 43 | Execution Trace | 챌린저 | 23.748855 | 23,748,854,800,000,000,000 |
| #44 | 44 | Execution Trace | 프로포저 | 27.110898 | 27,110,897,600,000,000,000 |
| #45 | 45 | Execution Trace | 챌린저 | 30.948893 | 30,948,893,200,000,000,000 |
| #46 | 46 | Execution Trace | 프로포저 | 35.330221 | 35,330,220,600,000,000,000 |
| #47 | 47 | Execution Trace | 챌린저 | 40.331797 | 40,331,797,000,000,000,000 |
| #48 | 48 | Execution Trace | 프로포저 | 46.041429 | 46,041,429,400,000,000,000 |
| #49 | 49 | Execution Trace | 챌린저 | 52.559355 | 52,559,354,600,000,000,000 |
| #50 | 50 | Execution Trace | 프로포저 | 60.000000 | 59,999,999,800,000,000,000 |

## 결론

### 테스트 실행 흐름

본 테스트는 본드 비용 측정을 위해 두 개의 게임을 연속으로 실행합니다.

#### 첫 번째 게임 (콜드 스타트)
1. **초기화**: 초기 상태와 prestate를 확보하기 위해 잘못된 루트 클레임을 제출
2. **챌린저 응답**: 정직한 챌린저가 대응하여 승리
3. **시간 경과**: 게임 지속 시간이 모두 소진되도록 시계 이동
4. **게임 종료**: `CloseGame()` 호출로 게임을 닫고 Challenger Won 상태 확인

#### 두 번째 게임 (본드 측정)
1. **게임 초기화**: 프로포저가 본드 없이 잘못된 루트 클레임 제출
2. **Output Bisection (깊이 0-14)**: 챌린저와 프로포저가 번갈아 클레임을 제출하며 출력 루트를 이분 탐색
3. **Execution Trace (깊이 15-50)**: 스플릿 깊이에 도달한 뒤 VM 실행 트레이스 이분 탐색으로 전환
4. **최대 깊이 도달**: 단일 VM 명령어에 해당하는 깊이 50까지 도달
5. **시간 경과**: 게임이 해결될 수 있도록 시간 이동
6. **챌린저 종료 확인**: 챌린저가 모든 동작을 마치고 Resolve까지 완료할 때까지 대기
7. **게임 종료**: `CloseGame()` 호출로 게임을 종료
8. **최종 상태**: 게임 상태가 **Challenger Won**인지 확인

### 구현 메모

이 테스트는 `WithoutWaitingForStep()` 옵션을 사용해 STEP 실행을 건너뛰고, 전체 분쟁 트리 깊이에 걸친 본드 비용 측정에 집중했습니다.

### 주요 관찰 사항

- **본드 증가 추세**: 깊이가 1 증가할 때마다 약 14.2%씩 지수적으로 상승 (깊이 1 → 0.091 ETH, 깊이 50 → 60 ETH)
- **경제적 안전장치**: 총 483.18 ETH의 본드가 필요하여 깊은 분쟁을 유발하는 스팸 공격을 억제
- **STEP 미실행**: 본드 측정에만 집중하기 위해 STEP 호출을 생략
- **게임 종료**: 시간 경과 후 CloseGame으로 정상 종료, 결과적으로 Challenger Won

---

## 본드 계산 공식

각 클레임에 필요한 본드 금액은 `FaultDisputeGame.sol` 956-997라인에 구현된 `getRequiredBond()` 함수를 통해 계산됩니다. 이는 “Big Bonds v1.5” 사양을 구현한 것입니다.

**컨트랙트 위치**: `packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol:956-997`

### 파라미터

`FaultDisputeGame.sol:961-963` 발췌:

```solidity
// Values taken from Big Bonds v1.5 (TM) spec.
uint256 assumedBaseFee = 200 gwei;
uint256 baseGasCharged = 400_000;
uint256 highGasCharged = 300_000_000;
```

컨트랙트 상수:
- `MAX_GAME_DEPTH = 50` (라인 139)

**⚠️ 중요**: 위 값들은 실시간 네트워크 가스 가격과 무관한 **하드코딩 상수**입니다.
- `assumedBaseFee = 200 gwei`는 컨트랙트에 고정된 값
- 실제 테스트 가스 가격: 0.7656 gwei (261배 낮음)
- 본드 계산은 실시간 가스 가격에 **영향받지 않는다**
- 즉, 본드는 가스 비용 환급이 아니라 **경제적 담보** 역할을 한다

### 수학적 공식

깊이에 따른 지수 성장을 사용합니다.

```
Bond(depth) = assumedBaseFee × requiredGas(depth)
```

`requiredGas(depth)`는 다음과 같이 계산됩니다.

```
requiredGas(depth) = baseGasCharged × multiplier^depth
```

`multiplier`는 다음에서 유도됩니다.

```
multiplier = (highGasCharged / baseGasCharged)^(1 / MAX_GAME_DEPTH)
multiplier = (300,000,000 / 400,000)^(1 / 50)
multiplier = 750^(1/50)
multiplier ≈ 1.141701559 (깊이당 약 14.17% 증가)
```

### 구현 상세

고정소수점(Fixed-point) 수학을 활용해 승수를 계산합니다.

1. **기본 승수 계산**
   ```
   a = highGasCharged / baseGasCharged = 750
   base = e^(ln(a) / MAX_GAME_DEPTH)
   ```

2. **깊이에 따른 지수 적용**
   ```
   rawGas = base^depth × baseGasCharged
   ```

3. **최종 본드 계산**
   ```
   requiredBond = assumedBaseFee × rawGas
   ```

### Solidity 코드

**출처**: `packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol:956-997`

```solidity
/// @notice Returns the required bond for a given move kind.
/// @param _position The position of the bonded interaction.
/// @return requiredBond_ The required ETH bond for the given move, in wei.
function getRequiredBond(Position _position) public view returns (uint256 requiredBond_) {
    uint256 depth = uint256(_position.depth());
    if (depth > MAX_GAME_DEPTH) revert GameDepthExceeded();

    // Values taken from Big Bonds v1.5 (TM) spec.
    uint256 assumedBaseFee = 200 gwei;
    uint256 baseGasCharged = 400_000;
    uint256 highGasCharged = 300_000_000;

    // Goal here is to compute the fixed multiplier that will be applied to the base gas
    // charged to get the required gas amount for the given depth. We apply this multiplier
    // some `n` times where `n` is the depth of the position. We are looking for some number
    // that, when multiplied by itself `MAX_GAME_DEPTH` times and then multiplied by the base
    // gas charged, will give us the maximum gas that we want to charge.
    // We want to solve for (highGasCharged/baseGasCharged) ** (1/MAX_GAME_DEPTH).
    // We know that a ** (b/c) is equal to e ** (ln(a) * (b/c)).
    // We can compute e ** (ln(a) * (b/c)) quite easily with FixedPointMathLib.

    // Set up a, b, and c.
    uint256 a = highGasCharged / baseGasCharged;
    uint256 b = FixedPointMathLib.WAD;
    uint256 c = MAX_GAME_DEPTH * FixedPointMathLib.WAD;

    // Compute ln(a).
    // slither-disable-next-line divide-before-multiply
    uint256 lnA = uint256(FixedPointMathLib.lnWad(int256(a * FixedPointMathLib.WAD)));

    // Computes (b / c) with full precision using WAD = 1e18.
    uint256 bOverC = FixedPointMathLib.divWad(b, c);

    // Compute e ** (ln(a) * (b/c))
    // sMulWad can be used here since WAD = 1e18 maintains the same precision.
    uint256 numerator = FixedPointMathLib.mulWad(lnA, bOverC);
    int256 base = FixedPointMathLib.expWad(int256(numerator));

    // Compute the required gas amount.
    int256 rawGas = FixedPointMathLib.powWad(base, int256(depth * FixedPointMathLib.WAD));
    uint256 requiredGas = FixedPointMathLib.mulWad(baseGasCharged, uint256(rawGas));

    // Compute the required bond.
    requiredBond_ = assumedBaseFee * requiredGas;
}
```

**주요 코드 포인트**
- 라인 961: `assumedBaseFee = 200 gwei` – Big Bonds v1.5 사양에서 그대로 가져옴
- 라인 962: `baseGasCharged = 400_000` – 깊이 0의 기본 가스량
- 라인 963: `highGasCharged = 300_000_000` – 최대 깊이에서 목표로 하는 가스량
- 라인 970: “(highGasCharged/baseGasCharged) ** (1/MAX_GAME_DEPTH)”를 해결하는 것이 목표
- 라인 971-972: `a ** (b/c) = e ** (ln(a) * (b/c))` 수학 공식 사용
- 라인 975: `a = highGasCharged / baseGasCharged` = 750
- 라인 976-977: WAD(1e18) 정밀도로 고정소수점 계산을 준비
- 라인 981: `ln(a)` 계산
- 라인 984: `(b / c) = (1 / MAX_GAME_DEPTH)` 계산
- 라인 988-989: `e ** (ln(a) * (b/c))`로 승수 도출
- 라인 992: 깊이만큼 승수를 거듭제곱
- 라인 996: 최종 본드 = `assumedBaseFee × requiredGas`

**단순화된 공식**
```

Bond(depth) = Gas Fee × Gas Amount(depth)
            = 200 gwei × [400,000 × (1.1417)^depth]

설명:
- 가스 요율(고정): assumedBaseFee = 200 gwei (변하지 않음)
- 깊이별 가스량: baseGasCharged × (multiplier)^depth
- multiplier = (highGasCharged / baseGasCharged)^(1 / MAX_GAME_DEPTH)
    ⇒ 1.1417 = 750^(1/50) ≈ 깊이당 약 14% 증가
```

**예시**
- 깊이 0: 200 gwei × 400,000 = 0.08 ETH
- 깊이 10: 200 gwei × 1,503,392 = 0.30 ETH
- 깊이 50: 200 gwei × 300,000,000 = 60 ETH

### 깊이별 예시 계산

공식을 적용한 깊이별 본드 값:

| 깊이 | 승수^깊이 | 필요 가스량 | 본드 (ETH) |
|------:|:---------|-----------:|-----------:|
| 0 | 1.0000 | 400,000 | 0.0800 |
| 1 | 1.1417 | 456,680 | 0.0913 |
| 10 | 3.7585 | 1,503,392 | 0.3007 |
| 20 | 14.1261 | 5,650,468 | 1.1301 |
| 30 | 53.0929 | 21,237,175 | 4.2474 |
| 40 | 199.5488 | 79,819,497 | 15.9639 |
| 50 | 750.0000 | 300,000,000 | 60.0000 |

### 경제적 배경

지수적 본드 증가는 다음과 같은 목적을 가집니다.

1. **스팸 차단**: 깊은 분쟁을 유도하려면 기하급수적으로 많은 자산이 필요하므로 무분별한 도전을 억제
2. **경제적 안전장치**: 공격자가 전체 트리를 강제로 탐색하려면 상당한 자본이 필요
3. **인센티브 정렬**: 정직한 참여자는 가능한 얕은 깊이에서 문제를 해결하려는 유인을 얻음
4. **예측 가능성**: 본드 금액이 고정되어 있어 가스 가격 변동과 무관하게 비용 계산이 쉬움

이를 통해 얻는 보장:
- 깊이 0(루트 클레임)에서는 0.08 ETH로 진입 장벽이 낮음
- 깊이 50(최대 깊이)에서는 60 ETH까지 상승하여 의미 있는 담보 요구
- 깊이가 1 증가할 때마다 본드가 약 14.17%씩 증가
- 전체 깊이(0~50)에 걸쳐 총 본드는 약 0.08 ETH에서 60 ETH까지 증가

---

## 왜 본드 값이 하드코딩되어 있을까?

### 본드 ≠ 가스 비용

본드 금액은 실제 네트워크 가스 가격을 반영하지 않습니다.

**테스트 환경 비교**
```
하드코딩 assumedBaseFee  : 200.0000 gwei (컨트랙트 고정)
테스트 가스 가격          :   0.7656 gwei (실제)
비율                       : 261배
```

즉, 실제 가스 비용을 기준으로 본다면 본드는 **261배** 높게 책정되어 있습니다. 이는 보안을 위한 의도적인 설계입니다.

### 고정 본드 설계 철학

실시간 가스 기반이 아닌 고정 값을 사용하는 이유는 다음과 같습니다.

#### 1. **예측 가능성과 안정성**

**동적 가격의 문제점**
- 가스 가격에 따라 본드가 크게 변동
- 야간/주말 등 가스가 싸질 때 공격자가 비용을 낮출 수 있음
- 저렴한 구간을 노린 공격 가능

**고정 값의 장점**
- 분쟁을 시작하기 전에 정확한 비용을 알 수 있음
- 가스 가격을 감시하거나 타이밍을 기다릴 필요가 없음
- 공격 비용을 추정하기 쉬움

#### 2. **경제적 안전 하한선**

**핵심 이슈**
```
가정: 가스 가격이 1 gwei로 하락
- 동적 본드라면: 공격 비용 = 1 gwei × 가스 ≈ 0.0004 ETH/클레임
- 고정 본드라면: 공격 비용 = 200 gwei × 가스 ≈ 0.08 ETH/클레임
- 차이: 동적 본드가 200배 저렴!
```

**실제 영향 (테스트 데이터 기반)**
- 고정 본드(200 gwei): 총 본드 483.18 ETH ≈ 공격 비용 140만 달러
- 동적 본드(0.7656 gwei): 총 본드 1.85 ETH ≈ 공격 비용 5,500달러
- 동적 본드를 쓰면 **261배** 보안이 약화

**고정 본드가 보장하는 것**
- 가스 가격과 무관한 최소 담보 (140만 달러 수준)
- L1 혼잡도가 낮아도 공격 비용은 비싸게 유지
- 가스 가격이 떨어져도 보안 수준이 유지

#### 3. **가스 가격 조작 방지**

**동적 가격 공격 시나리오**
1. 공격자가 가치 있는 분쟁(예: 100 ETH)을 발견
2. L1에 스팸 트랜잭션을 보내 가스 가격을 낮춤
3. 가스가 싸지면 낮은 본드로 분쟁을 시작
4. 분쟁이 진짜로 틀려도 이익을 얻을 수 있음

**고정 값의 효과**
- 본드 비용이 가스 가격 조작에 영향받지 않음
- 공격자는 혼잡도 조절로 본드 부담을 줄일 수 없음
- 분쟁 게임 보안이 L1 시장 상황과 분리됨

#### 4. **크로스체인 일관성**

**L1/L2 통합 시 어려움**
- L1 분쟁 게임이 L2 상태를 보호
- L1 가스 가격은 1 gwei → 100 gwei 이상까지 100배 이상 변동
- L2 가치가 L1 가스 시장 변동에 좌우되어서는 안 됨

**고정 본드의 장점**
- L1 환경 변화와 무관하게 일정한 보안 레벨 보장
- L2 참여자가 비용을 예측 가능
- 브리지 등 상호 운용성 구성 요소도 안정적인 경제 모델을 기대 가능

#### 5. **게임 이론 안정성**

**동적 본드의 문제**
```solidity
// 가상의 동적 구현 (사용되지 않음)
function getRequiredBond(Position _position) public view returns (uint256) {
    uint256 currentGasPrice = tx.gasprice;  // ❌ 조작 가능
    return currentGasPrice * calculatedGas;
}
```

문제점:
- 방어 측의 응답 시간이 가스 가격에 좌우됨
- “가스가 더 내려갈 때까지 기다리자”는 전략이 우세
- 가스가 비싼 구간에는 아무도 행동하지 않아 게임이 정체
- 승패가 진실 여부보다 타이밍 운에 좌우될 수 있음

**고정 본드의 효과**
- 순수하게 클레임의 진위 여부로 승패 결정
- 가스 가격에 따라 기다리거나 서두를 필요 없음
- 양측 모두 대칭적인 비용 구조
- 더 깔끔한 메커니즘 설계

#### 6. **미래 불확실성에 대한 보험**

**장기적 고려 사항**
- 이더리움 가스 비용은 다음 요인으로 크게 하락할 수 있음
  - 더 나은 확장 솔루션
  - 대체 실행 환경
  - 향후 프로토콜 업그레이드
- 본드가 가스에 연동된다면 시간이 지날수록 보안 수준이 저하될 수 있음

**고정 값의 장점**
- L1 개선이 있어도 보안 수준 유지
- 수년에 걸쳐 예측 가능한 경제 구조
- 가스 시장이 변해도 거버넌스 개입 없이 동작 가능

#### 7. **실제 비용 회수는 여전히 가능**

**오해**: “본드는 실제 사용한 가스를 보전해야 한다”

**현실**
- 분쟁에서 승리한 정직한 참여자는 상대방 본드까지 회수
- 승자는 자신의 본드 + 상대 본드를 가져가므로 대부분의 경우 실가스비를 초과 회수
- 부정행위를 한 참여자는 본드를 잃음

**예시**
```
정직한 챌린저의 비용:
- 25개 클레임 × 실제 가스 ≈ 25 × (0.7656 gwei × 200k gas) ≈ 0.004 ETH
- 잠긴 총 본드: 225.62 ETH
- 승리 후 회수: 225.62 ETH (자기 본드) + 257.56 ETH 중 일부 (프로포저 본드)
- 순이익: 220 ETH 이상 (실제 가스비를 크게 상회)
```

### “Big Bonds v1.5” 철학

“Big Bonds”라는 이름 자체가 의도적인 설계를 반영합니다.
- 본드가 실제 가스 비용보다 훨씬 큼
- 정직한 행동을 강하게 유도
- “v1.5”는 여러 차례 개선된 결과임을 의미
- “EIP-1559 스타일의 동적 본드”도 검토했으나 위 이유로 채택하지 않음

### 감수한 트레이드오프

**고정 값을 선택하면서 감수한 단점**
1. **저금액 분쟁에 대한 진입 장벽** 상승
   - 최소 0.08 ETH 본드는 소규모 분쟁에 부담
   - 다만 Optimism 분쟁 게임은 수십억 달러 규모의 TVL을 보호하는 용도

2. **저가 가스 환경에서의 과잉 담보**
   - 테스트 환경 기준 실제 가스 대비 261배 초과
   - 그러나 이는 보안을 위한 보험료에 해당

3. **ETH 가격 변동에 대한 자동 대응 부재**
   - ETH 가격이 10배 상승하면 본드의 USD 가치도 10배 상승
   - 모든 ETH 기반 계약이 가지는 공통 이슈이며, 필요 시 거버넌스 조정 가능

### 마무리

하드코딩된 본드 값은 우연이 아니라 **의도적인 보안 설계**입니다. 다음을 우선시합니다.
1. ✅ 예측 가능한 비용
2. ✅ 가스 시장과 무관한 보안 하한선
3. ✅ 가스 가격 조작에 대한 내성
4. ✅ 장기적인 안정성
5. ✅ 깔끔한 게임 이론 구조

대신 다음을 희생합니다.
1. ❌ 담보 요구의 최소화
2. ❌ 실제 가스 비용과의 긴밀한 연동
3. ❌ 동적 시장 기반 가격 결정

수십억 달러 규모의 L2 자산을 보호하는 시스템에는, 과잉 담보를 통한 보수적인 접근이 가장 합리적인 선택입니다.
