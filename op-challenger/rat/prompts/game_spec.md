
## Game관련 숙지 사항

1. Claim 타입
    의미:
    Claim은 단순히 bytes32의 래퍼 타입
    MPT (Merkle Patricia Trie) 루트를 나타냄
    결함 증명 프로그램의 상태를 나타내는 해시값

    '''
    type Claim is bytes32;
    '''


2. ClaimData

    의미:
    Claim 타입을 포함한 더 많은 메타데이터
    게임에서의 관계, 보증금, 시간 등 추가 정보

    '''
    struct ClaimData {
        uint32 parentIndex;      // 부모 클레임의 인덱스
        address counteredBy;     // 이 클레임을 반박한 주소
        address claimant;        // 클레임을 제출한 주소
        uint128 bond;           // 보증금
        Claim claim;            // 클레임 값 (해시)
        Position position;      // 게임에서의 위치
        Clock clock;            // 체스 시계 정보
    }
    '''

    (ex)
    '''
    // Solidity에서
    function getClaimData(uint256 index) external view returns (ClaimData memory) {
        return claimData[index];
    }

    ClaimData memory claim = ClaimData({
        parentIndex: 0,
        counteredBy: address(0),
        claimant: msg.sender,
        bond: 1000000,
        claim: Claim.wrap(keccak256("some state")),  // Claim 타입 사용
        position: Position.wrap(1),
        clock: Clock.wrap(0)
    });
    '''

3. Position
    '''
    /// @notice A `Position` represents a position of a claim within the game tree.
    /// @dev This is represented as a "generalized index" where the high-order bit
    /// is the level in the tree and the remaining bits is a unique bit pattern, allowing
    /// a unique identifier for each node in the tree. Mathematically, it is calculated
    /// as 2^{depth} + indexAtDepth.
    type Position is uint128;

    /// @notice The global root claim's position is always at gindex 1.
    Position internal constant ROOT_POSITION = Position.wrap(1);
    '''

    '''
    /// @notice Computes a generalized index (2^{depth} + indexAtDepth).
    /// @param _depth The depth of the position.
    /// @param _indexAtDepth The index at the depth of the position.
    /// @return position_ The computed generalized index.
    function wrap(uint8 _depth, uint128 _indexAtDepth) internal pure returns (Position position_) {
        assembly {
            // gindex = 2^{_depth} + _indexAtDepth
            position_ := add(shl(_depth, 1), _indexAtDepth)
        }
    }
    '''

    - 전체 트리에서의 고유 식별자
        - Position: gindex = 2^depth + indexAtDepth
        이렇게 depth와 indexAtDepth를 조합하여 게임 트리에서의 정확한 위치를 나타냅니다.

4. 게임에서의 공격과 방어의 위치

    '''
    // 공격: 왼쪽 자식
    Position attackPos = parentPos.move(true);   // depth+1, indexAtDepth*2

    // 방어: 오른쪽 자식
    Position defendPos = parentPos.move(false);  // depth+1, indexAtDepth*2+1

    '''


4. FaultDisputeGame 의 attack() 또는 defend() 함수 호출시, 보증금 계산 방법
    4.1. 함수 호출
    '''
    // FaultDisputeGame 컨트랙트에서
    function getRequiredBond(Position _position) public view returns (uint256 requiredBond_)
    '''

    4.2. 루트 에서의 보증금 계산
    '''
    Position attackPos = Position.wrap(2);
    function getRequiredBond(Position attackPos) public view returns (uint256 requiredBond_)
    '''

5. GameId

    /// @notice A `GameId` represents a packed 4 byte game ID, a 8 byte timestamp, and a 20 byte address.
    /// @dev The packed layout of this type is as follows:
    /// ┌───────────┬───────────┐
    /// │   Bits    │   Value   │
    /// ├───────────┼───────────┤
    /// │ [0, 32)   │ Game Type │
    /// │ [32, 96)  │ Timestamp │
    /// │ [96, 256) │ Address   │
    /// └───────────┴───────────┘
    type GameId is bytes32;

    '''
    /// @title LibGameId
    /// @notice Utility functions for packing and unpacking GameIds.
    library LibGameId {
        /// @notice Packs values into a 32 byte GameId type.
        /// @param _gameType The game type.
        /// @param _timestamp The timestamp of the game's creation.
        /// @param _gameProxy The game proxy address.
        /// @return gameId_ The packed GameId.
        function pack(
            GameType _gameType,
            Timestamp _timestamp,
            address _gameProxy
        )
            internal
            pure
            returns (GameId gameId_)
        {
            assembly {
                gameId_ := or(or(shl(224, _gameType), shl(160, _timestamp)), _gameProxy)
            }
        }

        /// @notice Unpacks values from a 32 byte GameId type.
        /// @param _gameId The packed GameId.
        /// @return gameType_ The game type.
        /// @return timestamp_ The timestamp of the game's creation.
        /// @return gameProxy_ The game proxy address.
        function unpack(GameId _gameId)
            internal
            pure
            returns (GameType gameType_, Timestamp timestamp_, address gameProxy_)
        {
            assembly {
                gameType_ := shr(224, _gameId)
                timestamp_ := and(shr(160, _gameId), 0xFFFFFFFFFFFFFFFF)
                gameProxy_ := and(_gameId, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            }
        }
    }

    '''


6.