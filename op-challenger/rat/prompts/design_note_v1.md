
# Randomized Attention Test (RAT)

## 📄 논문 정보
- **제목**: Looking for Attention: Randomized Attention Test Design for Validator Monitoring in Optimistic Rollups
https://docs.google.com/presentation/d/16BTSqXo1aihtgTdZ-egk5gYK4c8Oulr2/edit?slide=id.p4#slide=id.p4


## 🔧 RAT (Randomized Attention Test) 프로토콜

### 핵심 아이디어
- **확률적 도전**: 검증자를 무작위로 선택하여 주기적으로 테스트
- **사전 검증**: 사기 발생 전에 검증자의 준비 상태 확인
- **경제적 인센티브**: 실패 시 직접적인 경제적 페널티

### Attention Puzzle 메커니즘
- **Commitment Binding**: 특정 상태 커밋먼트에 고유하게 바인딩
- **Knowledge Proof**: 올바른 L2 상태 정보를 가진 검증자만 해결 가능
- **효율성**: 두 개의 자식 해시 (LV, RV)만 제출하면 됨


### RAT
```
1. RAT 컨트랙은 L1에 배포한다.
2. RAT 컨트랙은은 챌린저를 위한 스테이킹 함수를 지원한다.
    2.1. 챌린저들은 1(?) ETH 스테이킹을 해야 RAT시스템에 참여할 수 있다.
3. RAT은 챌린저를 {아이디, 챌린저 Address, 스테이킹 양} 구조로 정보를 저장한다.
    2.1. 챌린저 아이디로 정보를 가져올수있고, 챌린저 Address로 알수도 있고  정보을 알수있는 인터페이스를 지원한다.
    2.2. 챌린저 목록을 알 수 잇다.
4. RAT 컨트랙에는 파라미터를 입력받아, 특정 챌린저에게 Attention Test 를 하는 이벤트를 발생하는 함수가 있다. (onAttentionTrigger)
```


### 프로토콜 흐름
```
1. Proposer가 L2 상태 전환 계산 -> 기존 옵티미즘에서 구현되어 있는 기능
2. L1 스마트 컨트랙트에 상태 커밋먼트 제출 -> 기존 옵티미즘에서 구현되어 있는 기능
3. Proposer가 πa 확률로 RAT 컨트랙에 Attention Puzzle 트랜잭션 RAT.onAttentionTrigger(L2blocknumber, sigma P) 을 실행한다.
    3.1. RAT.onAttentionTrigger(sigma P) 함수는 L2 block number 와 sigma P 를 이용하여 어텐션 할 챌린저를 결정하고 OnAttentionTrigger (challengerId, L2 block number) Event를 발생시킨다.
4. onAttentionTrigger 함수에 따라 지목된 챌린저는 submitAttentionProof(proof) 트랜잭션을 제출하여야 한다.
    4.1. onAttentionTrigger 함수가 발생되고 언제까지 제출해야 하는가?
    4.2. 기간안데 제출되지 않았다면 어떻게 해야 하는가?
    4.3. 제출한 검증값이 틀렸는지, 맞았는지 여부는 누가 체크하는가? 어떻게 체크하는가?
    4.4. 제출한 검증값이 틀렷다면 어떻게 해야 하는가?
    4.5. 제출한 검증값이 맞았다면 어떻게 해야 하는가? -> 디파짓을 차감한다. 구체적인 차감로직은 구현시에 구체화시키자.
```

### 챌린저
```
1. 챌린저들은 RAT 컨트랙트에 1 ETH 스테이킹을 해야 RAT시스템에 참여할 수 있다.
2. RAT 컨트랙을 모니터링하고 있어야 한다.
3. OnAttentionTrigger (challengerId, L2 block number) Event 에서 챌린저아이디가 본인의 아이디라면
    2.1. 이벤트를 보고 질문을 파악한다. => 어떤 값이 이벤트의 파라미터로 들어가야 하는가? 질문이 무엇인가?
    2.2. 챌린저는 답을 어떻게 찾아야 하는가?

```


**미팅에서 요구사항1**
 누구나 챌린지를 할수있으면서, 의무를 가지는 챌린저 집합이 존재를 해야 한다. 그 주소의 집합만 챌린지를 하게 하는건 아니다.  누군가 들은 최소한의 자원을 통해 관리가 되어야 한다. 컨트랙트에 관리 할수있께 하고, 그 주소에 대해서만 랜덤하게 테스트를 수행하게 하는 메커니즘이 필요하다.
    => 누구나 챌린지를 할수있으면서 : 기존 옵티미즘 챌린지 기능 그대로 사용
    => 2에 반영. 의무를 가지는 챌린저 집합이 존재 : RAT에 스테이킹한 챌린저 집합이 존재
    => 3에 반영. 그 주소에 대해서만 랜덤하게 테스트를 수행하게 : Proposer가 RAT 컨트랙에 Attention Puzzle 트랜잭션에 시그마 값을 랜덤하게 제출하여 챌린저를 랜덤하게 결정


**미팅에서 요구사항2**
L1 ⇒ 게임팩토리 컨트랙을 수정해서 구현하고자 한다. 챌린저 관리 하는 식으로 : 챌린저 스테이킹
=> 설계를 보니 게임팩토리와 상관이 없는 역할임, RAT 컨트랙트과 관련있다고 판다되는데.. 혹시 어떤 이유에서 게임팩토리에서 구현하고자 하였는지 ?

**이벤트 → 어텐션 테스트 트리거 → 응답에 따라 디파짓을 차감하는 식으로**
=> 4.4 에 반영


### 질문
```
1. 챌린저가 RAT은 응답을 하지만 실제 Dispute Game을 검사하지 않으면 어떻하는가? 실제적으로 위 어텐션 기능은 Dispute Game 에 참여하고 있다는 것을 증명하지 못하고 있다.
2. 위의 RAT에 참여함으로서 챌린저가 얻는 이익은 ?
```

