
# Randomized Attention Test (RAT) Challenger

RAT은 챌리저들이 성실히 모니터링을 하고 있는지 챌린저 attention 테스트하기 위해 설계되었습니다.

**컨트랙 관련사항은 build_contracts.md 를 참고한다.**

## 구현 방향

1. 최소 스테이킹 조건 충족
- 챌린저 실행시, 스테이킹 금액을 확인해서, 최소 스테이킹금액보다 작으면 최소 스테이킹 이상되도록 스테이킹한다.

2.game_solver.go
- 파일: op-challenger/game/fault/solver/game_solver.go

    2.1. 어텐션 올바른 증거제출 함수 추가
        - 루트 클래임이 올바르다고 판단된 경우 실행되는 함수입니다.
        - RAT 컨트랙에서 게임아이디에 해당하는 어텐션 정보를 조회합니다.
        - 어텐션 정보의 챌린저 주소와 워커 챌린저의 주소가 동일하다면
            - 올바른 증거 제출 함수를 실행합니다.
            ```solidity
            function submitCorrectEvidence(
                address _gameAddress,
                bytes32 _proofLV,
                bytes32 _proofRV
            ) external
            ```
        - 어텐션 정보의 챌린저 주소와 워커 챌린저의 주소가 틀리면 아무 작업 없이 종료합니다.

    2.2. CalculateNextActions 함수 변경
        - 챌린저가 루트 클래임의 참/거짓 확인시 어텐션 조건에 따른 어텐션 실행
        - 루트 클래임도 올바르고, L2 블록번호도 올바르다면, '어텐션 올바른 증거제출 함수' 함수를 호출합니다.
        - 루트 클래임이 틀리다면 -> 이미 챌린저에게 자동으로 실행합니다. 그런데, RAT에서 실행하면 중복실행이 되는데..어떻게 할까요?
        - 루트 클래임은 올바른데, L2 블록번호가 틀리다면 ??? => 어떻게 할까요?


