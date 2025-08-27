
# Randomized Attention Test (RAT) Contracts

RAT은 챌리저들이 성실히 모니터링을 하고 있는지 챌린저 attention 테스트하기 위해 설계되었습니다.

**FaultDisputeGame 관련사항은 game_spec.md를 참고한다.**

**기존 존재하는 코드는 아래 기재한 코드외에는 수정해서는 안된다.**

## 구현 요소

### RAT 컨트랙트

1. **파일 위치**: `packages/contracts-bedrock/src/L1/` 폴더에 `RAT.sol` 생성

2. **스토리지 구조**
   - **챌린저 정보 저장**: `{아이디 번호, 챌린저 Address, 스테이킹 양, 삭감된 양}`
   - **DisputeGameFactory 컨트랙트 주소**
   - **건당 삭감 보증금 양**: 어텐션 챌린지 시 삭감보증금 만큼 삭감
   - **어텐션 매핑 정보**: `FaultDisputeGame`, 어텐션정보 관리
     - 어텐션정보: `{GameId, 챌리저 address, stateRoot, L2 block number, block hash, 삭감된 보증금 양, L1 블록, 증거제출완료여부}` 저장
   - **어텐션 테스트 증거 제출 기간 (블록수)**: 증거제출기간 안에 증거를 제출해야 삭감된 보증금을 되살릴 수 있다
   - **유효한 챌린저 리스트**: 스테이킹할 때 확인해서 추가. 나중에 game에서 이기면 보증금을 되돌려줘야 한다
   - **유효하지 않은 챌린저 리스트**: 어텐션 트리거 시 보증금삭감하고, 조건이 되면 유효하지 않은 챌린저도 이동
   - **FaultDisputeGame로 GameId 매핑**
   - **최소 스테이킹 잔액** : 관리자가 설정가능해야 한다 .

