
## 모니터링 이벤트

1. 이벤트 처리 흐름
L1 블록 헤드 변경 감지 → onNewL1Head 호출
새로운 게임 확인 → GetGamesAtOrAfter 호출
게임 스케줄링 → scheduler.Schedule 호출
게임 플레이어 생성 → 각 게임에 대한 플레이어 생성
게임 상태 모니터링 → 정기적으로 게임 상태 체크

2. 주요 특징
실시간 구독: L1 블록 헤드 변경만 실시간 구독
폴링 기반: 대부분의 게임 상태는 정기적 폴링으로 확인
재구독 메커니즘: 연결 실패 시 자동 재구독
배치 처리: 여러 게임을 배치로 처리하여 효율성 증대
챌린저는 주로 L1 블록 헤드 이벤트를 실시간으로 구독하고, 나머지 게임 관련 정보는 정기적 폴링을 통해 수집합니다.


## 게임 시작 과정 (폴링 기반)

1. L1 블록 헤드 이벤트 구독 (트리거)
// op-challenger/game/monitor.go
'''
// op-challenger/game/monitor.go
func (m *gameMonitor) onNewL1Head(ctx context.Context, sig eth.L1BlockRef) {
    m.clock.SetTime(sig.Time)
    // 새로운 L1 블록마다 게임 진행 상태 체크
    if err := m.progressGames(ctx, sig.Hash, sig.Number); err != nil {
        m.logger.Error("Failed to progress games", "err", err)
    }
}
'''
L1 블록 헤드 변경 이벤트 구독
새로운 블록마다 onNewL1Head 호출

2. 게임 데이터 폴링 (GetGamesAtOrAfter)
'''
// op-challenger/game/monitor.go
func (m *gameMonitor) progressGames(ctx context.Context, blockHash common.Hash, blockNumber uint64) error {
    // 1. 최소 타임스탬프 계산 (게임 윈도우 기반)
    minGameTimestamp := clock.MinCheckedTimestamp(m.clock, m.gameWindow)

    // 2. 폴링으로 게임 목록 수집
    games, err := m.source.GetGamesAtOrAfter(ctx, blockHash, minGameTimestamp)

    // 3. 허용된 게임만 필터링
    var gamesToPlay []types.GameMetadata
    for _, game := range games {
        if !m.allowedGame(game.Proxy) {
            continue
        }
        gamesToPlay = append(gamesToPlay, game)
    }

    // 4. 게임 스케줄링
    if err := m.scheduler.Schedule(gamesToPlay, blockNumber); err != nil {
        return fmt.Errorf("failed to schedule games: %w", err)
    }
}

'''
GetGamesAtOrAfter 호출로 최근 게임 목록 수집
타임스탬프 기반 필터링 (게임 윈도우 내 게임만)
허용된 게임만 필터링

- 폴링 로직 상세 (GetGamesAtOrAfter)
'''

// op-challenger/game/fault/contracts/gamefactory.go
func (f *DisputeGameFactoryContract) GetGamesAtOrAfter(ctx context.Context, blockHash common.Hash, earliestTimestamp uint64) ([]types.GameMetadata, error) {
    // 1. 전체 게임 개수 가져오기
    count, err := f.GetGameCount(ctx, blockHash)

    // 2. 배치 단위로 게임 데이터 수집
    for {
        // 게임 인덱스별로 데이터 수집
        calls := make([]batching.Call, 0, rangeEnd-rangeStart)
        for i := rangeEnd - 1; ; i-- {
            calls = append(calls, f.contract.Call(methodGameAtIndex, new(big.Int).SetUint64(i)))
        }

        // 배치 호출로 게임 메타데이터 수집
        results, err := f.multiCaller.Call(ctx, rpcblock.ByHash(blockHash), calls...)

        // 3. 타임스탬프 필터링 (최근 게임만)
        for i, result := range results {
            game := f.decodeGame(idx, result)
            if game.Timestamp < earliestTimestamp {
                return games, nil  // 오래된 게임은 무시
            }
            games = append(games, game)
        }
    }
}

'''
수집된 게임들을 스케줄러에 전달
각 게임에 대해 플레이어 생성


3. 게임 스케줄링
'''
// op-challenger/game/scheduler/scheduler.go
func (s *Scheduler) Schedule(games []types.GameMetadata, blockNumber uint64) error {
    select {
    case s.scheduleQueue <- blockGames{blockNumber: blockNumber, games: games}:
        return nil
    default:
        return ErrBusy  // 스케줄러가 바쁘면 스킵
    }
}
'''
수집된 게임들을 스케줄러에 전달
각 게임에 대해 플레이어 생성


4. 게임 플레이어 생성 및 시작
'''
// op-challenger/game/scheduler/coordinator.go
func (c *coordinator) scheduleGames(ctx context.Context, games []types.GameMetadata) {
    for _, game := range games {
        // 각 게임에 대해 플레이어 생성
        player, err := c.createPlayer(game, c.disk)
        if err != nil {
            continue
        }

        // 게임 플레이어 시작
        c.startPlayer(ctx, player)
    }
}
'''
각 게임 플레이어가 실제 게임 로직 실행
클레임 분석, 응답 결정, 트랜잭션 전송


핵심 특징
폴링 기반: 이벤트 구독이 아닌 정기적 폴링으로 게임 발견
배치 처리: 여러 게임을 한 번에 처리하여 효율성 증대
필터링: 타임스탬프와 허용 목록으로 관련 게임만 처리
비동기 처리: 스케줄러가 게임 플레이어를 비동기로 관리
따라서 게임 시작은 폴링으로 수집한 게임 목록을 확인한 후, 각 게임에 대해 플레이어를 생성하여 시작하는 방식입니다!