
# Randomized Attention Test (RAT) Challenger

RAT은 챌리저들이 성실히 모니터링을 하고 있는지 챌린저 attention 테스트하기 위해 설계되었습니다.

**FaultDisputeGame 관련사항은 game_spec.md를 참고한다.**

**컨트랙 관련사항은 build_contracts.md 를 참고한다.**



## 구현 요소

### RAT 모니터링

1. 챌린저가 실행할때,
    1.1. RAT 컨트랙에 스테이킹된 금액이 **최소 스테이킹 잔액** 보다 많은지 확인한다.
    1.2. 스테이킹 잔액이 최소 스테이킹 잔액보다 작으면 최소 스테이킹 잔액 이상이 되도록 스테이킹한다.
    1.3. RAT 컨트랙의 어텐션 트리거 이벤트를 모니터링한다.

2. 어텐션 트리거 이벤트 AttentionTriggered 가 발생되었을때,
    2.1. 이벤트의 challengerAddress 주소가 본인 주소일경우, 해당 stateRoot 가 맞는지 체크해야 한다.
    2.2. 해당 stateRoot가 맞으면 올바른 증거 제출 함수를 호출한다.
    2.3. 해당 stateRoot가 틀리면 틀린 증거 제출 함수를 호출한다.

3.