3. **구현사항**

   #### 3.1. Optimism 코드베이스 패턴
   - **상속**: `ProxyAdminOwnedBase`, `Initializable`, `ReinitializableBase`, `ISemver`
   - 모든 L1 컨트랙트는 `ProxyAdminOwnedBase`, `Initializable`, `ReinitializableBase`, `ISemver`를 상속
   - `onlyProxyAdminOwner` modifier 사용
   - Semantic versioning 적용 (`1.0.0-beta.1` 형식)

   #### 3.2. ReinitializableBase의 역할
   - 프록시 업그레이드 시 재초기화를 관리
   - 같은 버전으로는 두 번 초기화할 수 없음
   - 업그레이드 시에만 더 높은 버전으로 재초기화 가능
   - 대부분의 Optimism L1 컨트랙트가 버전 2 사용
   - ETHLockbox만 버전 1 사용
   - RAT는 표준을 따라 버전 2 사용

   ```solidity
   constructor() ReinitializableBase(2) {
       initialize({
       });
   }
   ```

   #### 3.3. 보안 고려사항
   - `onlyProxyAdminOwner` modifier로 관리자 권한 제한
   - ETH를 전송 실패 시 적절한 에러 처리
   - 중복 스테이킹 방지
   - 유효한 챌린저 리스트 관리 시 O(1) 제거를 위한 인덱스 매핑 사용

   #### 3.4. 챌린저가 ETH를 스테이킹할 수 있는 트랜잭션 함수
   - 스테이킹 잔액이 '최소 스테이킹 잔액' 이상되도록 스테이킹 해야 한다.
   - 여러번 스케이킹 가능하다.

   #### 3.5. 특정 챌린저 정보를 볼 수 있는 뷰 함수

   #### 3.6. 총 챌린저 수 확인 함수

   #### 3.7. 유효한 챌린저 리스트를 따로 관리해야 한다
   - 유효한 챌린저를 대상으로 어텐션 트리거가 실행되어야 하기 때문

   #### 3.8. 유효하지 않은 챌린저 리스트를 따로 관리해야 한다

   #### 3.9. 어텐션 트리거 트랜잭션 함수
   - **3.9.1. DisputeGameFactory만 이 함수를 호출할 수 있다**
   - **3.9.2. 어텐션 트리거 함수에서 받는 파라미터**
     - `GameId`
     - `state root`
     - `L2 block number`
     - `block hash`
   - **3.9.3. 동작**
     - `block hash` 정보로 유효한 validator 리스트에서 한명 선정
       - 예: `validator index = blockhash mod |validator set|`
       - 가스비를 고려해서, `block hash`를 작은값으로 가공해서 모듈러연산이 더 작은 가스비가 든다면, 가공할 수 있다
     - 해당 챌린저의 스테이킹 양이 보증금양보다 큰지 확인해야 함
       - 해당 챌린저의 스테이킹 양이 보증금양보다 작으면, 해당 챌린저를 유효한 챌리저에서 삭제해야 함
       - **유효한 챌리저에서 삭제하고, 다시 챌린저를 찾아야 하나??**
     - 해당 챌린저정보.스테이킹양 -= 어텐션 매핑의 GameId어텐션정보의 보증금양
     - 챌린저의 스테이킹양이 보증금양보다 작으면 유효한 챌리저에게 삭제한다
     - GameId 에서 FaultDisputeGame 찾아서, FaultDisputeGame:어텐션정보 매핑정보 저장한다.
   - **3.9.4. 이벤트 발생**
     - `(GameId, stateroot, L2 blocknumber, 챌린저 주소)` 파라미터를 포함한 이벤트를 발생시켜야 한다. 이벤트에 명시된 챌린저는 이 이벤트에 맞는 증거를 제출(트랜잭션)해야 한다

   #### 3.10. 참이라는 어텐션증거 제출 함수
   - **3.10.1. 파라미터**
     - `FaultDisputeGame`
     - `proof{LV, RV}`: `state root`를 계산할 수 있는 LV와 RV를 파라미터로 받는다
   - **3.10.2. 동작**
     - 어텐션매핑정보에서 FaultDisputeGame 로 `GameId`, `sender`, `L2 blocknumber`로 어텐션정보를 찾는다
     - **어텐션정보.sender == Transaction.sender** => 이 조건 필요한가?
     - 어텐션정보.증거제출완료여부 == false
     - `current L1 blocknumber < 어텐션정보.L1블록 + 어텐션 테스트 증거 제출 기간 (블록수)`
     - 증거제출완료여부.stateRoot == hash(proof{LV, RV})
     - 위 조건을 모두 만족하면
       - 어텐션정보.증거제출완료여부 = true
       - 챌린저정보.스테이킹양 += 어텐션 매핑의 GameId어텐션정보의 삭감된보증금양
   - **3.10.3. 이벤트 발생**
     - 이벤트 파라미터
       - `GameId`
       - `sender`
       - `proof{LV, RV}`
       - 원복된 스테이킹 양

   #### 3.11. 틀리다는 어텐션 증거 제출함수 =>
   **기존 챌린저 프로그램에서 자동으로 게임을 시작한다. 또는 다른 챌린저가 게임을 시작했을수도 있다. 따라서 현재상태에 맞는 클래임을 시작했더라도 블록에 누가먼저 들어갔냐에 따라 트랜잭션이 실패할수있다.**

   - **3.11.1. payable 함수입니다**
     - 파라미터로 받은 `FaultDisputeGame` 컨트랙트 주소를 구한다
     - `FaultDisputeGame`에서 아래 함수로 보증금을 계산합니다
       ```solidity
       Position attackPos = Position.wrap(2);
       function getRequiredBond(Position attackPos) public view returns (uint256 requiredBond_)
       ```
     - 보증금을 이더로 함수 호출 시 같이 전송해야 합니다
   - **3.11.2. 파라미터**
     - `FaultDisputeGame`
     - `claim`: Claim Type, The `Claim` at the relative attack position
   - **3.11.3. 동작**: FaultDisputeGame 시작한다
     - 어텐션매핑정보에서 `FaultDisputeGame`로 `sender`, `L2 blocknumber`로 어텐션정보를 찾는다
     - **어텐션정보.sender == Transaction.sender** => 이 조건 필요한가?
     - 어텐션정보.증거제출완료여부 == false
     - `current L1 blocknumber < 어텐션정보.L1블록 + 어텐션 테스트 증거 제출 기간 (블록수)`
     - `msg.value === FaultDisputeGame.getRequiredBond(2)`
     - `FaultDisputeGame.attack(어텐션정보.stateRoot, 0, Claim claim)` 함수를 실행한다
   - **3.11.4. 이벤트 발생**
     - 이벤트 파라미터
        - `GameId`
        - `claim`
        - `msg.value`

   #### 3.12. resolve 함수 추가 => **누구든지 게임에 참여할수있기 때문에.. 누가 resolve를 먼저하는지??**
   - **3.12.1. 파라미터**
     - 없음
   - **3.12.2. 동작**
     - 게임을 시작하여, 챌린저가 승리한 경우 호출되는 함수
     - `msg.sender`가 `FaultDisputeGame`이다
     - `FaultDisputeGame`으로 어텐션정보 `{GameId, 챌리저 address, stateRoot, L2 block number, block hash, 삭감된 보증금 양, L1 블록, 증거제출완료여부}` 조회
     - 어텐션정보.챌리저address != address(0)
     - 어텐션정보.증거제출완료여부 == false
     - 위 조건을 만족하면
       - 어텐션정보.증거제출완료여부 = true
       - 챌린저정보.스테이킹양 += 어텐션 매핑의 GameId어텐션정보의 삭감된보증금양
     - 챌린저가 유효한 챌린저가 아닌데, 스테이킹 양이 삭감 보증금보다 많으면 유효한 챌린저로 이동
   - **3.12.3. 이벤트 발생**
     - 이벤트 파라미터
        - `GameId`
        - 챌린저 address
        - 추가된 보증금 양

4. **단위 테스트 코드 작성**
   - 경로: `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/test/L1/RAT.t.sol`

### DisputeGameFactory 컨트랙트 업그레이드

1. **파일**: `packages/contracts-bedrock/src/dispute/DisputeGameFactory.sol` 컨트랙트를 업그레이드한다

2. **RAT.sol 컨트랙트의 주소 저장**: RAT.sol 컨트랙트의 주소는 owner만 변경 가능하다

3. **create 함수 기능 추가하여 업그레이드**
   - **3.1. 게임타입이 GameTypes.CANNON 인경우, FaultDisputeGame initialize 할때, rat 주소도 함께 전달**
     ```solidity

      // proxy_.initialize{ value: msg.value }();

      if (gameType.raw() == GameTypes.CANNON.raw()) {
        proxy_.initialize{ value: msg.value }(rat);
      } else {
        proxy_.initialize{ value: msg.value }();
      }

     ```

   - **3.2. DisputeGameCreated 이벤트 실행 후에 RAT 컨트랙트의 어텐션 트리거 함수를 호출한다**
     - 어텐션 트리거 함수에 전달하는 파라미터
       - `GameId`
       - `state root`
       - `L2 block number`
       - `block hash`

4. **업그레이드 및 단위 테스트 코드 추가 작성**
   - 경로: `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/test/dispute/DisputeGameFactory.t.sol`

### FaultDisputeGame 컨트랙트 업그레이드

1. **파일**: `packages/contracts-bedrock/src/dispute/FaultDisputeGame.sol` 컨트랙트를 업그레이드한다

2. rat 스토리지 추가
   ```solidity
   address public rat;
   ```
3. initialize(address rat_) 함수 추가

   ```solidity

    /// @notice Initializes the contract with RAT address.
    /// @dev This function may only be called once.
    function initialize(address _rat) public payable virtual {
        _initialize(_rat);
    }


    /// @notice Initializes the contract.
    /// @dev This function may only be called once.
    function _initialize(address _rat) public virtual {
        // SAFETY: Any revert in this function will bubble up to the DisputeGameFactory and
        // prevent the game from being created.
        //
        // Implicit assumptions:
        // - The `gameStatus` state variable defaults to 0, which is `GameStatus.IN_PROGRESS`
        // - The dispute game factory will enforce the required bond to initialize the game.
        //
        // Explicit checks:
        // - The game must not have already been initialized.
        // - An output root cannot be proposed at or before the starting block number.

        // INVARIANT: The game must not have already been initialized.
        if (initialized) revert AlreadyInitialized();

        // Grab the latest anchor root.
        (Hash root, uint256 rootBlockNumber) = ANCHOR_STATE_REGISTRY.getAnchorRoot();

        // Should only happen if this is a new game type that hasn't been set up yet.
        if (root.raw() == bytes32(0)) revert AnchorRootNotFound();

        // Set the starting proposal.
        startingOutputRoot = Proposal({ l2SequenceNumber: rootBlockNumber, root: root });

        // Revert if the calldata size is not the expected length.
        //
        // This is to prevent adding extra or omitting bytes from to `extraData` that result in a different game UUID
        // in the factory, but are not used by the game, which would allow for multiple dispute games for the same
        // output proposal to be created.
        //
        // Expected length: 154 bytes
        // - 4 bytes selector
        // - 20 bytes creator address
        // - 32 bytes root claim
        // - 32 bytes l1 head
        // - 32 bytes extraData
        // - 2 bytes CWIA length
        if (msg.data.length != 122) revert BadExtraData();

        // Do not allow the game to be initialized if the root claim corresponds to a block at or before the
        // configured starting block number.
        if (l2BlockNumber() <= rootBlockNumber) revert UnexpectedRootClaim(rootClaim());

        // Set the root claim
        claimData.push(
            ClaimData({
                parentIndex: type(uint32).max,
                counteredBy: address(0),
                claimant: gameCreator(),
                bond: uint128(msg.value),
                claim: rootClaim(),
                position: ROOT_POSITION,
                clock: LibClock.wrap(Duration.wrap(0), Timestamp.wrap(uint64(block.timestamp)))
            })
        );

        // Set the game as initialized.
        initialized = true;

        // Deposit the bond.
        refundModeCredit[gameCreator()] += msg.value;
        WETH.deposit{ value: msg.value }();

        // Set the game's starting timestamp
        createdAt = Timestamp.wrap(uint64(block.timestamp));

        // Set whether the game type was respected when the game was created.
        wasRespectedGameTypeWhenCreated =
            GameType.unwrap(ANCHOR_STATE_REGISTRY.respectedGameType()) == GameType.unwrap(GAME_TYPE);

         if(_rat != address(0)) rat = _rat;
    }

   ```

5. initialize() 함수 변경

  /// @notice Initializes the contract without RAT.
  /// @dev This function may only be called once.
  function initialize() public payable virtual {
      _initialize(address(0));
  }


4. **gameDataWithRat() 함수 추가**
   ```solidity
    /// @notice A compliant implementation of this interface should return the components of the
    ///         game UUID's preimage provided in the cwia payload. The preimage of the UUID is
    ///         constructed as `keccak256(gameType . rootClaim . extraData)` where `.` denotes
    ///         concatenation.
    /// @return gameType_ The type of proof system being used.
    /// @return rootClaim_ The root claim of the DisputeGame.
    /// @return extraData_ Any extra data supplied to the dispute game contract by the creator.
    /// @return ratAddress_ The address of the RAT contract.
    function gameDataWithRat() external view returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_, address ratAddress_) {
        gameType_ = gameType();
        rootClaim_ = rootClaim();
        extraData_ = extraData();
        ratAddress_ = rat;
    }
   ```

5. **resolve() 함수 수정**
   - `emit Resolved(status = status_);` 이벤트 호출 밑에 `ratAddress.resolve()` 함수 추가
   ```solidity
   function resolve() external returns (GameStatus status_) {
       // ...

       emit Resolved(status = status_);

       if (rat != address(0) && status_ == GameStatus.CHALLENGER_WINS) {
            try IRAT(rat).resolve() {} catch {}
       }

   }
   ```


6. 업그레이드 및 단위 테스트 코드 추가 작성**
   - 경로: `/Users/zena/tokamak-projects/optimism/packages/contracts-bedrock/test/dispute/FaultDisputeGame.t.sol`


##  IDisputeGameFactory 수정

1. **파일**: `packages/contracts-bedrock/interfaces/dispute/IDisputeGameFactory.sol` 컨트랙트

2.  rat() 함수를 추가
    '''
    function rat() external view returns (address);
    '''

3.  setRAT() 함수를 추가
    '''
    function setRAT(address _rat) external;
    '''


### IFaultDisputeGame 컨트랙트 수정

1. **파일**: `packages/contracts-bedrock/interfaces/dispute/IFaultDisputeGame.sol` 컨트랙트

2. gameDataWithRat() 함수 추가

    '''
    function gameDataWithRat() external view returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_, address ratAddress_);
    '''

### IInitializable 컨트랙트 수정
1. **파일**: `packages/contracts-bedrock/interfaces/dispute/IInitializable.sol` 컨트랙트

2. initialize(address _rat) 함수 추가
  '''
  function initialize(address _rat) external payable;
  '''
